package main

import (
	"os/exec"
	"strconv"
	"time"
)

// SetBrightness sets the backlight. The slider sends many values while it
// is dragged; only the latest is applied, at most about 20 times a second.
// logind sets it for the user of the active session (no root needed);
// brightnessctl is the fallback.
func (r *resident) SetBrightness(percent int) {
	r.mu.Lock()
	if r.brightCh == nil {
		r.brightCh = make(chan int, 1)
		go r.brightLoop(r.brightCh)
	}
	ch := r.brightCh
	r.mu.Unlock()
	select {
	case <-ch: // drop the value not applied yet
	default:
	}
	ch <- percent
}

func (r *resident) brightLoop(ch chan int) {
	for p := range ch {
		name, max := r.stats.Backlight()
		if name == "" {
			continue
		}
		v := max * p / 100
		if v < 1 {
			v = 1
		}
		err := exec.Command("busctl", "call", "org.freedesktop.login1", "/org/freedesktop/login1/session/auto",
			"org.freedesktop.login1.Session", "SetBrightness", "ssu", "backlight", name, strconv.Itoa(v)).Run()
		if err != nil {
			exec.Command("brightnessctl", "-q", "-d", name, "set", strconv.Itoa(v)).Run()
		}
		time.Sleep(50 * time.Millisecond)
	}
}
