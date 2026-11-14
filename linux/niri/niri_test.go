package niri

import (
	"bufio"
	"encoding/json"
	"net"
	"path/filepath"
	"testing"
)

// fake serves one canned reply per connection and records the requests.
func fake(t *testing.T, reply func(req string) string) (*Client, *[]string) {
	t.Helper()
	p := filepath.Join(t.TempDir(), "niri.sock")
	l, err := net.Listen("unix", p)
	if err != nil {
		t.Skip("unix sockets unavailable:", err)
	}
	t.Cleanup(func() { l.Close() })
	var got []string
	go func() {
		for {
			c, err := l.Accept()
			if err != nil {
				return
			}
			line, _ := bufio.NewReader(c).ReadString('\n')
			got = append(got, line[:len(line)-1])
			c.Write([]byte(reply(line[:len(line)-1]) + "\n"))
			c.Close()
		}
	}()
	return &Client{Path: p}, &got
}

func TestWindows(t *testing.T) {
	c, got := fake(t, func(string) string {
		return `{"Ok":{"Windows":[{"id":7,"title":"Lite Go","app_id":"litego","pid":42,"workspace_id":1,"is_focused":true,"is_floating":false,"is_urgent":false,"layout":{}}]}}`
	})
	ws, err := c.Windows()
	if err != nil {
		t.Fatal(err)
	}
	if len(ws) != 1 || ws[0].ID != 7 || ws[0].AppID != "litego" || !ws[0].Focused {
		t.Fatalf("windows: %+v", ws)
	}
	if (*got)[0] != `"Windows"` {
		t.Fatalf("request: %s", (*got)[0])
	}
}

func TestActions(t *testing.T) {
	c, got := fake(t, func(string) string { return `{"Ok":"Handled"}` })
	if err := c.FocusWindow(7); err != nil {
		t.Fatal(err)
	}
	c.Spawn([]string{"foot"})
	c.Quit()
	want := []string{
		`{"Action":{"FocusWindow":{"id":7}}}`,
		`{"Action":{"Spawn":{"command":["foot"]}}}`,
		`{"Action":{"Quit":{"skip_confirmation":true}}}`,
	}
	for i, w := range want {
		var a, b any
		json.Unmarshal([]byte((*got)[i]), &a)
		json.Unmarshal([]byte(w), &b)
		ja, _ := json.Marshal(a)
		jb, _ := json.Marshal(b)
		if string(ja) != string(jb) {
			t.Errorf("request %d: %s, want %s", i, (*got)[i], w)
		}
	}
}

func TestErr(t *testing.T) {
	c, _ := fake(t, func(string) string { return `{"Err":"no such window"}` })
	if err := c.FocusWindow(1); err == nil || err.Error() != "niri: no such window" {
		t.Fatalf("err: %v", err)
	}
	var none *Client
	if err := none.FocusWindow(1); err != ErrNoNiri {
		t.Fatalf("nil client: %v", err)
	}
}
