package update

import (
	"archive/tar"
	"compress/gzip"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
)

func exists(p string) bool { _, err := os.Stat(p); return err == nil }

func self() string {
	exe, err := os.Executable()
	if err != nil {
		return ""
	}
	if r, err := filepath.EvalSymlinks(exe); err == nil {
		exe = r
	}
	return exe
}

// Detect works out how this copy was installed. The .deb and .rpm packages
// leave a file named install-kind beside the program.
func Detect() Kind {
	exe := self()
	if strings.HasPrefix(exe, "/nix/store/") {
		return KindNix
	}
	if b, err := os.ReadFile(filepath.Join(filepath.Dir(exe), "install-kind")); err == nil {
		switch strings.TrimSpace(string(b)) {
		case "deb":
			return KindDeb
		case "rpm":
			if exists("/run/ostree-booted") {
				return KindOSTree
			}
			return KindRPM
		case "arch":
			return KindArch
		}
	}
	if b, err := os.ReadFile(filepath.Join(filepath.Dir(exe), ".ember-install")); err == nil && strings.TrimSpace(string(b)) == "user" {
		if syscall.Access(filepath.Dir(exe), 2) == nil { // W_OK
			return KindUser
		}
	}
	return KindDev
}

// Install installs the downloaded file. Packages ask for the password once
// (pkexec); the home-folder copy replaces itself.
func Install(ctx context.Context, k Kind, path string) (Result, error) {
	switch k {
	case KindUser:
		return Result{Restart: true}, replaceFromTar(path, self())
	case KindDeb:
		if _, err := exec.LookPath("apt-get"); err == nil {
			return Result{Restart: true}, run(ctx, "pkexec", "apt-get", "install", "-y", "--allow-downgrades", path)
		}
		return Result{Restart: true}, run(ctx, "pkexec", "dpkg", "-i", path)
	case KindRPM:
		if _, err := exec.LookPath("dnf"); err == nil {
			return Result{Restart: true}, run(ctx, "pkexec", "dnf", "install", "-y", path)
		}
		if _, err := exec.LookPath("zypper"); err == nil {
			return Result{Restart: true}, run(ctx, "pkexec", "zypper", "--non-interactive", "install", "--allow-unsigned-rpm", path)
		}
		return Result{Restart: true}, run(ctx, "pkexec", "rpm", "-U", "--force", path)
	}
	return Result{}, fmt.Errorf("updates for this copy come from %s", k.Managed())
}

func run(ctx context.Context, name string, args ...string) error {
	cmd := exec.CommandContext(ctx, name, args...)
	out, err := cmd.CombinedOutput()
	if err != nil {
		msg := strings.TrimSpace(string(out))
		if i := strings.LastIndexByte(msg, '\n'); i >= 0 {
			msg = msg[i+1:]
		}
		if ee := (*exec.ExitError)(nil); errors.As(err, &ee) && (ee.ExitCode() == 126 || ee.ExitCode() == 127) && name == "pkexec" {
			return errors.New("the password was not given")
		}
		if msg != "" {
			return fmt.Errorf("%s: %s", filepath.Base(name), msg)
		}
		return err
	}
	return nil
}

// replaceFromTar puts the program from the release archive in place of exe
// with one rename (the running copy keeps going).
func replaceFromTar(archive, exe string) error {
	f, err := os.Open(archive)
	if err != nil {
		return err
	}
	defer f.Close()
	zr, err := gzip.NewReader(f)
	if err != nil {
		return err
	}
	tr := tar.NewReader(zr)
	want := map[string]string{"ember": exe}
	done := map[string]string{}
	for {
		h, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}
		dst, ok := want[filepath.Base(h.Name)]
		if !ok || h.Typeflag != tar.TypeReg {
			continue
		}
		tmp := dst + ".new"
		w, err := os.OpenFile(tmp, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0o755)
		if err != nil {
			return err
		}
		if _, err := io.Copy(w, io.LimitReader(tr, 512<<20)); err != nil {
			w.Close()
			os.Remove(tmp)
			return err
		}
		if err := w.Close(); err != nil {
			return err
		}
		done[dst] = tmp
	}
	if len(done) != len(want) {
		for _, tmp := range done {
			os.Remove(tmp)
		}
		return errors.New("the release archive has no ember program")
	}
	return os.Rename(done[exe], exe)
}

// Restart starts the new Ember in a moment, once this one has quit (the
// resident socket is free by then).
func Restart() error {
	cmd := exec.Command("sh", "-c", `sleep 1; exec "$0"`, self())
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	return cmd.Start()
}
