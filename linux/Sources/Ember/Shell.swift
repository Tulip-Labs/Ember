import CAdw
import Dispatch
import FoundationEssentials
import Glibc

// Ember's screen: the wallpaper blurred behind clear glass, the dashboard
// along the top, the search, the apps in pages (icons with their names, as
// in a Mac's Launchpad) and a bar along the bottom with the appearance,
// the pages and the power button.

final class Shell {
    let window: GtkW
    let stage = Stage()
    let sys = SysReader()
    var settings: Settings
    var palette: Palette
    var dark: Bool

    // what the screen is made of (the other files fill these in)
    var dash: Dashboard!
    var grid: Grid!
    var bar: Bar!

    /// the screen coming up (0 → 1) and going (→ 0)
    var open = Spring(0, stiffness: 170)
    /// one appearance giving way to the other
    var swap = Spring(1, stiffness: 120)
    var closing = false
    var onClosed: (() -> Void)?

    /// the layout's numbers, for the parts
    struct Frame {
        var w = 0.0, h = 0.0, margin = 56.0
        var dash = Rect(), search = Rect(), grid = Rect(), bottom = Rect()
    }
    private(set) var frame = Frame()

    init(settings: Settings) {
        self.settings = settings
        dark = settings.dark
        palette = Palette(dark: dark)
        window = gtk_window_new()!
        gtk_window_set_title(win, "Ember")
        gtk_window_set_decorated(win, 0)
        gtk_window_set_default_size(win, 1280, 800)
        UI.cls(window, "ember", dark ? "dark" : "light")
        gtk_window_set_child(win, stage.widget)
        setScheme()

        stage.background = { [unowned self] s, w, h in self.drawBack(s, w, h) }
        stage.layout = { [unowned self] w, h in self.layout(w, h) }
        stage.extraStep = { [unowned self] dt in self.step(dt) }

        dash = Dashboard(self)
        grid = Grid(self)
        bar = Bar(self)

        // a press away from a menu or panel closes it
        let click = gtk_gesture_click_new()!
        gtk_gesture_single_set_button(OpaquePointer(click), 0)
        gtk_event_controller_set_propagation_phase(OpaquePointer(click), GTK_PHASE_CAPTURE)
        onPress(Ptr(click), "pressed") { [unowned self] _, x, y in
            self.bar.pressed(x, y)
            gtk_gesture_set_state(OpaquePointer(click), GTK_EVENT_SEQUENCE_DENIED)
        }
        gtk_widget_add_controller(stage.widget, OpaquePointer(click))

        let keys = gtk_event_controller_key_new()!
        gtk_event_controller_set_propagation_phase(keys, GTK_PHASE_CAPTURE)
        onKey(Ptr(keys)) { [unowned self] key, state in
            if self.key(key, state) { return true }
            // typing goes to the search, wherever the focus was
            if !self.bar.searchFocused {
                self.bar.focusSearch()
                return gtk_event_controller_key_forward(keys, self.bar.entryWidget) != 0
            }
            return false
        }
        gtk_widget_add_controller(window, keys)

        let scroll = gtk_event_controller_scroll_new(GTK_EVENT_CONTROLLER_SCROLL_BOTH_AXES)!
        onScroll(Ptr(scroll)) { [unowned self] dx, dy in self.grid.scrolled(dx, dy) }
        gtk_widget_add_controller(stage.widget, scroll)

        onBool0(Ptr(window), "close-request") { [unowned self] in
            self.onClosed?()
            return false
        }
        every(ms: 1000) { [weak self] in self?.dash.tick(); return self != nil }
        every(ms: 60_000) { [weak self] in self?.followClock(); return self != nil }
    }

    var win: UnsafeMutablePointer<GtkWindow> { UnsafeMutablePointer<GtkWindow>(OpaquePointer(window)) }

    func present() {
        gtk_window_fullscreen(win)
        gtk_window_present(win)
        bar.focusSearch()
        if !closing && open.target == 1 { return }
        closing = false
        open.target = 1
        grid.opening()
        stage.kick()
    }

    /// goes, then onClosed
    func close() {
        guard !closing else { return }
        closing = true
        bar.closeOverlays()
        open.target = 0
        grid.closing()
        stage.kick()
        after(ms: stage.animations ? 260 : 0) { [weak self] in self?.onClosed?() }
    }

    private func setScheme() {
        adw_style_manager_set_color_scheme(adw_style_manager_get_default(), dark ? ADW_COLOR_SCHEME_FORCE_DARK : ADW_COLOR_SCHEME_FORCE_LIGHT)
    }

    // MARK: appearance

    func setAppearance(_ a: Appearance) {
        settings.appearance = a
        settings.save()
        applyAppearance()
        bar.appearanceChanged()
        DispatchQueue.global().async { [settings] in Theme.applyOutside(settings) }
    }

    /// Auto: the hour passed from day to night (or back)
    private func followClock() {
        if settings.dark != dark { applyAppearance() }
    }

    func applyAppearance() {
        let d = settings.dark
        guard d != dark else { return }
        dark = d
        palette = Palette(dark: d)
        UI.setCls(window, "dark", d)
        UI.setCls(window, "light", !d)
        setScheme()
        // the old backdrop stays under the new one while it fades in
        if let old = prevBlur { g_object_unref(Ptr(old)) }
        prevBlur = blurTex
        prevRect = blurRect
        blurTex = nil
        if let s = sharpTex { g_object_unref(Ptr(s)) }
        sharpTex = nil
        swap.snap(0)
        swap.target = 1
        dash.restyle()
        grid.restyle()
        bar.restyle()
        stage.dirtyChrome()
        stage.kick()
    }

    func saveSettings() { settings.save() }

    // MARK: springs

    private func step(_ dt: Double) -> Bool {
        var m = open.step(dt)
        m = swap.step(dt) || m
        m = bar.step(dt) || m
        if swap.settled, let old = prevBlur {
            g_object_unref(Ptr(old))
            prevBlur = nil
        }
        // up and still: the sharp wallpaper is only for coming up
        if !m && open.target == 1 && open.settled && blurTex != nil, let sh = sharpTex {
            g_object_unref(Ptr(sh))
            sharpTex = nil
        }
        return m
    }

    // MARK: layout

    private func layout(_ w: Double, _ h: Double) {
        var f = Frame()
        f.w = w
        f.h = h
        f.margin = w < 1100 ? 28 : 56
        let top = h < 760 ? 18.0 : 28
        let dashH = h < 700 ? 0.0 : 128 // no dashboard on short screens
        f.dash = Rect(x: f.margin, y: top, w: w - 2 * f.margin, h: dashH)
        let sy = dashH > 0 ? f.dash.maxY + 24 : top
        let sw = min(460, max(260, w * 0.32))
        f.search = Rect(x: (w - sw) / 2, y: sy, w: sw, h: 44)
        f.bottom = Rect(x: f.margin, y: h - 24 - 46, w: w - 2 * f.margin, h: 46)
        f.grid = Rect(x: f.margin, y: f.search.maxY + 28, w: w - 2 * f.margin, h: max(80, f.bottom.y - 20 - (f.search.maxY + 28)))
        frame = f
        dash.layout(f)
        bar.layout(f)
        grid.layout(f)
        stage.chromeHeight = dashH > 0 ? f.dash.maxY + 16 : 0
    }

    func relayout() { if stage.width > 0 { layout(stage.width, stage.height) } }

    // MARK: keys

    private func key(_ k: UInt32, _ state: UInt32) -> Bool {
        let ctrl = state & GDK_CONTROL_MASK.rawValue != 0
        switch Int32(k) {
        case GDK_KEY_Escape:
            if bar.closeOverlays() { return true }
            if !bar.query.isEmpty { bar.clearSearch(); return true }
            close()
            return true
        case GDK_KEY_Return, GDK_KEY_KP_Enter:
            grid.launchSelected()
            return true
        case GDK_KEY_Left: grid.move(-1); return true
        case GDK_KEY_Right: grid.move(1); return true
        case GDK_KEY_Tab: grid.move(state & GDK_SHIFT_MASK.rawValue != 0 ? -1 : 1); return true
        case GDK_KEY_ISO_Left_Tab: grid.move(-1); return true
        case GDK_KEY_Up: grid.move(-grid.cols); return true
        case GDK_KEY_Down: grid.move(grid.cols); return true
        case GDK_KEY_Page_Down: grid.go(grid.page + 1); return true
        case GDK_KEY_Page_Up: grid.go(grid.page - 1); return true
        case GDK_KEY_Home where ctrl || bar.query.isEmpty: grid.go(0); return true
        case GDK_KEY_End where ctrl || bar.query.isEmpty: grid.go(grid.pages.count - 1); return true
        default:
            return false
        }
    }

    // MARK: the backdrop: the wallpaper, blurred, under a veil

    private var sharpTex: OpaquePointer?
    private var blurTex: OpaquePointer?
    private var prevBlur: OpaquePointer?
    private var blurRect = Rect(), prevRect = Rect()
    private var texSize = (0.0, 0.0, 0.0)

    private var scale: Double {
        guard let n = gtk_widget_get_native(stage.widget), let s = gtk_native_get_surface(n) else { return 1 }
        return gdk_surface_get_scale(s)
    }

    /// the wallpaper at the screen's size in pixels (as large as it must be
    /// to cover it, no larger)
    private func loadSharp(_ w: Double, _ h: Double) -> OpaquePointer? {
        let k = scale
        let pw = Int32((w * k).rounded(.up)), ph = Int32((h * k).rounded(.up))
        let path = Wallpaper.file(dark: dark)
        // the wallpaper is 16:9: wider screens are covered by its width
        let byWidth = Double(pw) / Double(ph) > 16.0 / 9
        var err: UnsafeMutablePointer<GError>?
        guard let pb = gdk_pixbuf_new_from_file_at_scale(path, byWidth ? pw : -1, byWidth ? -1 : ph, 1, &err) else {
            g_clear_error(&err)
            return nil
        }
        let tex = gdk_texture_new_for_pixbuf(pb)
        g_object_unref(Ptr(pb))
        return tex.map { OpaquePointer($0) }
    }

    /// where the wallpaper goes to cover w × h, centred
    private func cover(_ tex: OpaquePointer, _ w: Double, _ h: Double) -> Rect {
        let tw = Double(gdk_texture_get_width(tex)), th = Double(gdk_texture_get_height(tex))
        let k = max(w / tw, h / th)
        return Rect(x: (w - tw * k) / 2, y: (h - th * k) / 2, w: tw * k, h: th * k)
    }

    private func drawBack(_ s: Snap, _ w: Double, _ h: Double) {
        let r = Rect(x: 0, y: 0, w: w, h: h)
        if texSize != (w, h, scale) {
            texSize = (w, h, scale)
            if let t = sharpTex { g_object_unref(Ptr(t)) }
            if let t = blurTex { g_object_unref(Ptr(t)) }
            sharpTex = nil
            blurTex = nil
        }
        if blurTex == nil {
            if sharpTex == nil { sharpTex = loadSharp(w, h) }
            if let sharp = sharpTex, let sub = gtk_snapshot_new() {
                // blurred past the edges, so the edges stay as bright as the middle
                var clip = grect(r)
                gtk_snapshot_push_clip(sub, &clip)
                gtk_snapshot_push_blur(sub, 56)
                let c = cover(sharp, w, h)
                Stage.drawTexture(sub, sharp, Rect(x: c.x - 120, y: c.y - 120, w: c.w + 240, h: c.h + 240))
                gtk_snapshot_pop(sub)
                gtk_snapshot_pop(sub)
                if let node = gtk_snapshot_free_to_node(sub) {
                    if let (t, rr) = stage.renderTexture(node, r) { blurTex = t; blurRect = rr }
                    gsk_render_node_unref(node)
                }
            }
        }
        guard sharpTex != nil || blurTex != nil else {
            Draw.color(s, dark ? RGBA(0.06, 0.05, 0.14) : RGBA(0.93, 0.91, 0.96), r)
            return
        }
        // the desktop's wallpaper, sharp, blurs over as Ember comes up
        // (once Ember is up, the sharp picture is let go: the blur covers it)
        let o = sharpTex == nil ? 1 : min(1, max(0, open.value))
        if let sharp = sharpTex { Stage.drawTexture(s, sharp, cover(sharp, w, h)) }
        if let prev = prevBlur, swap.value < 0.999 {
            gtk_snapshot_push_opacity(s, o)
            Stage.drawTexture(s, prev, prevRect)
            gtk_snapshot_pop(s)
        }
        if let blur = blurTex {
            gtk_snapshot_push_opacity(s, o * (prevBlur != nil ? min(1, max(0, swap.value)) : 1))
            Stage.drawTexture(s, blur, blurRect)
            gtk_snapshot_pop(s)
        }
        Draw.color(s, palette.veil.alpha(o), r)
    }

    // MARK: notes

    func note(_ text: String, action: String? = nil, _ f: (() -> Void)? = nil) {
        bar.note(text, action: action, f)
    }
}
