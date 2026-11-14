// Package sysinfo reads what Ember's dashboard shows: processor load, memory,
// network, disk and battery. On Linux it reads /proc and /sys only; no daemon
// and no library is needed.
package sysinfo

// Stats is one reading of the dashboard.
type Stats struct {
	CPU                   float64 // 0..100
	MemUsedGB, MemTotGB   float64
	Net                   Net
	DiskFreeGB, DiskTotGB float64
	Battery               int // -1 when there is none
	Charging              bool
	OwnMB                 float64 // Ember's own memory
	Brightness            int     // the backlight, 0..100; -1 when there is none
}

// Net is the network card: 0 none, 1 Wi-Fi, 2 wired.
type Net struct {
	State   int
	Name    string // the network (SSID) or the interface
	Signal  int    // 0..100 for Wi-Fi
	HasWifi bool
}

// Reader keeps what a reading needs from the previous one (the processor
// counters), so a reading costs a few small file reads.
type Reader struct {
	Root              string // "" for the real system; tests point it at a fake tree
	Home              string // the disk card shows this file system
	prevIdle, prevAll uint64
	slowAt            int
	last              Stats
}
