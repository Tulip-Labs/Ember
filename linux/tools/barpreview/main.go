// barpreview writes the Ember bar's Waybar files for one theme, and prints
// the color behind the bar, for the screenshots the CI takes:
//
//	go run ./tools/barpreview <dir> <theme>
package main

import (
	"fmt"
	"os"
	"path/filepath"

	"ember/bar"
	"ember/shell"
)

func main() {
	dir, id := os.Args[1], os.Args[2]
	th := shell.ThemeByID(id)
	os.MkdirAll(dir, 0o755)
	os.WriteFile(filepath.Join(dir, "config.jsonc"), []byte(bar.Config()), 0o644)
	os.WriteFile(filepath.Join(dir, "style.css"), []byte(bar.Style(th)), 0o644)
	bg := th.G5
	if th.Grad != nil {
		bg = th.Grad[1]
	}
	fmt.Printf("#%02x%02x%02x\n", bg.R(), bg.G(), bg.B())
}
