#!/bin/sh
# Ember for Linux builds.
#   ./build.sh           the program, build/ember (runs the tests first)
#   ./build.sh dist      also Ember-linux-<arch>.tar.gz, the .deb and the .rpm (in build/)
#   ./build.sh install   build and install for you (~/.local/bin) and add Ember to niri
#   ./build.sh uninstall take it out again
# Building needs Go 1.24+ and Gio's development files:
#   Fedora:        sudo dnf install golang gcc pkgconf wayland-devel libxkbcommon-devel libxkbcommon-x11-devel mesa-libEGL-devel mesa-libGLES-devel libX11-devel libXcursor-devel libXfixes-devel
#   Fedora Atomic: the same inside a toolbox (toolbox create && toolbox enter)
#   Debian/Ubuntu: sudo apt install golang gcc pkg-config libwayland-dev libxkbcommon-dev libxkbcommon-x11-dev libegl-dev libgles-dev libx11-dev libx11-xcb-dev libxcursor-dev libxfixes-dev
#   Arch:          sudo pacman -S go gcc pkgconf wayland libxkbcommon libxkbcommon-x11 mesa libx11 libxcursor libxfixes
set -eu
cd "$(dirname "$0")"
export GOFLAGS="${GOFLAGS:--mod=mod}"
VERSION=$(sed -n 's/^const version = "\(.*\)"/\1/p' cmd/ember/main.go)
case "$(uname -m)" in
x86_64) ARCH=x86_64 DEBARCH=amd64 ;;
aarch64) ARCH=aarch64 DEBARCH=arm64 ;;
*) ARCH=$(uname -m) DEBARCH=$ARCH ;;
esac
BIN="${XDG_BIN_HOME:-$HOME/.local/bin}"

build() {
	go test ./apps ./niri ./shell ./sysinfo ./update
	mkdir -p build
	CGO_ENABLED=1 go build -tags novulkan -trimpath -ldflags "-s -w" -o build/ember ./cmd/ember
	echo "Built build/ember ($VERSION)"
}

tarball() {
	d=build/Ember-linux-$ARCH
	rm -rf "$d"
	mkdir -p "$d"
	cp build/ember ../LICENSE ../README.md "$d/"
	cp packaging/install.sh "$d/"
	tar -C build -czf "build/Ember-linux-$ARCH.tar.gz" "Ember-linux-$ARCH"
}

# the libraries the program links, as each package format names them
deb_depends() {
	t=$(mktemp -d)
	mkdir -p "$t/debian"
	printf 'Source: ember-shell\n\nPackage: ember-shell\nArchitecture: any\n' > "$t/debian/control"
	cp build/ember "$t/"
	(cd "$t" && dpkg-shlibdeps -O -e ember 2>/dev/null) | sed -n 's/^shlibs:Depends=//p'
	rm -rf "$t"
}

rpm_depends() {
	suffix="()(64bit)"
	{
		objdump -p build/ember | awk '/NEEDED/ {print $2}'
		echo libGLESv2.so.2 # opened at run time
	} | while read -r lib; do echo "      - $lib$suffix"; done
}

packages() {
	# libGLESv2 is opened at run time (dlopen), so it is not in the list
	deps="$(deb_depends), libgles2"
	echo "deb depends: $deps"
	{
		cat <<NFPM
name: ember-shell
version: $VERSION
arch: $DEBARCH
platform: linux
section: x11
maintainer: Tulip Labs <tulip-labs@users.noreply.github.com>
vendor: Tulip Labs
homepage: https://github.com/Tulip-Labs/Ember
license: GPL-3.0-only
description: |-
  Ember, a calm full-screen home for the niri compositor.
  A dashboard, your apps and your open windows on one pastel screen.
  Run ember once inside niri: it adds itself to niri's settings
  (Super+D shows or hides it).
contents:
  - src: build/ember
    dst: /usr/lib/ember-shell/ember
    file_info: {mode: 0755}
  - src: packaging/install-kind-deb
    dst: /usr/lib/ember-shell/install-kind
    packager: deb
  - src: packaging/install-kind-rpm
    dst: /usr/lib/ember-shell/install-kind
    packager: rpm
  - src: /usr/lib/ember-shell/ember
    dst: /usr/bin/ember
    type: symlink
  - src: ../README.md
    dst: /usr/share/doc/ember-shell/README.md
  - src: ../LICENSE
    dst: /usr/share/licenses/ember-shell/LICENSE
overrides:
  deb:
    depends: [$deps]
    recommends: [niri]
  rpm:
    recommends: [niri]
    depends:
NFPM
		rpm_depends
	} > build/nfpm.yaml
	nfpm="go run github.com/goreleaser/nfpm/v2/cmd/nfpm@v2.41.0"
	for p in deb rpm; do
		$nfpm package --config build/nfpm.yaml --packager $p --target build/
	done
}

case "${1:-build}" in
build) build ;;
dist)
	build
	tarball
	packages
	ls -l build/*.tar.gz build/*.deb build/*.rpm
	;;
install)
	build
	tarball
	"build/Ember-linux-$ARCH/install.sh"
	;;
uninstall) packaging/install.sh --remove ;;
*)
	echo "usage: $0 [build|dist|install|uninstall]"
	exit 2
	;;
esac
