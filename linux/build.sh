#!/bin/sh
# Ember for Linux builds (Swift, GTK 4, libadwaita).
#   ./build.sh           the program, build/ember (runs the tests first)
#   ./build.sh dist      also Ember-linux-<arch>.tar.gz, the .deb and the .rpm (in build/)
#   ./build.sh install   build and install for you (~/.local/bin) and add Ember to niri
#   ./build.sh uninstall take it out again
# Building needs Swift 6.0 or newer (swift.org/install) and the GTK 4 and
# libadwaita development files:
#   Fedora:        sudo dnf install gtk4-devel libadwaita-devel pkgconf
#   Fedora Atomic: the same inside a toolbox (toolbox create && toolbox enter)
#   Debian/Ubuntu: sudo apt install libgtk-4-dev libadwaita-1-dev pkg-config
#   Arch:          sudo pacman -S gtk4 libadwaita pkgconf
# Swift's own libraries are built into the program (--static-swift-stdlib),
# so it needs only GTK 4.14+, libadwaita 1.5+ and GLib where it runs.
set -eu
cd "$(dirname "$0")"
VERSION=$(sed -n 's/.*static let version = "\(.*\)"/\1/p' Sources/Ember/Main.swift)
case "$(uname -m)" in
x86_64) ARCH=x86_64 DEBARCH=amd64 ;;
aarch64) ARCH=aarch64 DEBARCH=arm64 ;;
*) ARCH=$(uname -m) DEBARCH=$ARCH ;;
esac

build() {
	swift test
	swift build -c release --static-swift-stdlib -Xlinker --as-needed
	mkdir -p build
	strip -o build/ember "$(swift build -c release --show-bin-path)/Ember"
	echo "Built build/ember ($VERSION)"
}

tarball() {
	d=build/Ember-linux-$ARCH
	rm -rf "$d"
	mkdir -p "$d"
	cp build/ember ../LICENSE ../README.md packaging/install.sh "$d/"
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
	objdump -p build/ember | awk '/NEEDED/ {print $2}' | while read -r lib; do echo "      - $lib()(64bit)"; done
}

packages() {
	deps="$(deb_depends)"
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
  A dashboard and your apps (icons with their names, in pages) on clear
  liquid glass over a wallpaper of Iris, light by day and dark by night.
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
    recommends: [niri, swaybg]
  rpm:
    recommends: [niri, swaybg]
    depends:
NFPM
		rpm_depends
	} > build/nfpm.yaml
	if command -v nfpm >/dev/null 2>&1; then nfpm=nfpm; else nfpm="go run github.com/goreleaser/nfpm/v2/cmd/nfpm@v2.41.0"; fi
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
