import Foundation
import XCTest
@testable import Ember

final class EmberTests: XCTestCase {
    func testExecFields() {
        XCTAssertEqual(Apps.fields("firefox %u"), ["firefox"])
        XCTAssertEqual(Apps.fields("env A=1 \"my app\" --x=%%y %F"), ["env", "A=1", "my app", "--x=%y"])
        XCTAssertEqual(Apps.fields("sh -c \"echo \\\"hi\\\"\""), ["sh", "-c", "echo \"hi\""])
    }

    func testSearchOrder() {
        let a = [App(id: "a", name: "Files", exec: ["nautilus"]), App(id: "b", name: "Firefox", exec: ["firefox"]),
                 App(id: "c", name: "Text Editor", generic: "Editor", keywords: ["notes"], exec: ["te"]),
                 App(id: "d", name: "Profiler", exec: ["p"])]
        XCTAssertEqual(Apps.filter(a, "fi").map(\.id), ["a", "b", "d"])
        XCTAssertEqual(Apps.filter(a, "edi").map(\.id), ["c"])
        XCTAssertEqual(Apps.filter(a, "note").map(\.id), ["c"])
        XCTAssertEqual(Apps.filter(a, "").count, 4)
    }

    func testVersions() {
        XCTAssertTrue(Updates.newer("2.0.0", "1.0.5"))
        XCTAssertTrue(Updates.newer("1.10", "1.9"))
        XCTAssertFalse(Updates.newer("2.0.0", "2.0.0"))
        XCTAssertFalse(Updates.newer("2.0", "2.0.1"))
    }

    func testOldSettings() throws {
        let old = #"{"hidden":["x.desktop"],"theme":"daylight","autoUpdate":false}"#
        let s = try JSONDecoder().decode(Settings.self, from: Data(old.utf8))
        XCTAssertEqual(s.hidden, ["x.desktop"])
        XCTAssertEqual(s.appearance, .light)
        XCTAssertFalse(s.autoUpdate)
        XCTAssertTrue(s.wallpaper)
        let s2 = try JSONDecoder().decode(Settings.self, from: Data(#"{"theme":"liquid"}"#.utf8))
        XCTAssertEqual(s2.appearance, .auto)
    }

    func testAuto() {
        var s = Settings()
        s.appearance = .auto
        let cal = Calendar.current
        let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        let night = cal.date(bySettingHour: 22, minute: 0, second: 0, of: Date())!
        let dawn = cal.date(bySettingHour: 5, minute: 0, second: 0, of: Date())!
        XCTAssertFalse(s.appearance.isDark(s, at: noon))
        XCTAssertTrue(s.appearance.isDark(s, at: night))
        XCTAssertTrue(s.appearance.isDark(s, at: dawn))
    }

    func testIni() throws {
        let dir = NSTemporaryDirectory() + "ember-test-\(getpid())"
        let p = dir + "/settings.ini"
        Theme.setIni(p, "gtk-application-prefer-dark-theme", "1")
        XCTAssertEqual(Paths.read(p), "[Settings]\ngtk-application-prefer-dark-theme=1\n")
        Paths.write(p, "[Settings]\ngtk-font-name=Inter 11\ngtk-application-prefer-dark-theme=1\n[Other]\nx=1\n")
        Theme.setIni(p, "gtk-application-prefer-dark-theme", "0")
        XCTAssertEqual(Paths.read(p), "[Settings]\ngtk-font-name=Inter 11\ngtk-application-prefer-dark-theme=0\n[Other]\nx=1\n")
        Paths.write(p, "[Settings]\ngtk-font-name=Inter 11\n[Other]\nx=1\n")
        Theme.setIni(p, "gtk-application-prefer-dark-theme", "1")
        XCTAssertEqual(Paths.read(p), "[Settings]\ngtk-font-name=Inter 11\ngtk-application-prefer-dark-theme=1\n[Other]\nx=1\n")
        try? FileManager.default.removeItem(atPath: dir)
    }

    func testThemeKDL() {
        let l = Theme.kdl(dark: false, blur: false), d = Theme.kdl(dark: true, blur: true)
        XCTAssertTrue(l.contains("geometry-corner-radius 14"))
        XCTAssertFalse(l.contains("background-effect"))
        XCTAssertTrue(d.contains("background-effect"))
        XCTAssertNotEqual(l, d)
        // braces balance
        for k in [l, d, Niri.emberKDL] {
            XCTAssertEqual(k.filter { $0 == "{" }.count, k.filter { $0 == "}" }.count)
        }
    }

    func testNiriSetupAndLines() throws {
        let dir = NSTemporaryDirectory() + "ember-niri-\(getpid())"
        setenv("XDG_CONFIG_HOME", dir, 1)
        defer { unsetenv("XDG_CONFIG_HOME"); try? FileManager.default.removeItem(atPath: dir) }
        let cfg = "input {}\nspawn-at-startup \"waybar\"\n    spawn-sh-at-startup \"swaybg -i ~/a.png\"\n"
        Paths.write(Niri.configPath, cfg)
        XCTAssertTrue(try Niri.setup(Settings()))
        let after = Paths.read(Niri.configPath)!
        XCTAssertTrue(Niri.hasInclude(after))
        XCTAssertTrue(after.contains("    // hidden by Ember: spawn-sh-at-startup \"swaybg"), after)
        XCTAssertTrue(Paths.exists(Niri.dir + "/ember.kdl"))
        XCTAssertTrue(Paths.exists(Niri.dir + "/ember-theme.kdl"))
        XCTAssertFalse(try Niri.setup(Settings())) // once only
        Niri.remove()
        XCTAssertEqual(Paths.read(Niri.configPath), cfg + "\n")
        XCTAssertFalse(Paths.exists(Niri.dir + "/ember.kdl"))
    }

    func testHelpers() {
        XCTAssertEqual(fixed(0.64, 1), "0.6")
        XCTAssertEqual(fixed(7.96, 0), "8")
        XCTAssertEqual(fixed(12.05, 1), "12.1")
        XCTAssertEqual(jsonString("a\"b\\c\n"), #""a\"b\\c\n""#)
        XCTAssertEqual("  x y \n".trimmed(), "x y")
        XCTAssertEqual("'prefer-dark'\n".trimmed("' \n"), "prefer-dark")
        XCTAssertEqual(dirname("/a/b/c"), "/a/b")
        XCTAssertEqual(dirname("/a"), "/")
        XCTAssertEqual(Theme.hex(RGBA(1, 0, 0.5, 1)), "#ff0080ff")
    }

    func testRun() {
        XCTAssertEqual(Run.output(["echo", "hi"]), "hi\n")
        XCTAssertNil(Run.output(["false"]))
        XCTAssertNil(Run.output(["sleep", "5"], timeout: 0.3))
        XCTAssertNil(Run.output(["no-such-program-ember"]))
    }

    func testWallpapersBuiltIn() {
        var n = 0
        let p = ember_wallpaper_size(dark: true, &n)
        XCTAssertTrue(p && n > 100_000)
    }
}

private func ember_wallpaper_size(dark: Bool, _ n: inout Int) -> Bool {
    let dir = NSTemporaryDirectory() + "ember-wp-\(getpid())"
    setenv("XDG_DATA_HOME", dir, 1)
    defer { unsetenv("XDG_DATA_HOME"); try? FileManager.default.removeItem(atPath: dir) }
    let p = Wallpaper.file(dark: dark)
    n = (try? FileManager.default.attributesOfItem(atPath: p)[.size] as? Int) ?? 0
    // a JPEG
    let head = FileManager.default.contents(atPath: p)?.prefix(3) ?? Data()
    return head == Data([0xFF, 0xD8, 0xFF])
}
