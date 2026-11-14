//go:build linux

package sysinfo

import (
	"os"
	"path/filepath"
	"testing"
)

func put(t *testing.T, root, p, s string) {
	t.Helper()
	p = filepath.Join(root, p)
	os.MkdirAll(filepath.Dir(p), 0o755)
	if err := os.WriteFile(p, []byte(s), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestFakeTree(t *testing.T) {
	root := t.TempDir()
	put(t, root, "proc/stat", "cpu  100 0 100 800 0 0 0 0 0 0\n")
	put(t, root, "proc/meminfo", "MemTotal:       8388608 kB\nMemFree: 1 kB\nMemAvailable:   2097152 kB\n")
	put(t, root, "sys/class/power_supply/BAT0/type", "Battery\n")
	put(t, root, "sys/class/power_supply/BAT0/capacity", "64\n")
	put(t, root, "sys/class/power_supply/BAT0/status", "Discharging\n")
	put(t, root, "sys/class/net/lo/operstate", "unknown\n")
	put(t, root, "sys/class/net/wlan0/operstate", "up\n")
	put(t, root, "sys/class/net/wlan0/wireless/x", "")
	put(t, root, "proc/net/wireless", "Inter-| sta-|   Quality\n face | tus | link level noise\nwlan0: 0000   49.  -61.  -256\n")
	put(t, root, "sys/class/backlight/acpi_video0/type", "firmware\n")
	put(t, root, "sys/class/backlight/acpi_video0/max_brightness", "100\n")
	put(t, root, "sys/class/backlight/acpi_video0/actual_brightness", "30\n")
	put(t, root, "sys/class/backlight/intel_backlight/type", "raw\n")
	put(t, root, "sys/class/backlight/intel_backlight/max_brightness", "96000\n")
	put(t, root, "sys/class/backlight/intel_backlight/actual_brightness", "48000\n")
	os.MkdirAll(filepath.Join(root, "home"), 0o755)
	r := &Reader{Root: root, Home: "/home"}
	s := r.Fast()
	if s.MemTotGB != 8 || s.MemUsedGB != 6 {
		t.Errorf("memory %v / %v", s.MemUsedGB, s.MemTotGB)
	}
	if s.Brightness != 30 {
		t.Errorf("brightness %d (the firmware backlight)", s.Brightness)
	}
	if s.Battery != 64 || s.Charging {
		t.Errorf("battery %d %v", s.Battery, s.Charging)
	}
	if s.Net.State != 1 || s.Net.Name != "wlan0" || s.Net.Signal != 70 {
		t.Errorf("net %+v", s.Net)
	}
	if s.DiskTotGB <= 0 {
		t.Errorf("disk %v", s.DiskTotGB)
	}
	put(t, root, "proc/stat", "cpu  200 0 200 900 0 0 0 0 0 0\n")
	if s := r.Fast(); s.CPU < 66 || s.CPU > 67 {
		t.Errorf("cpu %v", s.CPU)
	}
}

func TestRealSystem(t *testing.T) {
	r := &Reader{}
	r.Fast()
	s := r.Fast()
	if s.MemTotGB <= 0 || s.OwnMB <= 0 {
		t.Errorf("real reading: %+v", s)
	}
}
