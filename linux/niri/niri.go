// Package niri talks to the niri compositor over its IPC socket.
//
// niri (https://github.com/YaLTeR/niri) manages the windows; Ember only asks
// it what is open, and tells it what to focus, close or start. Each request
// is one line of JSON on a fresh connection to $NIRI_SOCKET, and the reply is
// one line: {"Ok": ...} or {"Err": "..."}.
package niri

import (
	"bufio"
	"encoding/json"
	"errors"
	"net"
	"os"
	"sort"
	"time"
)

// Window is one window niri manages.
type Window struct {
	ID          uint64 `json:"id"`
	Title       string `json:"title"`
	AppID       string `json:"app_id"`
	PID         int    `json:"pid"`
	WorkspaceID uint64 `json:"workspace_id"`
	Focused     bool   `json:"is_focused"`
	Floating    bool   `json:"is_floating"`
	Urgent      bool   `json:"is_urgent"`
}

// Workspace is one workspace of an output.
type Workspace struct {
	ID     uint64 `json:"id"`
	Idx    int    `json:"idx"`
	Name   string `json:"name"`
	Output string `json:"output"`
	Active bool   `json:"is_active"`
}

// Client is a connection target; the zero value has no socket.
type Client struct {
	Path    string
	Timeout time.Duration
}

// FromEnv returns the client for the running niri session, or nil outside niri.
func FromEnv() *Client {
	p := os.Getenv("NIRI_SOCKET")
	if p == "" {
		return nil
	}
	return &Client{Path: p, Timeout: 2 * time.Second}
}

// ErrNoNiri is returned when Ember runs outside a niri session.
var ErrNoNiri = errors.New("niri: not running inside a niri session")

// Request sends one request and decodes the Ok value into out (when out is not nil).
func (c *Client) Request(req any, out any) error {
	if c == nil || c.Path == "" {
		return ErrNoNiri
	}
	t := c.Timeout
	if t <= 0 {
		t = 2 * time.Second
	}
	conn, err := net.DialTimeout("unix", c.Path, t)
	if err != nil {
		return err
	}
	defer conn.Close()
	conn.SetDeadline(time.Now().Add(t))
	b, err := json.Marshal(req)
	if err != nil {
		return err
	}
	if _, err := conn.Write(append(b, '\n')); err != nil {
		return err
	}
	line, err := bufio.NewReader(conn).ReadBytes('\n')
	if err != nil && len(line) == 0 {
		return err
	}
	return decodeReply(line, out)
}

func decodeReply(line []byte, out any) error {
	var r struct {
		Ok  json.RawMessage `json:"Ok"`
		Err *string         `json:"Err"`
	}
	if err := json.Unmarshal(line, &r); err != nil {
		return err
	}
	if r.Err != nil {
		return errors.New("niri: " + *r.Err)
	}
	if out == nil {
		return nil
	}
	return json.Unmarshal(r.Ok, out)
}

// Windows lists the open windows, most recently focused first.
func (c *Client) Windows() ([]Window, error) {
	var r struct {
		Windows []Window `json:"Windows"`
	}
	if err := c.Request("Windows", &r); err != nil {
		return nil, err
	}
	return r.Windows, nil
}

// Workspaces lists the workspaces of every output.
func (c *Client) Workspaces() ([]Workspace, error) {
	var r struct {
		Workspaces []Workspace `json:"Workspaces"`
	}
	if err := c.Request("Workspaces", &r); err != nil {
		return nil, err
	}
	sort.Slice(r.Workspaces, func(i, j int) bool {
		a, b := r.Workspaces[i], r.Workspaces[j]
		if a.Output != b.Output {
			return a.Output < b.Output
		}
		return a.Idx < b.Idx
	})
	return r.Workspaces, nil
}

// Action runs one niri action, named as niri's IPC names it, with its fields.
func (c *Client) Action(name string, fields map[string]any) error {
	if fields == nil {
		fields = map[string]any{}
	}
	return c.Request(map[string]any{"Action": map[string]any{name: fields}}, nil)
}

// FocusWindow brings a window to the front (switching workspace if needed).
func (c *Client) FocusWindow(id uint64) error {
	return c.Action("FocusWindow", map[string]any{"id": id})
}

// CloseWindow asks a window to close.
func (c *Client) CloseWindow(id uint64) error {
	return c.Action("CloseWindow", map[string]any{"id": &id})
}

// Spawn starts a program as a child of niri, so it outlives Ember.
func (c *Client) Spawn(argv []string) error {
	return c.Action("Spawn", map[string]any{"command": argv})
}

// FocusWorkspace switches to the workspace with this id.
func (c *Client) FocusWorkspace(idx int) error {
	return c.Action("FocusWorkspace", map[string]any{"reference": map[string]any{"Index": idx}})
}

// Quit ends the niri session (signs out).
func (c *Client) Quit() error {
	return c.Action("Quit", map[string]any{"skip_confirmation": true})
}

// PowerOffMonitors turns the screens off until the next input.
func (c *Client) PowerOffMonitors() error { return c.Action("PowerOffMonitors", nil) }
