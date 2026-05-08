import Foundation

/// Discovers an existing profiles config or bootstraps a new one for
/// fresh installs. Wraps the read / import / seed dance the host's
/// first launch performs:
///
///   1. `~/Library/Application Support/AVPainReliever/profiles.toml` —
///      the canonical Swift-app config; load it directly.
///   2. `~/.hammerspoon/profiles.lua` — auto-migrate users coming from
///      the Phase 1 Hammerspoon prototype. Imported profiles get
///      written to the canonical TOML so future edits and the
///      Add-Profile wizard operate on the same file.
///   3. Neither file exists — write a starter `profiles.toml` so the
///      engine has a working "laptop" fallback to apply on first
///      launch instead of running idle.
///
/// Lives in the engine library so the host AppDelegate can stay a
/// thin caller and the bootstrap behavior is testable without the
/// app target.
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

    /// Load profiles from the canonical TOML, falling through to
    /// Hammerspoon migration, falling through to a starter config
    /// write. Logs each branch via `ApplierLogger` so the host's
    /// console pipeline gets a uniform audit trail. Returns an empty
    /// array only when every fallback failed; the engine then runs
    /// idle until the user creates a config.
    public func loadOrBootstrap(logger: ApplierLogger) -> [Profile] {
        let tomlURL = Self.canonicalTOMLURL
        let luaURL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".hammerspoon/profiles.lua")

        if FileManager.default.fileExists(atPath: tomlURL.path) {
            do {
                let profiles = try ConfigLoader().loadProfiles(from: tomlURL)
                logger.info("loaded \(profiles.count) profiles from \(tomlURL.path)")
                return profiles
            } catch {
                logger.warn("failed to load \(tomlURL.path): \(error)")
            }
        }

        if FileManager.default.fileExists(atPath: luaURL.path) {
            do {
                let lua = try String(contentsOf: luaURL, encoding: .utf8)
                let importer = ConfigImporter()
                let profiles = try importer.parse(lua)
                // One-shot migration: write the imported profiles to
                // the canonical TOML location so future launches AND
                // the Add-Profile wizard work against the same file.
                // Without this, the first wizard save creates a TOML
                // containing only the new profile, silently shadowing
                // everything in profiles.lua.
                do {
                    let toml = try importer.convertToTOML(lua)
                    try FileManager.default.createDirectory(
                        at: tomlURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try toml.write(to: tomlURL, atomically: true, encoding: .utf8)
                    logger.info("migrated \(profiles.count) profiles from \(luaURL.path) (Hammerspoon) → \(tomlURL.path); future edits should go to the TOML file")
                } catch {
                    logger.warn("loaded \(profiles.count) profiles from \(luaURL.path) but migration to \(tomlURL.path) failed: \(error). Wizard saves won't include these until migration succeeds.")
                }
                return profiles
            } catch {
                logger.warn("failed to import \(luaURL.path): \(error)")
            }
        }

        // Fresh user with no Hammerspoon and no Swift-app config:
        // bootstrap a starter `profiles.toml` so the app does
        // something useful on first launch (apply MacBook audio
        // defaults when undocked) instead of staring blankly until
        // the user creates a config.
        do {
            try writeStarterConfig(at: tomlURL)
            let profiles = try ConfigLoader().loadProfiles(from: tomlURL)
            logger.info("first launch — wrote a starter config to \(tomlURL.path) (\(profiles.count) profile)")
            return profiles
        } catch {
            logger.warn("failed to write starter config to \(tomlURL.path): \(error) — engine will run idle until a config is created")
            return []
        }
    }

    /// Default `profiles.toml` content, written on first launch when
    /// neither an existing TOML nor a Hammerspoon `profiles.lua`
    /// exists. Includes one always-matches "laptop" profile with
    /// modern-Mac defaults plus inline comments showing the user how
    /// to add docked locations.
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
