// Ember for Linux: a full-screen launcher and dashboard for the niri
// compositor, in the house style of Ember for Windows.
//
// niri manages the windows; Ember is the screen you come back to. One Ember
// stays resident per session: `ember` starts it (or shows it), and
// `ember --toggle` (bound to a key in niri) shows or hides it.
package main

import (
	"bufio"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"log"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"runtime/debug"
	"strings"
	"sync"
	"time"

	"gioui.org/app"

	"ember/apps"
	"ember/bar"
	"ember/niri"
	"ember/shell"
	"ember/sysinfo"
)

const version = "1.0.1"

func main() {
	toggle := flag.Bool("toggle", false, "show Ember, or hide it when it is on screen")
	hide := flag.Bool("hide", false, "hide Ember")
	daemon := flag.Bool("daemon", false, "does nothing (Ember no longer stays in the background)")
	ver := flag.Bool("version", false, "print the version")
	niriTheme := flag.Bool("niri-theme", false, "write niri's colors for the current theme and exit")
	setupNiri := flag.Bool("setup-niri", false, "add Ember to niri's settings (Super+D, start at sign-in) and exit")
	removeNiri := flag.Bool("remove-niri", false, "take Ember out of niri's settings and exit")
	setupBar := flag.Bool("setup-bar", false, "give Waybar Ember's look (the Ember bar) and exit")
	removeBar := flag.Bool("remove-bar", false, "put Waybar's own config back and exit")
	power := flag.Bool("power", false, "show Ember with the power panel open")
	flag.Parse()
	if *setupNiri || *removeNiri {
		os.Exit(niriSetupCmd(*removeNiri))
	}
	if *setupBar || *removeBar {
		os.Exit(barCmd(*removeBar))
	}
	if *niriTheme {
		r := &resident{}
		cfg, _ := os.UserConfigDir()
		r.conf = filepath.Join(cfg, "ember")
		r.loadSettings()
		if err := niri.WriteTheme(niri.ConfigDir(), shell.ThemeByID(r.theme)); err != nil {
			log.Fatal(err)
		}
		return
	}
	if *ver {
		fmt.Println("Ember", version)
		return
	}
	cmd := "show"
	switch {
	case *toggle:
		cmd = "toggle"
	case *hide:
		cmd = "hide"
	case *daemon:
		cmd = "daemon"
	case *power:
		cmd = "power"
	}
	sock := socketPath()
	// a resident Ember is already there: hand it the command and leave
	if send(sock, cmd) == nil {
		return
	}
	if cmd == "hide" || cmd == "daemon" {
		return // Ember only runs while it is on screen
	}
	// a small heap: collect early, and hard above 40 MB
	debug.SetGCPercent(25)
	debug.SetMemoryLimit(40 << 20)
	app.ID = "ember" // the Wayland app id niri's window rule matches
	r := newResident()
	if err := r.listen(sock); err != nil {
		log.Fatal(err)
	}
	r.show()
	app.Main()
}

// socketPath is per user and per Wayland display, so two sessions never meet.
func socketPath() string {
	dir := os.Getenv("XDG_RUNTIME_DIR")
	if dir == "" {
		dir = os.TempDir()
	}
	disp := os.Getenv("WAYLAND_DISPLAY")
	if disp == "" {
		disp = "x"
	}
	return filepath.Join(dir, fmt.Sprintf("ember-%d-%s.sock", os.Getuid(), filepath.Base(disp)))
}

func send(path, cmd string) error {
	c, err := net.DialTimeout("unix", path, 300*time.Millisecond)
	if err != nil {
		return err
	}
	defer c.Close()
	c.SetDeadline(time.Now().Add(time.Second))
	if _, err := c.Write([]byte(cmd + "\n")); err != nil {
		return err
	}
	_, err = bufio.NewReader(c).ReadString('\n') // the resident answers once done
	return err
}

// resident is the process that stays: it keeps the app list and settings
// while the window comes and goes (the window, and its memory, is released
// whenever Ember is hidden).
type resident struct {
	mu     sync.Mutex
	niri   *niri.Client
	stats  sysinfo.Reader
	win    *window // nil while hidden
	conf   string
	hidden []string
	theme  string
	upd    updates
	// startNote is shown once, the first time Ember opens (niri setup)
	startNote string
	openPower bool // the power panel opens with the next frame
	listener  net.Listener
	brightCh  chan int
	list      []apps.App
	stamp     int64
	dirs      []string
}

func newResident() *resident {
	r := &resident{niri: niri.FromEnv(), dirs: apps.Dirs()}
	r.upd.on = true
	cfg, _ := os.UserConfigDir()
	r.conf = filepath.Join(cfg, "ember")
	r.loadSettings()
	r.autoSetupNiri()
	r.autoSetupBar()
	r.niriColors()
	r.rescan()
	go r.updateLoop()
	return r
}

type settings struct {
	Hidden []string `json:"hidden"`
	Theme  string   `json:"theme,omitempty"` // one of Lite Go's palettes
	// AutoUpdate is nil until changed: updates are on by default
	AutoUpdate    *bool `json:"autoUpdate,omitempty"`
	UpdateChecked int64 `json:"updateChecked,omitempty"`
}

func (r *resident) loadSettings() {
	b, err := os.ReadFile(filepath.Join(r.conf, "settings.json"))
	if err != nil {
		return
	}
	var s settings
	if json.Unmarshal(b, &s) == nil {
		r.hidden, r.theme = s.Hidden, s.Theme
		r.upd.on = s.AutoUpdate == nil || *s.AutoUpdate
		r.upd.checked = s.UpdateChecked
	}
}

func (r *resident) saveSettings() {
	os.MkdirAll(r.conf, 0o755)
	r.mu.Lock()
	on := r.upd.on
	b, _ := json.MarshalIndent(settings{Hidden: r.hidden, Theme: r.theme, AutoUpdate: &on, UpdateChecked: r.upd.checked}, "", "  ")
	r.mu.Unlock()
	tmp := filepath.Join(r.conf, "settings.json.tmp")
	if os.WriteFile(tmp, b, 0o644) == nil {
		os.Rename(tmp, filepath.Join(r.conf, "settings.json"))
	}
}

// rescan reads the app folders again when something was installed or removed.
func (r *resident) rescan() bool {
	st := apps.Stamp(r.dirs)
	if st == r.stamp && r.list != nil {
		return false
	}
	desk := os.Getenv("XDG_CURRENT_DESKTOP")
	if i := strings.IndexByte(desk, ':'); i >= 0 {
		desk = desk[:i]
	}
	if desk == "" {
		desk = "niri"
	}
	r.list = apps.Scan(r.dirs, desk)
	r.stamp = st
	return true
}

func (r *resident) listen(path string) error {
	os.Remove(path) // a socket left by an Ember that crashed
	l, err := net.Listen("unix", path)
	if err != nil {
		return err
	}
	os.Chmod(path, 0o600)
	r.listener = l
	go func() {
		for {
			c, err := l.Accept()
			if err != nil {
				return
			}
			go r.serve(c)
		}
	}()
	return nil
}

func (r *resident) serve(c net.Conn) {
	defer c.Close()
	c.SetDeadline(time.Now().Add(2 * time.Second))
	line, _ := bufio.NewReader(c).ReadString('\n')
	switch strings.TrimSpace(line) {
	case "show":
		r.show()
	case "power":
		r.mu.Lock()
		r.openPower = true
		r.mu.Unlock()
		r.show()
	case "hide":
		r.hide()
	case "toggle":
		r.mu.Lock()
		shown := r.win != nil
		r.mu.Unlock()
		if shown {
			r.hide()
		} else {
			r.show()
		}
	}
	c.Write([]byte("ok\n"))
}

func (r *resident) show() {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.win != nil {
		r.win.raise()
		return
	}
	r.win = openWindow(r)
}

func (r *resident) hide() {
	r.mu.Lock()
	w := r.win
	r.mu.Unlock()
	if w != nil {
		w.close()
	}
}

// closed is called by the window once it is gone.
// closed is called once the window is gone. Ember then quits, so it uses no
// memory at all while you are in your apps; Super+D starts it again in a
// moment. An update that is downloading finishes first.
func (r *resident) closed(w *window) {
	r.mu.Lock()
	if r.win == w {
		r.win = nil
	}
	r.mu.Unlock()
	debug.FreeOSMemory()
	for {
		r.mu.Lock()
		busy, shown := r.upd.busy, r.win != nil
		r.mu.Unlock()
		if shown {
			return // shown again while the update finished
		}
		if !busy {
			break
		}
		time.Sleep(time.Second)
	}
	r.quit()
}

func (r *resident) quit() {
	if r.listener != nil {
		r.listener.Close()
	}
	os.Remove(socketPath())
	os.Exit(0)
}

// ---- shell.Host ----

// spawn starts a program detached from Ember: through niri when it runs (so
// the program is niri's child and gets its environment), directly otherwise.
func (r *resident) spawn(argv []string, dir string) error {
	if len(argv) == 0 {
		return errors.New("nothing to run")
	}
	if p := argv[0]; !strings.ContainsRune(p, '/') {
		if _, err := exec.LookPath(p); err != nil {
			return fmt.Errorf("%s is not installed", p)
		}
	}
	if dir != "" {
		argv = append([]string{"sh", "-c", `cd "$0" && exec "$@"`, dir}, argv...)
	}
	if r.niri != nil {
		if err := r.niri.Spawn(argv); err == nil {
			return nil
		}
	}
	return startDetached(argv)
}

func (r *resident) Launch(a apps.App) error { return r.spawn(a.Command(), a.Path) }

func (r *resident) Run(argv ...string) error {
	for i, a := range argv {
		if a == "~" {
			argv[i], _ = os.UserHomeDir()
		}
	}
	return r.spawn(argv, "")
}

func (r *resident) FocusWindow(id uint64) error { return r.niri.FocusWindow(id) }
func (r *resident) CloseWindow(id uint64) error { return r.niri.CloseWindow(id) }
func (r *resident) Hide()                       { go r.hide() }

func (r *resident) SaveHidden(ids []string) {
	r.mu.Lock()
	r.hidden = ids
	r.mu.Unlock()
	r.saveSettings()
}

func (r *resident) SaveTheme(id string) {
	r.mu.Lock()
	r.theme = id
	r.mu.Unlock()
	r.saveSettings()
	r.niriColors()
}

// niriColors gives niri the colors of Ember's theme (focus ring, backdrop,
// shadows, overview), when Ember is set up in niri's config; niri picks the
// change up by itself.
func (r *resident) niriColors() {
	dir := niri.ConfigDir()
	if _, err := os.Stat(filepath.Join(dir, "ember.kdl")); err != nil {
		return
	}
	r.mu.Lock()
	id := r.theme
	r.mu.Unlock()
	if err := niri.WriteTheme(dir, shell.ThemeByID(id)); err != nil {
		log.Println("ember: niri colors:", err)
	}
	if ok, _ := bar.Restyle(bar.Dir(), shell.ThemeByID(id)); ok {
		bar.Reload()
	}
}

func (r *resident) Power(p shell.PowerItem) error {
	first := func(cands ...[]string) error {
		for _, c := range cands {
			if _, err := exec.LookPath(c[0]); err == nil {
				return r.spawn(c, "")
			}
		}
		return fmt.Errorf("%s is not installed", cands[0][0])
	}
	switch p.ID {
	case "lock":
		r.Hide()
		return first([]string{"swaylock", "-f"}, []string{"hyprlock"}, []string{"gtklock"}, []string{"loginctl", "lock-session"})
	case "sleep":
		r.Hide()
		return first([]string{"systemctl", "suspend"}, []string{"loginctl", "suspend"})
	case "signout":
		if r.niri != nil {
			return r.niri.Quit()
		}
		return first([]string{"loginctl", "terminate-session", os.Getenv("XDG_SESSION_ID")})
	case "restart":
		return first([]string{"systemctl", "reboot"}, []string{"loginctl", "reboot"})
	case "poweroff":
		return first([]string{"systemctl", "poweroff"}, []string{"loginctl", "poweroff"})
	case "screensoff":
		r.Hide()
		return r.niri.PowerOffMonitors()
	case "exit":
		os.Remove(socketPath())
		os.Exit(0)
	}
	return nil
}
