import CAdw
import Dispatch
import FoundationEssentials
import Glibc

// The apps, in pages, as in a Mac's Launchpad: each app's icon with its name
// under it. The pages slide sideways (the wheel, the arrow keys, the dots);
// the search narrows them as you type; a right click hides an app.

final class Grid {
    unowned let shell: Shell
    private(set) var apps: [App] = []
    private var tiles: [String: Tile] = [:]
    /// what the pages show now, in order
    private(set) var shown: [App] = []
    private(set) var pages: [Item] = []
    private(set) var page = 0
    private(set) var cols = 6, rows = 4
    private var cell = (w: 120.0, h: 120.0)
    private var iconSize: Int32 = 72
    private var area = Rect()
    private var pageRect = Rect()
    /// the tile the keys are on
    private var sel: Int?
    private var empty: Item!
    private var emptyLabel: GtkW!
    private var wheel = 0.0
    private var wheelAt = Date.distantPast
    var hiddenMode = false

    final class Tile {
        let app: App
        let button: GtkW
        let image: GtkW
        let label: GtkW
        var part: Part
        init(app: App, button: GtkW, image: GtkW, label: GtkW, part: Part) {
            self.app = app; self.button = button; self.image = image; self.label = label; self.part = part
        }
    }

    init(_ shell: Shell) {
        self.shell = shell
        emptyLabel = UI.label("", "ember-empty")
        empty = shell.stage.add(emptyLabel, .page)
        shell.stage.show(empty, false, animated: false)
        reload()
    }

    /// reads the apps again (Ember reads them each time it comes up)
    func reload() {
        apps = Apps.all()
        var keep: [String: Tile] = [:]
        for a in apps { keep[a.id] = tiles[a.id] ?? makeTile(a) }
        for (id, t) in tiles where keep[id] == nil { detach(t); g_object_unref(Ptr(t.button)) }
        tiles = keep
        refilter()
    }

    private func makeTile(_ a: App) -> Tile {
        let v = UI.box(true, 8)
        let img: GtkW
        if let icon = a.icon {
            img = gtk_image_new_from_gicon(icon)
        } else {
            img = gtk_image_new_from_icon_name("application-x-executable")
        }
        gtk_image_set_pixel_size(OpaquePointer(img), iconSize)
        let l = UI.label(a.name)
        gtk_label_set_ellipsize(OpaquePointer(l), PANGO_ELLIPSIZE_END)
        gtk_label_set_justify(OpaquePointer(l), GTK_JUSTIFY_CENTER)
        UI.append(v, img)
        UI.append(v, l)
        let b = UI.button(v, ["ember-tile"]) { [unowned self] in self.launch(a) }
        if !a.generic.isEmpty && a.generic != a.name { gtk_widget_set_tooltip_text(b, a.generic) }
        g_object_ref_sink(Ptr(b))
        // a right click: Open, or Hide (Show in the hidden apps)
        let rc = gtk_gesture_click_new()!
        gtk_gesture_single_set_button(OpaquePointer(rc), 3)
        onPress(Ptr(rc), "pressed") { [unowned self] _, x, y in
            var p = graphene_point_t(), out = graphene_point_t()
            p.x = Float(x); p.y = Float(y)
            _ = gtk_widget_compute_point(b, self.shell.stage.widget, &p, &out)
            self.shell.bar.tileMenu(a, hidden: self.hiddenMode, at: (Double(out.x), Double(out.y)))
        }
        gtk_widget_add_controller(b, OpaquePointer(rc))
        shell.stage.watch(b)
        return Tile(app: a, button: b, image: img, label: l, part: Part(b, shell.palette.tile, onlyActive: true))
    }

    private func detach(_ t: Tile) {
        if let parent = gtk_widget_get_parent(t.button) {
            gtk_grid_remove(cp(parent), t.button)
        }
    }

    func restyle() {
        for t in tiles.values { t.part.glass = shell.palette.tile }
    }

    // MARK: what shows

    var hiddenIDs: Set<String> { Set(shell.settings.hidden) }

    /// the apps the search (or the hidden view) lets through
    func refilter(keepPage: Bool = false) {
        let q = shell.bar?.query ?? ""
        let hidden = hiddenIDs
        let pool = apps.filter { hiddenMode == hidden.contains($0.id) }
        shown = Apps.filter(pool, q)
        sel = nil
        if !keepPage { page = 0 }
        rebuild()
        // while searching, Return opens the first match: it shows as chosen
        if !q.trimmed().isEmpty && !shown.isEmpty { select(0) }
    }

    private func rebuild() {
        let per = max(1, cols * rows)
        let n = max(1, (shown.count + per - 1) / per)
        for t in tiles.values { detach(t); t.part.selected = false }
        while pages.count > n { shell.stage.remove(pages.removeLast(), animated: false) }
        while pages.count < n {
            let g = gtk_grid_new()!
            gtk_grid_set_row_homogeneous(cp(g), 1)
            gtk_grid_set_column_homogeneous(cp(g), 1)
            // a page with fewer apps keeps its rows at the top
            gtk_widget_set_valign(g, GTK_ALIGN_START)
            let it = shell.stage.add(g, .page)
            it.alpha.snap(shell.open.target)
            pages.append(it)
        }
        for (i, a) in shown.enumerated() {
            guard let t = tiles[a.id] else { continue }
            let p = i / per, k = i % per
            gtk_grid_attach(cp(pages[p].w), t.button, Int32(k % cols), Int32(k / cols), 1, 1)
        }
        for (p, it) in pages.enumerated() {
            it.parts = shown[min(shown.count, p * per)..<min(shown.count, (p + 1) * per)].compactMap { tiles[$0.id]?.part }
        }
        // a short single row (a search) is centred; full pages line up
        for it in pages { gtk_widget_set_halign(it.w, n == 1 && shown.count < cols ? GTK_ALIGN_CENTER : GTK_ALIGN_START) }
        page = min(page, n - 1)
        let q = shell.bar?.query ?? ""
        if shown.isEmpty {
            UI.setLabel(emptyLabel, hiddenMode ? "No hidden apps" : q.isEmpty ? "No apps found" : "No apps match “\(q)”")
        }
        shell.stage.show(empty, shown.isEmpty, animated: false)
        place(animate: false)
        shell.bar?.pagesChanged()
    }

    // MARK: layout

    func layout(_ f: Shell.Frame) {
        area = f.grid
        // icons and cells grow with the screen, as many as fit
        let icon = Int32(min(96, max(48, min(f.w / 15, f.h / 11.5)).rounded()))
        let cw = max(Double(icon) * 1.85, 112)
        let ch = Double(icon) + 62
        let c = max(3, min(8, Int(area.w / cw)))
        let r = max(1, Int(area.h / ch))
        let changed = c != cols || r != rows || icon != iconSize
        cols = c
        rows = r
        cell = (cw, ch)
        if icon != iconSize {
            iconSize = icon
            for t in tiles.values { gtk_image_set_pixel_size(OpaquePointer(t.image), icon) }
        }
        for t in tiles.values {
            gtk_widget_set_size_request(t.button, Int32(cw) - 10, Int32(ch) - 6)
            gtk_label_set_max_width_chars(OpaquePointer(t.label), Int32(cw / 8.2))
        }
        let pw = Double(cols) * cw, ph = Double(rows) * ch
        pageRect = Rect(x: area.x + (area.w - pw) / 2, y: area.y + max(0, (area.h - ph) / 3), w: pw, h: ph)
        let (ew, eh) = UI.natural(emptyLabel)
        shell.stage.place(empty, Rect(x: area.midX - ew / 2, y: area.y + area.h * 0.3, w: ew, h: eh), animate: false)
        if changed { rebuild() } else { place(animate: false) }
    }

    /// puts the pages side by side, the current one in view
    private func place(animate: Bool) {
        let w = shell.stage.width > 0 ? shell.stage.width : 1280
        for (i, it) in pages.enumerated() {
            var r = pageRect
            r.x += Double(i - page) * w
            shell.stage.place(it, r, animate: animate)
            // only the pages in view or sliding through are drawn
            gtk_widget_set_child_visible(it.w, abs(i - page) <= 1 || (animate && it.frame.rect.x.magnitude < w * 1.5) ? 1 : 0)
        }
        shell.stage.relayout()
        if animate {
            after(ms: 900) { [weak self] in
                guard let self else { return }
                for (i, it) in self.pages.enumerated() { gtk_widget_set_child_visible(it.w, abs(i - self.page) <= 1 ? 1 : 0) }
            }
        }
    }

    func go(_ p: Int) {
        let p = min(pages.count - 1, max(0, p))
        guard p != page else { return }
        // pages passed over on the way slide through too
        let lo = min(p, page), hi = max(p, page)
        for i in lo...hi { gtk_widget_set_child_visible(pages[i].w, 1) }
        page = p
        place(animate: true)
        if let s = sel, s / max(1, cols * rows) != page { select(page * cols * rows) }
        shell.bar.pagesChanged()
    }

    /// the wheel and touchpad turn the pages
    func scrolled(_ dx: Double, _ dy: Double) -> Bool {
        if shell.bar.overlayOpen { return false }
        wheel += abs(dx) > abs(dy) ? dx : dy
        guard abs(wheel) >= 1, Date().timeIntervalSince(wheelAt) > 0.35 else { return true }
        go(page + (wheel > 0 ? 1 : -1))
        wheel = 0
        wheelAt = Date()
        return true
    }

    // MARK: open and close

    func opening() {
        for it in pages {
            it.scale.value = 1.08
            it.alpha.value = 0
            shell.stage.show(it, true)
        }
    }

    func closing() {
        for it in pages {
            it.alpha.target = 0
            it.scale.target = 1.06
        }
    }

    // MARK: keys

    private func select(_ i: Int?) {
        if let s = sel, s < shown.count { tiles[shown[s].id]?.part.selected = false }
        sel = i.map { min(shown.count - 1, max(0, $0)) }
        if let s = sel, s >= 0, s < shown.count {
            tiles[shown[s].id]?.part.selected = true
            let p = s / max(1, cols * rows)
            if p != page { go(p) }
        }
        shell.stage.kick()
    }

    func move(_ d: Int) {
        guard !shown.isEmpty else { return }
        guard let s = sel else { select(page * cols * rows); return }
        select(s + d)
    }

    func launchSelected() {
        let i = sel ?? (shown.isEmpty ? nil : page * cols * rows)
        guard let i, i < shown.count else { return }
        launch(shown[i])
    }

    func launch(_ a: App) {
        do {
            try a.launch()
            shell.close()
        } catch {
            shell.note("Could not open \(a.name): \(error)")
        }
    }

    // MARK: hiding apps

    func setHidden(_ a: App, _ hide: Bool) {
        var h = shell.settings.hidden.filter { $0 != a.id }
        if hide { h.append(a.id) }
        shell.settings.hidden = h
        shell.saveSettings()
        refilter(keepPage: true)
        shell.note(hide ? "\(a.name) is hidden: the eye at the bottom shows the hidden apps" : "\(a.name) is back")
    }

    func setHiddenMode(_ on: Bool) {
        hiddenMode = on
        refilter()
    }
}
