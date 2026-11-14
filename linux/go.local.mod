module ember

go 1.24.0

require (
	gioui.org v0.10.3
	golang.org/x/image v0.26.0
)

require (
	gioui.org/shader v1.0.9 // indirect
	github.com/go-text/typesetting v0.3.5 // indirect
	github.com/godbus/dbus/v5 v5.2.2 // indirect
	golang.org/x/exp/shiny v0.0.0-20250408133849-7e4ce0ab07d0 // indirect
	golang.org/x/net v0.48.0 // indirect
	golang.org/x/sys v0.39.0 // indirect
	golang.org/x/text v0.32.0 // indirect
)

replace (
	eliasnaur.com/font => /home/claude/deps/stub/efont
	gioui.org => /home/claude/deps/gio
	gioui.org/cpu => /home/claude/deps/stub/cpu
	gioui.org/shader => /home/claude/deps/shader
	github.com/dchest/siphash => /home/claude/deps/stub/siphash
	github.com/go-text/typesetting => /home/claude/deps/typesetting
	github.com/go-text/typesetting-utils => /home/claude/deps/stub/tsutils
	github.com/godbus/dbus/v5 => /home/claude/deps/dbus
	github.com/google/uuid => /home/claude/deps/stub/uuid
	github.com/ncruces/go-sqlite3 => /home/claude/deps/sqlite3
	github.com/ncruces/julianday => /home/claude/deps/julianday
	github.com/ncruces/sort => /home/claude/deps/ncsort
	github.com/ncruces/wbt => /home/claude/deps/wbt
	github.com/psanford/httpreadat => /home/claude/deps/stub/httpreadat
	github.com/tetratelabs/wazero => /home/claude/deps/wazero
	golang.org/x/crypto => /home/claude/deps/stub/xcrypto
	golang.org/x/exp => /home/claude/deps/exp
	golang.org/x/exp/shiny => /home/claude/deps/exp/shiny
	golang.org/x/image => /home/claude/deps/image
	golang.org/x/net => /home/claude/deps/net
	golang.org/x/sync => /home/claude/deps/stub/xsync
	golang.org/x/sys => /home/claude/deps/sys
	golang.org/x/text => /home/claude/deps/text
	lukechampine.com/adiantum => /home/claude/deps/stub/adiantum
)
