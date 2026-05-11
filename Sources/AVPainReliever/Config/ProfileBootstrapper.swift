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
/// its new URL. The default implementation renames it in place to a
/// timestamped sibling so the broken copy stays right next to the
/// active config and isn't subject to Trash auto-empty. Tests inject
/// their own closure to keep their scratch directories deterministic.
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
    /// deterministic `quarantine` closure. Production uses the
    /// default in-place rename.
    public func loadOrBootstrap(
        from tomlURL: URL,
        logger: ApplierLogger,
        quarantine: QuarantineOp = ProfileBootstrapper.renameCorruptFileInPlace
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

    /// Default quarantine op: rename the corrupt file in place to a
    /// timestamped sibling. The broken copy stays in the Application
    /// Support directory next to the active config, so the user finds
    /// both when they open the folder. Filename pattern:
    /// `profiles.corrupted-{YYYY-MM-DD-HHMMSS-mmm}.toml`. Millisecond
    /// suffix prevents back-to-back corrupt saves from colliding.
    /// Throws if the move fails (read-only parent, etc.) so the
    /// caller can fall back to `.unrecoverable`.
    public static func renameCorruptFileInPlace(_ tomlURL: URL) throws -> URL {
        let timestamp = quarantineTimestamp(from: Date())
        let parent = tomlURL.deletingLastPathComponent()
        let destination = parent.appendingPathComponent("profiles.corrupted-\(timestamp).toml")
        try FileManager.default.moveItem(at: tomlURL, to: destination)
        return destination
    }

    /// Filename-safe timestamp: `YYYY-MM-DD-HHMMSS-mmm` in UTC. Used
    /// only by the default quarantine op; not part of the public API.
    private static func quarantineTimestamp(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss-SSS"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
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
