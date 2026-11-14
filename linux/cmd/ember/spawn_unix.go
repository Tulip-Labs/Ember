//go:build unix

package main

import (
	"os"
	"os/exec"
	"syscall"
)

// startDetached runs argv in its own session, so it survives Ember and does
// not share its terminal or signals.
func startDetached(argv []string) error {
	cmd := exec.Command(argv[0], argv[1:]...)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	cmd.Stdin, cmd.Stdout, cmd.Stderr = nil, nil, nil
	if home, err := os.UserHomeDir(); err == nil {
		cmd.Dir = home
	}
	if err := cmd.Start(); err != nil {
		return err
	}
	go cmd.Wait() // reap it, so no zombie is left
	return nil
}
