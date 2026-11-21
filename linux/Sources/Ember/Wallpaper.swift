import CData
import Dispatch
import FoundationEssentials
import Glibc

// Ember's wallpapers: Iris, goddess of the rainbow, in liquid glass, light by
// day and dark by night. They are built into the program; Ember writes them
// to ~/.local/share/ember/wallpapers, draws them blurred behind its own
// screen, and `ember --wallpaper` (started by niri) shows them on the desktop
// with swaybg, switching with the appearance.

enum Wallpaper {
    static var dir: String { Paths.data + "/wallpapers" }

    /// the wallpaper's file, written from the program when missing or old
    static func file(dark: Bool) -> String {
        let p = dir + "/iris-\(dark ? "dark" : "light").jpg"
        var size = 0
        guard let bytes = ember_wallpaper(dark ? 1 : 0, &size), size > 0 else { return p }
        var st = stat()
        if stat(p, &st) != 0 || Int(st.st_size) != size {
            Paths.write(p, Data(bytes: bytes, count: size))
        }
        return p
    }

    static var lockPath: String { Paths.runtime + "/ember-wallpaper.pid" }

    /// the running `ember --wallpaper`, if any
    static func supervisor() -> pid_t? {
        guard let s = Paths.read(lockPath), let pid = pid_t(s.trimmed()), pid > 0,
              kill(pid, 0) == 0, (Paths.read("/proc/\(pid)/cmdline") ?? "").contains("--wallpaper") else { return nil }
        return pid
    }

    /// the appearance or the wallpaper setting changed: the supervisor looks
    /// again, or one is started when there is none
    static func changed(_ s: Settings) {
        if let pid = supervisor() {
            kill(pid, SIGUSR1)
        } else if s.wallpaper, Niri.shared != nil, Niri.isSetUp {
            try? Run.detached([selfCommand, "--wallpaper"])
        }
    }

    /// how to start this program again ("ember" on PATH, or its own file)
    static var selfCommand: String {
        if let p = Paths.which("ember") { return p }
        let exe = (try? FileManager.default.destinationOfSymbolicLink(atPath: "/proc/self/exe")) ?? CommandLine.arguments[0]
        return exe.replacing(" (deleted)", with: "")
    }

    static func comm(_ pid: Int32) -> String {
        (Paths.read("/proc/\(pid)/comm") ?? "").trimmed()
    }

    static func ppid(_ pid: Int32) -> Int32 {
        for l in (Paths.read("/proc/\(pid)/status") ?? "").split(separator: "\n") where l.hasPrefix("PPid:") {
            return Int32(l.dropFirst(5).trimmed()) ?? 0
        }
        return 0
    }

    /// swaybg that Ember did not start (config.kdl's own wallpaper)
    static func killForeignSwaybg() {
        guard let ids = try? FileManager.default.contentsOfDirectory(atPath: "/proc") else { return }
        for id in ids {
            guard let pid = Int32(id), comm(pid) == "swaybg", comm(ppid(pid)) != "ember" else { continue }
            kill(pid, SIGTERM)
        }
    }

    // MARK: ember --wallpaper

    nonisolated(unsafe) static var poked: sig_atomic_t = 0
    nonisolated(unsafe) static var stop: sig_atomic_t = 0

    /// stays while niri runs: keeps swaybg showing the wallpaper of the
    /// appearance, switches it (and niri's look and apps' mode) when Auto
    /// passes from day to night, and looks again when Ember pokes it
    static func supervise() -> Never {
        Paths.mkdir(Paths.runtime)
        let fd = open(lockPath, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        if fd < 0 || flock(fd, LOCK_EX | LOCK_NB) != 0 { exit(0) } // one is running
        ftruncate(fd, 0)
        let pidText = "\(getpid())\n"
        _ = pidText.withCString { write(fd, $0, strlen($0)) }
        signal(SIGUSR1) { _ in Wallpaper.poked = 1 }
        signal(SIGTERM) { _ in Wallpaper.stop = 1 }
        signal(SIGINT) { _ in Wallpaper.stop = 1 }
        signal(SIGHUP) { _ in Wallpaper.stop = 1 }
        let display = Paths.env("WAYLAND_DISPLAY").map { $0.hasPrefix("/") ? $0 : Paths.runtime + "/" + $0 }
        let swaybg = Paths.which("swaybg")
        if swaybg == nil { fputs("ember: swaybg is not installed, so the desktop keeps niri's own background\n", stderr) }
        var child: pid_t = 0
        var showing = ""
        var applied: Bool?
        var failures = 0
        func end() -> Never {
            if child > 0 { kill(child, SIGTERM) }
            unlink(lockPath)
            exit(0)
        }
        while true {
            if stop != 0 { end() }
            if let display, !Paths.exists(display) { end() } // the session is over
            if child > 0 {
                var st: Int32 = 0
                if waitpid(child, &st, WNOHANG) == child {
                    child = 0
                    showing = ""
                    failures += 1
                }
            }
            let s = Settings.load()
            let dark = s.dark
            if applied != dark {
                applied = dark
                if Niri.isSetUp { Paths.write(Niri.dir + "/ember-theme.kdl", Theme.kdl(dark: dark)) }
                Theme.systemScheme(dark: dark)
            }
            if s.wallpaper, let swaybg, failures < 6 {
                let img = file(dark: dark)
                if img != showing {
                    // the new one first, then the old one goes: no flash
                    let words: [String] = [swaybg, "-o", "*", "-m", "fill", "-i", img]
                    var argv: [UnsafeMutablePointer<CChar>?] = words.map { strdup($0) } + [nil]
                    var pid: pid_t = 0
                    if posix_spawn(&pid, swaybg, nil, nil, &argv, environ) == 0 {
                        let old = child
                        child = pid
                        showing = img
                        if old > 0 {
                            usleep(400_000)
                            kill(old, SIGTERM)
                            waitpid(old, nil, 0)
                        }
                    } else {
                        failures += 1
                    }
                    argv.forEach { free($0) }
                }
            } else if child > 0 {
                kill(child, SIGTERM)
                waitpid(child, nil, 0)
                child = 0
                showing = ""
            }
            poked = 0
            // until the next change of hour, at most 30 s (a poke wakes it)
            var left: UInt32 = 30
            while left > 0 && poked == 0 && stop == 0 {
                left = sleep(left)
            }
        }
    }
}
