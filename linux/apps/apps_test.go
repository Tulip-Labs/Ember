package apps

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

func TestFields(t *testing.T) {
	cases := map[string][]string{
		`firefox %u`:                     {"firefox"},
		`"/opt/My App/run" --flag %F`:    {"/opt/My App/run", "--flag"},
		`sh -c "echo \"hi\" && sleep 1"`: {"sh", "-c", `echo "hi" && sleep 1`},
		`app --rate=50%%`:                {"app", "--rate=50%"},
		`env FOO=1 code --new-window %U`: {"env", "FOO=1", "code", "--new-window"},
		`flatpak run org.x.Y --file-forwarding org.x.Y @@u %u @@`: {"flatpak", "run", "org.x.Y", "--file-forwarding", "org.x.Y", "@@u", "@@"},
	}
	for in, want := range cases {
		if got := Fields(in); !reflect.DeepEqual(got, want) {
			t.Errorf("Fields(%q) = %q, want %q", in, got, want)
		}
	}
}

func write(t *testing.T, dir, name, body string) {
	t.Helper()
	os.MkdirAll(dir, 0o755)
	if err := os.WriteFile(filepath.Join(dir, name), []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestScan(t *testing.T) {
	t.Setenv("LANG", "es_CO.UTF-8")
	user, sys := filepath.Join(t.TempDir(), "user"), filepath.Join(t.TempDir(), "sys")
	write(t, sys, "files.desktop", "[Desktop Entry]\nType=Application\nName=Files\nName[es]=Archivos\nExec=nautilus --new-window\n")
	write(t, sys, "hidden.desktop", "[Desktop Entry]\nType=Application\nName=Helper\nExec=helper\nNoDisplay=true\n")
	write(t, sys, "gnome.desktop", "[Desktop Entry]\nType=Application\nName=Gnome Only\nExec=x\nOnlyShowIn=GNOME;\n")
	write(t, sys, "missing.desktop", "[Desktop Entry]\nType=Application\nName=Gone\nExec=gone\nTryExec=/nonexistent/gone\n")
	write(t, sys, "editor.desktop", "[Desktop Entry]\nType=Application\nName=Editor\nExec=sysedit\n[Desktop Action new]\nName=New Window\nExec=other\n")
	write(t, user, "editor.desktop", "[Desktop Entry]\nType=Application\nName=My Editor\nExec=myedit %F\nKeywords=text;code;\n")
	write(t, filepath.Join(sys, "kde"), "term.desktop", "[Desktop Entry]\nType=Application\nName=Top\nExec=htop\nTerminal=true\n")
	got := Scan([]string{user, sys}, "niri")
	var names []string
	for _, a := range got {
		names = append(names, a.Name)
	}
	if want := []string{"Archivos", "My Editor", "Top"}; !reflect.DeepEqual(names, want) {
		t.Fatalf("names %q, want %q", names, want)
	}
	if got[1].ID != "editor.desktop" || got[1].Exec[0] != "myedit" || len(got[1].Exec) != 1 {
		t.Errorf("user override: %+v", got[1])
	}
	if got[2].ID != "kde-term.desktop" || !got[2].Terminal {
		t.Errorf("subfolder id: %+v", got[2])
	}
	if got[1].Matches("code") != 1 || got[1].Matches("edi") != 2 || got[1].Matches("zzz") != 0 {
		t.Errorf("matching")
	}
}
