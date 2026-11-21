import Dispatch
import FoundationEssentials
import Glibc

// What the dashboard shows: processor load, memory, the network, the disk,
// the battery and the screen's brightness, read from /proc and /sys.

struct Stats {
    var cpu = 0.0
    var memUsed = 0.0, memTotal = 0.0 // GB
    var diskFree = 0.0, diskTotal = 0.0 // GB
    var battery = -1
    var charging = false
    var net = Net()
    var brightness = -1

    struct Net {
        enum State { case none, wifi, wired }
        var state = State.none
        var name = ""
        var signal = 0
        var hasWifi = false
    }
}

final class SysReader {
    var root = "" // tests read a made-up /proc and /sys from here
    private var prevAll: UInt64 = 0, prevIdle: UInt64 = 0
    private var last = Stats()
    private var n = 0

    private func read(_ p: String) -> String { Paths.read(root + p) ?? "" }
    private func trimmed(_ p: String) -> String { read(p).trimmed() }

    /// a new reading; the slow parts (disk, battery, network) every 5th time
    func read() -> Stats {
        var s = last
        s.cpu = cpu()
        (s.memUsed, s.memTotal) = mem()
        s.brightness = brightness()
        if n % 5 == 0 {
            (s.diskFree, s.diskTotal) = disk()
            (s.battery, s.charging) = battery()
            s.net = net()
        }
        n += 1
        last = s
        return s
    }

    func cpu() -> Double {
        let line = read("/proc/stat").split(separator: "\n").first ?? ""
        let f = line.split(separator: " ")
        guard f.count >= 5, f[0] == "cpu" else { return last.cpu }
        var all: UInt64 = 0, idle: UInt64 = 0
        for (i, v) in f.dropFirst().prefix(8).enumerated() {
            let x = UInt64(v) ?? 0
            all += x
            if i == 3 || i == 4 { idle += x }
        }
        defer { prevAll = all; prevIdle = idle }
        guard prevAll > 0, all > prevAll else { return last.cpu }
        let d = Double(all - prevAll)
        return min(100, max(0, 100 * (d - Double(idle - prevIdle)) / d))
    }

    func mem() -> (Double, Double) {
        var tot = 0.0, avail = 0.0
        for l in read("/proc/meminfo").split(separator: "\n") {
            let f = l.split(separator: " ")
            guard f.count >= 2 else { continue }
            if f[0] == "MemTotal:" { tot = Double(f[1]) ?? 0 }
            if f[0] == "MemAvailable:" { avail = Double(f[1]) ?? 0 }
        }
        let gb = 1024.0 * 1024
        return ((tot - avail) / gb, tot / gb)
    }

    func disk() -> (Double, Double) {
        var st = statvfs()
        guard statvfs(root.isEmpty ? Paths.home : root, &st) == 0 else { return (0, 0) }
        let gb = Double(1 << 30)
        return (Double(st.f_bavail) * Double(st.f_frsize) / gb, Double(st.f_blocks) * Double(st.f_frsize) / gb)
    }

    func battery() -> (Int, Bool) {
        let base = "/sys/class/power_supply"
        for d in ((try? FileManager.default.contentsOfDirectory(atPath: root + base)) ?? []).sorted() {
            let p = base + "/" + d
            guard trimmed(p + "/type") == "Battery", trimmed(p + "/scope") != "Device",
                  let c = Int(trimmed(p + "/capacity")) else { continue }
            let st = trimmed(p + "/status")
            return (min(100, max(0, c)), st == "Charging" || st == "Full" || st == "Not charging")
        }
        return (-1, false)
    }

    func net() -> Stats.Net {
        var n = Stats.Net()
        var wired = ""
        let base = "/sys/class/net"
        for name in ((try? FileManager.default.contentsOfDirectory(atPath: root + base)) ?? []).sorted() where name != "lo" {
            let d = root + base + "/" + name
            let wifi = Paths.exists(d + "/wireless")
            if !wifi && !Paths.exists(d + "/device") { continue } // bridges, containers, VPNs
            n.hasWifi = n.hasWifi || wifi
            guard trimmed(base + "/" + name + "/operstate") == "up" else { continue }
            if wifi && n.state != .wifi {
                n.state = .wifi
                n.name = name
                n.signal = signal(name)
                if root.isEmpty, let s = ssid(name) { n.name = s }
            } else if !wifi && wired.isEmpty {
                wired = name
            }
        }
        if n.state == .none && !wired.isEmpty { n.state = .wired; n.name = wired }
        return n
    }

    func signal(_ ifc: String) -> Int {
        for l in read("/proc/net/wireless").split(separator: "\n") {
            let f = l.split(separator: " ")
            if f.count >= 3, f[0].trimmed(":") == ifc {
                let q = Double(f[2].trimmed(".")) ?? 0
                return Int(min(100, max(0, q * 100 / 70)))
            }
        }
        return 0
    }

    func ssid(_ ifc: String) -> String? {
        if let out = Run.output(["nmcli", "-t", "-f", "active,ssid", "dev", "wifi"], timeout: 0.8) {
            for l in out.split(separator: "\n") where l.hasPrefix("yes:") {
                return String(l.dropFirst(4)).replacing("\\:", with: ":")
            }
        }
        if let out = Run.output(["iwgetid", ifc, "-r"], timeout: 0.8) {
            let s = out.trimmed()
            return s.isEmpty ? nil : s
        }
        return nil
    }

    /// the screen's backlight: its name and highest value
    func backlight() -> (String, Int)? {
        let base = "/sys/class/backlight"
        let rank = ["firmware": 3, "platform": 2, "raw": 1]
        var best: (String, Int, Int)?
        for d in (try? FileManager.default.contentsOfDirectory(atPath: root + base)) ?? [] {
            guard let m = Int(trimmed(base + "/" + d + "/max_brightness")), m > 0 else { continue }
            let k = rank[trimmed(base + "/" + d + "/type")] ?? 0
            if best == nil || k > best!.2 { best = (d, m, k) }
        }
        return best.map { ($0.0, $0.1) }
    }

    func brightness() -> Int {
        guard let (name, m) = backlight() else { return -1 }
        let d = "/sys/class/backlight/" + name
        guard let v = Int(trimmed(d + "/actual_brightness")) ?? Int(trimmed(d + "/brightness")) else { return -1 }
        return min(100, max(0, Int((Double(v) * 100 / Double(m)).rounded())))
    }

    /// sets the backlight (1…100 %), through logind or brightnessctl
    func setBrightness(_ percent: Int) {
        guard let (name, m) = backlight() else { return }
        let v = max(1, m * percent / 100)
        if !Run.ok(["busctl", "call", "org.freedesktop.login1", "/org/freedesktop/login1/session/auto",
                    "org.freedesktop.login1.Session", "SetBrightness", "ssu", "backlight", name, "\(v)"], timeout: 2) {
            Run.ok(["brightnessctl", "-q", "-d", name, "set", "\(v)"], timeout: 2)
        }
    }
}
