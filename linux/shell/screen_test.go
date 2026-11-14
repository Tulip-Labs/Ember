package shell

import (
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"

	"ember/apps"
	"ember/niri"
	"ember/raster"
	"ember/sysinfo"
	"ember/ui"
)

type fakeHost struct {
	launched []string
	focused  []uint64
	closed   []uint64
	ran      [][]string
	hidden   []string
	power    []string
	hides    int
	theme    string
}

func (h *fakeHost) Launch(a apps.App) error {
	if a.Name == "Broken" {
		return errors.New("not found")
	}
	h.launched = append(h.launched, a.Name)
	return nil
}
func (h *fakeHost) FocusWindow(id uint64) error { h.focused = append(h.focused, id); return nil }
func (h *fakeHost) CloseWindow(id uint64) error { h.closed = append(h.closed, id); return nil }
func (h *fakeHost) Run(argv ...string) error    { h.ran = append(h.ran, argv); return nil }
func (h *fakeHost) Hide()                       { h.hides++ }
func (h *fakeHost) Power(p PowerItem) error     { h.power = append(h.power, p.ID); return nil }
func (h *fakeHost) SaveHidden(ids []string)     { h.hidden = ids }
func (h *fakeHost) SaveTheme(id string)         { h.theme = id }

var names = []string{"Archivos", "Blender", "Calculator", "Discord", "Firefox", "foot", "GIMP", "Inkscape",
	"Kdenlive", "Krita", "Lite Go", "LibreOffice Writer", "LibreOffice Calc", "Obsidian", "OBS Studio",
	"Spotify", "Steam", "Text Editor", "Thunderbird", "VLC media player", "Visual Studio Code", "Zed"}

func sample(t *testing.T) (*Screen, *fakeHost) {
	h := &fakeHost{}
	s := New(h)
	var list []apps.App
	for _, n := range names {
		list = append(list, apps.App{ID: n + ".desktop", Name: n, Exec: []string{"true"}})
	}
	s.SetApps(list, []string{"Steam.desktop"})
	s.Now = time.Date(2026, 11, 14, 9, 41, 0, 0, time.UTC)
	s.Stats = sysinfo.Stats{CPU: 23, MemUsedGB: 5.4, MemTotGB: 15.5, DiskFreeGB: 182, DiskTotGB: 476, Battery: 76,
		OwnMB: 21.4, Net: sysinfo.Net{State: 1, Name: "Tulip Labs", Signal: 82, HasWifi: true}}
	s.Niri = true
	s.Wins = []niri.Window{
		{ID: 3, Title: "Lite Go", AppID: "litego", Focused: true},
		{ID: 5, Title: "~/repo/ember — foot", AppID: "foot"},
		{ID: 9, Title: "Spotify Premium", AppID: "spotify", Urgent: true},
	}
	return s, h
}

var fonts = raster.NewFonts()

func shot(t *testing.T, s *Screen, w, h int, name string) *raster.Canvas {
	t.Helper()
	dir := os.Getenv("EMBER_SHOTS")
	if dir != "" && name != "" {
		// the pictures are drawn at twice the size, like a HiDPI screen
		c := raster.New(w, h, 2, fonts)
		s.Frame(c, float32(w), float32(h))
		os.MkdirAll(dir, 0o755)
		if err := c.SavePNG(filepath.Join(dir, name+".png")); err != nil {
			t.Fatal(err)
		}
		return c
	}
	c := raster.New(w, h, 1, fonts)
	s.Frame(c, float32(w), float32(h))
	if false {
		os.MkdirAll(dir, 0o755)
		if err := c.SavePNG(filepath.Join(dir, name+".png")); err != nil {
			t.Fatal(err)
		}
	}
	return c
}

func at(s *Screen, x, y float32) {
	s.In.MX, s.In.MY = x, y
}

func click(t *testing.T, s *Screen, x, y float32, w, h int) {
	at(s, x, y)
	s.In.Pressed, s.In.Down = true, true
	shot(t, s, w, h, "")
	s.In.Released, s.In.Down = true, false
	shot(t, s, w, h, "")
}

func TestScreens(t *testing.T) {
	s, _ := sample(t)
	shot(t, s, 1440, 900, "ember")
	if v := s.Visible(); len(v) != len(names)-1 {
		t.Fatalf("hidden app shown: %d tiles", len(v))
	}
	s.In.Typed = "li"
	shot(t, s, 1440, 900, "ember-search")
	if v := s.Visible(); len(v) < 3 || v[0] != "LibreOffice Writer" && v[0] != "Lite Go" && v[0] != "LibreOffice Calc" {
		t.Fatalf("search: %q", v)
	}
	s.Reset()
	at(s, 1440-48-26, 900-46)
	s.In.Pressed, s.In.Down = true, true
	shot(t, s, 1440, 900, "")
	s.In.Released, s.In.Down = true, false
	shot(t, s, 1440, 900, "")
	shot(t, s, 1440, 900, "ember-power")
	s2, _ := sample(t)
	s2.Stats.Battery = -1
	s2.Stats.Net = sysinfo.Net{State: 2, Name: "enp3s0"}
	shot(t, s2, 1024, 640, "ember-small")
	s2.In.Typed = "hidden"
	shot(t, s2, 1024, 640, "ember-hidden")
	if v := s2.Visible(); len(v) != 1 || v[0] != "Steam" {
		t.Fatalf("hidden mode: %q", v)
	}
}

func TestLaunchAndKeys(t *testing.T) {
	s, h := sample(t)
	l := s.layout(1440, 900)
	r := l.tile(0)
	click(t, s, r.CX(), r.CY(), 1440, 900)
	if len(h.launched) != 1 || h.launched[0] != "Archivos" || h.hides != 1 {
		t.Fatalf("click: %v hides=%d", h.launched, h.hides)
	}
	s.In.Typed = "fire"
	shot(t, s, 1440, 900, "")
	s.In.Keys = []ui.KeyPress{{Key: ui.KEnter}}
	shot(t, s, 1440, 900, "")
	if h.launched[len(h.launched)-1] != "Firefox" {
		t.Fatalf("enter: %v", h.launched)
	}
	s.In.Keys = []ui.KeyPress{{Key: ui.KEscape}}
	shot(t, s, 1440, 900, "")
	if s.Filter() != "" {
		t.Fatalf("escape kept %q", s.Filter())
	}
	s.In.Keys = []ui.KeyPress{{Key: ui.KEscape}}
	shot(t, s, 1440, 900, "")
	if h.hides != 3 {
		t.Fatalf("escape on an empty search hides: %d", h.hides)
	}
	// right-click hides an app
	at(s, r.CX(), r.CY())
	s.In.RightPressed = true
	shot(t, s, 1440, 900, "")
	if len(h.hidden) != 2 {
		t.Fatalf("hidden: %v", h.hidden)
	}
	// keyboard selection
	s.In.Keys = []ui.KeyPress{{Key: ui.KDown}, {Key: ui.KRight}, {Key: ui.KEnter}}
	shot(t, s, 1440, 900, "")
	want := s.Visible()[1]
	if got := h.launched[len(h.launched)-1]; got != want {
		t.Fatalf("keyboard launched %q, want %q", got, want)
	}
}

func TestWindowsRow(t *testing.T) {
	s, h := sample(t)
	l := s.layout(1440, 900)
	// the first window pill sits after the heading
	c := raster.New(1440, 900, 1, fonts)
	s.Frame(c, 1440, 900)
	x := l.wins.X + 60 + c.Measure("10 windows", ui.Font{Size: 15, Bold: true}) + 18 + 20
	click(t, s, x, l.wins.CY(), 1440, 900)
	if len(h.focused) != 1 || h.focused[0] != 3 {
		t.Fatalf("focus: %v", h.focused)
	}
	at(s, x, l.wins.CY())
	s.In.RightPressed = true
	shot(t, s, 1440, 900, "")
	if len(h.closed) != 1 || h.closed[0] != 3 {
		t.Fatalf("close: %v", h.closed)
	}
}

func TestThemes(t *testing.T) {
	s, h := sample(t)
	if s.Th.ID != "lagoon" {
		t.Fatalf("default theme %s", s.Th.ID)
	}
	s.SetTheme("spring") // removed: falls back to Lagoon
	if s.Th.ID != "lagoon" {
		t.Fatalf("spring kept: %s", s.Th.ID)
	}
	for _, id := range []string{"peach", "night", "crocus"} {
		s.SetTheme(id)
		shot(t, s, 1440, 900, "ember-"+id)
	}
	// clicking a dot switches the palette and keeps the choice
	l := s.layout(1440, 900)
	n := len(Themes)
	x := l.files.X - 18 - float32(n)*26 + 8
	click(t, s, x+1*26+9, l.strip.CY(), 1440, 900)
	if s.Th.ID != Themes[1].ID || h.theme != Themes[1].ID {
		t.Fatalf("theme %s, saved %q", s.Th.ID, h.theme)
	}
}
