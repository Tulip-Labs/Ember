package bar

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"ember/ui"
)

func TestConfigIsJSON(t *testing.T) {
	c := strings.TrimPrefix(Config(), Mark)
	var v map[string]any
	if err := json.Unmarshal([]byte(c), &v); err != nil {
		t.Fatal(err)
	}
	if v["layer"] != "top" {
		t.Fatal("layer")
	}
}

func TestStyle(t *testing.T) {
	for _, th := range ui.Themes {
		s := Style(th)
		if strings.Count(s, "{") != strings.Count(s, "}") || strings.ContainsAny(strings.ReplaceAll(s, "INK", ""), "§") {
			t.Fatal(th.ID)
		}
		for _, w := range []string{"DEEP", "GTOP", "GBOTTOM", "RIM", "SHINE", "SHADE", "INK", "SHADOW", "HTOP", "HBOTTOM", "DANGER", "LABEL"} {
			if strings.Contains(s, w) {
				t.Fatalf("%s: %s left in the style", th.ID, w)
			}
		}
	}
}

func TestSetupAndRemove(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("XDG_DATA_HOME", t.TempDir())
	os.WriteFile(filepath.Join(dir, "config"), []byte("theirs"), 0o644)
	os.WriteFile(filepath.Join(dir, "style.css"), []byte("their style"), 0o644)
	if err := Setup(dir, ui.ThemeByID("lagoon")); err != nil {
		t.Fatal(err)
	}
	if !Installed(dir) {
		t.Fatal("not installed")
	}
	if b, _ := os.ReadFile(filepath.Join(dir, "config.before-ember")); string(b) != "theirs" {
		t.Fatal("their config was not kept")
	}
	if _, err := os.Stat(filepath.Join(dir, "config")); err == nil {
		t.Fatal("their config is still read by Waybar")
	}
	if ok, err := Restyle(dir, ui.ThemeByID("night")); !ok || err != nil {
		t.Fatal("restyle", err)
	}
	if err := Setup(dir, ui.ThemeByID("night")); err != nil { // twice: their copies stay
		t.Fatal(err)
	}
	if b, _ := os.ReadFile(filepath.Join(dir, "style.css.before-ember")); string(b) != "their style" {
		t.Fatal("their style was replaced by ours")
	}
	if err := Remove(dir); err != nil {
		t.Fatal(err)
	}
	if b, _ := os.ReadFile(filepath.Join(dir, "config")); string(b) != "theirs" {
		t.Fatal("their config is not back")
	}
	if b, _ := os.ReadFile(filepath.Join(dir, "style.css")); string(b) != "their style" {
		t.Fatal("their style is not back")
	}
	if Installed(dir) {
		t.Fatal("still installed")
	}
}
