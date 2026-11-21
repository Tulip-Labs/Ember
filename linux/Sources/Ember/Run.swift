import CAdw
import Dispatch
import FoundationEssentials
import Glibc

// Starting programs: apps and helpers detached from Ember (Ember quits when
// it hides, and what it opened goes on), and short commands it waits for.

enum Run {
    enum Failure: Error, CustomStringConvertible {
        case missing(String)
        case failed(String)
        var description: String {
            switch self {
            case let .missing(p): return "\(p) is not installed"
            case let .failed(m): return m
            }
        }
    }

    /// starts argv on its own (niri starts it when Ember runs on niri, so it
    /// lives in niri's session rather than Ember's)
    static func detached(_ argv: [String], dir: String? = nil) throws {
        guard let first = argv.first else { throw Failure.failed("nothing to run") }
        if Paths.which(first) == nil { throw Failure.missing(first) }
        var argv = argv
        if let dir, !dir.isEmpty { argv = ["sh", "-c", "cd \"$0\" && exec \"$@\"", dir] + argv }
        if let n = Niri.shared, (try? n.spawn(argv)) != nil { return }
        try spawn(argv)
    }

    /// g_spawn_async: GLib reaps the child, so no zombie is left
    static func spawn(_ argv: [String], dir: String? = nil) throws {
        var c: [UnsafeMutablePointer<CChar>?] = argv.map { strdup($0) } + [nil]
        defer { c.forEach { free($0) } }
        var err: UnsafeMutablePointer<GError>?
        let setup: GSpawnChildSetupFunc = { _ in _ = setsid() }
        let ok = g_spawn_async(dir ?? Paths.home, &c, nil, GSpawnFlags(rawValue: 1 << 2), setup, nil, nil, &err)
        if ok == 0 {
            let m = err.flatMap { str($0.pointee.message) } ?? "could not start \(argv[0])"
            g_clear_error(&err)
            throw Failure.failed(m)
        }
    }

    /// runs argv and waits (at most `timeout` seconds); stdout, or nil when
    /// it failed or took too long
    @discardableResult
    static func output(_ argv: [String], timeout: Double = 5) -> String? {
        guard let first = argv.first, let path = Paths.which(first) else { return nil }
        var fds: [Int32] = [0, 0]
        guard pipe(&fds) == 0 else { return nil }
        var fa = posix_spawn_file_actions_t()
        posix_spawn_file_actions_init(&fa)
        defer { posix_spawn_file_actions_destroy(&fa) }
        posix_spawn_file_actions_addopen(&fa, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&fa, fds[1], 1)
        posix_spawn_file_actions_addopen(&fa, 2, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addclose(&fa, fds[0])
        posix_spawn_file_actions_addclose(&fa, fds[1])
        var c: [UnsafeMutablePointer<CChar>?] = argv.map { strdup($0) } + [nil]
        defer { c.forEach { free($0) } }
        var pid: pid_t = 0
        let rc = posix_spawn(&pid, path, &fa, nil, &c, environ)
        close(fds[1])
        guard rc == 0 else { close(fds[0]); return nil }
        var out = [UInt8]()
        var buf = [UInt8](repeating: 0, count: 8192)
        let deadline = Date().addingTimeInterval(timeout)
        var timedOut = false
        while true {
            let left = deadline.timeIntervalSinceNow
            if left <= 0 { timedOut = true; break }
            var p = pollfd(fd: fds[0], events: Int16(POLLIN), revents: 0)
            let r = poll(&p, 1, Int32(min(left, 1) * 1000) + 1)
            if r < 0 && errno == EINTR { continue }
            if r <= 0 { continue }
            let n = read(fds[0], &buf, buf.count)
            if n <= 0 { break }
            out += buf[0..<n]
        }
        close(fds[0])
        if timedOut { kill(pid, SIGKILL) }
        var st: Int32 = 0
        while waitpid(pid, &st, 0) < 0 && errno == EINTR {}
        // exited (low 7 bits 0) with status 0
        guard !timedOut, st & 0x7f == 0, (st >> 8) & 0xff == 0 else { return nil }
        return String(decoding: out, as: UTF8.self)
    }

    /// runs argv and waits; true when it worked
    @discardableResult
    static func ok(_ argv: [String], timeout: Double = 10) -> Bool { output(argv, timeout: timeout) != nil }

    /// the user's terminal and the words that make it run a command
    static func terminal() -> [String] {
        if let t = Paths.env("TERMINAL") { return [t, "-e"] }
        let known: [[String]] = [
            ["foot"], ["ghostty", "-e"], ["kitty"], ["alacritty", "-e"], ["wezterm", "start", "--"],
            ["ptyxis", "--"], ["kgx", "-e"], ["konsole", "-e"], ["gnome-terminal", "--"], ["xfce4-terminal", "-x"], ["xterm", "-e"],
        ]
        return known.first { Paths.which($0[0]) != nil } ?? ["xterm", "-e"]
    }

    /// the terminal alone, to open at a prompt
    static func terminalAlone() -> [String] {
        var t = terminal()
        if let l = t.last, ["-e", "-x", "--"].contains(l) { t.removeLast() }
        if t.count > 1 && t[1] == "start" { t = [t[0]] }
        return t
    }

    /// argv inside a terminal
    static func inTerminal(_ argv: [String]) -> [String] { terminal() + argv }
}
