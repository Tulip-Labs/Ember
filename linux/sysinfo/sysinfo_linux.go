package sysinfo

import (
	"bufio"
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"
)

func (r *Reader) path(p string) string { return filepath.Join("/", r.Root, p) }

func (r *Reader) read(p string) []byte {
	b, _ := os.ReadFile(r.path(p))
	return b
}

// Fast reads the clock-rate values: processor and memory (every second while
// Ember is on screen). Every few calls it also reads disk, battery and network.
func (r *Reader) Fast() Stats {
	s := r.last
	s.CPU = r.cpu()
	s.MemUsedGB, s.MemTotGB = r.mem()
	s.OwnMB = r.own()
	if r.slowAt%5 == 0 {
		s.DiskFreeGB, s.DiskTotGB = r.disk()
		s.Battery, s.Charging = r.battery()
		s.Net = r.net()
	}
	r.slowAt++
	r.last = s
	return s
}

// Slow forces disk, battery and network on the next Fast.
func (r *Reader) Slow() { r.slowAt = 0 }

func (r *Reader) cpu() float64 {
	b := r.read("proc/stat")
	line, _, _ := bytes.Cut(b, []byte{'\n'})
	f := strings.Fields(string(line))
	if len(f) < 5 || f[0] != "cpu" {
		return r.last.CPU
	}
	var all, idle uint64
	for i, v := range f[1:] {
		n, _ := strconv.ParseUint(v, 10, 64)
		if i >= 8 { // guest time is already in user time
			break
		}
		all += n
		if i == 3 || i == 4 { // idle and iowait
			idle += n
		}
	}
	defer func() { r.prevIdle, r.prevAll = idle, all }()
	if r.prevAll == 0 || all <= r.prevAll {
		return r.last.CPU
	}
	d := float64(all - r.prevAll)
	return clamp(100*(d-float64(idle-r.prevIdle))/d, 0, 100)
}

func (r *Reader) mem() (used, total float64) {
	var tot, avail float64
	sc := bufio.NewScanner(bytes.NewReader(r.read("proc/meminfo")))
	for sc.Scan() {
		f := strings.Fields(sc.Text())
		if len(f) < 2 {
			continue
		}
		v, _ := strconv.ParseFloat(f[1], 64)
		switch f[0] {
		case "MemTotal:":
			tot = v
		case "MemAvailable:":
			avail = v
		}
	}
	const gb = 1024 * 1024 // kB to GB
	return (tot - avail) / gb, tot / gb
}

func (r *Reader) own() float64 {
	if r.Root != "" {
		return r.last.OwnMB
	}
	sc := bufio.NewScanner(bytes.NewReader(r.read("proc/self/status")))
	for sc.Scan() {
		if v, ok := strings.CutPrefix(sc.Text(), "VmRSS:"); ok {
			n, _ := strconv.ParseFloat(strings.Fields(v)[0], 64)
			return n / 1024
		}
	}
	return 0
}

func (r *Reader) disk() (free, total float64) {
	home := r.Home
	if home == "" {
		home, _ = os.UserHomeDir()
	}
	var st syscall.Statfs_t
	if err := syscall.Statfs(r.path(home), &st); err != nil {
		return 0, 0
	}
	const gb = 1 << 30
	return float64(st.Bavail) * float64(st.Bsize) / gb, float64(st.Blocks) * float64(st.Bsize) / gb
}

func (r *Reader) battery() (int, bool) {
	ms, _ := filepath.Glob(r.path("sys/class/power_supply/*"))
	for _, m := range ms {
		if strings.TrimSpace(string(readFile(m, "type"))) != "Battery" {
			continue
		}
		if s := strings.TrimSpace(string(readFile(m, "scope"))); s == "Device" {
			continue // a mouse or headset battery
		}
		c, err := strconv.Atoi(strings.TrimSpace(string(readFile(m, "capacity"))))
		if err != nil {
			continue
		}
		st := strings.TrimSpace(string(readFile(m, "status")))
		return int(clamp(float64(c), 0, 100)), st == "Charging" || st == "Full" || st == "Not charging"
	}
	return -1, false
}

func readFile(dir, name string) []byte {
	b, _ := os.ReadFile(filepath.Join(dir, name))
	return b
}

func (r *Reader) net() Net {
	var n Net
	ifs, _ := filepath.Glob(r.path("sys/class/net/*"))
	wired := ""
	for _, d := range ifs {
		name := filepath.Base(d)
		if name == "lo" {
			continue
		}
		_, werr := os.Stat(filepath.Join(d, "wireless"))
		wifi := werr == nil
		if !wifi {
			if _, err := os.Stat(filepath.Join(d, "device")); err != nil {
				continue // virtual: bridges, containers, VPN tunnels
			}
		}
		n.HasWifi = n.HasWifi || wifi
		up := strings.TrimSpace(string(readFile(d, "operstate"))) == "up"
		if !up {
			continue
		}
		if wifi && n.State != 1 {
			n.State, n.Name = 1, name
			n.Signal = r.signal(name)
			if ssid := ssid(name, r.Root); ssid != "" {
				n.Name = ssid
			}
		} else if !wifi && wired == "" {
			wired = name
		}
	}
	if n.State == 0 && wired != "" {
		n.State, n.Name = 2, wired
	}
	return n
}

// signal reads the link quality of /proc/net/wireless (0..70 on most cards).
func (r *Reader) signal(ifc string) int {
	sc := bufio.NewScanner(bytes.NewReader(r.read("proc/net/wireless")))
	for sc.Scan() {
		f := strings.Fields(sc.Text())
		if len(f) >= 3 && strings.TrimSuffix(f[0], ":") == ifc {
			q, _ := strconv.ParseFloat(strings.TrimSuffix(f[2], "."), 64)
			return int(clamp(q*100/70, 0, 100))
		}
	}
	return 0
}

// ssid asks NetworkManager or iwd for the network name, when one of them is
// there; the card shows the interface name otherwise.
func ssid(ifc, root string) string {
	if root != "" {
		return ""
	}
	try := func(name string, args ...string) string {
		p, err := exec.LookPath(name)
		if err != nil {
			return ""
		}
		cmd := exec.Command(p, args...)
		done := make(chan []byte, 1)
		go func() { b, _ := cmd.Output(); done <- b }()
		select {
		case b := <-done:
			return string(b)
		case <-time.After(800 * time.Millisecond):
			if cmd.Process != nil {
				cmd.Process.Kill()
			}
			return ""
		}
	}
	if out := try("nmcli", "-t", "-f", "active,ssid", "dev", "wifi"); out != "" {
		for _, l := range strings.Split(out, "\n") {
			if s, ok := strings.CutPrefix(l, "yes:"); ok {
				return strings.ReplaceAll(s, `\:`, ":")
			}
		}
	}
	if out := try("iwgetid", ifc, "-r"); out != "" {
		return strings.TrimSpace(out)
	}
	return ""
}

func clamp(v, lo, hi float64) float64 { return max(lo, min(hi, v)) }
