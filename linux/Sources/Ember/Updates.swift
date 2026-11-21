import Dispatch
import FoundationEssentials
import Glibc

// Updates from Ember's GitHub releases, at most once a day. A copy in the
// home folder (the .tar.gz) installs a new version by itself and offers a
// restart; a .deb or .rpm downloads it and asks before installing (the
// system asks for the password). Every download is checked against the
// release's SHA256SUMS.

enum Updates {
    static let repo = "Tulip-Labs/Ember"

    enum Kind: String { case user, deb, rpm, ostree, arch, dev }

    /// how this copy was installed
    static func kind() -> Kind {
        let exe = Wallpaper.selfCommand
        let real = (try? FileManager.default.destinationOfSymbolicLink(atPath: exe)).map {
            $0.hasPrefix("/") ? $0 : dirname(exe) + "/" + $0
        } ?? exe
        let dir = dirname(real)
        if Paths.exists(dir + "/.ember-install") { return .user }
        if let k = Paths.read(dir + "/install-kind")?.trimmed() {
            if k == "rpm" && Paths.exists("/run/ostree-booted") { return .ostree }
            return Kind(rawValue: k) ?? .dev
        }
        return .dev
    }

    static var arch: String {
        var u = utsname()
        uname(&u)
        let m = withUnsafeBytes(of: &u.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return m == "arm64" ? "aarch64" : m
    }

    static var debArch: String { arch == "x86_64" ? "amd64" : arch == "aarch64" ? "arm64" : arch }

    static func asset(_ k: Kind, _ v: String) -> String {
        switch k {
        case .deb: return "ember-shell_\(v)_\(debArch).deb"
        case .rpm, .ostree: return "ember-shell-\(v)-1.\(arch).rpm"
        default: return "Ember-linux-\(arch).tar.gz"
        }
    }

    /// is a newer than b? (1.10 > 1.9)
    static func newer(_ a: String, _ b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    struct Release {
        var version: String
        var assets: [String: String] // name → download URL
    }

    static func latest() -> Release? {
        struct Asset: Decodable { let name: String; let browser_download_url: String }
        struct Reply: Decodable { let tag_name: String; let assets: [Asset]? }
        guard let out = Run.output(["curl", "-fsSL", "--max-time", "20", "-H", "Accept: application/vnd.github+json",
                                    "-A", "Ember-updater", "https://api.github.com/repos/\(repo)/releases/latest"], timeout: 25),
              let r = try? JSONDecoder().decode(Reply.self, from: Data(out.utf8)) else { return nil }
        var assets: [String: String] = [:]
        for a in r.assets ?? [] { assets[a.name] = a.browser_download_url }
        let tag = r.tag_name
        return Release(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag, assets: assets)
    }

    enum Failure: Error, CustomStringConvertible {
        case msg(String)
        var description: String { if case let .msg(m) = self { return m }; return "" }
    }

    /// downloads the asset for this copy and checks it; returns its path
    static func fetch(_ r: Release, _ k: Kind) throws -> String {
        let name = asset(k, r.version)
        guard let url = r.assets[name] else { throw Failure.msg("the release has no \(name)") }
        guard let sumsURL = r.assets["SHA256SUMS"], let sums = Run.output(["curl", "-fsSL", "--max-time", "30", sumsURL], timeout: 35) else {
            throw Failure.msg("the release has no SHA256SUMS: not installing an unchecked file")
        }
        guard let want = sums.split(separator: "\n").first(where: { $0.hasSuffix("  " + name) || $0.hasSuffix(" *" + name) })?.split(separator: " ").first else {
            throw Failure.msg("SHA256SUMS has no line for \(name)")
        }
        let dir = Paths.cache + "/updates"
        Paths.mkdir(dir)
        let path = dir + "/" + name
        guard Run.ok(["curl", "-fsSL", "--max-time", "600", "-o", path, url], timeout: 620) else { throw Failure.msg("the download failed") }
        guard let got = Run.output(["sha256sum", path])?.split(separator: " ").first, got == want else {
            unlink(path)
            throw Failure.msg("the download does not match SHA256SUMS")
        }
        return path
    }

    /// installs a downloaded file (a restart then brings the new version)
    static func install(_ k: Kind, _ path: String) throws {
        switch k {
        case .user:
            let tmp = Paths.cache + "/updates/unpacked"
            Run.ok(["rm", "-rf", tmp])
            Paths.mkdir(tmp)
            guard Run.ok(["tar", "-xzf", path, "-C", tmp], timeout: 60) else { throw Failure.msg("could not unpack it") }
            let new = tmp + "/Ember-linux-\(arch)/ember"
            let exe = Wallpaper.selfCommand
            guard Paths.exists(new) else { throw Failure.msg("the archive has no program") }
            guard Run.ok(["install", "-m", "755", new, exe + ".new"]), rename(exe + ".new", exe) == 0 else {
                throw Failure.msg("could not replace \(exe)")
            }
        case .deb:
            guard Run.ok(["pkexec", "apt-get", "install", "-y", path], timeout: 900) else { throw Failure.msg("apt did not install it") }
        case .rpm:
            let ok = Paths.which("dnf") != nil ? Run.ok(["pkexec", "dnf", "install", "-y", path], timeout: 900)
                : Run.ok(["pkexec", "zypper", "--non-interactive", "install", "--allow-unsigned-rpm", path], timeout: 900)
            guard ok else { throw Failure.msg("the package manager did not install it") }
        default:
            throw Failure.msg("this copy is updated by its package manager")
        }
    }

    /// once a day while Ember is on screen
    static func check(_ shell: Shell, force: Bool = false) {
        let k = kind()
        guard shell.settings.autoUpdate || force, k != .dev, k != .arch else { return }
        let now = Int64(Date().timeIntervalSince1970)
        guard force || now - shell.settings.updateChecked > 86_400 else { return }
        shell.settings.updateChecked = now
        shell.saveSettings()
        DispatchQueue.global(qos: .utility).async {
            guard let r = latest(), newer(r.version, EmberMain.version) else { return }
            switch k {
            case .ostree:
                idle { shell.note("Ember \(r.version) is out: rpm-ostree upgrade brings it") }
            case .user:
                do {
                    let p = try fetch(r, k)
                    try install(k, p)
                    idle { shell.note("Ember \(r.version) is installed", action: "Restart") { EmberMain.restart() } }
                } catch {
                    idle { shell.note("Ember \(r.version) was not installed: \(error)") }
                }
            default:
                idle {
                    shell.note("Ember \(r.version) is out", action: "Install") {
                        shell.note("Downloading Ember \(r.version)…")
                        DispatchQueue.global().async {
                            do {
                                let p = try fetch(r, k)
                                try install(k, p)
                                idle { shell.note("Ember \(r.version) is installed", action: "Restart") { EmberMain.restart() } }
                            } catch {
                                idle { shell.note("Ember \(r.version) was not installed: \(error)") }
                            }
                        }
                    }
                }
            }
        }
    }
}
