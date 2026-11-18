Ember: a calm, full-screen home for your desktop. A dashboard and your apps on one screen of clear glass.

## New in 1.0.5

- **Colorless liquid glass.** Icons, cards, buttons and text are clear glass with no color of their own; only the backdrop keeps the theme's color. Text stays readable on every theme.
- **niri's windows are glass too**: rounded corners, a fine glass focus ring, slightly see-through when not in use, and blurred behind on niri 26.04 or newer.
- **Dark themes turn on dark mode, light themes light mode** for your apps (GTK and libadwaita apps, and the browsers and Electron apps that follow the desktop).
- **A quieter screen**: no name or hints in the footer, and no row of open windows (niri's overview shows them).
- **Power** now offers just Sleep, Restart and Shut down.
- **Click the network card** to open a terminal with the Wi-Fi networks nearby and a short guide to nmcli (connect, disconnect, saved networks, Wi-Fi on and off).

## New in 1.0.4

- **New glass themes**, in the spirit of Apple's Liquid Glass. **Liquid** is the new default: a black backdrop with soft light behind clear glass panes and glossy liquid icons. Also Graphite, Deep Sea, Ember and Aurora (dark), and Daylight, Mist, Rose, Sunrise and Mint (light). The old palettes are gone; a saved one switches to Liquid.

## New in 1.0.3

- Ember hides the top bar niri starts (Waybar) the first time it runs; Power, then Top bar, brings it back. The line in niri's config.kdl that starts it becomes a comment marked as Ember's (the old file is config.kdl.before-ember).

## New in 1.0.2

- The Ember bar is gone: Ember no longer changes Waybar, the bar at the top of niri. If 1.0.1 had restyled it, 1.0.2 puts Waybar's own files back by itself.

## New in 1.0.1

- **No memory while hidden**: Ember quits when it hides, and Super+D starts it again.
- **Brightness** card on the dashboard: drag or scroll.
- **Seven new themes**: Ember Glow, Sunset and Terracotta (warm and strong); Midnight, Ember Night, Aurora and Abyss (night).

## Ember for Linux 1.0.0 (on niri)

- Dashboard (clock, processor, memory, network, disk, battery), app grid with search and hidden apps, a row of open windows from niri, and a power panel.
- Lite Go's themes, with Lagoon by default; niri's colors follow the theme.
- Run `ember` once inside niri: it adds itself to niri's settings. Super+D shows or hides it.
- Updates itself from these releases (power panel: Automatic updates).

## Install

- Fedora: `sudo dnf config-manager addrepo --from-repofile=https://tulip-labs.github.io/Ember/ember-shell.repo && sudo dnf install ember-shell`
- Debian, Ubuntu: see the README for the apt repository, or install the `.deb` below.
- Any distribution: unpack `Ember-linux-x86_64.tar.gz` and run `./install.sh`.
- Arch: `PKGBUILD` below (`makepkg -si`). Nix: `nix profile install github:Tulip-Labs/Ember`.

## Ember for Windows 3.1

`Ember-3.1-windows.zip`: read README.txt inside before installing.
