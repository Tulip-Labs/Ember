// Package bar gives Waybar, the top bar niri starts, Ember's look: glass
// pills in the theme's colors, Nunito, plain words instead of icons, and an
// Ember button that shows Ember (Super+D does the same).
//
// Ember writes Waybar's config.jsonc and style.css (keeping a copy of the
// ones it replaces), writes style.css again when the theme changes, and asks
// Waybar to reload.
package bar

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"ember/assets"
	"ember/ui"
)

// Mark is the first line of every file Ember writes, so it knows its own.
const Mark = "/* Written by Ember: the Ember bar. Ember rewrites it when the theme changes. */"

// Config is Waybar's config.jsonc.
func Config() string {
	return Mark + `
{
    "layer": "top",
    "position": "top",
    "height": 38,
    "margin-top": 8,
    "margin-left": 12,
    "margin-right": 12,
    "spacing": 6,
    "modules-left": ["custom/ember", "niri/workspaces", "niri/window"],
    "modules-center": ["clock"],
    "modules-right": ["network", "pulseaudio", "cpu", "memory", "battery", "custom/power"],

    "custom/ember": {
        "format": "Ember",
        "tooltip-format": "Show Ember (Super+D)",
        "on-click": "ember --toggle"
    },
    "niri/workspaces": {
        "format": "{index}"
    },
    "niri/window": {
        "format": "{title}",
        "max-length": 56,
        "separate-outputs": true
    },
    "clock": {
        "format": "{:%A %d %B  ·  %I:%M %p}",
        "tooltip-format": "<tt>{calendar}</tt>"
    },
    "network": {
        "format-wifi": "Wi-Fi  {essid}",
        "format-ethernet": "Wired",
        "format-linked": "Connecting",
        "format-disconnected": "Offline",
        "tooltip-format": "{ifname}  {ipaddr}",
        "tooltip-format-wifi": "{essid}  ·  signal {signalStrength}%  ·  {ipaddr}"
    },
    "pulseaudio": {
        "format": "Sound  {volume}%",
        "format-muted": "Muted",
        "on-click": "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle",
        "scroll-step": 5
    },
    "cpu": {
        "format": "CPU  {usage}%",
        "interval": 3
    },
    "memory": {
        "format": "Memory  {used:0.1f} GB",
        "interval": 5,
        "tooltip-format": "{used:0.1f} of {total:0.1f} GB in use"
    },
    "battery": {
        "format": "Battery  {capacity}%",
        "format-charging": "Charging  {capacity}%",
        "format-plugged": "Plugged in  {capacity}%",
        "format-full": "Full",
        "states": { "low": 15 },
        "tooltip-format": "{timeTo}"
    },
    "custom/power": {
        "format": "Power",
        "tooltip-format": "Lock, sleep, restart, shut down",
        "on-click": "ember --power"
    }
}
`
}

func rgba(c ui.Color, a float64) string {
	return fmt.Sprintf("rgba(%d, %d, %d, %.2f)", c.R(), c.G(), c.B(), a)
}

func hex(c ui.Color) string { return fmt.Sprintf("#%02x%02x%02x", c.R(), c.G(), c.B()) }

// Style is Waybar's style.css for a theme. GTK cannot blur what is behind
// the bar, so the glass is drawn the way Ember draws it: a pale gradient
// that is lighter at the top, a bright inner edge along the top, a faint
// rim and a soft shadow underneath.
func Style(th *ui.Theme) string {
	top, bottom := rgba(ui.White, 0.86), rgba(ui.White, 0.56)
	rim, shine, shade := rgba(ui.White, 0.90), rgba(ui.White, 0.95), rgba(th.Shadow, 0.05)
	shadow := rgba(th.Shadow, 0.18)
	hoverTop, hoverBottom := rgba(ui.White, 0.97), rgba(ui.White, 0.80)
	if th.Dark {
		top, bottom = rgba(th.G4, 0.88), rgba(th.G5, 0.78)
		rim, shine, shade = rgba(th.Ink, 0.14), rgba(th.Ink, 0.16), rgba(ui.Black, 0.25)
		shadow = rgba(ui.Black, 0.45)
		hoverTop, hoverBottom = rgba(th.G2, 0.95), rgba(th.G4, 0.90)
	}
	on := "#ffffff"
	if th.Dark {
		on = hex(th.G5)
	}
	r := strings.NewReplacer(
		"INK2", hex(th.Ink2), "INK", hex(th.Ink), "DEEP2", hex(th.Deep2), "DEEP", hex(th.Deep), "ON", on,
		"DANGER", hex(th.Danger), "GTOP", top, "GBOTTOM", bottom, "RIM", rim, "SHINE", shine, "SHADE", shade,
		"SHADOW", shadow, "HTOP", hoverTop, "HBOTTOM", hoverBottom, "LABEL", th.Label,
	)
	return r.Replace(Mark + `
/* LABEL theme */
* {
    font-family: "Nunito", "Cantarell", sans-serif;
    font-weight: 700;
    font-size: 13px;
    border: none;
    border-radius: 0;
    min-height: 0;
}

window#waybar {
    background: transparent;
    color: INK;
}

tooltip {
    background: linear-gradient(to bottom, GTOP, GBOTTOM);
    border: 1px solid RIM;
    border-radius: 14px;
    box-shadow: inset 0 1px 0 SHINE;
}

tooltip label {
    color: INK;
    padding: 4px 6px;
}

/* every module is a glass pill */
#custom-ember, #workspaces, #window, #clock, #network, #pulseaudio,
#cpu, #memory, #battery, #custom-power {
    background: linear-gradient(to bottom, GTOP, GBOTTOM);
    border: 1px solid RIM;
    border-radius: 19px;
    box-shadow: inset 0 1px 0 SHINE, inset 0 -1px 0 SHADE, 0 4px 12px SHADOW;
    padding: 0 15px;
    margin: 2px 0 8px 0;
    color: INK;
    transition: background 150ms ease;
}

#custom-ember {
    background: linear-gradient(to bottom, DEEP2, DEEP);
    border-color: DEEP;
    color: ON;
    font-weight: 800;
    padding: 0 18px;
}

#custom-ember:hover {
    background: linear-gradient(to bottom, DEEP, DEEP);
}

#custom-power:hover, #clock:hover, #network:hover, #pulseaudio:hover {
    background: linear-gradient(to bottom, HTOP, HBOTTOM);
}

#workspaces {
    padding: 0 4px;
}

#workspaces button {
    color: INK2;
    padding: 0 9px;
    margin: 4px 1px;
    border-radius: 14px;
    background: transparent;
    box-shadow: none;
}

#workspaces button:hover {
    background: linear-gradient(to bottom, HTOP, HBOTTOM);
    color: INK;
}

#workspaces button.active, #workspaces button.focused {
    background: linear-gradient(to bottom, DEEP2, DEEP);
    color: ON;
}

#workspaces button.urgent {
    color: DANGER;
}

/* no window title: no empty pill */
window#waybar.empty #window {
    background: transparent;
    border-color: transparent;
    box-shadow: none;
}

#network.disconnected, #pulseaudio.muted {
    color: INK2;
}

#battery.low:not(.charging) {
    color: DANGER;
}

#battery.charging, #battery.plugged {
    color: DEEP;
}

#custom-power {
    color: DEEP;
}
`)
}

// Files is what Setup writes into Waybar's config folder.
func files(th *ui.Theme) map[string]string {
	return map[string]string{"config.jsonc": Config(), "style.css": Style(th)}
}

// Dir is Waybar's config folder.
func Dir() string {
	if d := os.Getenv("XDG_CONFIG_HOME"); d != "" {
		return filepath.Join(d, "waybar")
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".config", "waybar")
}

func ours(p string) bool {
	b, err := os.ReadFile(p)
	return err == nil && bytes.HasPrefix(b, []byte(Mark))
}

// Setup writes the Ember bar into dir. A config of someone else's is kept as
// <name>.before-ember first (Waybar reads config.jsonc before config, so an
// old "config" file is moved aside too).
func Setup(dir string, th *ui.Theme) error {
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	for _, name := range []string{"config", "config.jsonc", "style.css"} {
		p := filepath.Join(dir, name)
		if _, err := os.Stat(p); err == nil && !ours(p) {
			if err := os.Rename(p, p+".before-ember"); err != nil {
				return err
			}
		}
	}
	for name, body := range files(th) {
		if err := write(filepath.Join(dir, name), body); err != nil {
			return err
		}
	}
	return installFonts()
}

// Restyle writes style.css for a new theme, if the Ember bar is in use.
func Restyle(dir string, th *ui.Theme) (bool, error) {
	p := filepath.Join(dir, "style.css")
	if !ours(p) {
		return false, nil
	}
	return true, write(p, Style(th))
}

// Installed reports whether the Ember bar is in use.
func Installed(dir string) bool { return ours(filepath.Join(dir, "config.jsonc")) }

// Remove puts back the files the Ember bar replaced.
func Remove(dir string) error {
	for _, name := range []string{"config", "config.jsonc", "style.css"} {
		p := filepath.Join(dir, name)
		if ours(p) {
			os.Remove(p)
		}
		if _, err := os.Stat(p + ".before-ember"); err == nil {
			if err := os.Rename(p+".before-ember", p); err != nil {
				return err
			}
		}
	}
	return nil
}

func write(p string, body string) error {
	if old, err := os.ReadFile(p); err == nil && string(old) == body {
		return nil
	}
	tmp := p + ".tmp"
	if err := os.WriteFile(tmp, []byte(body), 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, p)
}

// installFonts puts Nunito where the bar finds it (~/.local/share/fonts).
func installFonts() error {
	d := os.Getenv("XDG_DATA_HOME")
	if d == "" {
		home, _ := os.UserHomeDir()
		d = filepath.Join(home, ".local", "share")
	}
	d = filepath.Join(d, "fonts", "ember")
	if err := os.MkdirAll(d, 0o755); err != nil {
		return err
	}
	changed := false
	for name, b := range map[string][]byte{"Nunito-Regular.ttf": assets.NunitoRegular, "Nunito-Bold.ttf": assets.NunitoBold} {
		p := filepath.Join(d, name)
		if old, err := os.ReadFile(p); err == nil && bytes.Equal(old, b) {
			continue
		}
		if err := os.WriteFile(p, b, 0o644); err != nil {
			return err
		}
		changed = true
	}
	if changed {
		if fc, err := exec.LookPath("fc-cache"); err == nil {
			exec.Command(fc, "-f", d).Run()
		}
	}
	return nil
}

// Reload asks a running Waybar to read its config and style again.
func Reload() {
	exec.Command("pkill", "-SIGUSR2", "-x", "waybar").Run()
}
