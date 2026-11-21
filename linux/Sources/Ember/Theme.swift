import CAdw
import Dispatch
import FoundationEssentials
import Glibc

// Ember's two appearances, Light and Dark (Auto picks one by the time of
// day), as on a Mac: the colours of Ember's glass and text, niri's look
// (ember-theme.kdl) and the light or dark mode apps follow.

struct Palette {
    let dark: Bool
    var ink: RGBA { dark ? RGBA(0.96, 0.96, 0.97) : RGBA(0.11, 0.11, 0.12) }
    /// over the blurred wallpaper, so glass and text read on any part of it
    var veil: RGBA { dark ? RGBA(0.02, 0.01, 0.06, 0.34) : RGBA(1, 1, 1, 0.20) }

    /// the dashboard's cards and the search
    func card(_ radius: Double) -> Glass {
        Glass(radius: radius, tint: dark ? RGBA(1, 1, 1, 0.07) : RGBA(1, 1, 1, 0.30),
              bend: 8, rim: 16, lens: 0.02, shadow: dark ? 0.6 : 0.8, rimLight: dark ? 0.55 : 1)
    }

    /// panels over everything (power, menus, notes): more solid, for reading
    func panel(_ radius: Double) -> Glass {
        Glass(radius: radius, tint: dark ? RGBA(0.13, 0.12, 0.18, 0.80) : RGBA(0.99, 0.99, 1, 0.78),
              bend: 9, rim: 18, lens: 0.02, blur: 3, shadow: 1.4, rimLight: dark ? 0.6 : 1)
    }

    /// behind an app's icon when the pointer or the keys are on it
    var tile: Glass {
        Glass(radius: 24, tint: dark ? RGBA(1, 1, 1, 0.10) : RGBA(1, 1, 1, 0.34), bend: 6, rim: 12, rimLight: dark ? 0.6 : 1)
    }

    var button: Glass {
        Glass(radius: 999, tint: dark ? RGBA(1, 1, 1, 0.08) : RGBA(1, 1, 1, 0.32), bend: 5, rim: 10, shadow: 0.6, rimLight: dark ? 0.6 : 1)
    }
}

enum Theme {
    // MARK: niri

    static func hex(_ c: RGBA) -> String {
        "#" + [c.r, c.g, c.b, c.a].map { v -> String in
            let h = String(min(255, max(0, Int((v * 255).rounded()))), radix: 16)
            return h.count == 1 ? "0" + h : h
        }.joined()
    }

    /// ember-theme.kdl: rounded windows with soft shadows and gaps, as on a
    /// Mac; a focus ring of Iris's colours; the wallpaper's colours behind
    static func kdl(dark: Bool, blur: Bool = Niri.hasBlur) -> String {
        let bg = dark ? "#141233" : "#ece6f4"
        let backdrop = dark ? "#0a0920" : "#d9d3e8"
        let ringFrom = dark ? "#ffffffd0" : "#7c6cf0d0"
        let ringTo = dark ? "#a78bfa80" : "#38bdf8a0"
        let inactive = dark ? "#ffffff1f" : "#1d1d1f14"
        let shadow = dark ? "#00000088" : "#1d1a4a38"
        var s = """
        // Written by Ember for its \(dark ? "Dark" : "Light") appearance. Ember rewrites this file
        // when the appearance changes, so make changes in config.kdl instead.

        layout {
            gaps 14
            background-color "\(bg)"
            focus-ring {
                width 2
                active-gradient from="\(ringFrom)" to="\(ringTo)" angle=160
                inactive-color "\(inactive)"
            }
            border {
                off
            }
            shadow {
                on
                softness 36
                spread 3
                offset x=0 y=12
                color "\(shadow)"
            }
        }

        overview {
            backdrop-color "\(backdrop)"
        }

        // rounded corners, as on a Mac
        window-rule {
            exclude app-id="^ember$"
            geometry-corner-radius 14
            clip-to-geometry true

        """
        if blur {
            s += """
                // what shows through translucent windows is blurred
                background-effect {
                    blur true
                }

            """
        }
        s += "}\n"
        return s
    }

    // MARK: apps

    /// light or dark mode for apps (GNOME's setting, which GTK, libadwaita,
    /// browsers and Electron apps follow, and GTK's own settings.ini)
    static func systemScheme(dark: Bool) {
        let scheme = dark ? "prefer-dark" : "prefer-light"
        let gtk = dark ? "Adwaita-dark" : "Adwaita"
        if Paths.which("gsettings") != nil {
            let iface = "org.gnome.desktop.interface"
            func get(_ k: String) -> String {
                (Run.output(["gsettings", "get", iface, k], timeout: 3) ?? "").trimmed("' \n")
            }
            if get("color-scheme") != scheme { Run.ok(["gsettings", "set", iface, "color-scheme", scheme]) }
            let cur = get("gtk-theme")
            if cur != gtk && (cur.isEmpty || cur == "Adwaita" || cur == "Adwaita-dark") {
                Run.ok(["gsettings", "set", iface, "gtk-theme", gtk])
            }
        }
        let cfg = Paths.env("XDG_CONFIG_HOME") ?? Paths.home + "/.config"
        for v in ["gtk-3.0", "gtk-4.0"] {
            setIni(cfg + "/\(v)/settings.ini", "gtk-application-prefer-dark-theme", dark ? "1" : "0")
        }
    }

    /// key=value in the [Settings] group of an ini file
    static func setIni(_ path: String, _ key: String, _ value: String) {
        let old = Paths.read(path) ?? ""
        var lines = old.isEmpty ? [] : old.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        while lines.last == "" { lines.removeLast() }
        var group = -1, done = false
        var i = 0
        while i < lines.count {
            let t = lines[i].trimmed()
            if t.hasPrefix("[") {
                if group >= 0 && !done {
                    lines.insert("\(key)=\(value)", at: i)
                    done = true
                    break
                }
                if t == "[Settings]" { group = i }
            } else if group >= 0, let eq = t.firstIndex(of: "="), t[..<eq].trimmed() == key {
                lines[i] = "\(key)=\(value)"
                done = true
                break
            }
            i += 1
        }
        if !done {
            if group < 0 { lines.append("[Settings]") }
            lines.append("\(key)=\(value)")
        }
        let out = lines.joined(separator: "\n") + "\n"
        if out != old { Paths.write(path, out) }
    }

    /// everything that follows the appearance outside Ember: niri's look,
    /// apps' light or dark mode, and the wallpaper
    static func applyOutside(_ s: Settings) {
        let dark = s.dark
        if Niri.isSetUp { Paths.write(Niri.dir + "/ember-theme.kdl", kdl(dark: dark)) }
        systemScheme(dark: dark)
        Wallpaper.changed(s)
    }
}
