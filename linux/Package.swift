// swift-tools-version: 6.0
//
// Ember for Linux: Swift, GTK 4 and libadwaita, drawn in Liquid Glass (the
// same Stage and Glass code as the Iris browser). No dependencies beyond the
// system's GTK 4.14+, libadwaita 1.5+ and GLib.
import Foundation
import PackageDescription

let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path

let package = Package(
    name: "Ember",
    targets: [
        .systemLibrary(name: "CAdw", pkgConfig: "libadwaita-1"),
        .systemLibrary(name: "CGioUnix", pkgConfig: "gio-unix-2.0"),
        // the wallpapers, built into the program (an update that replaces
        // only the program still brings them)
        .target(name: "CData", exclude: ["iris-light.jpg", "iris-dark.jpg"], cSettings: [.define("EMBER_DATA_DIR", to: "\"\(here)/Sources/CData\"")]),
        .executableTarget(name: "Ember", dependencies: ["CAdw", "CGioUnix", "CData"]),
        .testTarget(name: "EmberTests", dependencies: ["Ember"]),
    ],
    swiftLanguageModes: [.v5]
)
