package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"ember/niri"
	"ember/shell"
)

// niriSetupCmd is ember --setup-niri and --remove-niri.
func niriSetupCmd(remove bool) int {
	dir := niri.ConfigDir()
	if remove {
		// and do not add it back by itself
		if cfg, err := os.UserConfigDir(); err == nil {
			os.MkdirAll(filepath.Join(cfg, "ember"), 0o755)
			os.WriteFile(filepath.Join(cfg, "ember", "niri-setup-done"), nil, 0o644)
		}
		if err := niri.Remove(dir); err != nil {
			fmt.Fprintln(os.Stderr, "ember:", err)
			return 1
		}
		fmt.Println("Ember is out of niri's settings.")
		return 0
	}
	r := &resident{}
	cfg, _ := os.UserConfigDir()
	r.conf = filepath.Join(cfg, "ember")
	r.loadSettings()
	res, err := niri.Setup(dir, shell.ThemeByID(r.theme))
	if err != nil {
		fmt.Fprintln(os.Stderr, "ember:", err)
		return 1
	}
	if res.Added {
		fmt.Printf("Added %s to %s (the old file is %s).\n", niri.Include, filepath.Join(dir, "config.kdl"), res.Backup)
	}
	fmt.Println("Ember is in niri's settings: Super+D shows or hides it, and it starts when you sign in.")
	return 0
}

// autoSetupNiri: the first time Ember runs inside niri, it adds itself to
// niri's settings (with a backup), so installing the package is all it takes.
// Once done (or after --remove-niri left a marker) it never does it again.
func (r *resident) autoSetupNiri() {
	if r.niri == nil {
		return
	}
	marker := filepath.Join(r.conf, "niri-setup-done")
	if _, err := os.Stat(marker); err == nil {
		return
	}
	dir := niri.ConfigDir()
	if b, err := os.ReadFile(filepath.Join(dir, "config.kdl")); err == nil && niri.HasInclude(b) {
		os.MkdirAll(r.conf, 0o755)
		os.WriteFile(marker, nil, 0o644)
		return
	}
	res, err := niri.Setup(dir, shell.ThemeByID(r.theme))
	if err != nil {
		return
	}
	os.MkdirAll(r.conf, 0o755)
	os.WriteFile(marker, nil, 0o644)
	if res.Added {
		r.startNote = "Ember added itself to niri: Super+D shows or hides it"
	}
}

// removeOldBar undoes the Ember bar that Ember 1.0.1 could set up (it was
// taken out in 1.0.2): if Waybar still has Ember's files, they go, Waybar's
// own files come back, and Waybar starts again. Nothing happens otherwise.
func removeOldBar(c *niri.Client) {
	const mark = "/* Written by Ember: the Ember bar."
	cfg, _ := os.UserConfigDir()
	dir := filepath.Join(cfg, "waybar")
	os.Remove(filepath.Join(cfg, "ember", "bar-setup-done"))
	changed := false
	for _, name := range []string{"config", "config.jsonc", "style.css"} {
		p := filepath.Join(dir, name)
		if b, err := os.ReadFile(p); err == nil && strings.HasPrefix(string(b), mark) {
			os.Remove(p)
			changed = true
		}
		if _, err := os.Stat(p + ".before-ember"); err == nil {
			if _, err := os.Stat(p); err != nil {
				os.Rename(p+".before-ember", p)
				changed = true
			}
		}
	}
	if d := os.Getenv("XDG_DATA_HOME"); d != "" {
		os.RemoveAll(filepath.Join(d, "fonts", "ember"))
	} else if home, err := os.UserHomeDir(); err == nil {
		os.RemoveAll(filepath.Join(home, ".local", "share", "fonts", "ember"))
	}
	if !changed || exec.Command("pgrep", "-x", "waybar").Run() != nil {
		return
	}
	exec.Command("pkill", "-x", "waybar").Run()
	time.Sleep(300 * time.Millisecond)
	if c != nil && c.Spawn([]string{"waybar"}) == nil {
		return
	}
	startDetached([]string{"waybar"})
}

// The top bar niri starts (Waybar). Ember hides it: Ember's own dashboard
// has the clock, battery, network and the rest. The power panel's "Top bar"
// row shows it again.

// autoHideBar hides the top bar the first time Ember 1.0.3 or later runs
// inside niri.
func (r *resident) autoHideBar() {
	if r.niri == nil {
		return
	}
	marker := filepath.Join(r.conf, "bar-hidden-once")
	if _, err := os.Stat(marker); err == nil {
		return
	}
	os.MkdirAll(r.conf, 0o755)
	os.WriteFile(marker, nil, 0o644)
	if err := setTopBar(false, r.niri); err == nil {
		r.startNote = "The top bar is hidden: Power, then Top bar, brings it back"
	}
}

// setTopBar shows or hides Waybar now and at the next sign-in.
func setTopBar(show bool, c *niri.Client) error {
	dir := niri.ConfigDir()
	systemd := func(args ...string) error {
		return exec.Command("systemctl", append([]string{"--user"}, args...)...).Run()
	}
	if !show {
		if _, err := niri.HideBar(dir); err != nil {
			return err
		}
		// some setups start it as a systemd user service instead
		if systemd("is-enabled", "--quiet", "waybar.service") == nil {
			systemd("disable", "--now", "waybar.service")
			cfg, _ := os.UserConfigDir()
			os.WriteFile(filepath.Join(cfg, "ember", "waybar-service-was-enabled"), nil, 0o644)
		}
		exec.Command("pkill", "-x", "waybar").Run()
		return nil
	}
	if _, err := niri.ShowBar(dir); err != nil {
		return err
	}
	cfg, _ := os.UserConfigDir()
	flag := filepath.Join(cfg, "ember", "waybar-service-was-enabled")
	if _, err := os.Stat(flag); err == nil {
		os.Remove(flag)
		return systemd("enable", "--now", "waybar.service")
	}
	if exec.Command("pgrep", "-x", "waybar").Run() == nil {
		return nil
	}
	if c != nil && c.Spawn([]string{"waybar"}) == nil {
		return nil
	}
	return startDetached([]string{"waybar"})
}

// SetTopBar is the power panel's "Top bar" row.
func (r *resident) SetTopBar(show bool) error { return setTopBar(show, r.niri) }

// TopBarShown reports whether niri starts the top bar.
func topBarShown() bool { return !niri.BarHidden(niri.ConfigDir()) }
