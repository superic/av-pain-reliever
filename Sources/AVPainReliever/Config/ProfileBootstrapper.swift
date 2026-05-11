import Foundation

/// Outcome of a `ProfileBootstrapper.loadOrBootstrap` call. Carries
/// the resolved profile list and, when corruption was recovered from,
/// the URL of the moved-aside copy so the host can show the user
/// where to find their data.
public enum LoadOutcome {
    case loaded([Profile])
    case bootstrapped([Profile])
    case quarantinedAndReset([Profile], quarantinedAs: URL)
    case unrecoverable

    public var profiles: [Profile] {
        switch self {
        case .loaded(let p), .bootstrapped(let p), .quarantinedAndReset(let p, _):
            return p
        case .unrecoverable:
            return []
        }
    }
}

/// Closure that moves a corrupt config file out of the way and returns
/// its new URL. The default implementation moves the file to the
/// user's Trash so recovery uses the standard Finder affordance
/// (right-click, Put Back). Tests inject a sibling-rename closure to
/// keep their scratch directories self-contained.
public typealias QuarantineOp = (URL) throws -> URL

/// Discovers an existing profiles config or bootstraps a new one.
/// Three branches:
///
///   1. File parses cleanly: load and return.
///   2. File doesn't exist: write the starter so the engine has a
///      "laptop" fallback to apply.
///   3. File exists but won't parse (typo, schema violation): move
///      the corrupt copy out of the way before writing a starter, and
///      surface its new location in `LoadOutcome` so the host can
///      tell the user. Without this branch, a single bad save (a typo
///      caught by the auto-reload watcher) would silently overwrite
///      every custom profile.
public struct ProfileBootstrapper {
    public init() {}

    /// Canonical location of the Swift-app's `profiles.toml`. Single
    /// source of truth used by the first-launch bootstrap, the
    /// Add-Profile wizard's writer, and the menu-bar's delete path.
    public static let canonicalTOMLURL: URL =
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(
                "Library/Application Support/AVPainReliever/profiles.toml"
            )

    /// Load profiles from the canonical TOML. Production entry point;
    /// delegates to the URL-taking overload for test reach.
    public func loadOrBootstrap(logger: ApplierLogger) -> LoadOutcome {
        loadOrBootstrap(from: Self.canonicalTOMLURL, logger: logger)
    }

    /// URL-parameterized loader. Tests pass a scratch directory and a
    /// sibling-rename `quarantine` closure so they don't reach into
    /// the user's real Trash. Production uses the default Trash op.
    public func loadOrBootstrap(
        from tomlURL: URL,
        logger: ApplierLogger,
        quarantine: QuarantineOp = ProfileBootstrapper.trashCorruptFile
    ) -> LoadOutcome {
        if FileManager.default.fileExists(atPath: tomlURL.path) {
            do {
                let profiles = try ConfigLoader().loadProfiles(from: tomlURL)
                logger.info("loaded \(profiles.count) profiles from \(tomlURL.path)")
                return .loaded(profiles)
            } catch {
                logger.warn("failed to parse \(tomlURL.path): \(error)")
                // Move the corrupt file aside before any write. If the
                // quarantine op fails, the user's broken-but-recoverable
                // file stays in place; the destructive overwrite that
                // used to happen on this path is gone.
                do {
                    let quarantineURL = try quarantine(tomlURL)
                    try writeStarterConfig(at: tomlURL)
                    let starterProfiles = try ConfigLoader().loadProfiles(from: tomlURL)
                    logger.info("moved corrupt config to \(quarantineURL.path); wrote fresh starter")
                    return .quarantinedAndReset(starterProfiles, quarantinedAs: quarantineURL)
                } catch {
                    logger.warn("could not recover from corrupt config: \(error). Leaving file in place, engine runs idle.")
                    return .unrecoverable
                }
            }
        }

        // Fresh user with no Swift-app config: bootstrap a starter
        // `profiles.toml` so the app does something useful on first
        // launch (apply MacBook audio defaults when undocked) instead
        // of staring blankly until the user creates a config.
        do {
            try writeStarterConfig(at: tomlURL)
            let profiles = try ConfigLoader().loadProfiles(from: tomlURL)
            logger.info("first launch: wrote a starter config to \(tomlURL.path) (\(profiles.count) profile)")
            return .bootstrapped(profiles)
        } catch {
            logger.warn("failed to write starter config to \(tomlURL.path): \(error). Engine will run idle until a config is created.")
            return .unrecoverable
        }
    }

    /// Default quarantine op: move the corrupt file to the user's
    /// Trash. macOS handles collision naming (adds a numeric suffix if
    /// the Trash already holds `profiles.toml`). Returns the resulting
    /// URL inside the Trash so the host can offer a reveal-in-Finder
    /// action. Throws if `trashItem` fails (read-only volume, etc.).
    public static func trashCorruptFile(_ tomlURL: URL) throws -> URL {
        var resultingURL: NSURL?
        try FileManager.default.trashItem(at: tomlURL, resultingItemURL: &resultingURL)
        guard let url = resultingURL as URL? else {
            throw CocoaError(.fileWriteUnknown)
        }
        return url
    }

    /// Default `profiles.toml` content, written on first launch when
    /// no existing config is present. Includes one always-matches
    /// "laptop" profile with modern-Mac defaults plus inline comments
    /// showing the user how to add docked locations.
    static let starterConfig = """
    # AV Pain Reliever — profile config.
    # Each [profiles.<name>] section defines a location.
    #
    # A profile matches when every USB device in its `fingerprint` is
    # currently attached. Most-specific match wins; alphabetical
    # tiebreak. An empty fingerprint matches always (specificity 0),
    # making such a profile the implicit fallback when nothing more
    # specific matches.

    [profiles.laptop]
    # Implicit fallback — no fingerprint means this matches whenever
    # no docked profile does (typical state: undocked MacBook).
    audioInput  = "MacBook Pro Microphone"
    audioOutput = "MacBook Pro Speakers"

    # Add a docked profile here, e.g.:
    #
    # [profiles.home-office]
    # audioInput  = "Yeti Stereo Microphone"
    # audioOutput = "External DAC"
    # fingerprint = [
    #   { vendorID = 0x2188, productID = 0x6533, name = "Dock" },
    #   { vendorID = 0x043e, productID = 0x9a68, name = "External camera" },
    # ]
    #
    # Easier: click the menu bar → Add Profile… and the wizard
    # captures your currently-attached devices automatically.

    """

    private func writeStarterConfig(at url: URL) throws {
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent, withIntermediateDirectories: true
        )
        try Self.starterConfig.write(to: url, atomically: true, encoding: .utf8)
    }
}
