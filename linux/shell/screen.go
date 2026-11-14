// Package shell is Ember's full-screen launcher: the dashboard, the open
// windows and the app grid, drawn immediate-mode on ui.Gfx. The same code
// draws the Gio window and the test screenshots.
package shell

import (
	"fmt"
	"sort"
	"strings"
	"time"
	"unicode"

	"ember/apps"
	"ember/niri"
	"ember/sysinfo"
	"ember/ui"
)

// Host does what the screen asks for.
type Host interface {
	Launch(a apps.App) error
	FocusWindow(id uint64) error
	CloseWindow(id uint64) error
	Run(argv ...string) error // a helper program (file manager, terminal, power)
	Hide()
	Power(p PowerItem) error
	SaveHidden(ids []string)
	SaveTheme(id string)
	// SetUpdates turns the automatic updates on or off; UpdateNow does what
	// the update notice offers (install a downloaded package, or restart
	// into the new version).
	SetUpdates(on bool)
	UpdateNow()
	// SetBrightness sets the screen's backlight, 1..100 percent.
	SetBrightness(percent int)
}

// PowerItem is one row of the power panel.
type PowerItem struct {
	Glyph Glyph
	Label string
	ID    string
}

// Power lists the panel's rows; a separator follows the first five.
var Power = []PowerItem{
	{GLock, "Lock", "lock"},
	{GMoon, "Sleep", "sleep"},
	{GSignOut, "Sign out", "signout"},
	{GRestart, "Restart", "restart"},
	{GPower, "Shut down", "poweroff"},
	{GScreenOff, "Turn the screens off", "screensoff"},
	{GDownload, "Automatic updates", "updates"},
	{GExit, "Exit Ember", "exit"},
}

const powerSep = 5

// Screen is Ember's state between frames.
type Screen struct {
	Host   Host
	Th     *ui.Theme
	In     *ui.Input
	St     ui.State
	Now    time.Time
	Stats  sysinfo.Stats
	Niri   bool          // windows come from niri (the row is shown even when empty)
	Wins   []niri.Window // the open windows, Ember's own left out
	Redraw bool
	// Updates: whether they are on, and a notice with its button (empty
	// when there is nothing to say)
	UpdatesOn    bool
	Notice       string
	NoticeAction string

	apps   []apps.App
	hidden map[string]bool
	vis    []int // indices into apps of the tiles shown
	filter []rune
	scroll int
	sel    int
	keynav bool
	panel  bool
	wheel  float32
	// brightness: dragging the slider, and until when the reading waits
	dragBright bool
	brightHold float64
	toast      string
	toastT     float64
	u          ui.Ui
}

// DefaultTheme is the palette Ember starts in.
const DefaultTheme = "lagoon"

// Themes are Lite Go's palettes that Ember offers (all but Spring Mix).
var Themes = func() []*ui.Theme {
	var out []*ui.Theme
	for _, t := range ui.Themes {
		if t.ID != "spring" {
			out = append(out, t)
		}
	}
	return out
}()

// ThemeByID returns one of Ember's palettes, or Lagoon for an unknown id.
func ThemeByID(id string) *ui.Theme {
	for _, t := range Themes {
		if t.ID == id {
			return t
		}
	}
	return ui.ThemeByID(DefaultTheme)
}

// New returns a screen in the Lagoon palette (SetTheme picks another).
func New(h Host) *Screen {
	return &Screen{Host: h, Th: ThemeByID(DefaultTheme), In: ui.NewInput(), hidden: map[string]bool{}, sel: -1}
}

// SetApps replaces the app list (after a scan) and the hidden set.
func (s *Screen) SetApps(list []apps.App, hidden []string) {
	s.apps = list
	s.hidden = map[string]bool{}
	for _, h := range hidden {
		s.hidden[h] = true
	}
	s.rebuild()
}

// SetTheme picks one of Lite Go's palettes by id.
func (s *Screen) SetTheme(id string) {
	s.Th = ThemeByID(id) // an unknown or old choice (Spring Mix) falls back to Lagoon
}

// Apps returns the app list.
func (s *Screen) Apps() []apps.App { return s.apps }

// Reset puts the screen back as it opens: no search, at the top.
func (s *Screen) Reset() {
	s.filter, s.scroll, s.sel, s.keynav, s.panel = nil, 0, -1, false, false
	s.rebuild()
}

// OpenPower opens the power panel (ember --power, the bar's Power button).
func (s *Screen) OpenPower() { s.panel = true }

// Toast shows a short note in the footer.
func (s *Screen) Toast(t string) { s.toast, s.toastT = t, s.In.Now+4 }

func (s *Screen) hiddenMode() bool {
	return strings.EqualFold(strings.TrimSpace(string(s.filter)), "hidden")
}

func (s *Screen) rebuild() {
	s.vis = s.vis[:0]
	q := string(s.filter)
	if s.hiddenMode() {
		for i, a := range s.apps {
			if s.hidden[a.ID] {
				s.vis = append(s.vis, i)
			}
		}
		return
	}
	// names that start with the search first, then the other matches
	for pass := 2; pass >= 1; pass-- {
		for i, a := range s.apps {
			if s.hidden[a.ID] {
				continue
			}
			if m := a.Matches(q); m == pass || (q == "" && pass == 2) {
				s.vis = append(s.vis, i)
			}
		}
		if q == "" {
			break
		}
	}
	if s.sel >= len(s.vis) {
		s.sel = len(s.vis) - 1
	}
}

func (s *Screen) toggleHidden(a apps.App) {
	if s.hidden[a.ID] {
		delete(s.hidden, a.ID)
		s.Toast(a.Name + " is back in the list")
	} else {
		s.hidden[a.ID] = true
		s.Toast(a.Name + " is hidden  ·  type \"hidden\" to see it")
	}
	ids := make([]string, 0, len(s.hidden))
	for id := range s.hidden {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	s.Host.SaveHidden(ids)
	s.rebuild()
}

// ---- layout (logical pixels; the same numbers as the Windows version) ----

type layout struct {
	w, h, mg                          float32
	dash, strip, wins, grid           ui.Rect
	cols, rows                        int
	clock                             ui.Rect
	stats                             []ui.Rect
	files, term, power, panel, winsIn ui.Rect
}

const (
	dashY, dashH   = 32, 132
	stripH         = 58
	winsH          = 52
	tileH, tilePit = 64, 78
)

func (s *Screen) layout(w, h float32) layout {
	l := layout{w: w, h: h, mg: 48}
	if w < 1100 {
		l.mg = 28
	}
	total := w - 2*l.mg
	n := len(s.cards())
	gap := float32(14)
	cw := min(max(total*0.28, 260), 500)
	if each := (total - cw - 16 - float32(n-1)*gap) / float32(n); each < 118 {
		cw = max(200, total-16-float32(n)*118-float32(n-1)*gap)
	}
	l.clock = ui.Rect{X: l.mg, Y: dashY, W: cw, H: dashH}
	x0 := l.clock.R() + 16
	each := max(60, (w-l.mg-x0-float32(n-1)*gap)/float32(n))
	for i := 0; i < n; i++ {
		l.stats = append(l.stats, ui.Rect{X: x0 + float32(i)*(each+gap), Y: dashY, W: each, H: dashH})
	}
	y := float32(dashY + dashH + 18)
	l.strip = ui.Rect{X: l.mg, Y: y, W: total, H: stripH}
	bh := float32(38)
	by := y + (stripH-bh)/2
	l.term = ui.Rect{X: l.strip.R() - 20 - 150, Y: by, W: 150, H: bh}
	l.files = ui.Rect{X: l.term.X - 12 - 130, Y: by, W: 130, H: bh}
	y += stripH
	if s.Niri {
		y += 14
		l.wins = ui.Rect{X: l.mg, Y: y, W: total, H: winsH}
		y += winsH
	}
	y += 22
	l.cols = min(6, max(2, int(total/290)))
	l.rows = max(1, int((h-y-80+tilePit-tileH)/tilePit))
	l.grid = ui.Rect{X: l.mg, Y: y, W: total, H: float32(l.rows) * tilePit}
	l.power = ui.RectAround(w-l.mg-26, h-46, 48, 48)
	ph := float32(len(Power))*46 + 30
	l.panel = ui.Rect{X: w - l.mg - 300, Y: l.power.Y - 14 - ph, W: 300, H: ph}
	return l
}

func (l layout) tile(d int) ui.Rect {
	cell := l.grid.W / float32(l.cols)
	return ui.Rect{X: l.grid.X + float32(d%l.cols)*cell, Y: l.grid.Y + float32(d/l.cols)*tilePit, W: cell - 16, H: tileH}
}

func (l layout) powerRow(i int) ui.Rect {
	y := l.panel.Y + 15 + float32(i)*46
	return ui.Rect{X: l.panel.X + 10, Y: y, W: l.panel.W - 20, H: 42}
}

func (s *Screen) maxScroll(l layout) int {
	rows := (len(s.vis) + l.cols - 1) / l.cols
	return max(0, rows-l.rows)
}

// ---- input ----

func (s *Screen) keys(l layout) {
	in := s.In
	if in.Typed != "" {
		for _, r := range in.Typed {
			if unicode.IsPrint(r) && len(s.filter) < 64 {
				if r == ' ' && len(s.filter) == 0 {
					continue
				}
				s.filter = append(s.filter, r)
			}
		}
		s.scroll, s.sel, s.keynav = 0, -1, false
		s.panel = false
		s.rebuild()
	}
	for _, k := range in.Keys {
		switch k.Key {
		case ui.KBackspace:
			if len(s.filter) > 0 {
				if k.Ctrl {
					s.filter = nil
				} else {
					s.filter = s.filter[:len(s.filter)-1]
				}
				s.scroll, s.sel, s.keynav = 0, -1, false
				s.rebuild()
			}
		case ui.KEscape:
			switch {
			case s.panel:
				s.panel = false
			case len(s.filter) > 0:
				s.filter = nil
				s.scroll, s.sel, s.keynav = 0, -1, false
				s.rebuild()
			default:
				s.Host.Hide()
			}
		case ui.KEnter:
			i := 0
			if s.keynav && s.sel >= 0 {
				i = s.sel
			}
			if i < len(s.vis) {
				s.launch(s.apps[s.vis[i]])
			}
		case ui.KLeft:
			s.move(-1, l)
		case ui.KRight, ui.KTab:
			s.move(1, l)
		case ui.KUp:
			s.move(-l.cols, l)
		case ui.KDown:
			s.move(l.cols, l)
		case ui.KPageDown:
			s.scroll = min(s.maxScroll(l), s.scroll+l.rows)
		case ui.KPageUp:
			s.scroll = max(0, s.scroll-l.rows)
		case ui.KHome:
			s.scroll = 0
		case ui.KEnd:
			s.scroll = s.maxScroll(l)
		}
	}
}

func (s *Screen) move(d int, l layout) {
	if len(s.vis) == 0 {
		return
	}
	if !s.keynav || s.sel < 0 {
		s.keynav, s.sel = true, s.scroll*l.cols
		return
	}
	s.sel = min(len(s.vis)-1, max(0, s.sel+d))
	row := s.sel / l.cols
	if row < s.scroll {
		s.scroll = row
	} else if row >= s.scroll+l.rows {
		s.scroll = row - l.rows + 1
	}
}

func (s *Screen) launch(a apps.App) {
	if err := s.Host.Launch(a); err != nil {
		s.Toast("Could not open " + a.Name + ": " + err.Error())
		return
	}
	s.Host.Hide()
}

// ---- drawing ----

// Frame draws one frame of a w by h screen and handles its input.
func (s *Screen) Frame(g ui.Gfx, w, h float32) {
	s.u = ui.Ui{G: g, In: s.In, Th: s.Th, St: &s.St, W: w, H: h}
	s.u.ResetHit()
	s.Redraw = false
	l := s.layout(w, h)
	s.keys(l)
	if s.In.WheelY != 0 && !s.panel && s.brightWheel(l) {
		// the wheel went to the brightness card
	} else if s.In.WheelY != 0 && !s.panel {
		s.wheel += s.In.WheelY
		for s.wheel >= 1 {
			s.wheel--
			s.scroll--
		}
		for s.wheel <= -1 {
			s.wheel++
			s.scroll++
		}
		s.scroll = min(s.maxScroll(l), max(0, s.scroll))
	}
	s.scroll = min(s.maxScroll(l), max(0, s.scroll))

	s.backdrop(g, w, h)
	s.dashboard(g, l)
	s.strip(g, l)
	if s.Niri {
		s.windows(g, l)
	}
	s.grid(g, l)
	s.footer(g, l)
	if s.panel {
		s.powerPanel(g, l)
	}
	if s.toast != "" && s.In.Now > s.toastT {
		s.toast = ""
	}
	if s.toast != "" {
		s.Redraw = true
	}
	s.u.DrawTooltip()
	s.In.EndFrame()
}

// backdrop is the theme's background, as in Lite Go: the pastel themes merge
// three colors from top to bottom; the others are the Windows version's wash
// of five soft color fields over the theme's base.
func (s *Screen) backdrop(g ui.Gfx, w, h float32) {
	th := s.Th
	if th.Grad != nil {
		ui.FillGradient3(g, ui.Rect{W: w, H: h}, 0, th.Grad)
		return
	}
	g.FillRect(ui.Rect{W: w, H: h}, th.G5)
	pos := [5][2]float32{{0.04, 0.02}, {0.97, 0.03}, {0.55, 0.45}, {0.03, 0.99}, {0.98, 0.98}}
	rad := [5]float32{0.62, 0.58, 0.55, 0.60, 0.62}
	cols := []ui.Color{th.G1, th.G2, th.G3, th.G4, th.G6}
	d := max(w, h)
	for i, p := range pos {
		g.Radial(p[0]*w, p[1]*h, rad[i]*d, rad[i]*d, cols[i].Alpha(0.92))
	}
}

func (s *Screen) card(r ui.Rect, rad float32, strong bool) {
	ui.Glass(s.u.G, r, rad, s.Th, strong, true)
}

func (s *Screen) tints() []ui.Color {
	th := s.Th
	return []ui.Color{th.TBlue, th.TGreen, th.THoney, th.TPink, th.TLav}
}

func (s *Screen) dashboard(g ui.Gfx, l layout) {
	th := s.Th
	c := l.clock
	s.card(c, 24, false)
	date := s.Now.Format("Monday, 2 January")
	g.Text(date, c.X+26, c.Y+34, ui.Font{Size: 17, Bold: true}, th.Ink)
	clock := ui.Font{Size: 54, Bold: true}
	g.Text(s.Now.Format("3:04 PM"), c.X+24, c.Y+92, clock, th.Ink)
	g.Text(fmt.Sprintf("Ember  ·  %.1f MB", s.Stats.OwnMB), c.X+28, c.B()-18, ui.FSmall, th.Ink2)
	for i, r := range l.stats {
		s.stat(g, i, r)
	}
}

func pct(a, b float64) int {
	if b <= 0 {
		return 0
	}
	return int(a*100/b + 0.5)
}

// The dashboard's cards, in order; battery and brightness only where the
// machine has them.
const (
	cardCPU = iota
	cardMemory
	cardNetwork
	cardDisk
	cardBattery
	cardBrightness
)

func (s *Screen) cards() []int {
	c := []int{cardCPU, cardMemory, cardNetwork, cardDisk}
	if s.Stats.Battery >= 0 {
		c = append(c, cardBattery)
	}
	if s.Stats.Brightness >= 0 {
		c = append(c, cardBrightness)
	}
	return c
}

// brightRect is the brightness card, if there is one.
func (s *Screen) brightRect(l layout) (ui.Rect, bool) {
	for i, k := range s.cards() {
		if k == cardBrightness && i < len(l.stats) {
			return l.stats[i], true
		}
	}
	return ui.Rect{}, false
}

// setBright changes the screen brightness (0..100); the host applies it.
func (s *Screen) setBright(p int) {
	p = min(100, max(1, p)) // never fully dark: the screen must stay usable
	if p != s.Stats.Brightness {
		s.Stats.Brightness = p
		s.Host.SetBrightness(p)
	}
	s.brightHold = s.In.Now + 1.5 // the reading catches up after a moment
}

func (s *Screen) brightWheel(l layout) bool {
	r, ok := s.brightRect(l)
	if !ok || !s.u.Over(r) {
		return false
	}
	step := 5
	if s.In.WheelY < 0 {
		step = -5
	}
	s.setBright(s.Stats.Brightness + step)
	return true
}

// SetStats takes a new reading, keeping the brightness the reader is setting.
func (s *Screen) SetStats(st sysinfo.Stats) {
	if s.In.Now < s.brightHold || s.dragBright {
		st.Brightness = s.Stats.Brightness
	}
	s.Stats = st
}

func (s *Screen) stat(g ui.Gfx, i int, r ui.Rect) {
	th, st := s.Th, s.Stats
	s.card(r, 24, false)
	kind := s.cards()[i]
	labels := []string{"CPU", "MEMORY", "NETWORK", "DISK", "BATTERY", "BRIGHTNESS"}
	var val, capt string
	var frac float64
	glyph := GCPU
	switch kind {
	case cardBrightness:
		glyph = GSun
		val = fmt.Sprintf("%d%%", st.Brightness)
		capt = "Drag or scroll"
		frac = float64(st.Brightness) / 100
	case cardCPU:
		val, capt, frac = fmt.Sprintf("%d%%", int(st.CPU+0.5)), "Processor load", st.CPU/100
	case cardMemory:
		glyph = GMemory
		val = fmt.Sprintf("%.1f / %.1f GB", st.MemUsedGB, st.MemTotGB)
		capt = fmt.Sprintf("%d%% in use", pct(st.MemUsedGB, st.MemTotGB))
		if st.MemTotGB > 0 {
			frac = st.MemUsedGB / st.MemTotGB
		}
	case cardNetwork:
		n := st.Net
		switch {
		case n.State == 2:
			glyph, val, capt = GEthernet, "Wired", "Connected  ·  "+n.Name
		case n.State == 1:
			glyph, val, capt = GWifi, n.Name, fmt.Sprintf("Signal %d%%", n.Signal)
		case n.HasWifi:
			glyph, val, capt = GWifiOff, "Not connected", "Offline"
		default:
			glyph, val, capt = GEthernet, "No network", "Offline"
		}
		frac = float64(n.Signal) / 100
		if n.State == 2 {
			frac = 1
		}
	case cardDisk:
		glyph = GDisk
		val = fmt.Sprintf("%.0f GB free", st.DiskFreeGB)
		capt = fmt.Sprintf("%d%% used", pct(st.DiskTotGB-st.DiskFreeGB, st.DiskTotGB))
		if st.DiskTotGB > 0 {
			frac = (st.DiskTotGB - st.DiskFreeGB) / st.DiskTotGB
		}
	default:
		glyph = GBattery
		val = fmt.Sprintf("%d%%", st.Battery)
		capt = "On battery"
		if st.Charging {
			capt = "Charging"
		}
		frac = float64(st.Battery) / 100
	}
	const pad, chipR = 16, 17
	ccx, ccy := r.X+pad+chipR, r.Y+pad+chipR
	ui.FillOval(g, ui.RectAround(ccx, ccy, 2*chipR, 2*chipR), s.tints()[kind%5])
	DrawGlyph(g, glyph, ccx, ccy, 20, th.Ink)
	if glyph == GBattery && st.Battery > 0 {
		k := float32(20) / 24
		bx, by := ccx-10, ccy-10
		fill := th.Deep
		if st.Battery <= 15 {
			fill = th.Danger
		}
		ui.FillRound(g, ui.Rect{X: bx + 4.4*k, Y: by + 9.8*k, W: max(2, 12.6*k*float32(st.Battery)/100), H: 5 * k}, 1.2, fill)
	}
	lx := ccx + chipR + 10
	ui.TextFit(g, labels[kind], lx, ui.Mid(g, r.Y+pad, 2*chipR, ui.FSmallBold), ui.FSmallBold, th.Ink2, r.R()-pad-lx)
	ui.TextFit(g, val, r.X+pad, r.Y+78, ui.Font{Size: 18, Bold: true}, th.Ink, r.W-2*pad)
	ui.TextFit(g, capt, r.X+pad, r.Y+98, ui.FSmall, th.Ink2, r.W-2*pad)
	bar := ui.Rect{X: r.X + pad, Y: r.B() - 24, W: r.W - 2*pad, H: 6}
	ui.FillRound(g, bar, 3, th.Body.Alpha(0.15))
	if f := float32(min(1, max(0, frac))); f > 0 {
		ui.FillRound(g, ui.Rect{X: bar.X, Y: bar.Y, W: max(6, bar.W*f), H: bar.H}, 3, th.Deep)
	}
	if kind == cardBrightness {
		s.brightSlider(g, r, bar)
	}
}

// brightSlider makes the brightness card's bar a slider: press anywhere on
// the card's lower half and drag.
func (s *Screen) brightSlider(g ui.Gfx, card, bar ui.Rect) {
	th, in := s.Th, s.In
	hit := ui.Rect{X: card.X, Y: bar.Y - 26, W: card.W, H: card.B() - bar.Y + 26}
	if in.Pressed && s.u.Over(hit) && !s.panel {
		s.dragBright = true
	}
	if s.dragBright {
		if in.Down {
			s.setBright(int((in.MX-bar.X)/bar.W*100 + 0.5))
		} else {
			s.dragBright = false
		}
	}
	f := float32(s.Stats.Brightness) / 100
	kx := bar.X + bar.W*f
	knob := ui.RectAround(kx, bar.CY(), 16, 16)
	if s.u.Hover(hit) || s.dragBright {
		knob = ui.RectAround(kx, bar.CY(), 19, 19)
	}
	ui.FillOval(g, knob, ui.White)
	ui.StrokeOval(g, knob, 2, th.Deep)
}

func (s *Screen) chip(g ui.Gfx, id ui.ID, r ui.Rect, glyph Glyph, label string) bool {
	hot := s.u.Hover(r)
	ui.Glass(g, r, r.H/2, s.Th, hot, false)
	if hot {
		ui.FillRound(g, r, r.H/2, s.Th.Deep.Alpha(0.06))
	}
	DrawGlyph(g, glyph, r.X+26, r.CY(), 18, s.Th.Ink)
	ui.TextFit(g, label, r.X+46, ui.Mid(g, r.Y, r.H, ui.FBodyBold), ui.FBodyBold, s.Th.Ink, r.W-56)
	return s.u.Clickable(id, r)
}

func (s *Screen) strip(g ui.Gfx, l layout) {
	th, st := s.Th, l.strip
	s.card(st, 22, false)
	mid := st.CY()
	ui.FillOval(g, ui.RectAround(st.X+32, mid, 34, 34), th.TLav)
	DrawGlyph(g, GSearch, st.X+32, mid, 18, th.Ink)
	var label string
	n := len(s.vis)
	switch {
	case s.hiddenMode():
		label = fmt.Sprintf("Hidden apps  ·  %d  ·  right-click one to bring it back", n)
	case len(s.filter) > 0:
		word := "results"
		if n == 1 {
			word = "result"
		}
		label = fmt.Sprintf("“%s”  ·  %d %s", string(s.filter), n, word)
	default:
		label = fmt.Sprintf("%d apps  ·  start typing to search", n)
	}
	f := ui.Font{Size: 15, Bold: true}
	dotsX := s.themes(g, l)
	ui.TextFit(g, label, st.X+60, ui.Mid(g, st.Y, st.H, f), f, th.Ink, dotsX-14-st.X-60)
	if len(s.filter) > 0 && !s.hiddenMode() {
		// a caret after the search, so typing reads as typing
		cx := st.X + 60 + g.Measure("“"+string(s.filter), f) + 1
		if cx < dotsX-20 && int(s.In.Now*2)%2 == 0 {
			g.FillRect(ui.Rect{X: cx, Y: mid - 9, W: 1.6, H: 18}, th.Deep)
		}
		s.Redraw = true
	}
	if s.chip(g, ui.Id("files"), l.files, GFolder, "Files") {
		s.runHelper("Files", "xdg-open", "~")
	}
	if s.chip(g, ui.Id("term"), l.term, GTerminal, "Terminal") {
		s.runHelper("Terminal", terminal()...)
	}
}

// themes draws Lite Go's palettes as dots before the Files chip (click one
// to switch; the choice is kept) and returns where the dots start.
func (s *Screen) themes(g ui.Gfx, l layout) float32 {
	const d, gap = 15, 6
	n := len(Themes)
	x := l.files.X - 18 - float32(n)*(d+gap) + gap
	cy := l.strip.CY()
	for i, t := range Themes {
		r := ui.RectAround(x+float32(i)*(d+gap)+d/2, cy, d, d)
		if t.Grad != nil {
			ui.FillGradient3(g, r, d/2, t.Grad)
		} else {
			g.FillPathGradient(ui.NewPath().Ellipse(r), t.G1, t.Deep, r.Y, r.B())
		}
		ui.StrokeOval(g, r, 1, s.Th.Ink.Alpha(0.12))
		if t == s.Th {
			ui.StrokeOval(g, r.Inset(-3.5), 2, s.Th.Ink)
		} else if s.u.Hover(r.Inset(-4)) {
			ui.StrokeOval(g, r.Inset(-3.5), 1.4, s.Th.Ink.Alpha(0.4))
		}
		s.u.Tooltip(t.Label, r)
		if s.u.Clickable(ui.IdN("theme", i), r.Inset(-4)) && t != s.Th {
			s.Th = t
			s.Host.SaveTheme(t.ID)
		}
	}
	return x
}

func terminal() []string {
	t := apps.App{Exec: []string{}, Terminal: true}.Command()
	if len(t) == 0 {
		return []string{"xterm"}
	}
	// the terminal alone, without the "-e" that would precede a command
	if last := t[len(t)-1]; last == "-e" || last == "-x" || last == "--" {
		t = t[:len(t)-1]
	}
	if len(t) > 1 && t[1] == "start" {
		t = t[:1]
	}
	return t
}

func (s *Screen) runHelper(name string, argv ...string) {
	if err := s.Host.Run(argv...); err != nil {
		s.Toast("Could not open " + name + ": " + err.Error())
		return
	}
	s.Host.Hide()
}

// windows is the row of open windows niri manages: click one to go to it,
// right-click to close it.
func (s *Screen) windows(g ui.Gfx, l layout) {
	th, r := s.Th, l.wins
	s.card(r, 22, false)
	ui.FillOval(g, ui.RectAround(r.X+32, r.CY(), 34, 34), th.TBlue)
	DrawGlyph(g, GWindows, r.X+32, r.CY(), 18, th.Ink)
	head := "No open windows"
	if n := len(s.Wins); n == 1 {
		head = "1 window"
	} else if n > 1 {
		head = fmt.Sprintf("%d windows", n)
	}
	f := ui.Font{Size: 15, Bold: true}
	g.Text(head, r.X+60, ui.Mid(g, r.Y, r.H, f), f, th.Ink)
	x := r.X + 60 + max(g.Measure("10 windows", f), g.Measure(head, f)) + 18
	end := r.R() - 12
	for i, w := range s.Wins {
		title := w.Title
		if title == "" {
			title = w.AppID
		}
		pw := min(260, max(150, g.Measure(title, ui.FBodyBold)+64))
		left := len(s.Wins) - i
		if x+pw > end || (left > 1 && x+pw > end-70) {
			if left > 0 && x+56 <= end {
				more := ui.Rect{X: x, Y: r.Y + 8, W: 56, H: r.H - 16}
				ui.FillRound(g, more, more.H/2, th.Body.Alpha(0.08))
				ui.TextCenter(g, fmt.Sprintf("+%d", left), more, ui.FBodyBold, th.Ink2)
			}
			break
		}
		p := ui.Rect{X: x, Y: r.Y + 8, W: pw, H: r.H - 16}
		hot := s.u.Hover(p)
		ui.Glass(g, p, p.H/2, th, hot || w.Focused, false)
		if w.Focused {
			ui.StrokeRound(g, p.Inset(0.8), p.H/2, 1.6, th.Deep.Alpha(0.8))
		}
		badge(g, p.X+20, p.CY(), 13, w.AppID+title, s.tints(), th.Ink, ui.FSmallBold)
		ui.TextFit(g, title, p.X+40, ui.Mid(g, p.Y, p.H, ui.FBodyBold), ui.FBodyBold, th.Ink, p.W-52)
		if w.Urgent {
			ui.FillOval(g, ui.RectAround(p.R()-12, p.Y+8, 7, 7), th.Hl)
		}
		id := ui.IdN("win", int(w.ID))
		if s.u.Clickable(id, p) {
			if err := s.Host.FocusWindow(w.ID); err != nil {
				s.Toast("Could not switch: " + err.Error())
			} else {
				s.Host.Hide()
			}
		}
		if s.In.RightPressed && s.u.Over(p) {
			s.Host.CloseWindow(w.ID)
			s.Toast("Closing " + title)
		}
		x += pw + 10
	}
}

// badge is the letter chip of a tile: the first letter or digit of the name
// on one of the five pastel tints, picked by the name so it never changes.
func badge(g ui.Gfx, cx, cy, r float32, name string, tints []ui.Color, ink ui.Color, f ui.Font) {
	h := uint32(7)
	for _, c := range strings.ToLower(name) {
		h = h*31 + uint32(c)
	}
	ui.FillOval(g, ui.RectAround(cx, cy, 2*r, 2*r), tints[h%5])
	ch := "#"
	for _, c := range name {
		if unicode.IsLetter(c) || unicode.IsDigit(c) {
			ch = string(unicode.ToUpper(c))
			break
		}
	}
	ui.TextCenter(g, ch, ui.RectAround(cx, cy, 2*r, 2*r), f, ink)
}

func (s *Screen) grid(g ui.Gfx, l layout) {
	th := s.Th
	if len(s.vis) == 0 {
		msg := "No apps found"
		if s.hiddenMode() {
			msg = "No hidden apps"
		} else if len(s.filter) > 0 {
			msg = "No apps match “" + string(s.filter) + "”"
		}
		ui.TextCenter(g, msg, ui.Rect{X: l.mg, Y: l.grid.Y, W: l.grid.W, H: 120}, ui.Font{Size: 18, Bold: true}, th.Ink2)
		return
	}
	nf := ui.Font{Size: 15, Bold: true}
	for d := 0; d < l.cols*l.rows; d++ {
		vi := s.scroll*l.cols + d
		if vi >= len(s.vis) {
			break
		}
		a := s.apps[s.vis[vi]]
		r := l.tile(d)
		hot := s.u.Hover(r) && !s.panel
		sel := s.keynav && vi == s.sel
		s.card(r, 20, hot || sel)
		if hot {
			ui.FillRound(g, r, 20, th.Deep.Alpha(0.05))
		}
		badge(g, r.X+32, r.CY(), 19, a.Name, s.tints(), th.Ink, ui.Font{Size: 15, Bold: true})
		ui.TextFit(g, a.Name, r.X+62, ui.Mid(g, r.Y, r.H, nf), nf, th.Ink, r.W-76)
		if sel {
			ui.StrokeRound(g, r.Inset(1.1), 20, 2.2, th.Deep.Alpha(0.92))
		}
		if !s.panel {
			if s.u.Clickable(ui.IdN("tile", s.vis[vi]), r) {
				s.launch(a)
			}
			if s.In.RightPressed && s.u.Over(r) {
				s.toggleHidden(a)
				return
			}
		}
	}
	// a thin scroll indicator when there is more than one screen of apps
	if m := s.maxScroll(l); m > 0 {
		track := ui.Rect{X: l.w - l.mg/2 - 2, Y: l.grid.Y, W: 4, H: l.grid.H - 14}
		ui.FillRound(g, track, 2, th.Body.Alpha(0.10))
		rows := float32(m + l.rows)
		th2 := track.H * float32(l.rows) / rows
		ui.FillRound(g, ui.Rect{X: track.X, Y: track.Y + (track.H-th2)*float32(s.scroll)/float32(m), W: 4, H: th2}, 2, th.Deep.Alpha(0.55))
	}
}

func (s *Screen) footer(g ui.Gfx, l layout) {
	th := s.Th
	fy := l.h - 46
	mark := ui.Font{Size: 26, Bold: true}
	g.Text("Ember", l.mg, fy+9, mark, th.Ink)
	hx := l.mg + g.Measure("Ember", mark) + 18
	if s.toast != "" {
		ui.TextFit(g, s.toast, hx, fy+5, ui.FSmallBold, th.Deep, l.power.X-hx-20)
	} else {
		hint := "Super+D shows or hides  ·  Enter opens the top result  ·  right-click hides an app"
		if s.Niri {
			hint += "  ·  right-click a window to close it"
		}
		ui.TextFit(g, hint, hx, fy+5, ui.FSmall, th.Ink2, l.power.X-hx-20)
	}
	if s.Notice != "" {
		// the update notice, as a chip left of the power button
		f := ui.FSmallBold
		w := g.Measure(s.Notice, f) + 40
		if s.NoticeAction != "" {
			w += g.Measure(s.NoticeAction, f) + 28
		}
		r := ui.Rect{X: l.power.X - 14 - w, Y: l.power.CY() - 19, W: w, H: 38}
		ui.Glass(g, r, 19, th, s.u.Hover(r), false)
		DrawGlyph(g, GDownload, r.X+20, r.CY(), 16, th.Deep)
		g.Text(s.Notice, r.X+34, ui.Mid(g, r.Y, r.H, f), f, th.Ink)
		if s.NoticeAction != "" {
			b := ui.Rect{X: r.R() - g.Measure(s.NoticeAction, f) - 30, Y: r.Y + 5, W: g.Measure(s.NoticeAction, f) + 24, H: r.H - 10}
			ui.FillRound(g, b, b.H/2, th.Deep)
			ui.TextCenter(g, s.NoticeAction, b, f, ui.White)
			if s.u.Clickable(ui.Id("update"), r) {
				s.Host.UpdateNow()
			}
		}
	}
	hot := s.u.Hover(l.power) || s.panel
	ui.Glass(g, l.power, 24, th, hot, true)
	DrawGlyph(g, GPower, l.power.CX(), l.power.CY(), 22, th.Ink)
	if s.u.Clickable(ui.Id("power"), l.power) {
		s.panel = !s.panel
	}
}

func (s *Screen) powerPanel(g ui.Gfx, l layout) {
	th, p := s.Th, l.panel
	ui.Shadow(g, p, 24, th.Shadow, 1.4, 8)
	ui.FillRound(g, p, 24, th.G5)
	ui.Glass(g, p, 24, th, true, false)
	if !th.Dark {
		ui.FillRound(g, p, 24, ui.White.Alpha(0.55))
	}
	for i, it := range Power {
		r := l.powerRow(i)
		hot := s.u.Hover(r)
		if hot {
			ui.FillRound(g, r, 14, th.Deep.Alpha(0.12))
		}
		DrawGlyph(g, it.Glyph, r.X+26, r.CY(), 20, th.Ink)
		f := ui.Font{Size: 15, Bold: true}
		label := it.Label
		if it.ID == "updates" {
			label = "Automatic updates: Off"
			if s.UpdatesOn {
				label = "Automatic updates: On"
			}
		}
		ui.TextFit(g, label, r.X+54, ui.Mid(g, r.Y, r.H, f), f, th.Ink, r.W-62)
		if i == powerSep-1 {
			g.FillRect(ui.Rect{X: p.X + 20, Y: r.B() + 1.5, W: p.W - 40, H: 1}, th.Body.Alpha(0.16))
		}
		if s.u.Clickable(ui.IdN("pwr", i), r) {
			if it.ID == "updates" {
				s.UpdatesOn = !s.UpdatesOn
				s.Host.SetUpdates(s.UpdatesOn)
				continue
			}
			s.panel = false
			if err := s.Host.Power(it); err != nil {
				s.Toast(it.Label + " did not work: " + err.Error())
			}
		}
	}
	// a press outside the panel (and off the power button) closes it
	if s.In.Pressed && !s.u.Over(p) && !s.u.Over(l.power) {
		s.panel = false
	}
}

// Filter returns the current search (for tests).
func (s *Screen) Filter() string { return string(s.filter) }

// Visible returns the names of the tiles that match, in order (for tests).
func (s *Screen) Visible() []string {
	out := make([]string, len(s.vis))
	for i, v := range s.vis {
		out[i] = s.apps[v].Name
	}
	return out
}
