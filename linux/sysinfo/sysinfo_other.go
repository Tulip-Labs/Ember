//go:build !linux

package sysinfo

// Fast returns an empty reading where /proc does not exist.
func (r *Reader) Fast() Stats { return Stats{Battery: -1} }

// Slow does nothing outside Linux.
func (r *Reader) Slow() {}
