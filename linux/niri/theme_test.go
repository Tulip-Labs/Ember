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
	if err := WriteTheme(dir, ui.ThemeByID("lagoon")); err != nil {
		t.Fatal(err)
	}
	b, _ := os.ReadFile(filepath.Join(dir, ThemeFile))
	if !strings.Contains(string(b), "Lagoon") {
		t.Fatal(string(b))
	}
	if os.Getenv("SHOW") != "" {
		t.Log("\n" + string(b))
	}
}
