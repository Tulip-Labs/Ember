//go:build !unix

package main

import "os/exec"

// startDetached runs argv (Ember is meant for Linux; this keeps other
// systems building, which helps checking the code).
func startDetached(argv []string) error {
	cmd := exec.Command(argv[0], argv[1:]...)
	if err := cmd.Start(); err != nil {
		return err
	}
	go cmd.Wait()
	return nil
}
