package main

import (
	"context"
	"os"
	"path/filepath"
	"time"

	"ember/update"
)

// updates from the GitHub releases. A home-folder copy (.tar.gz) installs a
// new version by itself and offers a restart; a .deb or .rpm copy downloads it
// and offers Install (the system then asks for the password).
type updates struct {
	on      bool
	checked int64 // Unix seconds of the last check
	kind    update.Kind
	busy    bool
	notice  string // shown in the footer, with its button
	action  string
	pending string // a downloaded package, waiting for Install
	ver     string
	restart bool // the new version is installed
}

const updateEvery = 6 * 3600

func (r *resident) updateLoop() {
	k := update.Detect()
	r.mu.Lock()
	r.upd.kind = k
	r.mu.Unlock()
	if !k.CanSelf() {
		return
	}
	time.Sleep(45 * time.Second) // not while the session is starting
	for {
		r.checkUpdate(false)
		time.Sleep(30 * time.Minute)
	}
}

func (r *resident) note(text, action string) {
	r.mu.Lock()
	r.upd.notice, r.upd.action = text, action
	w := r.win
	r.mu.Unlock()
	if w != nil {
		w.w.Invalidate()
	}
}

// checkUpdate looks for a newer release (every six hours, or now when forced).
func (r *resident) checkUpdate(force bool) {
	r.mu.Lock()
	u := &r.upd
	if !u.on || !u.kind.CanSelf() || u.busy || u.pending != "" || u.restart ||
		(!force && time.Now().Unix()-u.checked < updateEvery) {
		r.mu.Unlock()
		return
	}
	u.busy = true
	k := u.kind
	r.mu.Unlock()
	defer func() {
		r.mu.Lock()
		r.upd.busy = false
		r.mu.Unlock()
	}()
	ctx := context.Background()
	rel, err := update.Latest(ctx)
	r.mu.Lock()
	r.upd.checked = time.Now().Unix()
	r.mu.Unlock()
	r.saveSettings()
	if err != nil || !update.Newer(rel.Version(), version) {
		return
	}
	ver := rel.Version()
	dir := updateDir()
	os.RemoveAll(dir)
	p, err := update.Fetch(ctx, rel, k, dir, nil)
	if err != nil {
		return // tried again at the next check
	}
	if k == update.KindUser {
		if _, err := update.Install(ctx, k, p); err != nil {
			r.note("Ember "+ver+" could not be installed", "")
			return
		}
		r.mu.Lock()
		r.upd.restart, r.upd.ver = true, ver
		r.mu.Unlock()
		r.note("Ember "+ver+" is installed", "Restart")
		return
	}
	r.mu.Lock()
	r.upd.pending, r.upd.ver = p, ver
	r.mu.Unlock()
	r.note("Ember "+ver+" is ready", "Install")
}

func updateDir() string {
	d, err := os.UserCacheDir()
	if err != nil {
		d = os.TempDir()
	}
	return filepath.Join(d, "ember", "updates")
}

// SetUpdates turns the automatic updates on or off (the power panel's switch).
func (r *resident) SetUpdates(on bool) {
	r.mu.Lock()
	r.upd.on = on
	r.mu.Unlock()
	r.saveSettings()
	if on {
		go r.checkUpdate(false)
	}
}

// UpdateNow is the notice's button: Install a downloaded package, or Restart
// into the version just installed.
func (r *resident) UpdateNow() {
	r.mu.Lock()
	u := &r.upd
	if u.restart {
		r.mu.Unlock()
		if update.Restart() == nil {
			os.Remove(socketPath())
			os.Exit(0)
		}
		return
	}
	if u.pending == "" || u.busy {
		r.mu.Unlock()
		return
	}
	p, k, ver := u.pending, u.kind, u.ver
	u.busy = true
	r.mu.Unlock()
	r.note("Installing Ember "+ver+"…", "")
	go func() {
		_, err := update.Install(context.Background(), k, p)
		r.mu.Lock()
		r.upd.busy = false
		if err == nil {
			r.upd.pending, r.upd.restart = "", true
		}
		r.mu.Unlock()
		if err != nil {
			r.note("Ember "+ver+" was not installed: "+err.Error(), "Install")
			return
		}
		r.note("Ember "+ver+" is installed", "Restart")
	}()
}
