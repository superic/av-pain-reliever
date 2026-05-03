// swift-tools-version: 5.10
import PackageDescription

// AV Pain Reliever — Swift Package manifest for the menu-bar app.
//
// `swift run AVPainRelieverApp` from the repo root launches the
// menu-bar agent. `swift test` runs the full test suite. The
// package will eventually be wrapped by an Xcode project for the
// signed-and-notarized .app distribution build, but the SPM
// manifest stays the canonical source of dependencies + targets.
//
// The earlier Hammerspoon-based prototype that this Swift app
// supersedes is archived under `prototypes/hammerspoon/`; see
// `prototypes/README.md` for context.
let package = Package(
    name: "AVPainReliever",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AVPainReliever", targets: ["AVPainReliever"]),
        .executable(name: "AVPainRelieverApp", targets: ["AVPainRelieverApp"]),
    ],
    dependencies: [
        // TOML parser. Foundation has JSON/plist but no TOML; locked
        // architectural choice (see SWIFT_PORT.md) is TOML for the
        // human-edited profiles config, so we pick this up.
        // TOMLKit wraps tomlplusplus and exposes a Codable interface.
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.5.5"),
        // Sparkle 2 — auto-update framework. Reads the EdDSA-signed
        // appcast hosted on GitHub raw, downloads / verifies / installs
        // updates with no server of our own. Only the
        // AVPainRelieverApp target links it; the engine library has
        // no awareness of bundling or updates.
        //
        // Pinned to upToNextMinor because Sparkle is the most
        // notarization-sensitive dependency in the build (its nested
        // Updater.app + XPC services + Autoupdate helper all need to
        // re-sign cleanly inside-out — see scripts/make-app.sh).
        // A new minor could re-shuffle that layout and break our
        // SPARKLE_NESTED list silently. Bumping to a new minor is a
        // deliberate decision, not an automatic Package.resolved
        // refresh.
        .package(url: "https://github.com/sparkle-project/Sparkle.git", .upToNextMinor(from: "2.9.0")),
    ],
    targets: [
        .target(
            name: "AVPainReliever",
            dependencies: ["TOMLKit"]
        ),
        .executableTarget(
            name: "AVPainRelieverApp",
            dependencies: [
                "AVPainReliever",
                .product(name: "Sparkle", package: "Sparkle"),
            ]
        ),
        .testTarget(
            name: "AVPainRelieverTests",
            dependencies: ["AVPainReliever"]
        ),
        // Tests for the app target's pure-logic helpers (Theme,
        // ProfileIcon, NotificationCopy, SettingsStore). The view code
        // itself is exercised by hand; this target keeps the
        // map/copy/persist helpers under unit-test coverage.
        .testTarget(
            name: "AVPainRelieverAppTests",
            dependencies: ["AVPainRelieverApp"]
        ),
    ]
)
