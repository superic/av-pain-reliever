import Foundation
import AppKit
import SwiftUI
import AVPainReliever

/// Owns the engine and exposes its current profile to the SwiftUI
/// status item via `@Published`. Created by SwiftUI through
/// `@NSApplicationDelegateAdaptor` in `App.swift`.
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    /// Pretty-cased title shown in the menu bar. Defaults to the
    /// product name until the engine performs its first evaluation.
    @Published var currentProfileTitle: String = "AV Pain Reliever"

    private var engine: Engine?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide the Dock icon programmatically. The eventual signed
        // .app bundle will set LSUIElement = YES in Info.plist, which
        // is the same effect at launch time. For an SPM-built binary
        // we don't have an Info.plist, so we set the activation
        // policy at runtime.
        NSApp.setActivationPolicy(.accessory)

        let logger = ConsoleLogger()
        let profiles = loadProfiles(logger: logger)
        let engine = buildEngine(profiles: profiles, logger: logger)
        engine.onProfileApplied = { [weak self] profile in
            // Engine fires onProfileApplied on the same thread the
            // debouncer/initial-start ran on (main, in production).
            // SwiftUI requires @Published mutations from the main
            // thread, which is satisfied here.
            self?.currentProfileTitle = PrettyName.format(profile.name)
        }
        engine.start()
        self.engine = engine
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine?.stop()
    }

    // MARK: - Bootstrap

    private func buildEngine(profiles: [Profile], logger: ApplierLogger) -> Engine {
        let watcher = IOKitUSBWatcher()
        let resolver = ProfileResolver(profiles: profiles)
        let audio = CoreAudioController()
        let obs = ProcessOBSController() // nil if obs-cmd not installed
        if obs == nil {
            logger.warn("obs-cmd not installed — OBS scene switching will be skipped")
        }
        let applier = ProfileApplier(audio: audio, obs: obs, logger: logger)
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
    ///   3. Empty list — engine logs a warning and runs idle until
    ///      the user creates a config.
    private func loadProfiles(logger: ApplierLogger) -> [Profile] {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let tomlURL = home
            .appendingPathComponent("Library/Application Support/AVPainReliever/profiles.toml")
        let luaURL = home
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
                let profiles = try ConfigImporter().parse(lua)
                logger.info("imported \(profiles.count) profiles from \(luaURL.path) (Hammerspoon)")
                return profiles
            } catch {
                logger.warn("failed to import \(luaURL.path): \(error)")
            }
        }

        logger.warn("no profile config found at \(tomlURL.path) or \(luaURL.path) — engine will run idle until a config is created")
        return []
    }
}
