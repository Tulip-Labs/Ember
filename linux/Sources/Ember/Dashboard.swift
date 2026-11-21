import CAdw
import Dispatch
import FoundationEssentials
import Glibc

// The dashboard along the top: the clock, then cards for the processor,
// memory, network, disk, battery and the screen's brightness. Clear glass
// over the wallpaper, as a Mac's widgets.

final class Dashboard {
    unowned let shell: Shell
    private var clock: Item!
    private var dateLabel: GtkW!
    private var timeLabel: GtkW!
    private var cards: [Card] = []
    private var stats = Stats()
    private var reading = false
    private var lastMinute = ""
    private var brightBusy = false
    private var brightWant: Int?
    private var dragging = false

    enum Kind { case cpu, memory, network, disk, battery, brightness }

    final class Card {
        let kind: Kind
        var item: Item!
        let glyph: GtkW
        let caps: GtkW
        let value: GtkW
        let caption: GtkW
        var level: GtkW?
        var scale: GtkW?
        init(_ kind: Kind, glyph: GtkW, caps: GtkW, value: GtkW, caption: GtkW) {
            self.kind = kind; self.glyph = glyph; self.caps = caps; self.value = value; self.caption = caption
        }
    }

    init(_ shell: Shell) {
        self.shell = shell
        let v = UI.box(true, 2)
        UI.cls(v, "ember-card")
        dateLabel = UI.label("", "ember-date", "ember-dim")
        timeLabel = UI.label("", "ember-clock")
        UI.left(dateLabel)
        UI.left(timeLabel)
        gtk_widget_set_vexpand(timeLabel, 1)
        gtk_label_set_yalign(OpaquePointer(timeLabel), 0.5)
        UI.append(v, dateLabel)
        UI.append(v, timeLabel)
        setMargins(v, 18, 24)
        clock = shell.stage.add(v, .chrome, glass: shell.palette.card(26))
        stats = shell.sys.read()
        var kinds: [Kind] = [.cpu, .memory, .network, .disk]
        if stats.battery >= 0 { kinds.append(.battery) }
        if stats.brightness >= 0 { kinds.append(.brightness) }
        for k in kinds { cards.append(make(k)) }
        tick()
        refresh()
    }

    private func setMargins(_ w: GtkW, _ v: Int32, _ h: Int32) {
        gtk_widget_set_margin_top(w, v)
        gtk_widget_set_margin_bottom(w, v)
        gtk_widget_set_margin_start(w, h)
        gtk_widget_set_margin_end(w, h)
    }

    private func make(_ k: Kind) -> Card {
        let glyph: Glyph = [.cpu: .cpu, .memory: .memory, .network: .wifi, .disk: .disk, .battery: .battery, .brightness: .sun][k]!
        let names: [Kind: String] = [.cpu: "PROCESSOR", .memory: "MEMORY", .network: "NETWORK", .disk: "DISK", .battery: "BATTERY", .brightness: "BRIGHTNESS"]
        let g = Glyphs.view(glyph, size: 18)
        let caps = UI.label(names[k]!, "ember-caps", "ember-dim")
        UI.left(caps)
        UI.ellipsize(caps, chars: 6)
        gtk_widget_set_hexpand(caps, 1)
        let head = UI.box(false, 8)
        UI.append(head, g)
        UI.append(head, caps)
        let value = UI.label("", "ember-value")
        let caption = UI.label("", "ember-caption", "ember-dim")
        for l in [value, caption] { UI.left(l); UI.ellipsize(l, chars: 6) }
        let v = UI.box(true, 0)
        UI.append(v, head)
        let gap = UI.box(true, 0)
        gtk_widget_set_vexpand(gap, 1)
        UI.append(v, gap)
        UI.append(v, value)
        UI.append(v, caption)
        let c = Card(k, glyph: g, caps: caps, value: value, caption: caption)
        if k == .brightness {
            let sc = gtk_scale_new_with_range(GTK_ORIENTATION_HORIZONTAL, 1, 100, 1)!
            UI.cls(sc, "ember")
            gtk_scale_set_draw_value(cp(sc), 0)
            gtk_widget_set_can_focus(sc, 0)
            gtk_widget_set_margin_top(sc, 10)
            gtk_range_set_value(cp(sc), Double(max(1, stats.brightness)))
            on(Ptr(sc), "value-changed") { [unowned self] in
                self.setBrightness(Int(gtk_range_get_value(cp(sc)).rounded()))
                self.shell.stage.dirtyChrome()
            }
            UI.append(v, sc)
            c.scale = sc
        } else {
            let lv = gtk_level_bar_new_for_interval(0, 1)!
            UI.cls(lv, "ember")
            gtk_level_bar_set_mode(OpaquePointer(lv), GTK_LEVEL_BAR_MODE_CONTINUOUS)
            for name in ["low", "high", "full"] { gtk_level_bar_remove_offset_value(OpaquePointer(lv), name) }
            gtk_widget_set_margin_top(lv, 10)
            UI.append(v, lv)
            c.level = lv
        }
        setMargins(v, 16, 18)
        var widget = v
        if k == .network {
            // the network card opens the Wi-Fi networks nearby in a terminal
            widget = UI.button(v) { [unowned self] in self.openNetworks() }
            gtk_widget_set_tooltip_text(widget, "Wi-Fi networks nearby and how to connect, in a terminal")
        }
        c.item = shell.stage.add(widget, .chrome, glass: shell.palette.card(26), reactive: k == .network)
        return c
    }

    func restyle() {
        clock.glass = shell.palette.card(26)
        for c in cards { c.item.glass = shell.palette.card(26) }
    }

    // MARK: layout

    func layout(_ f: Shell.Frame) {
        let r = f.dash
        let on = r.h > 0
        let gap = 14.0
        var cw = min(max(r.w * 0.27, 250), 460)
        // as many cards as fit, at least 132 wide each
        var n = cards.count
        while n > 0 && (r.w - cw - 16 - Double(n - 1) * gap) / Double(n) < 132 {
            if cw > 250 { cw = 250; continue }
            n -= 1
        }
        shell.stage.place(clock, on ? Rect(x: r.x, y: r.y, w: cw, h: r.h) : Rect(x: r.x, y: -200, w: cw, h: 128))
        gtk_widget_set_child_visible(clock.w, on ? 1 : 0)
        let x0 = r.x + cw + 16
        let each = n > 0 ? (r.maxX - x0 - Double(n - 1) * gap) / Double(n) : 0
        for (i, c) in cards.enumerated() {
            let shown = on && i < n
            gtk_widget_set_child_visible(c.item.w, shown ? 1 : 0)
            if shown { shell.stage.place(c.item, Rect(x: x0 + Double(i) * (each + gap), y: r.y, w: each, h: r.h)) }
        }
    }

    // MARK: readings

    /// the time as the language writes it (12 or 24 hours) and the date, by GLib
    private func format(_ fmt: String) -> String {
        guard let dt = g_date_time_new_now_local() else { return "" }
        defer { g_date_time_unref(dt) }
        return takeStr(g_date_time_format(dt, fmt)) ?? ""
    }

    private lazy var twelveHours: Bool = !format("%p").isEmpty

    private var ticks = 0

    /// every second: the clock (when the minute turns) and, every 3 s, the cards
    func tick() {
        let t = format(twelveHours ? "%-l:%M %p" : "%H:%M")
        if t != lastMinute {
            lastMinute = t
            UI.setLabel(timeLabel, t)
            UI.setLabel(dateLabel, format("%A, %-d %B"))
            shell.stage.dirtyChrome()
        }
        ticks += 1
        if ticks % 3 == 0 { refresh() }
    }

    private func refresh() {
        guard !reading else { return }
        reading = true
        let sys = shell.sys
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let s = sys.read()
            idle {
                guard let self else { return }
                self.reading = false
                self.stats = s
                self.show(s)
            }
        }
    }

    private func pct(_ a: Double, _ b: Double) -> Int { b > 0 ? Int((100 * a / b).rounded()) : 0 }

    private func show(_ s: Stats) {
        for c in cards {
            var frac = 0.0
            switch c.kind {
            case .cpu:
                UI.setLabel(c.value, "\(Int(s.cpu.rounded()))%")
                UI.setLabel(c.caption, "Processor load")
                frac = s.cpu / 100
            case .memory:
                UI.setLabel(c.value, "\(fixed(s.memUsed, 1)) / \(fixed(s.memTotal, 0)) GB")
                UI.setLabel(c.caption, "\(pct(s.memUsed, s.memTotal))% in use")
                frac = s.memTotal > 0 ? s.memUsed / s.memTotal : 0
            case .network:
                switch s.net.state {
                case .wired:
                    Glyphs.set(c.glyph, .ethernet)
                    UI.setLabel(c.value, "Wired")
                    UI.setLabel(c.caption, "Connected · \(s.net.name)")
                    frac = 1
                case .wifi:
                    Glyphs.set(c.glyph, .wifi)
                    UI.setLabel(c.value, s.net.name)
                    UI.setLabel(c.caption, "Signal \(s.net.signal)%")
                    frac = Double(s.net.signal) / 100
                case .none:
                    Glyphs.set(c.glyph, s.net.hasWifi ? .wifiOff : .ethernet)
                    UI.setLabel(c.value, s.net.hasWifi ? "Not connected" : "No network")
                    UI.setLabel(c.caption, "Offline")
                }
            case .disk:
                UI.setLabel(c.value, "\(fixed(s.diskFree, 0)) GB free")
                UI.setLabel(c.caption, "\(pct(s.diskTotal - s.diskFree, s.diskTotal))% used")
                frac = s.diskTotal > 0 ? (s.diskTotal - s.diskFree) / s.diskTotal : 0
            case .battery:
                UI.setLabel(c.value, "\(s.battery)%")
                UI.setLabel(c.caption, s.charging ? "Charging" : "On battery")
                frac = Double(s.battery) / 100
                Glyphs.setLevel(c.glyph, frac)
                UI.setCls(c.level!, "danger", s.battery <= 15 && !s.charging)
            case .brightness:
                UI.setLabel(c.value, "\(s.brightness)%")
                UI.setLabel(c.caption, "Drag to change")
                if !dragging && brightWant == nil, let sc = c.scale, Int(gtk_range_get_value(cp(sc))) != s.brightness {
                    gtk_range_set_value(cp(sc), Double(max(1, s.brightness)))
                }
            }
            if let lv = c.level { gtk_level_bar_set_value(OpaquePointer(lv), min(1, max(0, frac))) }
        }
        shell.stage.dirtyChrome()
    }

    /// the newest value wins; one change at a time goes to the screen
    private func setBrightness(_ p: Int) {
        brightWant = p
        if let c = cards.first(where: { $0.kind == .brightness }) { UI.setLabel(c.value, "\(p)%") }
        guard !brightBusy else { return }
        brightBusy = true
        let sys = shell.sys
        @Sendable func next() {
            guard let p = brightWant else { brightBusy = false; return }
            brightWant = nil
            DispatchQueue.global().async {
                sys.setBrightness(p)
                idle { next() }
            }
        }
        next()
    }

    private func openNetworks() {
        do {
            try Run.detached(Run.inTerminal(["sh", "-c", Dashboard.networkScript]))
            shell.close()
        } catch {
            shell.note("Could not open the terminal: \(error)")
        }
    }

    static let networkScript = #"""
    clear
    if ! command -v nmcli >/dev/null 2>&1; then
      echo "nmcli (NetworkManager) is not installed, so the networks cannot be listed."
      exec "${SHELL:-sh}"
    fi
    dev=$(nmcli -t -f DEVICE,TYPE device 2>/dev/null | awk -F: '$2=="wifi"{print $1; exit}')
    printf '\n  Wi-Fi networks nearby\n\n'
    if [ -n "$dev" ]; then
      nmcli --colors yes device wifi list --rescan yes
    else
      echo "  This computer has no Wi-Fi device."
    fi
    cat <<MANUAL

      How to use nmcli (NetworkManager)

      Connect to a network       nmcli device wifi connect "Name" --ask
      Connect to a hidden one    nmcli device wifi connect "Name" hidden yes --ask
      Look again for networks    nmcli device wifi list --rescan yes
      What is connected now      nmcli device status
      Disconnect                 nmcli device disconnect ${dev:-wlan0}
      Saved networks             nmcli connection show
      Forget a saved network     nmcli connection delete "Name"
      Turn Wi-Fi off or on       nmcli radio wifi off   /   nmcli radio wifi on
      Show the Wi-Fi password    nmcli device wifi show-password
      Menus instead of commands  nmtui

      "Name" is the network's name from the SSID column; --ask asks for the password.
      Type a command below, or close this window when you are done.

    MANUAL
    exec "${SHELL:-sh}"
    """#
}
