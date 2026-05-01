// swift-tools-version: 5.10
import PackageDescription

// AV Pain Reliever — Swift port (Phase 2 work-in-progress).
//
// This package will eventually be wrapped by the menu-bar app's Xcode
// project. For now it carries the framework-independent engine pieces
// (resolver, debouncer, models) so we can develop them with `swift test`
// before any AppKit/CoreAudio/IOKit code lands.
let package = Package(
    name: "AVPainReliever",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "AVPainReliever", targets: ["AVPainReliever"]),
    ],
    dependencies: [
        // TOML parser. Foundation has JSON/plist but no TOML; locked
        // architectural choice (see SWIFT_PORT.md) is TOML for the
        // human-edited profiles config, so we pick this up.
        // TOMLKit wraps tomlplusplus and exposes a Codable interface.
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.5.5"),
    ],
    targets: [
        .target(
            name: "AVPainReliever",
            dependencies: ["TOMLKit"]
        ),
        .testTarget(
            name: "AVPainRelieverTests",
            dependencies: ["AVPainReliever"]
        ),
    ]
)
