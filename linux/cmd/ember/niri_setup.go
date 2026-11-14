package main

import (
	"fmt"
	"os"
	"path/filepath"

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
