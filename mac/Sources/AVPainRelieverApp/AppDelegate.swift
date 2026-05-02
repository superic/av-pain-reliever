import Foundation
import AppKit
import SwiftUI
import AVPainReliever

/// Owns the engine and exposes its current profile to the SwiftUI
/// status item via `@Published`. Created by SwiftUI through
/// `@NSApplicationDelegateAdaptor` in `App.swift`.
/// Bundle of dependencies the Add-Profile wizard needs. Created
/// fresh per-window-open from `AppDelegate.addProfileDependencies()`
/// so the wizard isn't entangled with the engine's lifecycle.
struct AddProfileDependencies {
    let watcher: USBWatcher
    let audioController: AudioController
    let configURL: URL
    let onSaved: () -> Void
}

final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    /// Pretty-cased title shown in the menu bar. Defaults to the
    /// product name until the engine performs its first evaluation.
    @Published var currentProfileTitle: String = "AV Pain Reliever"

    private var engine: Engine?
    private let notifier: Notifier = AppleScriptNotifier()

    private static let profilesTOMLURL: URL =
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(
                "Library/Application Support/AVPainReliever/profiles.toml"
            )

    /// The most recent profile name we surfaced through
    /// `onProfileApplied`. Used to suppress a notification for the
    /// initial evaluation on launch (the menu-bar title is already
    /// up-to-date) and for re-applies of the same profile.
    private var lastNotifiedName: String?

    /// One-shot gate: we only toast about an unknown location once
    /// per "stretch of unknown-ness". Reset to false when the engine
    /// resolves to a profile with a real fingerprint, so docking at a
    /// new unconfigured place after configuring one re-arms the
    /// notification.
    private var notifiedUnknownLocation = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide the Dock icon programmatically. The eventual signed
        // .app bundle will set LSUIElement = YES in Info.plist, which
        // is the same effect at launch time. For an SPM-built binary
        // we don't have an Info.plist, so we set the activation
        // policy at runtime.
        NSApp.setActivationPolicy(.accessory)
        bootEngine()
    }

    /// Tear down any existing engine, re-read the config from disk,
    /// and start a fresh engine. Called on launch and on the menu's
    /// "Reload Config" action. Notification state
    /// (lastNotifiedName, notifiedUnknownLocation) is intentionally
    /// preserved across reloads — a reload that lands on the same
    /// profile is silent, while one that lands on a different profile
    /// toasts (the user's edit took effect).
    private func bootEngine() {
        engine?.stop()

        let logger = ConsoleLogger()
        let profiles = loadProfiles(logger: logger)
        let engine = buildEngine(profiles: profiles, logger: logger)
        engine.onProfileApplied = { [weak self] profile in
            // Engine fires onProfileApplied on the same thread the
            // debouncer/initial-start ran on (main, in production).
            // SwiftUI requires @Published mutations from the main
            // thread, which is satisfied here.
            self?.handleProfileApplied(profile)
        }
        engine.onUnknownLocation = { [weak self] devices in
            self?.handleUnknownLocation(devices: devices)
        }
        engine.start()
        self.engine = engine
    }

    private func handleProfileApplied(_ profile: Profile) {
        let pretty = PrettyName.format(profile.name)
        currentProfileTitle = pretty

        // Toast only on actual changes (different profile name from
        // the previous evaluation). The initial evaluation on launch
        // is intentionally silent — the menu-bar title is already
        // showing the correct profile, so a duplicate toast would
        // just be noise.
        if let last = lastNotifiedName, last != profile.name {
            notifier.notify(title: pretty, body: "AV profile activated")
        }
        lastNotifiedName = profile.name

        // Re-arm the unknown-location toast if the user just resolved
        // to a profile with a real fingerprint (i.e., they configured
        // the location they were at, or moved to a known one).
        if !profile.fingerprint.isEmpty {
            notifiedUnknownLocation = false
        }
    }

    private func handleUnknownLocation(devices: Set<USBDevice>) {
        // One toast per "stretch of unknown-ness" — re-armed when the
        // user resolves to a specific profile. Avoids spamming when
        // multiple USB events fire at the same unconfigured location.
        guard !notifiedUnknownLocation else { return }
        notifiedUnknownLocation = true

        let count = devices.count
        let unitNoun = count == 1 ? "device" : "devices"
        notifier.notify(
            title: "New location detected",
            body: "\(count) USB \(unitNoun) attached. Add it to your profiles so AV Pain Reliever can switch automatically."
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine?.stop()
    }

    /// Menu-bar entry point — force an immediate re-evaluation
    /// without waiting for the next USB event or for the debounce
    /// window to elapse. Useful when the user knows a state change
    /// happened that the engine hasn't observed (e.g., plugging in
    /// something the watcher missed, or just sanity-checking what the
    /// engine resolves to right now).
    func reevaluate() {
        engine?.evaluate()
    }

    /// Menu-bar entry point — re-read the config file from disk and
    /// rebuild the engine with the new profile list. The user clicks
    /// this after editing profiles.toml (or .lua) and wants the
    /// changes picked up without a full app restart.
    func reloadConfig() {
        bootEngine()
    }

    /// Build a fresh dependency bundle for the Add-Profile wizard.
    /// We hand the wizard its own `IOKitUSBWatcher` /
    /// `CoreAudioController` instances rather than reaching into
    /// the engine's internals — both are cheap to construct and the
    /// wizard's snapshot calls don't compete with the engine's
    /// long-lived watcher.
    func addProfileDependencies() -> AddProfileDependencies {
        AddProfileDependencies(
            watcher: IOKitUSBWatcher(),
            audioController: CoreAudioController(),
            configURL: Self.profilesTOMLURL,
            onSaved: { [weak self] in self?.reloadConfig() }
        )
    }

    // MARK: - Bootstrap

    private func buildEngine(profiles: [Profile], logger: ApplierLogger) -> Engine {
        let watcher = IOKitUSBWatcher()
        let resolver = ProfileResolver(profiles: profiles)
        let audio = CoreAudioController()
        let applier = ProfileApplier(audio: audio, logger: logger)
        return Engine(
            watcher: watcher,
            resolver: resolver,
            applier: applier,
            logger: logger,
            debounceInterval: 1.5,
            clock: DispatchClock()
        )
    }

    /// Profile-config discovery in priority order. Mirrors what the
    /// eventual first-run wizard will codify, but for now lets a
    /// developer or migrating Phase 1 user run the app immediately:
    ///
    ///   1. `~/Library/Application Support/AVPainReliever/profiles.toml`
    ///      — the canonical Swift-app config location.
    ///   2. `~/.hammerspoon/profiles.lua` — auto-import for users
    ///      migrating from the Hammerspoon Phase 1 engine.
    ///   3. **Bootstrap a default profiles.toml** — a fresh user
    ///      with neither file gets a working "laptop" fallback
    ///      profile written to (1) so the app actually does
    ///      something on first launch.
    private func loadProfiles(logger: ApplierLogger) -> [Profile] {
        let tomlURL = Self.profilesTOMLURL
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
    /// to add docked locations and OBS scenes.
    private static let starterConfig = """
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
