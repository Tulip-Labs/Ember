import Dispatch
import FoundationEssentials
import Glibc

// niri: its IPC socket ($NIRI_SOCKET, one JSON request and one reply per
// line) and Ember's place in its settings (~/.config/niri).

final class Niri {
    let path: String

    /// the niri Ember runs inside, if any
    static let shared: Niri? = Paths.env("NIRI_SOCKET").map { Niri(path: $0) }

    init(path: String) { self.path = path }

    enum Failure: Error { case io(String), niri(String) }

    /// sends a request (JSON), throws niri's error if it answers with one
    func request(_ req: String) throws {
        let fd = socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
        guard fd >= 0 else { throw Failure.io("socket") }
        defer { close(fd) }
        var tv = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        guard Unix.connect(fd, path) else { throw Failure.io("connect") }
        guard Unix.writeAll(fd, Data((req + "\n").utf8)) else { throw Failure.io("write") }
        guard let line = Unix.readLine(fd) else { throw Failure.io("read") }
        struct Reply: Decodable { let Err: String? }
        if let r = try? JSONDecoder().decode(Reply.self, from: Data(line.utf8)), let e = r.Err { throw Failure.niri(e) }
        guard line.hasPrefix("{\"Ok\"") else { throw Failure.io("reply") }
    }

    /// {"Action":{name:{fields}}} (fields already JSON)
    func action(_ name: String, _ fields: String = "") throws {
        try request("{\"Action\":{\(jsonString(name)):{\(fields)}}}")
    }

    func spawn(_ argv: [String]) throws { try action("Spawn", "\"command\":[" + argv.map(jsonString).joined(separator: ",") + "]") }
    func quit() throws { try action("Quit", "\"skip_confirmation\":true") }
    func powerOffMonitors() throws { try action("PowerOffMonitors") }

    // MARK: settings

    static let include = "include \"ember.kdl\""
    static var dir: String { Paths.niri }
    static var configPath: String { dir + "/config.kdl" }

    static func hasInclude(_ cfg: String) -> Bool {
        cfg.split(separator: "\n", omittingEmptySubsequences: false).contains { $0.trimmed() == include }
    }

    static var isSetUp: Bool { Paths.exists(dir + "/ember.kdl") }

    enum SetupError: Error, CustomStringConvertible {
        case noConfig
        var description: String { "niri has no config.kdl yet: start niri once, then run ember --setup-niri" }
    }

    /// writes ember.kdl and ember-theme.kdl and includes ember.kdl at the end
    /// of config.kdl (copied to config.kdl.before-ember first); returns
    /// whether the include was added
    @discardableResult
    static func setup(_ s: Settings) throws -> Bool {
        guard let first = Paths.read(configPath) else { throw SetupError.noConfig }
        Paths.write(dir + "/ember-theme.kdl", Theme.kdl(dark: s.dark))
        Paths.write(dir + "/ember.kdl", emberKDL)
        if s.wallpaper { _ = hideOtherWallpapers() }
        let cfg = Paths.read(configPath) ?? first
        if hasInclude(cfg) { return false }
        if !Paths.exists(configPath + ".before-ember") { Paths.write(configPath + ".before-ember", first) }
        var out = cfg
        while out.hasSuffix("\n") { out.removeLast() }
        Paths.write(configPath, out + "\n\n" + include + "\n")
        return true
    }

    static func remove() {
        if let cfg = Paths.read(configPath), hasInclude(cfg) {
            let lines = cfg.split(separator: "\n", omittingEmptySubsequences: false).filter { $0.trimmed() != include }
            Paths.write(configPath, lines.joined(separator: "\n"))
        }
        _ = showOtherWallpapers()
        unlink(dir + "/ember.kdl")
        unlink(dir + "/ember-theme.kdl")
    }

    static let emberKDL = """
    // Ember on niri. Ember copies this file next to your niri config and adds
    // `include "ember.kdl"` at the end of config.kdl. Settings here win over
    // the same keys earlier in config.kdl. Ember rewrites this file when it
    // updates, so make changes in config.kdl instead.

    // niri's look follows Ember's appearance (Light or Dark): Ember writes
    // ember-theme.kdl when it changes, and niri reloads it by itself.
    include "ember-theme.kdl"

    // Ember is the first thing on screen after you sign in, over its
    // wallpaper of Iris, goddess of the rainbow (light by day, dark by night).
    spawn-at-startup "ember"
    spawn-at-startup "ember" "--wallpaper"

    binds {
        // Super+D shows Ember, or hides it when it is on screen
        // (it takes over niri's default app launcher key).
        Mod+D hotkey-overlay-title="Show or hide Ember" { spawn "ember" "--toggle"; }
    }

    // Ember always covers the whole screen, with no border or shadow around it.
    window-rule {
        match app-id="^ember$"
        open-fullscreen true
        open-focused true
        draw-border-with-background false
        border { off; }
        focus-ring { off; }
        shadow { off; }
    }

    // the wallpaper stays in place in the overview, behind the workspaces
    layer-rule {
        match namespace="^wallpaper$"
        place-within-backdrop true
    }

    """

    // MARK: lines Ember comments out (Waybar, other wallpapers)

    static let mark = "// hidden by Ember: "

    static func isSpawn(_ t: String, _ names: [String]) -> Bool {
        (t.hasPrefix("spawn-at-startup") || t.hasPrefix("spawn-sh-at-startup")) && names.contains { t.contains($0) }
    }

    static let bars = ["waybar"]
    static let wallpapers = ["swaybg", "swww", "hyprpaper", "wpaperd", "waypaper", "mpvpaper", "wbg"]

    /// comments out (hide) or back in the startup lines naming one of
    /// `names`; returns whether config.kdl changed
    static func edit(_ names: [String], hide: Bool) -> Bool {
        guard let cfg = Paths.read(configPath) else { return false }
        var changed = false
        let lines = cfg.split(separator: "\n", omittingEmptySubsequences: false).map { l -> String in
            let s = String(l)
            let rest = s.drop { $0 == " " || $0 == "\t" }
            let ind = String(s.prefix(s.count - rest.count))
            if hide, isSpawn(String(rest), names), !rest.contains("\"ember\"") {
                changed = true
                return ind + mark + rest
            }
            if !hide, rest.hasPrefix(mark), isSpawn(String(rest.dropFirst(mark.count)), names) {
                changed = true
                return ind + rest.dropFirst(mark.count)
            }
            return s
        }
        guard changed else { return false }
        if !Paths.exists(configPath + ".before-ember") { Paths.write(configPath + ".before-ember", cfg) }
        Paths.write(configPath, lines.joined(separator: "\n"))
        return true
    }

    static func hideOtherWallpapers() -> Bool {
        guard edit(wallpapers, hide: true) else { return false }
        for w in wallpapers where w != "swaybg" { Run.ok(["pkill", "-x", w]) }
        // swaybg started by config.kdl (not Ember's, which has ember as its parent)
        Wallpaper.killForeignSwaybg()
        return true
    }

    static func showOtherWallpapers() -> Bool { edit(wallpapers, hide: false) }

    static var barHidden: Bool {
        (Paths.read(configPath) ?? "").split(separator: "\n").contains { $0.contains(mark) && $0.contains("waybar") }
    }

    /// shows or hides Waybar, the bar niri starts
    static func setBar(shown: Bool) {
        let flag = Paths.config + "/waybar-service-was-enabled"
        if !shown {
            _ = edit(bars, hide: true)
            if Run.ok(["systemctl", "--user", "is-enabled", "--quiet", "waybar.service"]) {
                Run.ok(["systemctl", "--user", "disable", "--now", "waybar.service"])
                Paths.touch(flag)
            }
            Run.ok(["pkill", "-x", "waybar"])
            return
        }
        _ = edit(bars, hide: false)
        if Paths.exists(flag) {
            unlink(flag)
            Run.ok(["systemctl", "--user", "enable", "--now", "waybar.service"])
            return
        }
        if Run.ok(["pgrep", "-x", "waybar"]) { return }
        try? Run.detached(["waybar"])
    }

    /// niri's version as (major, minor), e.g. (26, 4)
    static let version: (Int, Int)? = {
        guard let out = Run.output(["niri", "--version"], timeout: 2) else { return nil }
        let nums = out.split { !$0.isNumber && $0 != "." }.first { $0.contains(".") }
        let p = nums?.split(separator: ".").compactMap { Int($0) } ?? []
        return p.count >= 2 ? (p[0], p[1]) : nil
    }()

    /// window blur arrived in niri 26.04
    static var hasBlur: Bool {
        if let f = Paths.env("EMBER_NIRI_BLUR") { return f == "1" } // for checks without niri
        guard let v = version else { return false }
        return v.0 > 26 || (v.0 == 26 && v.1 >= 4)
    }
}

/// small POSIX socket helpers
enum Unix {
    static func address(_ path: String) -> sockaddr_un {
        var a = sockaddr_un()
        a.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8.prefix(107))
        withUnsafeMutableBytes(of: &a.sun_path) { raw in
            for (i, b) in bytes.enumerated() { raw[i] = b }
            raw[bytes.count] = 0
        }
        return a
    }

    static func connect(_ fd: Int32, _ path: String) -> Bool {
        var a = address(path)
        return withUnsafePointer(to: &a) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Glibc.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        } == 0
    }

    static func writeAll(_ fd: Int32, _ d: Data) -> Bool {
        d.withUnsafeBytes { raw in
            var off = 0
            while off < raw.count {
                let n = write(fd, raw.baseAddress! + off, raw.count - off)
                if n <= 0 { return false }
                off += n
            }
            return true
        }
    }

    /// reads up to a newline (or the end)
    static func readLine(_ fd: Int32, max: Int = 1 << 22) -> String? {
        var out = [UInt8]()
        var buf = [UInt8](repeating: 0, count: 4096)
        while out.count < max {
            let n = read(fd, &buf, buf.count)
            if n <= 0 { break }
            if let i = buf[0..<n].firstIndex(of: 10) {
                out += buf[0..<i]
                return String(decoding: out, as: UTF8.self)
            }
            out += buf[0..<n]
        }
        return out.isEmpty ? nil : String(decoding: out, as: UTF8.self)
    }
}
