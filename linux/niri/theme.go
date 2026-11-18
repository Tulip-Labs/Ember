package niri

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"

	"ember/ui"
)

// ThemeFile is the niri settings file Ember writes for its palette; ember.kdl
// includes it, and niri reloads it by itself whenever Ember rewrites it.
const ThemeFile = "ember-theme.kdl"

func hex(c ui.Color) string { return fmt.Sprintf("#%02x%02x%02x", c.R(), c.G(), c.B()) }

func hexA(c ui.Color, a float32) string {
	return fmt.Sprintf("#%02x%02x%02x%02x", c.R(), c.G(), c.B(), int(a*255+0.5))
}

// ThemeKDL returns niri's settings for one of Ember's palettes, for the
// installed niri (blur needs niri 26.04 or newer).
func ThemeKDL(th *ui.Theme) string { return ThemeKDLFor(th, HasBlur()) }

// ThemeKDLFor returns niri's settings for a palette: the backdrop between and
// behind windows, a clear glass focus ring, rounded and slightly see-through
// windows (frosted with blur when niri can), shadows and the overview, so
// niri and Ember look like one desktop of liquid glass.
func ThemeKDLFor(th *ui.Theme, blur bool) string {
	bg, top := th.G5, th.G3
	if th.Grad != nil && len(th.Grad) >= 3 {
		bg, top = th.Grad[1], th.Grad[0]
	}
	// glass: white light on dark themes, smoked glass on light ones
	glass, shadow := ui.Hex("#1d1d1f"), 0.22
	ringFrom, ringTo := float32(0.55), float32(0.22)
	if th.Dark {
		glass, shadow = ui.White, 0.55
		ringFrom, ringTo = 0.62, 0.20
	}
	var b bytes.Buffer
	fmt.Fprintf(&b, "// Written by Ember for the %s theme. Ember rewrites this file when you\n", th.Label)
	b.WriteString("// pick another theme, so edit ember.kdl or config.kdl instead.\n\n")
	b.WriteString("layout {\n")
	fmt.Fprintf(&b, "    background-color %q\n", hex(bg))
	b.WriteString("    focus-ring {\n        width 2\n")
	fmt.Fprintf(&b, "        active-gradient from=%q to=%q angle=160\n", hexA(glass, ringFrom), hexA(glass, ringTo))
	fmt.Fprintf(&b, "        inactive-color %q\n    }\n", hexA(glass, 0.10))
	b.WriteString("    border {\n        off\n")
	fmt.Fprintf(&b, "        urgent-color %q\n    }\n", hexA(glass, 0.85))
	b.WriteString("    shadow {\n        on\n        softness 40\n        spread 2\n        offset x=0 y=10\n")
	fmt.Fprintf(&b, "        color %q\n    }\n", hexA(th.Shadow, float32(shadow)))
	b.WriteString("}\n\n")
	fmt.Fprintf(&b, "overview {\n    backdrop-color %q\n}\n\n", hex(top))
	// every window but Ember's own: rounded glass, clearer when not in use
	b.WriteString("window-rule {\n    exclude app-id=\"^ember$\"\n")
	b.WriteString("    geometry-corner-radius 18\n    clip-to-geometry true\n    opacity 0.96\n")
	if blur {
		b.WriteString("    background-effect {\n        blur true\n    }\n")
	}
	b.WriteString("}\n\n")
	b.WriteString("window-rule {\n    exclude app-id=\"^ember$\"\n    match is-active=false\n    opacity 0.88\n}\n")
	return b.String()
}

var niriVer = regexp.MustCompile(`(\d+)\.(\d+)`)

// HasBlur reports whether the installed niri blurs behind windows (26.04+).
func HasBlur() bool {
	out, err := exec.Command("niri", "--version").Output()
	if err != nil {
		return false
	}
	return blurIn(string(out))
}

func blurIn(version string) bool {
	m := niriVer.FindStringSubmatch(version)
	if m == nil {
		return false
	}
	maj, _ := strconv.Atoi(m[1])
	mi, _ := strconv.Atoi(m[2])
	return maj > 26 || (maj == 26 && mi >= 4)
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
