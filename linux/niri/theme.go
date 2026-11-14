package niri

import (
	"bytes"
	"fmt"
	"os"
	"path/filepath"

	"ember/ui"
)

// ThemeFile is the niri settings file Ember writes for its palette; ember.kdl
// includes it, and niri reloads it by itself whenever Ember rewrites it.
const ThemeFile = "ember-theme.kdl"

func hex(c ui.Color) string { return fmt.Sprintf("#%02x%02x%02x", c.R(), c.G(), c.B()) }

func hexA(c ui.Color, a float32) string {
	return fmt.Sprintf("#%02x%02x%02x%02x", c.R(), c.G(), c.B(), int(a*255+0.5))
}

// ThemeKDL returns niri's colors for one of Ember's palettes: the backdrop
// between and behind windows, the focus ring around the active window, the
// shadows and the overview, so niri and Ember look like one desktop.
func ThemeKDL(th *ui.Theme) string {
	bg, top := th.G5, th.G3
	if th.Grad != nil && len(th.Grad) >= 3 {
		bg, top = th.Grad[1], th.Grad[0]
	}
	inactive := ui.Mix(th.Body, bg, 0.6)
	shadow := 0.28
	if th.Dark {
		shadow = 0.55
	}
	var b bytes.Buffer
	fmt.Fprintf(&b, "// Written by Ember for the %s theme. Ember rewrites this file when you\n", th.Label)
	b.WriteString("// pick another theme, so edit ember.kdl or config.kdl instead.\n\n")
	b.WriteString("layout {\n")
	fmt.Fprintf(&b, "    background-color %q\n", hex(bg))
	b.WriteString("    focus-ring {\n        width 3\n")
	fmt.Fprintf(&b, "        active-gradient from=%q to=%q angle=135\n", hex(th.Deep), hex(th.Deep2))
	fmt.Fprintf(&b, "        inactive-color %q\n    }\n", hex(inactive))
	b.WriteString("    border {\n        off\n")
	fmt.Fprintf(&b, "        urgent-color %q\n    }\n", hex(th.Danger))
	b.WriteString("    shadow {\n        on\n        softness 30\n        spread 4\n        offset x=0 y=6\n")
	fmt.Fprintf(&b, "        color %q\n    }\n", hexA(th.Shadow, float32(shadow)))
	b.WriteString("}\n\n")
	fmt.Fprintf(&b, "overview {\n    backdrop-color %q\n}\n", hex(top))
	return b.String()
}

// WriteTheme writes the palette's file into niri's config folder, only when
// it changed (each write makes niri reload its settings).
func WriteTheme(dir string, th *ui.Theme) error {
	p := filepath.Join(dir, ThemeFile)
	want := []byte(ThemeKDL(th))
	if old, err := os.ReadFile(p); err == nil && bytes.Equal(old, want) {
		return nil
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	tmp := p + ".tmp"
	if err := os.WriteFile(tmp, want, 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, p)
}

// ConfigDir is niri's config folder.
func ConfigDir() string {
	if d := os.Getenv("XDG_CONFIG_HOME"); d != "" {
		return filepath.Join(d, "niri")
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".config", "niri")
}
