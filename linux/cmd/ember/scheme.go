package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"ember/ui"
)

// systemScheme makes the desktop's apps follow Ember's theme: dark themes
// turn on dark mode, light themes light mode. GTK 4 and libadwaita apps (and
// Chromium, Firefox and Electron apps through the desktop portal) read
// color-scheme; GTK 3 apps read gtk-theme, changed only while it is one of
// Adwaita's two, so a theme chosen by hand stays.
func systemScheme(th *ui.Theme) {
	scheme, gtk, prefer := "prefer-light", "Adwaita", "0"
	if th.Dark {
		scheme, gtk, prefer = "prefer-dark", "Adwaita-dark", "1"
	}
	if _, err := exec.LookPath("gsettings"); err == nil {
		const iface = "org.gnome.desktop.interface"
		if cur := gget(iface, "color-scheme"); cur != scheme {
			exec.Command("gsettings", "set", iface, "color-scheme", scheme).Run()
		}
		if cur := gget(iface, "gtk-theme"); cur != gtk && (cur == "" || cur == "Adwaita" || cur == "Adwaita-dark") {
			exec.Command("gsettings", "set", iface, "gtk-theme", gtk).Run()
		}
	}
	// GTK 3 apps that start without the settings daemon read settings.ini
	cfg, err := os.UserConfigDir()
	if err != nil {
		return
	}
	for _, v := range []string{"gtk-3.0", "gtk-4.0"} {
		setIni(filepath.Join(cfg, v, "settings.ini"), "gtk-application-prefer-dark-theme", prefer)
	}
}

func gget(schema, key string) string {
	out, err := exec.Command("gsettings", "get", schema, key).Output()
	if err != nil {
		return ""
	}
	return strings.Trim(strings.TrimSpace(string(out)), "'")
}

// setIni sets key=value in the [Settings] group of a GTK settings.ini,
// keeping everything else in it.
func setIni(path, key, value string) {
	old, _ := os.ReadFile(path)
	lines := strings.Split(strings.TrimRight(string(old), "\n"), "\n")
	if len(old) == 0 {
		lines = nil
	}
	group, done := -1, false
	for i, ln := range lines {
		t := strings.TrimSpace(ln)
		if strings.HasPrefix(t, "[") {
			if group >= 0 && !done {
				lines = append(lines[:i], append([]string{key + "=" + value}, lines[i:]...)...)
				done = true
				break
			}
			if t == "[Settings]" {
				group = i
			}
			continue
		}
		if group >= 0 && !done {
			if k, _, ok := strings.Cut(t, "="); ok && strings.TrimSpace(k) == key {
				lines[i] = key + "=" + value
				done = true
			}
		}
	}
	if !done {
		if group < 0 {
			lines = append(lines, "[Settings]")
		}
		lines = append(lines, key+"="+value)
	}
	out := strings.Join(lines, "\n") + "\n"
	if out == string(old) {
		return
	}
	os.MkdirAll(filepath.Dir(path), 0o755)
	os.WriteFile(path, []byte(out), 0o644)
}
