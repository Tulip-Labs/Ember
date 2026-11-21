import CAdw
import Dispatch
import FoundationEssentials
import Glibc

// What floats over everything, in glass: the search with Files and
// Terminal beside it; along the bottom the appearance (Light, Auto, Dark),
// the hidden apps, the page dots and the power button; and the panels and
// notes they open.

final class Bar {
    unowned let shell: Shell
    private var stage: Stage { shell.stage }

    // the search
    private var search: Item!
    private var entry: GtkW!
    private var files: Item!
    private var term: Item!
    private(set) var query = ""

    // along the bottom
    private var seg: Item!
    private var segButtons: [(Appearance, GtkW)] = []
    private var thumb = LiquidSpan()
    private var eye: Item!
    private var eyeGlyph: GtkW!
    private var dots: Item!
    private var dotsBox: GtkW!
    private var power: Item!

    // panels and notes
    private var panel: Item?
    private var menu: Item?
    private var noteItem: Item?
    private var noteTimer: UInt32 = 0
    private var frame = Shell.Frame()

    init(_ shell: Shell) {
        self.shell = shell
        buildSearch()
        buildBottom()
    }

    // MARK: the search

    private func buildSearch() {
        let h = UI.box(false, 10)
        let g = Glyphs.view(.search, size: 18)
        gtk_widget_add_css_class(g, "ember-dim")
        UI.append(h, g)
        entry = gtk_text_new()!
        UI.cls(entry, "ember-search")
        gtk_widget_set_hexpand(entry, 1)
        gtk_widget_set_valign(entry, GTK_ALIGN_CENTER)
        gtk_text_set_placeholder_text(cp(entry), "Search")
        on(Ptr(entry), "changed") { [unowned self] in
            let q = UI.text(self.entry)
            guard q != self.query else { return }
            self.query = q
            let hidden = q.trimmed().lowercased() == "hidden"
            if hidden != self.shell.grid.hiddenMode { self.setHiddenMode(hidden, fromSearch: true) } else { self.shell.grid.refilter() }
        }
        UI.append(h, entry)
        gtk_widget_set_margin_start(h, 16)
        gtk_widget_set_margin_end(h, 16)
        search = stage.add(h, .overlay, glass: shell.palette.card(22))
        files = stage.add(UI.round(.folder, "Files") { [unowned self] in self.run("Files", ["xdg-open", Paths.home]) }, .overlay, glass: shell.palette.button, reactive: true)
        term = stage.add(UI.round(.terminal, "Terminal") { [unowned self] in self.run("the terminal", Run.terminalAlone()) }, .overlay, glass: shell.palette.button, reactive: true)
    }

    var searchFocused: Bool { gtk_widget_has_focus(entry) != 0 }
    var entryWidget: GtkW { entry }

    func focusSearch() {
        if gtk_widget_has_focus(entry) == 0 {
            gtk_widget_grab_focus(entry)
            gtk_editable_set_position(OpaquePointer(entry), -1)
        }
    }

    func clearSearch() {
        UI.setText(entry, "")
    }

    private func run(_ name: String, _ argv: [String]) {
        do {
            try Run.detached(argv)
            shell.close()
        } catch {
            note("Could not open \(name): \(error)")
        }
    }

    // MARK: the bottom

    private func buildBottom() {
        let h = UI.box(false, 2)
        for (a, g, name) in [(Appearance.light, Glyph.sun, "Light"), (.auto, .auto, "Auto"), (.dark, .moon, "Dark")] {
            let row = UI.box(false, 7)
            UI.append(row, Glyphs.view(g, size: 16))
            UI.append(row, UI.label(name))
            let b = UI.button(row, ["ember-seg"]) { [unowned self] in self.shell.setAppearance(a) }
            gtk_widget_set_tooltip_text(b, a == .auto ? "Light by day, dark by night" : "\(name) appearance")
            UI.append(h, b)
            segButtons.append((a, b))
        }
        gtk_widget_set_margin_start(h, 4)
        gtk_widget_set_margin_end(h, 4)
        seg = stage.add(h, .overlay, glass: shell.palette.card(23))
        // the selected one sits on a drop of glass that slides
        seg.overGlass = { [unowned self] s, r in
            guard self.thumb.hi.value > self.thumb.lo.value else { return }
            let t = Rect(x: r.x + self.thumb.lo.value, y: r.y + 5, w: self.thumb.hi.value - self.thumb.lo.value, h: r.h - 10)
            var g = self.shell.palette.button
            g.tint = self.shell.dark ? RGBA(1, 1, 1, 0.16) : RGBA(1, 1, 1, 0.75)
            g.shadow = 0.5
            Draw.glass(s, nil, t, g)
        }

        eyeGlyph = Glyphs.view(.eyeOff, size: 20)
        let eb = UI.button(eyeGlyph, ["ember-round"]) { [unowned self] in self.setHiddenMode(!self.shell.grid.hiddenMode) }
        gtk_widget_set_size_request(eb, 46, 46)
        eye = stage.add(eb, .overlay, glass: shell.palette.button, reactive: true)

        dotsBox = UI.box(false, 0)
        dots = stage.add(dotsBox, .overlay)

        power = stage.add(UI.round(.power, "Power", size: 46) { [unowned self] in self.togglePower() }, .overlay, glass: shell.palette.button, reactive: true)
        appearanceChanged()
    }

    func restyle() {
        search.glass = shell.palette.card(22)
        seg.glass = shell.palette.card(23)
        for it in [files, term, eye, power] { it?.glass = shell.palette.button }
        panel?.glass = shell.palette.panel(22)
        menu?.glass = shell.palette.panel(18)
        noteItem?.glass = shell.palette.panel(22)
    }

    func appearanceChanged() {
        for (a, b) in segButtons { UI.setCls(b, "on", a == shell.settings.appearance) }
        moveThumb(animate: true)
    }

    private func moveThumb(animate: Bool) {
        guard let b = segButtons.first(where: { $0.0 == shell.settings.appearance })?.1 else { return }
        var o = graphene_point_t(), out = graphene_point_t()
        guard gtk_widget_compute_point(b, seg.w, &o, &out) != 0 else { return }
        let x = Double(out.x), w = Double(gtk_widget_get_width(b))
        guard w > 0 else { return }
        thumb.go(x, x + w, animate: animate && stage.animations)
        stage.kick()
    }

    func step(_ dt: Double) -> Bool { thumb.step(dt) }

    func pagesChanged() {
        guard dotsBox != nil else { return }
        let n = shell.grid.pages.count
        var child = gtk_widget_get_first_child(dotsBox)
        while let c = child {
            child = gtk_widget_get_next_sibling(c)
            gtk_box_remove(cp(dotsBox), c)
        }
        if n > 1 {
            for i in 0..<n {
                let d = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0)!
                UI.cls(d, "ember-dot")
                if i == shell.grid.page { UI.cls(d, "on") }
                let b = UI.button(d) { [unowned self] in self.shell.grid.go(i) }
                gtk_widget_set_size_request(b, 18, 24)
                gtk_widget_set_valign(d, GTK_ALIGN_CENTER)
                gtk_widget_set_halign(d, GTK_ALIGN_CENTER)
                UI.append(dotsBox, b)
            }
        }
        layoutDots()
        updateEye()
    }

    private func layoutDots() {
        let (w, h) = UI.natural(dotsBox)
        let b = frame.bottom
        stage.place(dots, Rect(x: b.midX - w / 2, y: b.midY - h / 2, w: w, h: h), animate: false)
        gtk_widget_set_child_visible(dots.w, shell.grid.pages.count > 1 ? 1 : 0)
    }

    private func updateEye() {
        let n = shell.settings.hidden.count
        let on = shell.grid.hiddenMode
        Glyphs.set(eyeGlyph, on ? .eye : .eyeOff)
        gtk_widget_set_tooltip_text(eye.w, on ? "Back to all apps" : "Hidden apps (\(n))")
        stage.show(eye, n > 0 || on)
    }

    func setHiddenMode(_ on: Bool, fromSearch: Bool = false) {
        if !on && !fromSearch && query.lowercased() == "hidden" { clearSearch() }
        shell.grid.setHiddenMode(on)
        gtk_text_set_placeholder_text(cp(entry), on ? "Hidden apps: right-click one to show it again" : "Search")
        updateEye()
    }

    // MARK: layout

    func layout(_ f: Shell.Frame) {
        frame = f
        stage.place(search, f.search)
        let s = f.search
        stage.place(files, Rect(x: s.maxX + 12, y: s.y, w: 44, h: 44))
        stage.place(term, Rect(x: s.maxX + 64, y: s.y, w: 44, h: 44))
        let b = f.bottom
        let (sw, _) = UI.natural(seg.w)
        stage.place(seg, Rect(x: b.x, y: b.y, w: sw, h: b.h))
        stage.place(eye, Rect(x: b.x + sw + 12, y: b.y, w: b.h, h: b.h))
        stage.place(power, Rect(x: b.maxX - b.h, y: b.y, w: b.h, h: b.h))
        layoutDots()
        if let p = panel { stage.place(p, panelRect(p)) }
        if let n = noteItem { stage.place(n, noteRect(n)) }
        after(ms: 30) { [weak self] in self?.moveThumb(animate: false) }
    }

    // MARK: panels

    var overlayOpen: Bool { panel != nil || menu != nil }

    @discardableResult
    func closeOverlays() -> Bool {
        var any = false
        if let p = panel { stage.remove(p); panel = nil; any = true }
        if let m = menu { stage.remove(m); menu = nil; any = true }
        return any
    }

    /// a press: one away from an open panel or menu closes it
    func pressed(_ x: Double, _ y: Double) {
        if let p = panel, !p.frame.rect.contains(x, y), !power.frame.rect.contains(x, y) {
            stage.remove(p)
            panel = nil
        }
        if let m = menu, !m.frame.rect.contains(x, y) {
            stage.remove(m)
            menu = nil
        }
    }

    private func panelRect(_ p: Item) -> Rect {
        let (w, h) = UI.natural(p.w)
        let pw = max(260, w)
        return Rect(x: power.frame.target.maxX - pw, y: power.frame.target.y - 14 - h, w: pw, h: h)
    }

    private func togglePower() {
        if let p = panel {
            stage.remove(p)
            panel = nil
            return
        }
        openPower()
    }

    func openPower() {
        guard panel == nil else { return }
        let v = UI.box(true, 2)
        gtk_widget_set_margin_top(v, 8)
        gtk_widget_set_margin_bottom(v, 8)
        gtk_widget_set_margin_start(v, 6)
        gtk_widget_set_margin_end(v, 6)
        let niri = Niri.shared
        var rows: [(Glyph, String, () -> Void)] = [
            (.lock, "Lock", { [unowned self] in self.lock() }),
            (.sleep, "Sleep", { [unowned self] in self.power("Sleep", [["systemctl", "suspend"], ["loginctl", "suspend"]], hide: true) }),
        ]
        if niri != nil {
            rows.append((.screens, "Turn off screens", { [unowned self] in
                self.shell.close()
                after(ms: 400) { try? Niri.shared?.powerOffMonitors() }
            }))
            rows.append((.signout, "Sign out", { try? Niri.shared?.quit() }))
        }
        rows.append((.restart, "Restart", { [unowned self] in self.power("Restart", [["systemctl", "reboot"], ["loginctl", "reboot"]]) }))
        rows.append((.power, "Shut down", { [unowned self] in self.power("Shut down", [["systemctl", "poweroff"], ["loginctl", "poweroff"]]) }))
        for (g, t, f) in rows { UI.append(v, UI.row(g, t, f).0) }
        UI.append(v, sep())
        if niri != nil {
            let barShown = !Niri.barHidden
            let (b, _) = UI.row(.bar, "Top bar") { [unowned self] in
                let show = Niri.barHidden
                DispatchQueue.global().async { Niri.setBar(shown: show) }
                Paths.touch(Paths.config + "/bar-hidden-once")
                self.closeOverlays()
                self.note(show ? "The top bar is back" : "The top bar is hidden")
            }
            UI.setCls(b, "on", barShown)
            UI.append(v, b)
            let (w, _) = UI.row(.image, "Iris wallpaper") { [unowned self] in self.toggleWallpaper() }
            UI.setCls(w, "on", shell.settings.wallpaper)
            UI.append(v, w)
        }
        let (u, _) = UI.row(.download, "Automatic updates") { [unowned self] in
            self.shell.settings.autoUpdate.toggle()
            self.shell.saveSettings()
            self.closeOverlays()
            self.note(self.shell.settings.autoUpdate ? "Ember keeps itself up to date" : "Automatic updates are off")
        }
        UI.setCls(u, "on", shell.settings.autoUpdate)
        UI.append(v, u)
        let p = stage.add(v, .overlay, glass: shell.palette.panel(22))
        panel = p
        stage.place(p, panelRect(p), animate: false)
        p.alpha.snap(0)
        stage.show(p, true)
    }

    private func sep() -> GtkW {
        let s = gtk_separator_new(GTK_ORIENTATION_HORIZONTAL)!
        UI.cls(s, "ember-sep")
        return s
    }

    private func toggleWallpaper() {
        shell.settings.wallpaper.toggle()
        shell.saveSettings()
        let s = shell.settings
        closeOverlays()
        DispatchQueue.global().async {
            if s.wallpaper { _ = Niri.hideOtherWallpapers() } else { _ = Niri.showOtherWallpapers() }
            Wallpaper.changed(s)
        }
        note(s.wallpaper ? "Iris is your wallpaper, light by day and dark by night" : "Your own wallpaper comes back at the next sign-in")
    }

    private func lock() {
        shell.close()
        let cands: [[String]] = [["swaylock", "-f"], ["hyprlock"], ["gtklock"], ["loginctl", "lock-session"]]
        if let c = cands.first(where: { Paths.which($0[0]) != nil }) { try? Run.detached(c) }
    }

    private func power(_ name: String, _ cands: [[String]], hide: Bool = false) {
        guard let c = cands.first(where: { Paths.which($0[0]) != nil }) else {
            note("\(name) did not work: \(cands[0][0]) is not installed")
            return
        }
        if hide { shell.close() }
        do { try Run.detached(c) } catch { note("\(name) did not work: \(error)") }
    }

    /// a right click on an app
    func tileMenu(_ a: App, hidden: Bool, at p: (Double, Double)) {
        closeOverlays()
        let v = UI.box(true, 2)
        gtk_widget_set_margin_top(v, 6)
        gtk_widget_set_margin_bottom(v, 6)
        gtk_widget_set_margin_start(v, 6)
        gtk_widget_set_margin_end(v, 6)
        UI.append(v, UI.row(.open, "Open") { [unowned self] in self.closeOverlays(); self.shell.grid.launch(a) }.0)
        if hidden {
            UI.append(v, UI.row(.eye, "Show in Ember") { [unowned self] in self.closeOverlays(); self.shell.grid.setHidden(a, false) }.0)
        } else {
            UI.append(v, UI.row(.eyeOff, "Hide from Ember") { [unowned self] in self.closeOverlays(); self.shell.grid.setHidden(a, true) }.0)
        }
        let m = stage.add(v, .overlay, glass: shell.palette.panel(18))
        menu = m
        let (w, h) = UI.natural(v)
        let mw = max(220, w)
        let x = min(stage.width - mw - 12, max(12, p.0))
        let y = min(stage.height - h - 12, max(12, p.1))
        stage.place(m, Rect(x: x, y: y, w: mw, h: h), animate: false)
        m.alpha.snap(0)
        stage.show(m, true)
    }

    // MARK: notes

    private func noteRect(_ n: Item) -> Rect {
        let (w, h) = UI.natural(n.w)
        let nw = min(w, stage.width - 2 * frame.margin)
        return Rect(x: (stage.width - nw) / 2, y: frame.bottom.y - 18 - h, w: nw, h: h)
    }

    /// a short note above the bottom bar, with a button if `action` is given
    func note(_ text: String, action: String? = nil, _ f: (() -> Void)? = nil) {
        if let old = noteItem { stage.remove(old) }
        if noteTimer != 0 { g_source_remove(noteTimer); noteTimer = 0 }
        let h = UI.box(false, 14)
        let l = UI.label(text, "ember-note")
        gtk_label_set_wrap(OpaquePointer(l), 1)
        gtk_label_set_max_width_chars(OpaquePointer(l), 70)
        UI.append(h, l)
        if let action, let f {
            let b = UI.button(UI.label(action), ["ember-action"]) { [unowned self] in
                if let n = self.noteItem { self.stage.remove(n); self.noteItem = nil }
                f()
            }
            gtk_widget_set_valign(b, GTK_ALIGN_CENTER)
            UI.append(h, b)
        }
        gtk_widget_set_margin_top(h, 11)
        gtk_widget_set_margin_bottom(h, 11)
        gtk_widget_set_margin_start(h, 20)
        gtk_widget_set_margin_end(h, action == nil ? 20 : 8)
        let n = stage.add(h, .overlay, glass: shell.palette.panel(22))
        noteItem = n
        stage.place(n, noteRect(n), animate: false)
        n.alpha.snap(0)
        stage.show(n, true)
        if action == nil {
            noteTimer = after(ms: 4500) { [weak self] in
                guard let self else { return }
                self.noteTimer = 0
                if let n = self.noteItem { self.stage.remove(n); self.noteItem = nil }
            }
        }
    }
}
