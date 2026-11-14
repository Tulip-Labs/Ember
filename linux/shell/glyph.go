package shell

import "ember/ui"

// Glyph is one of Ember's own line icons, drawn on a 24-unit grid like the
// Windows version's vector icons.
type Glyph uint8

const (
	GCPU Glyph = iota
	GMemory
	GWifi
	GWifiOff
	GEthernet
	GDisk
	GBattery
	GSearch
	GFolder
	GTerminal
	GPower
	GLock
	GMoon
	GSignOut
	GRestart
	GClock
	GExit
	GWindows
	GScreenOff
	GDownload
	GSun
	GTopBar
)

// DrawGlyph draws g centered on (cx, cy) in a box of size n.
func DrawGlyph(g ui.Gfx, k Glyph, cx, cy, n float32, c ui.Color) {
	s := n / 24
	w := max(1.3, 1.9*s)
	x0, y0 := cx-n/2, cy-n/2
	X := func(v float32) float32 { return x0 + v*s }
	Y := func(v float32) float32 { return y0 + v*s }
	line := func(xy ...float32) {
		p := ui.NewPath().MoveTo(X(xy[0]), Y(xy[1]))
		for i := 2; i+1 < len(xy); i += 2 {
			p.LineTo(X(xy[i]), Y(xy[i+1]))
		}
		ui.Pen(g, p, w, c)
	}
	box := func(x, y, bw, bh, r float32) {
		ui.StrokeRound(g, ui.Rect{X: X(x), Y: Y(y), W: bw * s, H: bh * s}, r*s, w, c)
	}
	fillBox := func(x, y, bw, bh, r float32) {
		ui.FillRound(g, ui.Rect{X: X(x), Y: Y(y), W: bw * s, H: bh * s}, r*s, c)
	}
	arc := func(cx, cy, r, a0, a1 float32) {
		ui.Pen(g, ui.NewPath().Arc(X(cx), Y(cy), r*s, a0, a1, true), w, c)
	}
	dot := func(x, y, r float32) {
		ui.FillOval(g, ui.Rect{X: X(x - r), Y: Y(y - r), W: 2 * r * s, H: 2 * r * s}, c)
	}
	switch k {
	case GCPU:
		box(6, 6, 12, 12, 2.5)
		fillBox(9.5, 9.5, 5, 5, 1)
		for _, v := range []float32{9.5, 14.5} {
			line(v, 2.5, v, 6)
			line(v, 18, v, 21.5)
			line(2.5, v, 6, v)
			line(18, v, 21.5, v)
		}
	case GMemory:
		box(3, 7, 18, 10, 2)
		for _, v := range []float32{7, 11, 15} {
			line(v+1, 10, v+1, 14)
		}
		line(6, 17, 6, 20)
		line(18, 17, 18, 20)
	case GWifi, GWifiOff:
		arc(12, 19, 15, 225, 315)
		arc(12, 19, 10, 225, 315)
		arc(12, 19, 5, 225, 315)
		dot(12, 19, 1.6)
		if k == GWifiOff {
			line(4, 4, 20, 20)
		}
	case GEthernet:
		box(4, 4, 16, 13, 2.5)
		line(8, 17, 8, 20.5, 16, 20.5, 16, 17)
		for _, v := range []float32{8.5, 12, 15.5} {
			line(v, 8, v, 11)
		}
	case GDisk:
		box(3, 6, 18, 12, 3)
		line(3.5, 13, 20.5, 13)
		dot(17, 15.5, 1.2)
	case GBattery:
		box(2.5, 8, 17, 8.5, 2.2)
		fillBox(20, 10.5, 2, 3.5, 0.8)
	case GSearch:
		ui.StrokeOval(g, ui.Rect{X: X(4), Y: Y(4), W: 12 * s, H: 12 * s}, w, c)
		line(14.5, 14.5, 20, 20)
	case GFolder:
		line(3, 7, 3, 18, 21, 18, 21, 9, 12, 9, 10, 6, 3, 6, 3, 7)
	case GTerminal:
		box(3, 4.5, 18, 15, 2.5)
		line(7, 9.5, 10, 12, 7, 14.5)
		line(12, 15, 17, 15)
	case GPower:
		arc(12, 13, 7.5, -50, 230)
		line(12, 3.5, 12, 11)
	case GLock:
		box(5, 10.5, 14, 10, 2.5)
		arc(12, 10.5, 4.5, 180, 360)
		line(7.5, 10.5, 7.5, 9.5)
		line(16.5, 10.5, 16.5, 9.5)
		dot(12, 15.5, 1.3)
	case GMoon:
		p := ui.NewPath().Arc(X(12), Y(12), 8*s, 60, 300, true)
		p.Arc(X(20), Y(12), 8*s, 240, 120, false)
		g.StrokePath(p.Close(), w, c)
	case GSignOut:
		line(14, 4, 5, 4, 5, 20, 14, 20)
		line(10, 12, 20, 12)
		line(16.5, 8.5, 20, 12, 16.5, 15.5)
	case GRestart:
		arc(12, 12, 7.5, -60, 250)
		line(16.5, 3.6, 16, 6.6, 19.1, 7.1)
	case GClock:
		ui.StrokeOval(g, ui.Rect{X: X(3.5), Y: Y(3.5), W: 17 * s, H: 17 * s}, w, c)
		line(12, 7.5, 12, 12, 15, 14)
	case GExit:
		line(6, 6, 18, 18)
		line(18, 6, 6, 18)
	case GWindows:
		box(3, 4, 18, 16, 2.5)
		line(3.5, 8.5, 20.5, 8.5)
		dot(6.2, 6.3, 0.9)
		dot(8.8, 6.3, 0.9)
	case GTopBar:
		box(3, 4, 18, 16, 2.5)
		fillBox(3, 4, 18, 4.5, 2)
	case GSun:
		ui.StrokeOval(g, ui.Rect{X: X(8), Y: Y(8), W: 8 * s, H: 8 * s}, w, c)
		for _, d := range [][4]float32{{12, 2.5, 12, 4.5}, {12, 19.5, 12, 21.5}, {2.5, 12, 4.5, 12}, {19.5, 12, 21.5, 12},
			{5.3, 5.3, 6.7, 6.7}, {17.3, 17.3, 18.7, 18.7}, {5.3, 18.7, 6.7, 17.3}, {17.3, 6.7, 18.7, 5.3}} {
			line(d[0], d[1], d[2], d[3])
		}
	case GDownload:
		line(12, 4, 12, 15)
		line(7.5, 10.5, 12, 15, 16.5, 10.5)
		line(5, 19.5, 19, 19.5)
	case GScreenOff:
		box(3, 4, 18, 12, 2)
		line(8, 20, 16, 20)
		line(12, 16, 12, 20)
	}
}
