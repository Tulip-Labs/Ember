import CAdw
import Dispatch
import FoundationEssentials
import Glibc

// Ember runs only while it is on screen: `ember` (or Super+D, `ember
// --toggle`) starts it, and it quits when it hides. A running Ember listens
// on a socket, so a second `ember` asks it instead of starting another.

@main
enum EmberMain {
    static let version = "2.0.0"

    static let usage = """
    Ember \(version): a calm, full-screen home for niri.

      ember                show Ember
      ember --toggle       show Ember, or hide it when it is on screen
      ember --hide         hide Ember
      ember --power        show Ember with the power panel open
      ember --light, --dark, --auto
                           pick the appearance (Auto: light by day, dark by night)
      ember --setup-niri   add Ember to niri's settings (Super+D, the wallpaper, the look)
      ember --remove-niri  take Ember out of niri's settings
      ember --hide-bar, --show-bar
                           hide or show the top bar niri starts (Waybar)
      ember --wallpaper    keep the Iris wallpaper on niri's desktop (niri starts this)
      ember --niri-theme   write niri's look for the current appearance and exit
      ember --version      print the version
    """

    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        let flag = args.first ?? ""
        switch flag {
        case "--version", "-v":
            print("Ember", version)
            return
        case "--help", "-h":
            print(usage)
            return
        case "--wallpaper":
            Wallpaper.supervise()
        case "--setup-niri":
            exit(setupNiri())
        case "--remove-niri":
            Paths.touch(Paths.config + "/niri-setup-done")
            Niri.remove()
            print("Ember is out of niri's settings.")
            return
        case "--niri-theme":
            let s = Settings.load()
            Paths.write(Niri.dir + "/ember-theme.kdl", Theme.kdl(dark: s.dark))
            return
        case "--hide-bar", "--show-bar":
            Niri.setBar(shown: flag == "--show-bar")
            Paths.touch(Paths.config + "/bar-hidden-once") // a choice made by hand stays
            return
        case "--light", "--dark", "--auto":
            var s = Settings.load()
            s.appearance = Appearance(rawValue: String(flag.dropFirst(2)))!
            s.save()
            if send("appearance") == nil { Theme.applyOutside(s) }
            return
        case "", "--toggle", "--hide", "--power", "--show", "--daemon":
            break
        default:
            fputs("ember: unknown option \(flag)\n\n\(usage)\n", stderr)
            exit(2)
        }
        let cmd = ["--toggle": "toggle", "--hide": "hide", "--power": "power", "--daemon": "hide"][flag] ?? "show"
        if send(cmd) != nil { return }
        if cmd == "hide" { return } // Ember only runs while it is on screen
        Resident().run(power: cmd == "power")
    }

    static func setupNiri() -> Int32 {
        do {
            let s = Settings.load()
            let added = try Niri.setup(s)
            if added { print("Added \(Niri.include) to \(Niri.configPath) (the old file is config.kdl.before-ember).") }
            print("Ember is in niri's settings: Super+D shows or hides it, and it starts when you sign in.")
            return 0
        } catch {
            fputs("ember: \(error)\n", stderr)
            return 1
        }
    }

    /// asks a running Ember; its answer, or nil when none runs
    static func send(_ cmd: String) -> String? {
        let fd = socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var tv = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        guard Unix.connect(fd, Paths.socket), Unix.writeAll(fd, Data((cmd + "\n").utf8)) else { return nil }
        return Unix.readLine(fd)
    }

    /// starts this program again in place (after an update)
    static func restart() {
        unlink(Paths.socket)
        let exe = Wallpaper.selfCommand
        var argv: [UnsafeMutablePointer<CChar>?] = [strdup(exe), nil]
        execv(exe, &argv)
        exit(0)
    }
}

/// the running Ember: its socket, its window, and what it does at start
final class Resident {
    var settings = Settings.load()
    var shell: Shell?
    private var listener: Int32 = -1

    func run(power: Bool) {
        g_set_prgname("ember") // the Wayland app id niri's window rule matches
        g_set_application_name("Ember")
        adw_init()
        let css = gtk_css_provider_new()!
        gtk_css_provider_load_from_string(css, UI.css)
        gtk_style_context_add_provider_for_display(gdk_display_get_default(), OpaquePointer(css), 600)
        listen()
        firstRun()
        let s = Shell(settings: settings)
        shell = s
        s.onClosed = { [unowned self] in self.quit() }
        s.present()
        if power { s.bar.openPower() }
        if let n = startNote { after(ms: 600) { s.note(n) } }
        after(ms: 3000) { Updates.check(s) }
        let loop = g_main_loop_new(nil, 0)
        g_main_loop_run(loop)
    }

    private var startNote: String?

    /// once: Ember adds itself to niri and hides Waybar; and every time:
    /// the appearance reaches niri and apps, and the wallpaper runs
    private func firstRun() {
        let conf = Paths.config
        Paths.mkdir(conf)
        if Niri.shared != nil {
            let marker = conf + "/niri-setup-done"
            let included = Paths.read(Niri.configPath).map(Niri.hasInclude) ?? false
            if !Paths.exists(marker) || included {
                // Ember 1's ember.kdl becomes Ember 2's (the wallpaper, the look)
                if (try? Niri.setup(settings)) == true { startNote = "Ember added itself to niri: Super+D shows or hides it" }
                Paths.touch(marker)
            }
            let barMarker = conf + "/bar-hidden-once"
            if !Paths.exists(barMarker) {
                Paths.touch(barMarker)
                Niri.setBar(shown: false)
                startNote = startNote ?? "The top bar is hidden: Power, then Top bar, brings it back"
            }
        }
        let s = settings
        DispatchQueue.global().async { Theme.applyOutside(s) }
    }

    // MARK: the socket

    private func listen() {
        let path = Paths.socket
        unlink(path) // left by an Ember that crashed
        let fd = socket(AF_UNIX, Int32(SOCK_STREAM.rawValue) | Int32(SOCK_CLOEXEC.rawValue), 0)
        var a = Unix.address(path)
        let ok = withUnsafePointer(to: &a) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        } == 0
        guard fd >= 0, ok, Glibc.listen(fd, 8) == 0 else {
            fputs("ember: cannot listen on \(path)\n", stderr)
            return
        }
        chmod(path, 0o600)
        listener = fd
        let data = Unmanaged.passUnretained(self).toOpaque()
        g_unix_fd_add(fd, G_IO_IN, { fd, _, d in
            let r = Unmanaged<Resident>.fromOpaque(d!).takeUnretainedValue()
            r.accept(fd)
            return 1
        }, data)
    }

    private func accept(_ fd: Int32) {
        let c = Glibc.accept(fd, nil, nil)
        guard c >= 0 else { return }
        var tv = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(c, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        let line = (Unix.readLine(c, max: 256) ?? "").trimmed()
        handle(line)
        _ = Unix.writeAll(c, Data("ok\n".utf8))
        close(c)
    }

    private func handle(_ cmd: String) {
        guard let s = shell else { return }
        switch cmd {
        case "show":
            s.present()
        case "power":
            s.present()
            s.bar.openPower()
        case "hide":
            s.close()
        case "toggle":
            if s.closing { s.present() } else { s.close() }
        case "appearance":
            let a = Settings.load().appearance
            s.setAppearance(a)
        default:
            break
        }
    }

    func quit() {
        if listener >= 0 { close(listener) }
        unlink(Paths.socket)
        exit(0)
    }
}
