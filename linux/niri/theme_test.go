package niri

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"ember/ui"
)

func TestThemeKDL(t *testing.T) {
	for _, th := range ui.Themes {
		k := ThemeKDL(th)
		if strings.Count(k, "{") != strings.Count(k, "}") || !strings.Contains(k, "background-color \"#") {
			t.Fatalf("%s:\n%s", th.ID, k)
		}
	}
	dir := t.TempDir()
	if err := WriteTheme(dir, ui.ThemeByID("liquid")); err != nil {
		t.Fatal(err)
	}
	b, _ := os.ReadFile(filepath.Join(dir, ThemeFile))
	if !strings.Contains(string(b), "Liquid") {
		t.Fatal(string(b))
	}
	if os.Getenv("SHOW") != "" {
		t.Log("\n" + string(b))
	}
}

func TestSetup(t *testing.T) {
	dir := t.TempDir()
	th := ui.ThemeByID("liquid")
	if _, err := Setup(dir, th); err != ErrNoConfig {
		t.Fatalf("no config: %v", err)
	}
	os.WriteFile(filepath.Join(dir, "config.kdl"), []byte("input {\n}\n"), 0o644)
	res, err := Setup(dir, th)
	if err != nil || !res.Added {
		t.Fatalf("setup: %+v %v", res, err)
	}
	b, _ := os.ReadFile(filepath.Join(dir, "config.kdl"))
	if string(b) != "input {\n}\n\n"+Include+"\n" {
		t.Fatalf("config: %q", b)
	}
	if res, _ := Setup(dir, th); res.Added {
		t.Fatal("added twice")
	}
	for _, f := range []string{"ember.kdl", ThemeFile, "config.kdl.before-ember"} {
		if _, err := os.Stat(filepath.Join(dir, f)); err != nil {
			t.Fatal(err)
		}
	}
	Remove(dir)
	b, _ = os.ReadFile(filepath.Join(dir, "config.kdl"))
	if HasInclude(b) {
		t.Fatalf("still included: %q", b)
	}
}

func TestBar(t *testing.T) {
	dir := t.TempDir()
	cfg := "input {\n}\n\nspawn-at-startup \"waybar\"\n    spawn-sh-at-startup \"waybar -c x\"\nspawn-at-startup \"mako\"\n"
	os.WriteFile(filepath.Join(dir, "config.kdl"), []byte(cfg), 0o644)
	if ok, err := HideBar(dir); !ok || err != nil {
		t.Fatal(ok, err)
	}
	b, _ := os.ReadFile(filepath.Join(dir, "config.kdl"))
	if !strings.Contains(string(b), "// hidden by Ember: spawn-at-startup \"waybar\"") || !strings.Contains(string(b), "    // hidden by Ember: spawn-sh-at-startup") || !strings.Contains(string(b), "\nspawn-at-startup \"mako\"") {
		t.Fatalf("hidden: %q", b)
	}
	if !BarHidden(dir) {
		t.Fatal("not reported hidden")
	}
	if ok, _ := HideBar(dir); ok {
		t.Fatal("hid twice")
	}
	ShowBar(dir)
	b, _ = os.ReadFile(filepath.Join(dir, "config.kdl"))
	if string(b) != cfg {
		t.Fatalf("not restored: %q", b)
	}
}
