//go:build !linux

package update

import (
	"context"
	"errors"
)

// Detect: Ember for Linux only updates itself on Linux.
func Detect() Kind { return KindDev }

// Install is not available here.
func Install(context.Context, Kind, string) (Result, error) {
	return Result{}, errors.New("updates are only for Linux")
}

// Restart does nothing here.
func Restart() error { return nil }
