import CAdw
import Dispatch
import FoundationEssentials
import Glibc

// Plain GTK pieces Ember is built from. They draw no backgrounds of their
// own: the Stage puts glass under them.

enum UI {
    static func cls(_ w: GtkW, _ names: String...) {
        for n in names { gtk_widget_add_css_class(w, n) }
    }

    static func setCls(_ w: GtkW, _ name: String, _ on: Bool) {
        if on { gtk_widget_add_css_class(w, name) } else { gtk_widget_remove_css_class(w, name) }
    }

    static func box(_ vertical: Bool = false, _ spacing: Int32 = 0) -> GtkW {
        gtk_box_new(vertical ? GTK_ORIENTATION_VERTICAL : GTK_ORIENTATION_HORIZONTAL, spacing)
    }

    static func append(_ box: GtkW, _ child: GtkW) {
        gtk_box_append(UnsafeMutablePointer<GtkBox>(OpaquePointer(box)), child)
    }

    static func label(_ text: String, _ classes: String...) -> GtkW {
        let l = gtk_label_new(text)!
        for c in classes { gtk_widget_add_css_class(l, c) }
        return l
    }

    static func setLabel(_ l: GtkW, _ text: String) {
        if str(gtk_label_get_text(OpaquePointer(l))) != text { gtk_label_set_text(OpaquePointer(l), text) }
    }

    static func left(_ l: GtkW) { gtk_label_set_xalign(OpaquePointer(l), 0) }

    static func ellipsize(_ l: GtkW, chars: Int32 = 4) {
        let lb = OpaquePointer(l)
        gtk_label_set_ellipsize(lb, PANGO_ELLIPSIZE_END)
        gtk_label_set_width_chars(lb, chars)
        gtk_label_set_max_width_chars(lb, chars)
    }

    static func button(_ child: GtkW, _ classes: [String] = [], _ f: @escaping () -> Void) -> GtkW {
        let b = gtk_button_new()!
        cls(b, "ember-flat")
        for c in classes { gtk_widget_add_css_class(b, c) }
        gtk_widget_set_focus_on_click(b, 0)
        gtk_widget_set_can_focus(b, 0)
        gtk_button_set_child(UnsafeMutablePointer<GtkButton>(OpaquePointer(b)), child)
        on(Ptr(b), "clicked", f)
        return b
    }

    /// a round button with a glyph
    static func round(_ g: Glyph, _ tip: String, size: Int32 = 44, _ f: @escaping () -> Void) -> GtkW {
        let b = button(Glyphs.view(g, size: size * 9 / 20), ["ember-round"], f)
        gtk_widget_set_size_request(b, size, size)
        gtk_widget_set_tooltip_text(b, tip)
        return b
    }

    /// a row of a panel: a glyph and words
    static func row(_ g: Glyph, _ text: String, _ f: @escaping () -> Void) -> (GtkW, GtkW) {
        let h = box(false, 12)
        append(h, Glyphs.view(g, size: 18))
        let l = label(text)
        left(l)
        gtk_widget_set_hexpand(l, 1)
        append(h, l)
        let b = button(h, ["ember-row"], f)
        return (b, l)
    }

    static func natural(_ w: GtkW, forWidth: Int32 = -1) -> (Double, Double) {
        var mw: Int32 = 0, nw: Int32 = 0, mh: Int32 = 0, nh: Int32 = 0
        gtk_widget_measure(w, GTK_ORIENTATION_HORIZONTAL, -1, &mw, &nw, nil, nil)
        gtk_widget_measure(w, GTK_ORIENTATION_VERTICAL, forWidth > 0 ? forWidth : nw, &mh, &nh, nil, nil)
        return (Double(nw), Double(nh))
    }

    static func text(_ t: GtkW) -> String { str(gtk_editable_get_text(OpaquePointer(t))) ?? "" }
    static func setText(_ t: GtkW, _ s: String) { gtk_editable_set_text(OpaquePointer(t), s) }

    static let css = """
    window.ember, window.ember.background { background: #000; box-shadow: none; }
    ember-stage { font-feature-settings: "tnum"; }
    window.ember.light ember-stage { color: #1d1d1f; }
    window.ember.dark ember-stage { color: #f5f5f7; }
    .ember-flat, .ember-flat:hover, .ember-flat:active, .ember-flat:checked, .ember-flat:focus {
      background: none; box-shadow: none; border: none; outline: none; text-shadow: none;
      -gtk-icon-shadow: none; color: inherit; }
    .ember-flat { min-height: 0; min-width: 0; padding: 0; }
    .ember-round { border-radius: 999px; }
    .ember-dim { opacity: .62; }
    .ember-caps { font-size: 11px; font-weight: 700; letter-spacing: .6px; }
    .ember-date { font-size: 15px; font-weight: 600; }
    .ember-clock { font-size: 56px; font-weight: 700; letter-spacing: -1.5px; }
    .ember-value { font-size: 19px; font-weight: 700; }
    .ember-caption { font-size: 12.5px; }
    .ember-search text { font-size: 16px; background: none; caret-color: #0a84ff; }
    .ember-search text placeholder { color: alpha(currentColor, .5); }
    .ember-search text selection { background: alpha(#0a84ff, .28); }
    .ember-tile { padding: 10px 6px 8px; border-radius: 24px; }
    .ember-tile label { font-size: 13px; font-weight: 500; }
    window.ember.dark .ember-tile label { text-shadow: 0 1px 3px alpha(black, .55); }
    window.ember.light .ember-tile label { text-shadow: 0 1px 2px alpha(white, .7); }
    .ember-tile image { -gtk-icon-shadow: 0 4px 10px alpha(black, .28); }
    .ember-row { padding: 9px 14px; border-radius: 14px; font-size: 14.5px; font-weight: 600; }
    .ember-row:hover { background: alpha(currentColor, .08); }
    .ember-row.on { color: #0a84ff; }
    .ember-panel-title { font-size: 12px; font-weight: 700; opacity: .55; margin: 6px 14px 2px; }
    .ember-sep { margin: 5px 12px; background: alpha(currentColor, .12); min-height: 1px; }
    .ember-seg { padding: 0 14px; border-radius: 999px; min-height: 36px; font-weight: 600; font-size: 13px; }
    .ember-dot { min-width: 8px; min-height: 8px; border-radius: 999px; background: alpha(currentColor, .3); margin: 0 5px; }
    .ember-dot.on { background: currentColor; }
    .ember-note { font-weight: 600; font-size: 14px; }
    .ember-action { padding: 5px 14px; border-radius: 999px; background: #0a84ff; color: white; font-weight: 700; font-size: 13px; }
    .ember-empty { font-size: 18px; font-weight: 600; opacity: .7; }
    levelbar.ember trough { min-height: 6px; border-radius: 3px; background: alpha(currentColor, .14); border: none; padding: 0; }
    levelbar.ember block { min-height: 6px; border-radius: 3px; border: none; }
    levelbar.ember block.filled, levelbar.ember block.low, levelbar.ember block.high, levelbar.ember block.full { background: alpha(currentColor, .78); }
    levelbar.ember.danger block.filled { background: #ff453a; }
    levelbar.ember block.empty { background: none; }
    scale.ember { padding: 0; margin: 0; }
    scale.ember trough { min-height: 6px; border-radius: 3px; background: alpha(currentColor, .14); }
    scale.ember highlight { min-height: 6px; border-radius: 3px; background: alpha(currentColor, .78); }
    scale.ember slider { min-width: 18px; min-height: 18px; margin: -7px; border-radius: 999px; background: white;
      box-shadow: 0 1px 4px alpha(black, .35), inset 0 0 0 .5px alpha(black, .1); }
    tooltip { border-radius: 10px; }
    """
}

// MARK: glyphs

/// Ember's own line icons (24 × 24, stroked in the text's colour), so they
/// look the same with every icon theme
enum Glyph: String {
    case search, power, restart, sleep, lock, signout, screens, sun, moon, auto
    case cpu, memory, wifi, wifiOff, ethernet, disk, battery, folder, terminal
    case eyeOff, eye, download, bar, open, image
}

enum Glyphs {
    static func paths(_ g: Glyph) -> (stroke: String, fill: String?) {
        switch g {
        case .search: return ("M11 4a7 7 0 1 0 0 14a7 7 0 1 0 0-14M16.2 16.2L20.5 20.5", nil)
        case .power: return ("M12 3v8M6.3 6.8a8 8 0 1 0 11.4 0", nil)
        case .restart: return ("M20 12a8 8 0 1 1-2.6-5.9M20 4v5h-5", nil)
        case .sleep, .moon: return ("M20.5 14.5A8.5 8.5 0 0 1 9.5 3.5a8.5 8.5 0 1 0 11 11z", nil)
        case .lock: return ("M6 11h12v9H6zM8.5 11V8a3.5 3.5 0 0 1 7 0v3", nil)
        case .signout: return ("M10 4H6a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h4M15 8l4 4-4 4M19 12H9", nil)
        case .screens: return ("M3 5h18v12H3zM9 21h6M12 17v4", nil)
        case .sun: return ("M12 8a4 4 0 1 0 0 8a4 4 0 1 0 0-8M12 2.5v2M12 19.5v2M5.3 5.3l1.4 1.4M17.3 17.3l1.4 1.4M2.5 12h2M19.5 12h2M5.3 18.7l1.4-1.4M17.3 6.7l1.4-1.4", nil)
        case .auto: return ("M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18", "M12 3a9 9 0 0 0 0 18z")
        case .cpu: return ("M7 7h10v10H7zM10.5 10.5h3v3h-3zM9.5 3v4M14.5 3v4M9.5 17v4M14.5 17v4M3 9.5h4M3 14.5h4M17 9.5h4M17 14.5h4", nil)
        case .memory: return ("M3 7h18v10H3zM7.5 10v4M12 10v4M16.5 10v4M6 17v3M18 17v3", nil)
        case .wifi: return ("M2.5 9a14 14 0 0 1 19 0M5.5 12.5a9.5 9.5 0 0 1 13 0M8.6 15.8a5 5 0 0 1 6.8 0M12 19.4v.2", nil)
        case .wifiOff: return ("M2.5 9a14 14 0 0 1 19 0M5.5 12.5a9.5 9.5 0 0 1 13 0M8.6 15.8a5 5 0 0 1 6.8 0M12 19.4v.2M3.5 3.5l17 17", nil)
        case .ethernet: return ("M4 9h16v9H4zM8 9V6h8v3M8 13.5v2M12 13.5v2M16 13.5v2", nil)
        case .disk: return ("M4 6.5a8 2.5 0 1 0 16 0a8 2.5 0 1 0-16 0M4 6.5v11c0 1.4 3.6 2.5 8 2.5s8-1.1 8-2.5v-11M4 12c0 1.4 3.6 2.5 8 2.5s8-1.1 8-2.5", nil)
        case .battery: return ("M3 8h15v8H3zM21 10.5v3", nil)
        case .folder: return ("M3 6.5A1.5 1.5 0 0 1 4.5 5H9l2 2h8.5A1.5 1.5 0 0 1 21 8.5v9a1.5 1.5 0 0 1-1.5 1.5h-15A1.5 1.5 0 0 1 3 17.5z", nil)
        case .terminal: return ("M4 5h16v14H4zM8 10l2.5 2L8 14M12.5 15H16", nil)
        case .eyeOff: return ("M3.5 3.5l17 17M10.6 6.1A9.8 9.8 0 0 1 12 6c5 0 9 6 9 6a16 16 0 0 1-2.6 3.1M6.6 7.6C4.2 9.2 3 12 3 12s4 6 9 6a8.6 8.6 0 0 0 4.3-1.2M9.9 10a3 3 0 0 0 4.1 4.2", nil)
        case .eye: return ("M3 12s4-6 9-6 9 6 9 6-4 6-9 6-9-6-9-6zM12 9.5a2.5 2.5 0 1 0 0 5a2.5 2.5 0 1 0 0-5", nil)
        case .download: return ("M12 4v11M7.5 10.5L12 15l4.5-4.5M5 20h14", nil)
        case .bar: return ("M3 5h18v14H3zM3 9h18", nil)
        case .open: return ("M7 17L17 7M9 7h8v8", nil)
        case .image: return ("M3 5h18v14H3zM3 16l5-5 4 4 3-3 6 6M15.5 9v.2", nil)
        }
    }

    /// a widget showing a glyph at size × size
    static func view(_ g: Glyph, size: Int32 = 18) -> GtkW {
        let w = gnew(glyphType, []).assumingMemoryBound(to: GtkWidget.self)
        set(w, g)
        gtk_widget_set_size_request(w, size, size)
        gtk_widget_set_valign(w, GTK_ALIGN_CENTER)
        gtk_widget_set_halign(w, GTK_ALIGN_CENTER)
        return w
    }

    static func set(_ w: GtkW, _ g: Glyph) {
        g_object_set_data_full(gptr(Ptr(w)), "ember-glyph", strdup(g.rawValue), free)
        gtk_widget_queue_draw(w)
    }

    /// the battery's charge, drawn inside its glyph (0…1, nil for none)
    static func setLevel(_ w: GtkW, _ level: Double?) {
        g_object_set_data_full(gptr(Ptr(w)), "ember-level", level.map { strdup(String($0)) }, free)
        gtk_widget_queue_draw(w)
    }

    private static var cache: [String: OpaquePointer] = [:]
    static func path(_ d: String) -> OpaquePointer? {
        if let p = cache[d] { return p }
        let p = gsk_path_parse(d)
        cache[d] = p
        return p
    }

    static func draw(_ s: Snap, _ g: Glyph, _ size: Double, _ c: RGBA, level: Double? = nil) {
        let (stroke, fill) = paths(g)
        gtk_snapshot_save(s)
        let k = Float(size / 24)
        gtk_snapshot_scale(s, k, k)
        var col = c.gdk
        if let fill, let p = path(fill) { gtk_snapshot_append_fill(s, p, GSK_FILL_RULE_WINDING, &col) }
        if let p = path(stroke) {
            let st = gsk_stroke_new(1.8)
            gsk_stroke_set_line_cap(st, GSK_LINE_CAP_ROUND)
            gsk_stroke_set_line_join(st, GSK_LINE_JOIN_ROUND)
            gtk_snapshot_append_stroke(s, p, st, &col)
            gsk_stroke_free(st)
        }
        if let level, level > 0 {
            var lc = (level <= 0.15 ? RGBA(1, 0.27, 0.23) : c).gdk
            var r = grect(Rect(x: 5, y: 10, w: 11 * min(1, level), h: 4))
            gtk_snapshot_append_color(s, &lc, &r)
        }
        gtk_snapshot_restore(s)
    }

    private static let glyphType: GType = {
        var info = GTypeInfo()
        info.class_size = guint16(MemoryLayout<GtkWidgetClass>.size)
        info.instance_size = guint16(MemoryLayout<GtkWidget>.size)
        info.class_init = { klass, _ in
            let wc = klass!.assumingMemoryBound(to: GtkWidgetClass.self)
            wc.pointee.snapshot = { w, s in
                guard let w, let s, let name = g_object_get_data(gptr(Ptr(w)), "ember-glyph"),
                      let g = Glyph(rawValue: String(cString: name.assumingMemoryBound(to: CChar.self))) else { return }
                var c = GdkRGBA()
                gtk_widget_get_color(w, &c)
                let size = Double(min(gtk_widget_get_width(w), gtk_widget_get_height(w)))
                let lv = g_object_get_data(gptr(Ptr(w)), "ember-level").flatMap { Double(String(cString: $0.assumingMemoryBound(to: CChar.self))) }
                Glyphs.draw(s, g, size, RGBA(Double(c.red), Double(c.green), Double(c.blue), Double(c.alpha)), level: lv)
            }
            gtk_widget_class_set_css_name(wc, "ember-glyph")
        }
        return g_type_register_static(gtk_widget_get_type(), "EmberGlyph", &info, GTypeFlags(rawValue: 0))
    }()
}
