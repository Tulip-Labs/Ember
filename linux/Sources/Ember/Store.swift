import Dispatch
import FoundationEssentials
import Glibc

// Ember's settings (~/.config/ember/settings.json) and the folders it uses.

enum Paths {
    static var home: String { ProcessInfo.processInfo.environment["HOME"] ?? "/" }

    static func env(_ k: String) -> String? {
        guard let v = ProcessInfo.processInfo.environment[k], !v.isEmpty else { return nil }
        return v
    }

    static var config: String { (env("XDG_CONFIG_HOME") ?? home + "/.config") + "/ember" }
    static var data: String { (env("XDG_DATA_HOME") ?? home + "/.local/share") + "/ember" }
    static var cache: String { (env("XDG_CACHE_HOME") ?? home + "/.cache") + "/ember" }
    static var runtime: String { env("XDG_RUNTIME_DIR") ?? "/tmp" }

    static var niri: String { (env("XDG_CONFIG_HOME") ?? home + "/.config") + "/niri" }

    /// the socket a running Ember listens on (one per user and display)
    static var socket: String {
        let disp = (env("WAYLAND_DISPLAY") ?? "x").split(separator: "/").last.map(String.init) ?? "x"
        return runtime + "/ember-\(getuid())-\(disp).sock"
    }

    static func exists(_ p: String) -> Bool { FileManager.default.fileExists(atPath: p) }

    static func read(_ p: String) -> String? { try? String(contentsOfFile: p, encoding: .utf8) }

    static func mkdir(_ p: String) {
        try? FileManager.default.createDirectory(atPath: p, withIntermediateDirectories: true)
    }

    /// writes a file only when its content changes, through a temporary file
    @discardableResult
    static func write(_ p: String, _ s: String) -> Bool { write(p, Data(s.utf8)) }

    @discardableResult
    static func write(_ p: String, _ d: Data) -> Bool {
        if let old = FileManager.default.contents(atPath: p), old == d { return true }
        mkdir(dirname(p))
        let tmp = p + ".tmp"
        guard FileManager.default.createFile(atPath: tmp, contents: d) else { return false }
        return rename(tmp, p) == 0
    }

    static func touch(_ p: String) { if !exists(p) { write(p, "") } }

    /// where a program is on PATH
    static func which(_ name: String) -> String? {
        if name.contains("/") { return access(name, X_OK) == 0 ? name : nil }
        for d in (env("PATH") ?? "/usr/local/bin:/usr/bin:/bin").split(separator: ":") {
            let p = "\(d)/\(name)"
            if access(p, X_OK) == 0 { return p }
        }
        return nil
    }
}

/// Light, Dark, or Auto (light by day, dark by night), as on a Mac
enum Appearance: String, Codable, CaseIterable {
    case light, auto, dark

    /// dark now? (Auto: dark from nightStarts until dayStarts)
    func isDark(_ s: Settings, at date: Date = Date()) -> Bool {
        switch self {
        case .light: return false
        case .dark: return true
        case .auto:
            var t = time_t(date.timeIntervalSince1970)
            var tm = tm()
            localtime_r(&t, &tm)
            let h = Int(tm.tm_hour)
            return h < s.dayStarts || h >= s.nightStarts
        }
    }
}

struct Settings: Codable, Equatable {
    var hidden: [String] = []
    var appearance: Appearance = .auto
    var autoUpdate = true
    var updateChecked: Int64 = 0
    /// Ember's wallpaper on niri's desktop
    var wallpaper = true
    var dayStarts = 7
    var nightStarts = 19

    init() {}

    enum CodingKeys: String, CodingKey {
        case hidden, appearance, autoUpdate, updateChecked, wallpaper, dayStarts, nightStarts, theme
    }

    // Ember 1 kept one of its ten themes in "theme"; its dark ones become Dark
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        hidden = try c.decodeIfPresent([String].self, forKey: .hidden) ?? []
        if let a = try? c.decodeIfPresent(Appearance.self, forKey: .appearance) {
            appearance = a
        } else if let t = try? c.decodeIfPresent(String.self, forKey: .theme) {
            let light = ["daylight", "mist", "rose", "sunrise", "mint", "light"]
            appearance = light.contains(t.lowercased()) ? .light : .auto
        }
        autoUpdate = try c.decodeIfPresent(Bool.self, forKey: .autoUpdate) ?? true
        updateChecked = try c.decodeIfPresent(Int64.self, forKey: .updateChecked) ?? 0
        wallpaper = try c.decodeIfPresent(Bool.self, forKey: .wallpaper) ?? true
        dayStarts = min(23, max(0, try c.decodeIfPresent(Int.self, forKey: .dayStarts) ?? 7))
        nightStarts = min(24, max(1, try c.decodeIfPresent(Int.self, forKey: .nightStarts) ?? 19))
    }

    func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: CodingKeys.self)
        try c.encode(hidden, forKey: .hidden)
        try c.encode(appearance, forKey: .appearance)
        try c.encode(autoUpdate, forKey: .autoUpdate)
        try c.encode(updateChecked, forKey: .updateChecked)
        try c.encode(wallpaper, forKey: .wallpaper)
        try c.encode(dayStarts, forKey: .dayStarts)
        try c.encode(nightStarts, forKey: .nightStarts)
    }

    var dark: Bool { appearance.isDark(self) }

    static var path: String { Paths.config + "/settings.json" }

    static func load() -> Settings {
        guard let d = FileManager.default.contents(atPath: path),
              let s = try? JSONDecoder().decode(Settings.self, from: d) else { return Settings() }
        return s
    }

    func save() {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let d = try? e.encode(self) { Paths.write(Settings.path, d) }
    }
}

/// the folder a path is in
func dirname(_ p: String) -> String {
    guard let i = p.lastIndex(of: "/") else { return "." }
    return i == p.startIndex ? "/" : String(p[..<i])
}

extension StringProtocol {
    /// without the given characters (blanks by default) at either end
    func trimmed(_ chars: String = " \t\n\r") -> String {
        let set = Set(chars)
        guard let a = firstIndex(where: { !set.contains($0) }), let b = lastIndex(where: { !set.contains($0) }) else { return "" }
        return String(self[a...b])
    }
}

/// a number with `digits` decimals ("%.1f")
func fixed(_ x: Double, _ digits: Int) -> String {
    guard x.isFinite else { return "0" }
    var k = 1.0
    for _ in 0..<digits { k *= 10 }
    let n = (abs(x) * k).rounded()
    let whole = Int(n / k), frac = Int(n.truncatingRemainder(dividingBy: k))
    let sign = x < 0 && n > 0 ? "-" : ""
    if digits == 0 { return sign + String(whole) }
    let f = String(frac)
    return sign + String(whole) + "." + String(repeating: "0", count: digits - f.count) + f
}

/// JSON for a string
func jsonString(_ s: String) -> String {
    var out = "\""
    for u in s.unicodeScalars {
        switch u {
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
        case "\n": out += "\\n"
        case "\r": out += "\\r"
        case "\t": out += "\\t"
        default:
            if u.value < 0x20 { out += "\\u" + String(repeating: "0", count: 4 - String(u.value, radix: 16).count) + String(u.value, radix: 16) } else { out.unicodeScalars.append(u) }
        }
    }
    return out + "\""
}
