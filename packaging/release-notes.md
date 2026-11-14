Ember: a calm, full-screen home for your desktop. A dashboard, your apps and your open windows on one pastel screen.

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
