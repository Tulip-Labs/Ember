#!/bin/sh
# Installs Ember for the current user (no root needed): the program to
# ~/.local/bin, and Ember into niri's settings.
#   ./install.sh            install (from the unpacked Ember-linux folder)
#   ./install.sh --remove   take it out again
# Ember needs GTK 4.14+ and libadwaita 1.5+ (most desktops have them),
# niri 25.11 or newer, and swaybg for its wallpaper.
set -eu
cd "$(dirname "$0")"
BIN="${XDG_BIN_HOME:-$HOME/.local/bin}"

if [ "${1:-}" = "--remove" ]; then
	if [ -x "$BIN/ember" ]; then
		"$BIN/ember" --hide 2>/dev/null || true
		"$BIN/ember" --remove-niri || true
	fi
	pkill -x ember 2>/dev/null || true
	pkill -f "ember --wallpaper" 2>/dev/null || true
	rm -f "$BIN/ember" "$BIN/.ember-install"
	echo "Ember is removed. niri reloads its settings by itself."
	exit 0
fi

[ -x ./ember ] || { echo "Run this from the unpacked Ember-linux folder." >&2; exit 1; }
mkdir -p "$BIN"
install -m 755 ember "$BIN/ember.new" && mv "$BIN/ember.new" "$BIN/ember"
echo user > "$BIN/.ember-install" # Ember updates this copy by itself
case ":$PATH:" in *":$BIN:"*) ;; *) echo "Note: $BIN is not on your PATH; niri needs to find 'ember' there.";; esac
if "$BIN/ember" --setup-niri; then
	:
else
	echo "Ember adds itself to niri the first time it runs inside niri."
fi
if command -v ldd >/dev/null 2>&1 && ldd "$BIN/ember" | grep -q "not found"; then
	echo "Some libraries are missing (install GTK 4 and libadwaita):" >&2
	ldd "$BIN/ember" | grep "not found" >&2
fi
command -v swaybg >/dev/null 2>&1 || echo "Note: install swaybg to see Ember's wallpaper on the desktop."
echo "Done. Super+D shows or hides Ember; it starts by itself at the next sign-in."
