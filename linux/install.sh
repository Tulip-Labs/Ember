#!/bin/sh
# Builds Ember and sets it up on niri, for the current user (no root needed).
#   ./install.sh            build, install to ~/.local/bin, hook into niri
#   ./install.sh --remove   take it all out again
# A release download comes built. Building from source needs Go 1.24+ and the Gio development files:
#   Debian/Ubuntu: sudo apt install golang gcc pkg-config libwayland-dev libxkbcommon-dev libegl-dev libgles-dev libvulkan-dev libx11-dev libx11-xcb-dev libxkbcommon-x11-dev libxcursor-dev libxfixes-dev
#   Fedora:        sudo dnf install golang gcc pkgconf wayland-devel libxkbcommon-devel mesa-libEGL-devel mesa-libGLES-devel vulkan-headers libX11-devel libxkbcommon-x11-devel libXcursor-devel libXfixes-devel
#   Arch:          sudo pacman -S go gcc pkgconf wayland libxkbcommon mesa vulkan-headers libx11 libxcursor libxfixes
set -eu
cd "$(dirname "$0")"
BIN="${XDG_BIN_HOME:-$HOME/.local/bin}"
NIRI="${XDG_CONFIG_HOME:-$HOME/.config}/niri"
LINE='include "ember.kdl"'

if [ "${1:-}" = "--remove" ]; then
	"$BIN/ember" --hide 2>/dev/null || true
	pkill -x ember 2>/dev/null || true
	rm -f "$BIN/ember" "$NIRI/ember.kdl"
	if [ -f "$NIRI/config.kdl" ]; then
		grep -vxF "$LINE" "$NIRI/config.kdl" > "$NIRI/config.kdl.tmp" && mv "$NIRI/config.kdl.tmp" "$NIRI/config.kdl"
	fi
	echo "Ember is removed. niri reloads its config by itself."
	exit 0
fi

if [ -x ./ember ]; then
	mkdir -p build && cp ./ember build/ember # a release download: already built
else
	echo "Building Ember..."
	go build -trimpath -ldflags "-s -w" -o build/ember ./cmd/ember
fi
mkdir -p "$BIN" "$NIRI"
install -m 755 build/ember "$BIN/ember"
install -m 644 dist/ember.kdl "$NIRI/ember.kdl"
if [ ! -f "$NIRI/config.kdl" ]; then
	echo "No niri config found: niri writes its default one on first start."
	echo "Add this line at the end of $NIRI/config.kdl afterwards:"
	echo "    $LINE"
elif ! grep -qxF "$LINE" "$NIRI/config.kdl"; then
	cp "$NIRI/config.kdl" "$NIRI/config.kdl.before-ember"
	printf '\n%s\n' "$LINE" >> "$NIRI/config.kdl"
	echo "Added '$LINE' to $NIRI/config.kdl (the old file is config.kdl.before-ember)."
fi
case ":$PATH:" in *":$BIN:"*) ;; *) echo "Note: $BIN is not on your PATH; niri needs to find 'ember' there.";; esac
if command -v niri >/dev/null 2>&1 && [ -n "${NIRI_SOCKET:-}" ]; then
	niri validate >/dev/null && echo "niri config is valid." || echo "niri reports a problem in its config (see: niri validate)."
fi
echo "Done. Super+D shows or hides Ember; it starts by itself at the next sign-in."
