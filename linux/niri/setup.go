package niri

import (
	"bytes"
	_ "embed"
	"errors"
	"os"
	"path/filepath"

	"ember/ui"
)

// EmberKDL is Ember's niri settings: start at sign-in, Super+D, the
// full-screen window rule, and the include of the theme colors.
//
//go:embed ember.kdl
var EmberKDL []byte

// Include is the line config.kdl needs (niri 25.11 or newer).
const Include = `include "ember.kdl"`

// SetupResult says what Setup did.
type SetupResult struct {
	Added  bool   // the include line was added to config.kdl
	Backup string // where the old config.kdl was copied first
}

// ErrNoConfig: niri writes its config on first start; Setup runs after that.
var ErrNoConfig = errors.New("niri has no config.kdl yet: start niri once, then run ember --setup-niri")

// Setup puts ember.kdl and ember-theme.kdl into niri's config folder and adds
// the include line at the end of config.kdl (once, after a backup). niri
// reloads its settings by itself.
func Setup(dir string, th *ui.Theme) (SetupResult, error) {
	var res SetupResult
	cfg := filepath.Join(dir, "config.kdl")
	old, err := os.ReadFile(cfg)
	if err != nil {
		return res, ErrNoConfig
	}
	// the theme file first: ember.kdl includes it
	if err := WriteTheme(dir, th); err != nil {
		return res, err
	}
	if err := writeIfChanged(filepath.Join(dir, "ember.kdl"), EmberKDL); err != nil {
		return res, err
	}
	if HasInclude(old) {
		return res, nil
	}
	res.Backup = cfg + ".before-ember"
	if err := os.WriteFile(res.Backup, old, 0o644); err != nil {
		return res, err
	}
	out := append(bytes.TrimRight(old, "\n"), []byte("\n\n"+Include+"\n")...)
	if err := writeIfChanged(cfg, out); err != nil {
		return res, err
	}
	res.Added = true
	return res, nil
}

// HasInclude reports whether config.kdl already includes ember.kdl.
func HasInclude(cfg []byte) bool {
	for _, l := range bytes.Split(cfg, []byte("\n")) {
		if string(bytes.TrimSpace(l)) == Include {
			return true
		}
	}
	return false
}

// Remove takes Ember out of niri's config again.
func Remove(dir string) error {
	cfg := filepath.Join(dir, "config.kdl")
	if b, err := os.ReadFile(cfg); err == nil && HasInclude(b) {
		var out [][]byte
		for _, l := range bytes.Split(b, []byte("\n")) {
			if string(bytes.TrimSpace(l)) != Include {
				out = append(out, l)
			}
		}
		if err := writeIfChanged(cfg, bytes.Join(out, []byte("\n"))); err != nil {
			return err
		}
	}
	os.Remove(filepath.Join(dir, "ember.kdl"))
	os.Remove(filepath.Join(dir, ThemeFile))
	return nil
}

func writeIfChanged(p string, b []byte) error {
	if old, err := os.ReadFile(p); err == nil && bytes.Equal(old, b) {
		return nil
	}
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		return err
	}
	tmp := p + ".tmp"
	if err := os.WriteFile(tmp, b, 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, p)
}
