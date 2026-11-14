// Package apps lists the installed programs from their .desktop entries (the
// freedesktop.org menu every Linux desktop shares) and starts them.
package apps

import (
	"bufio"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
)

// App is one entry of the list.
type App struct {
	ID       string   // the desktop file id, for example org.gnome.Nautilus.desktop
	Name     string   // what the tile shows
	Generic  string   // "Web Browser"; searched too
	Keywords []string // searched too
	Exec     []string // the command line, field codes removed
	Terminal bool     // runs inside a terminal
	Path     string   // the working directory, if the entry sets one
	File     string   // where the entry was read
}

// Dirs returns the application folders in priority order: the user's own
// first, then $XDG_DATA_DIRS, then the Flatpak and Snap exports.
func Dirs() []string {
	home, _ := os.UserHomeDir()
	data := os.Getenv("XDG_DATA_HOME")
	if data == "" {
		data = filepath.Join(home, ".local/share")
	}
	dirs := []string{data}
	sys := os.Getenv("XDG_DATA_DIRS")
	if sys == "" {
		sys = "/usr/local/share:/usr/share"
	}
	dirs = append(dirs, filepath.SplitList(sys)...)
	dirs = append(dirs, filepath.Join(data, "flatpak/exports/share"), "/var/lib/flatpak/exports/share", "/var/lib/snapd/desktop")
	var out []string
	seen := map[string]bool{}
	for _, d := range dirs {
		d = filepath.Join(d, "applications")
		if d != "" && !seen[d] {
			seen[d] = true
			out = append(out, d)
		}
	}
	return out
}

// Scan reads every entry of dirs. An id found in an earlier folder hides the
// same id in later ones (a user's copy overrides the system's).
func Scan(dirs []string, desktop string) []App {
	seen := map[string]bool{}
	var out []App
	for _, d := range dirs {
		filepath.WalkDir(d, func(p string, e os.DirEntry, err error) error {
			if err != nil || e.IsDir() || !strings.HasSuffix(p, ".desktop") {
				return nil
			}
			rel, _ := filepath.Rel(d, p)
			id := strings.ReplaceAll(rel, string(filepath.Separator), "-")
			if seen[id] {
				return nil
			}
			seen[id] = true
			if a, ok := Parse(p, desktop); ok {
				a.ID = id
				out = append(out, a)
			}
			return nil
		})
	}
	sort.SliceStable(out, func(i, j int) bool { return strings.ToLower(out[i].Name) < strings.ToLower(out[j].Name) })
	// two entries with the same name and command are one app
	w := 0
	for i, a := range out {
		if i > 0 && strings.EqualFold(a.Name, out[w-1].Name) && strings.Join(a.Exec, " ") == strings.Join(out[w-1].Exec, " ") {
			continue
		}
		out[w] = a
		w++
	}
	return out[:w]
}

// Stamp is a cheap fingerprint of the folders: it changes when an entry is
// installed or removed, so the list can refresh by itself.
func Stamp(dirs []string) int64 {
	var s int64
	for _, d := range dirs {
		if st, err := os.Stat(d); err == nil {
			s = s*31 + st.ModTime().UnixNano()
		}
	}
	return s
}

// Parse reads one entry. ok is false for entries that must not be listed:
// hidden ones, links and folders, ones for other desktops, ones whose
// program is missing.
func Parse(path, desktop string) (App, bool) {
	f, err := os.Open(path)
	if err != nil {
		return App{}, false
	}
	defer f.Close()
	lang := locale()
	var a App
	var exe, tryExec, typ string
	var hidden bool
	var only, not []string
	in := false
	names := map[string]string{}
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 64*1024), 1024*1024)
	for sc.Scan() {
		l := strings.TrimSpace(sc.Text())
		if l == "" || l[0] == '#' {
			continue
		}
		if l[0] == '[' {
			in = l == "[Desktop Entry]"
			continue
		}
		if !in {
			continue
		}
		k, v, ok := strings.Cut(l, "=")
		if !ok {
			continue
		}
		k, v = strings.TrimSpace(k), unescape(strings.TrimSpace(v))
		switch {
		case k == "Type":
			typ = v
		case k == "Name" || strings.HasPrefix(k, "Name["):
			names[k] = v
		case k == "GenericName":
			a.Generic = v
		case k == "Keywords":
			a.Keywords = list(v)
		case k == "Exec":
			exe = v
		case k == "TryExec":
			tryExec = v
		case k == "Terminal":
			a.Terminal = v == "true"
		case k == "Path":
			a.Path = v
		case k == "NoDisplay" || k == "Hidden":
			hidden = hidden || v == "true"
		case k == "OnlyShowIn":
			only = list(v)
		case k == "NotShowIn":
			not = list(v)
		}
	}
	if typ != "Application" || hidden || exe == "" {
		return App{}, false
	}
	if desktop != "" {
		if len(only) > 0 && !has(only, desktop) || has(not, desktop) {
			return App{}, false
		}
	}
	a.Name = names["Name"]
	for _, l := range lang {
		if n := names["Name["+l+"]"]; n != "" {
			a.Name = n
			break
		}
	}
	if a.Name == "" {
		return App{}, false
	}
	a.Exec = Fields(exe)
	if len(a.Exec) == 0 {
		return App{}, false
	}
	if tryExec != "" && !found(tryExec) {
		return App{}, false
	}
	a.File = path
	return a, true
}

// locale returns the Name[...] keys to try, most specific first: sr_RS@latin,
// sr_RS, sr@latin, sr.
func locale() []string {
	l := os.Getenv("LC_ALL")
	if l == "" {
		l = os.Getenv("LC_MESSAGES")
	}
	if l == "" {
		l = os.Getenv("LANG")
	}
	l, _, _ = strings.Cut(l, ".")
	if l == "" || l == "C" || l == "POSIX" {
		return nil
	}
	base, mod, _ := strings.Cut(l, "@")
	lang, _, hasC := strings.Cut(base, "_")
	var out []string
	if mod != "" {
		out = append(out, base+"@"+mod)
	}
	if hasC {
		out = append(out, base)
	}
	if mod != "" {
		out = append(out, lang+"@"+mod)
	}
	return append(out, lang)
}

func found(p string) bool {
	if filepath.IsAbs(p) {
		st, err := os.Stat(p)
		return err == nil && !st.IsDir()
	}
	_, err := exec.LookPath(p)
	return err == nil
}

func has(l []string, s string) bool {
	for _, x := range l {
		if strings.EqualFold(x, s) {
			return true
		}
	}
	return false
}

func list(v string) []string {
	var out []string
	for _, s := range strings.Split(v, ";") {
		if s = strings.TrimSpace(s); s != "" {
			out = append(out, s)
		}
	}
	return out
}

// unescape handles the escapes of string values (\s \n \t \r \\).
func unescape(s string) string {
	if !strings.Contains(s, `\`) {
		return s
	}
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		if s[i] == '\\' && i+1 < len(s) {
			i++
			switch s[i] {
			case 's':
				b.WriteByte(' ')
			case 'n':
				b.WriteByte('\n')
			case 't':
				b.WriteByte('\t')
			case 'r':
				b.WriteByte('\r')
			case '\\':
				b.WriteString(`\\`) // kept for Fields, which unquotes Exec once more
			default:
				b.WriteByte('\\')
				b.WriteByte(s[i])
			}
			continue
		}
		b.WriteByte(s[i])
	}
	return b.String()
}

// Fields splits an Exec value into arguments: double quotes group, a
// backslash inside quotes escapes the next character, and the field codes
// (%f %U %i ...) are dropped since Ember opens apps without files; %% is a
// literal percent sign.
func Fields(s string) []string {
	var out []string
	var cur strings.Builder
	inQ, have := false, false
	flush := func() {
		if have {
			out = append(out, cur.String())
		}
		cur.Reset()
		have = false
	}
	for i := 0; i < len(s); i++ {
		c := s[i]
		switch {
		case inQ && c == '\\' && i+1 < len(s):
			i++
			cur.WriteByte(s[i])
		case c == '\\' && i+1 < len(s):
			i++
			cur.WriteByte(s[i])
			have = true
		case c == '"':
			inQ = !inQ
			have = true
		case !inQ && (c == ' ' || c == '\t'):
			flush()
		case c == '%' && i+1 < len(s):
			i++
			if s[i] == '%' {
				cur.WriteByte('%')
				have = true
			}
			// any other field code is dropped
		default:
			cur.WriteByte(c)
			have = true
		}
	}
	flush()
	// an argument that was only a field code leaves nothing behind
	w := 0
	for _, a := range out {
		if a != "" {
			out[w] = a
			w++
		}
	}
	return out[:w]
}

// Terminals are tried in this order for entries with Terminal=true.
var Terminals = [][]string{
	{"foot"}, {"alacritty", "-e"}, {"kitty"}, {"wezterm", "start", "--"}, {"ghostty", "-e"},
	{"konsole", "-e"}, {"xfce4-terminal", "-x"}, {"gnome-terminal", "--"}, {"xterm", "-e"},
}

// Command returns the argv to run: the entry's command, inside a terminal
// when it asks for one.
func (a App) Command() []string {
	if !a.Terminal {
		return a.Exec
	}
	if t := os.Getenv("TERMINAL"); t != "" {
		return append([]string{t, "-e"}, a.Exec...)
	}
	for _, t := range Terminals {
		if _, err := exec.LookPath(t[0]); err == nil {
			return append(append([]string{}, t...), a.Exec...)
		}
	}
	return a.Exec
}

// Matches reports how well the app fits a search: 2 for a name that starts
// with it, 1 for a match anywhere in the name, the generic name or the
// keywords, 0 for none.
func (a App) Matches(q string) int {
	q = strings.ToLower(strings.TrimSpace(q))
	if q == "" {
		return 2
	}
	n := strings.ToLower(a.Name)
	if strings.HasPrefix(n, q) {
		return 2
	}
	for _, w := range strings.Fields(n) {
		if strings.HasPrefix(w, q) {
			return 2
		}
	}
	if strings.Contains(n, q) || strings.Contains(strings.ToLower(a.Generic), q) {
		return 1
	}
	for _, k := range a.Keywords {
		if strings.HasPrefix(strings.ToLower(k), q) {
			return 1
		}
	}
	return 0
}
