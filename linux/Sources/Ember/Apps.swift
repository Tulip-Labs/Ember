import CAdw
import CGioUnix
import Dispatch
import FoundationEssentials
import Glibc

// The apps: every .desktop entry GLib finds (system, ~/.local/share, Flatpak
// and Snap exports), with its icon, name and search words.

final class App {
    let id: String
    let name: String
    let generic: String
    let keywords: [String]
    let exec: [String]
    let terminal: Bool
    let dir: String?
    /// GIcon *
    let icon: OpaquePointer?

    init(id: String, name: String, generic: String = "", keywords: [String] = [], exec: [String], terminal: Bool = false, dir: String? = nil, icon: OpaquePointer? = nil) {
        self.id = id; self.name = name; self.generic = generic; self.keywords = keywords
        self.exec = exec; self.terminal = terminal; self.dir = dir; self.icon = icon
        if let icon { g_object_ref(Ptr(icon)) }
    }

    deinit { if let icon { g_object_unref(Ptr(icon)) } }

    var command: [String] { terminal ? Run.inTerminal(exec) : exec }

    func launch() throws { try Run.detached(command, dir: dir) }

    /// 2: the name (or a word of it) starts with q; 1: q is in the name,
    /// the kind or a keyword; 0: no match
    func matches(_ q: String) -> Int {
        let q = q.lowercased().trimmed()
        if q.isEmpty { return 2 }
        let n = name.lowercased()
        if n.hasPrefix(q) || n.split(separator: " ").contains(where: { $0.hasPrefix(q) }) { return 2 }
        if n.contains(q) || generic.lowercased().contains(q) { return 1 }
        if keywords.contains(where: { $0.lowercased().hasPrefix(q) }) { return 1 }
        return 0
    }
}

enum Apps {
    /// every app to show, by name
    static func all() -> [App] {
        var desktop = (Paths.env("XDG_CURRENT_DESKTOP") ?? "niri").split(separator: ":").first.map(String.init) ?? "niri"
        if desktop.isEmpty { desktop = "niri" }
        g_desktop_app_info_set_desktop_env(desktop)
        var out: [App] = []
        var list = g_app_info_get_all()
        let head = list
        while let l = list {
            defer { list = l.pointee.next }
            guard let info = l.pointee.data else { continue }
            let ai = OpaquePointer(info)
            let dai = OpaquePointer(info)
            guard g_app_info_should_show(ai) != 0,
                  let id = str(g_app_info_get_id(ai)),
                  let name = str(g_app_info_get_name(ai)), !name.isEmpty,
                  let execLine = takeStr(g_desktop_app_info_get_string(dai, "Exec")) else { continue }
            let exec = fields(execLine)
            guard !exec.isEmpty else { continue }
            var words: [String] = []
            if let kw = g_desktop_app_info_get_keywords(dai) {
                var i = 0
                while let k = kw[i] { words.append(String(cString: k)); i += 1 }
            }
            let dir = takeStr(g_desktop_app_info_get_string(dai, "Path"))
            out.append(App(id: id, name: name, generic: str(g_desktop_app_info_get_generic_name(dai)) ?? "",
                           keywords: words, exec: exec, terminal: g_desktop_app_info_get_boolean(dai, "Terminal") != 0,
                           dir: dir?.isEmpty == false ? dir : nil, icon: g_app_info_get_icon(ai)))
        }
        g_list_free_full(head) { g_object_unref($0) }
        out.sort { g_utf8_collate($0.name, $1.name) < 0 }
        // the same app from two places (a system copy and a Flatpak export)
        var seen = Set<String>()
        return out.filter { seen.insert($0.name.lowercased() + "\u{0}" + $0.exec.joined(separator: " ")).inserted }
    }

    /// the Exec line split into words, its field codes (%U, %f…) dropped
    static func fields(_ s: String) -> [String] {
        var out: [String] = []
        var cur = ""
        var have = false, quoted = false
        var it = Array(s)
        var i = 0
        func flush() { if have && !cur.isEmpty { out.append(cur) }; cur = ""; have = false }
        while i < it.count {
            let c = it[i]
            if c == "\\" && i + 1 < it.count {
                i += 1
                cur.append(it[i]); have = true
            } else if c == "\"" {
                quoted.toggle(); have = true
            } else if !quoted && (c == " " || c == "\t") {
                flush()
            } else if c == "%" && i + 1 < it.count {
                i += 1
                if it[i] == "%" { cur.append("%"); have = true }
            } else {
                cur.append(c); have = true
            }
            i += 1
        }
        flush()
        it.removeAll()
        return out
    }

    /// the order the grid shows: names that start with the search first
    static func filter(_ apps: [App], _ q: String) -> [App] {
        let q = q.trimmed()
        if q.isEmpty { return apps }
        let scored = apps.map { ($0, $0.matches(q)) }.filter { $0.1 > 0 }
        return scored.filter { $0.1 == 2 }.map(\.0) + scored.filter { $0.1 == 1 }.map(\.0)
    }
}
