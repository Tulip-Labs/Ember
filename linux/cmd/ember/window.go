package main

import (
	"log"
	"sync"
	"time"

	"gioui.org/app"
	"gioui.org/io/event"
	"gioui.org/io/key"
	"gioui.org/io/pointer"
	"gioui.org/io/system"
	"gioui.org/op"
	"gioui.org/op/clip"

	"ember/giox"
	"ember/shell"
)

// window is Ember on screen: one full-screen Gio window. It is created when
// Ember shows and destroyed when it hides.
type window struct {
	r    *resident
	w    *app.Window
	mu   sync.Mutex
	quit bool // close after the next frame
	done chan struct{}
}

// tag receives every pointer and key event of the window.
var tag = new(int)

func openWindow(r *resident) *window {
	win := &window{r: r, w: new(app.Window), done: make(chan struct{})}
	win.w.Option(app.Title("Ember"), app.Decorated(false), app.Fullscreen.Option())
	go func() {
		if err := win.loop(); err != nil {
			log.Println("ember:", err)
		}
		close(win.done)
		r.closed(win)
	}()
	go win.poll()
	return win
}

// raise brings Ember back to the front: niri focuses its window (Wayland
// gives programs no way to raise themselves).
func (w *window) raise() {
	if c := w.r.niri; c != nil {
		if ws, err := c.Windows(); err == nil {
			for _, x := range ws {
				if x.AppID == "ember" {
					c.FocusWindow(x.ID)
					break
				}
			}
		}
	}
	w.w.Perform(system.ActionRaise)
	w.w.Invalidate()
}

// close takes the window down; the frame loop closes it too, in case the
// request reaches it first.
func (w *window) close() {
	w.mu.Lock()
	w.quit = true
	w.mu.Unlock()
	select {
	case <-w.done:
	default:
		w.w.Perform(system.ActionClose)
	}
}

// poll wakes the window once a second for the clock, the dashboard and the
// open windows, and stops when the window is gone.
func (w *window) poll() {
	t := time.NewTicker(time.Second)
	defer t.Stop()
	for {
		select {
		case <-w.done:
			return
		case <-t.C:
			w.w.Invalidate()
		}
	}
}

func (w *window) loop() error {
	r := w.r
	s := shell.New(r)
	r.mu.Lock()
	r.rescan()
	s.SetApps(r.list, r.hidden)
	s.SetTheme(r.theme)
	r.mu.Unlock()
	s.Niri = r.niri != nil
	s.Stats = r.stats.Fast()
	r.stats.Slow()
	wins := func() {
		if r.niri == nil {
			return
		}
		ws, err := r.niri.Windows()
		if err != nil {
			return
		}
		s.Wins = s.Wins[:0]
		for _, x := range ws {
			if x.AppID != "ember" {
				s.Wins = append(s.Wins, x)
			}
		}
	}
	wins()
	g := giox.NewGfx()
	rd := &giox.Reader{Tag: tag}
	var ops op.Ops
	start := time.Now()
	last := start
	lastScan := start
	frames := 0
	for {
		switch e := w.w.Event().(type) {
		case app.DestroyEvent:
			return e.Err
		case app.FrameEvent:
			now := time.Now()
			if now.Sub(last) >= 900*time.Millisecond {
				last = now
				s.Stats = r.stats.Fast()
				wins()
			}
			if now.Sub(lastScan) >= 5*time.Second {
				lastScan = now
				r.mu.Lock()
				if r.rescan() {
					s.SetApps(r.list, r.hidden)
				}
				r.mu.Unlock()
			}
			s.Now = now
			r.mu.Lock()
			s.UpdatesOn = r.upd.on && r.upd.kind.CanSelf()
			s.Notice, s.NoticeAction = r.upd.notice, r.upd.action
			if r.openPower {
				s.OpenPower()
				r.openPower = false
			}
			if r.startNote != "" {
				s.Toast(r.startNote)
				r.startNote = ""
			}
			r.mu.Unlock()
			gtx := app.NewContext(&ops, e)
			scale := gtx.Metric.PxPerDp
			if frames < 3 {
				gtx.Execute(key.FocusCmd{Tag: tag})
				frames++
			}
			rd.Read(gtx, s.In, scale)
			s.In.Now = now.Sub(start).Seconds()
			area := clip.Rect{Max: e.Size}.Push(gtx.Ops)
			event.Op(gtx.Ops, tag)
			area.Pop()
			g.Begin(gtx.Ops, scale)
			s.Frame(g, float32(e.Size.X)/scale, float32(e.Size.Y)/scale)
			g.End()
			pointer.CursorDefault.Add(gtx.Ops)
			if s.Redraw {
				gtx.Execute(op.InvalidateCmd{At: now.Add(250 * time.Millisecond)})
			}
			e.Frame(gtx.Ops)
			w.mu.Lock()
			quit := w.quit
			w.mu.Unlock()
			if quit {
				w.w.Perform(system.ActionClose)
			}
		}
	}
}
