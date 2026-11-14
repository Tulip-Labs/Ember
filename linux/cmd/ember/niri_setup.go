package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"time"

	"ember/bar"
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

// barCmd is ember --setup-bar and --remove-bar.
func barCmd(remove bool) int {
	dir := bar.Dir()
	cfg, _ := os.UserConfigDir()
	marker := filepath.Join(cfg, "ember", "bar-setup-done")
	os.MkdirAll(filepath.Dir(marker), 0o755)
	os.WriteFile(marker, nil, 0o644) // done by hand: never again by itself
	if remove {
		if err := bar.Remove(dir); err != nil {
			fmt.Fprintln(os.Stderr, "ember:", err)
			return 1
		}
		restartWaybar(niri.FromEnv())
		fmt.Println("Waybar has its own config back.")
		return 0
	}
	r := &resident{}
	r.conf = filepath.Join(cfg, "ember")
	r.loadSettings()
	if err := bar.Setup(dir, shell.ThemeByID(r.theme)); err != nil {
		fmt.Fprintln(os.Stderr, "ember:", err)
		return 1
	}
	restartWaybar(niri.FromEnv())
	fmt.Println("Waybar has Ember's look (the old files end in .before-ember).")
	return 0
}

// autoSetupBar: the first time Ember runs inside niri with Waybar there, it
// gives the bar Ember's look (keeping Waybar's old files).
func (r *resident) autoSetupBar() {
	if r.niri == nil {
		return
	}
	if _, err := exec.LookPath("waybar"); err != nil {
		return
	}
	marker := filepath.Join(r.conf, "bar-setup-done")
	if _, err := os.Stat(marker); err == nil {
		return
	}
	os.MkdirAll(r.conf, 0o755)
	os.WriteFile(marker, nil, 0o644)
	if bar.Installed(bar.Dir()) {
		return
	}
	if err := bar.Setup(bar.Dir(), shell.ThemeByID(r.theme)); err != nil {
		return
	}
	restartWaybar(r.niri)
	if r.startNote == "" {
		r.startNote = "The top bar now has Ember's look (ember --remove-bar puts the old one back)"
	}
}

// restartWaybar starts Waybar again so it picks up the new files and font;
// niri starts it, so it stays niri's child as at sign-in.
func restartWaybar(c *niri.Client) {
	running := exec.Command("pgrep", "-x", "waybar").Run() == nil
	if !running {
		return
	}
	exec.Command("pkill", "-x", "waybar").Run()
	time.Sleep(300 * time.Millisecond)
	if c != nil && c.Spawn([]string{"waybar"}) == nil {
		return
	}
	startDetached([]string{"waybar"})
}
