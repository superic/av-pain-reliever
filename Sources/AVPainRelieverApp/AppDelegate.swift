import Foundation
import AppKit
import SwiftUI
import Combine
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
    let cameraController: CameraController
    let configURL: URL
    let editing: Profile?
    let onSaved: () -> Void
}

final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    /// Pretty-cased title shown in the menu bar. Defaults to the
    /// product name until the engine performs its first evaluation.
    @Published var currentProfileTitle: String = "AV Pain Reliever"

    /// Camera the active profile asks the system to prefer, or nil
    /// if the profile doesn't manage cameras. Surfaced in the menu
    /// for at-a-glance "what camera should I be on" info — useful
    /// because Zoom/Slack/Teams don't follow the system preference,
    /// so the user sometimes has to manually pick the same name in
    /// those apps.
    @Published var currentCameraDisplay: String? = nil

    /// Slug of the most-recently-applied profile. Used by the menu's
    /// "Switch to" submenu to put a checkmark next to the active
    /// entry. Differs from `currentProfileTitle` (pretty-cased,
    /// defaults to the product name) — this stays nil until the
    /// engine actually applies something.
    @Published var activeProfileSlug: String? = nil

    /// All profiles loaded from the canonical TOML config — drives
    /// the menu's "Switch to" submenu so the user can force a
    /// specific profile regardless of what's plugged in.
    @Published var availableProfiles: [Profile] = []

    /// True when the engine resolved to the empty-fingerprint fallback
    /// profile (e.g. "Laptop") AND the user has USB devices attached.
    /// That state means the user is plugged into hardware we don't
    /// have a profile for — the menu should make this visible (the
    /// fallback profile name alone is misleading: it implies "I'm
    /// undocked" when the user is actually at a new dock).
    @Published var atUnknownLocation: Bool = false

    /// Snapshot of attached USB devices the last time the engine
    /// surfaced an unknown-location signal. Used by the wizard's
    /// quick-add path so a user clicking "Set Up This Location" from
    /// the menu lands in the form with the right devices selected.
    @Published var lastUnknownDevices: Set<USBDevice> = []

    private var engine: Engine?

    /// Pick the bundle-aware UserNotifications notifier when running
    /// inside the signed `.app` (clean icon, click-to-dismiss). Fall
    /// back to the AppleScript shim for `swift run` dev binaries that
    /// don't have a bundle identifier. The bundle-id check matches
    /// the gate used for Sparkle below — same "are we inside a real
    /// .app?" signal.
    private let notifier: Notifier = {
        if Bundle.main.bundleIdentifier == "com.ericwillis.avpainreliever" {
            return UserNotificationsNotifier()
        }
        return AppleScriptNotifier()
    }()

    /// Sparkle updater wrapper. Stored so the underlying
    /// `SPUStandardUpdaterController` outlives every "Check for
    /// Updates…" click and the background-check timer. Constructed
    /// lazily in `applicationDidFinishLaunching` so an SPM unit-test
    /// host that imports the app target doesn't pick up a Sparkle
    /// timer it never asked for.
    private var updater: Updater?

    /// Persistent UI preferences. Owned here so views can be passed a
    /// shared `@ObservedObject` reference; the SettingsView and the
    /// menu both read from this.
    let settings = SettingsStore()

    /// Profile currently slated for editing. Set by
    /// `beginEditingProfile(_:)` before opening the wizard window;
    /// cleared once the wizard finishes. Reading this when building
    /// the wizard's `AddProfileDependencies` is what swaps it from
    /// "add new" mode to "edit existing".
    private(set) var profileBeingEdited: Profile?

    /// Bumped every time a wizard session begins (Add or Edit). The
    /// wizard window's content view applies this as a SwiftUI `.id`,
    /// which forces a fresh `@StateObject` view model on every open.
    /// Without this, SwiftUI reuses the prior session's view model —
    /// the wizard would appear with stale state from the previous
    /// open (empty Name field on Edit, or vice versa).
    @Published var wizardOpenToken: UUID = UUID()

    /// Bumped every time the About window is about to open. The About
    /// scene applies this as a SwiftUI `.id`, forcing the view tree to
    /// rebuild — which resets the confetti `@State` so the burst plays
    /// fresh on every open instead of just the first.
    @Published var aboutOpenToken: UUID = UUID()

    /// Same trick for the Welcome window. Bumped wherever
    /// `shouldShowWelcome` is flipped to true (first-launch + the
    /// "Show welcome again" link from About) so the welcome view tree
    /// rebuilds and the confetti burst replays on every open.
    @Published var welcomeOpenToken: UUID = UUID()

    private var cancellables: Set<AnyCancellable> = []

    override init() {
        super.init()
        // Republish SettingsStore changes through our own
        // ObservableObject so views that observe the AppDelegate (the
        // menu, the About scene) re-render when a setting flips —
        // without each view having to observe the store directly.
        settings.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

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
        // Set our brand icon as the app icon — visible in the About
        // window, in window title bars, and as the Dock-icon-on-
        // foreground for windows. Generated at runtime so a palette
        // tweak doesn't need a regenerated `.icns` asset.
        NSApp.applicationIconImage = AppIcon.image
        bootEngine()
        applyLaunchAtLoginPreference()
        // Spin up Sparkle only inside a real .app bundle that has a
        // real EdDSA public key embedded. The full predicate (and
        // the reasoning behind each branch) lives on Updater itself
        // so tests can exercise the gate without needing a bundle.
        if Updater.shouldEnable(
            bundleIdentifier: Bundle.main.bundleIdentifier,
            publicKey: Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        ) {
            updater = Updater()
        }
        maybeShowWelcomeWindow()
    }

    /// Menu-bar entry point — kick off a user-initiated Sparkle check.
    /// No-op when running as an SPM `swift run` binary (updater is nil).
    func checkForUpdates() {
        updater?.checkForUpdates()
    }

    /// Honour the persisted Launch-at-Login preference. Called at
    /// startup so a setting toggled in a previous session takes
    /// effect immediately. Failures (typically because the binary
    /// isn't a signed `.app` yet, so SMAppService can't register it)
    /// are logged but non-fatal — the toggle in Settings will surface
    /// the underlying issue.
    private func applyLaunchAtLoginPreference() {
        LaunchAtLogin.apply(enabled: settings.launchAtLogin)
    }

    /// Set true on first-launch when there are no real-fingerprint
    /// profiles AND the welcome has never been suppressed. App.swift
    /// observes this and opens the welcome window. The fresh-user
    /// starter config still writes (so the engine is operational),
    /// but a single empty-fingerprint laptop fallback doesn't count
    /// as "configured" — only a profile with a real fingerprint does.
    @Published var shouldShowWelcome: Bool = false

    /// Bridge published by the unknown-location notification's
    /// "Open Wizard" action. App.swift's `AddProfileOpener` view
    /// observes this and routes through `openWindow(id:)` — the
    /// SwiftUI environment value isn't reachable from AppDelegate
    /// directly, so we hop via an `@Published` flag the same way
    /// `shouldShowWelcome` does.
    @Published var shouldOpenAddProfileWindow: Bool = false

    /// Initial tab when the Settings window opens. Mutated by the
    /// menu's "Edit Profiles…" item before opening so the user lands
    /// directly on the Profiles list. Persists across opens — leaving
    /// the user on whichever tab they were last using is the macOS
    /// default and preferred over forcing General every time.
    @Published var settingsTab: SettingsTab = .general

    private func maybeShowWelcomeWindow() {
        guard !settings.suppressedWelcome else { return }
        let configured = availableProfiles.contains { !$0.fingerprint.isEmpty }
        guard !configured else { return }
        // Defer to the next runloop turn so SwiftUI's window graph is
        // ready to receive the openWindow request.
        DispatchQueue.main.async { [weak self] in
            self?.welcomeOpenToken = UUID()
            self?.shouldShowWelcome = true
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Suppress the first-run welcome from this point forward. Called
    /// from both `WelcomeView` callbacks (Skip and Add-Your-First).
    func dismissWelcome() {
        settings.suppressedWelcome = true
        shouldShowWelcome = false
    }

    /// Manual entry point — re-show the welcome window even if it
    /// was previously dismissed. Wired to a "Show Welcome Again"
    /// link in the About scene for users who clicked through too
    /// fast and want another look at the explainer.
    func showWelcomeAgain() {
        // Toggling false→true is what `WelcomeOpener` watches for.
        shouldShowWelcome = false
        DispatchQueue.main.async { [weak self] in
            self?.welcomeOpenToken = UUID()
            self?.shouldShowWelcome = true
            NSApp.activate(ignoringOtherApps: true)
        }
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
        availableProfiles = profiles
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
        currentCameraDisplay = profile.camera
        activeProfileSlug = profile.name

        // Toast only on actual changes (different profile name from
        // the previous evaluation). The initial evaluation on launch
        // is intentionally silent — the menu-bar title is already
        // showing the correct profile, so a duplicate toast would
        // just be noise. Settings.notificationsEnabled gates the
        // toast (default on; users can mute from Preferences).
        if let last = lastNotifiedName, last != profile.name {
            settings.incrementSwitchCount()
            if settings.notificationsEnabled {
                notifier.notify(
                    title: NotificationCopy.title(forSlug: profile.name),
                    body: "Audio + camera switched"
                )
            }
        }
        lastNotifiedName = profile.name

        // Re-arm the unknown-location toast if the user just resolved
        // to a profile with a real fingerprint (i.e., they configured
        // the location they were at, or moved to a known one). Also
        // clear the unknown-location menu indicator — it was set by
        // the fallback path; getting back to a real-fingerprint
        // resolution means we're at a known place again.
        if !profile.fingerprint.isEmpty {
            notifiedUnknownLocation = false
            atUnknownLocation = false
            lastUnknownDevices = []
        }
    }

    private func handleUnknownLocation(devices: Set<USBDevice>) {
        // Always update the status so the menu reflects the new
        // location even if we've already toasted about it. Setting
        // these every time is cheap and keeps the menu accurate.
        atUnknownLocation = true
        lastUnknownDevices = devices

        // One toast per "stretch of unknown-ness" — re-armed when the
        // user resolves to a specific profile. Avoids spamming when
        // multiple USB events fire at the same unconfigured location.
        guard !notifiedUnknownLocation else { return }
        notifiedUnknownLocation = true
        guard settings.notificationsEnabled else { return }

        notifier.notify(
            title: "New location detected",
            body: NotificationCopy.unknownLocationBody(deviceCount: devices.count),
            actionTitle: "Open Wizard",
            onAction: { [weak self] in
                // UN delivers the action callback on the main queue
                // already, so no extra hop is needed. Toggle the
                // bridge flag and let `AddProfileOpener` route
                // through SwiftUI's `openWindow`.
                self?.shouldOpenAddProfileWindow = true
                NSApp.activate(ignoringOtherApps: true)
            }
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

    /// Menu-bar entry point — force-apply a specific profile,
    /// bypassing the resolver. The override is one-shot: the next
    /// genuine USB event re-runs the resolver normally and may pick
    /// a different profile. Useful when the user wants to test a
    /// configuration or apply a "wrong-for-now" profile (e.g. set
    /// home-office audio defaults while undocked).
    func applyManually(_ profile: Profile) {
        engine?.applyManually(profile)
    }

    /// Build a fresh dependency bundle for the Add-Profile wizard.
    /// We hand the wizard its own `IOKitUSBWatcher` /
    /// `CoreAudioController` instances rather than reaching into
    /// the engine's internals — both are cheap to construct and the
    /// wizard's snapshot calls don't compete with the engine's
    /// long-lived watcher.
    ///
    /// `editing` is consumed once per wizard window: the next call
    /// returns the edit target, and clearing it after the bundle is
    /// built ensures a subsequent "Add Profile…" doesn't accidentally
    /// reopen in edit mode.
    func addProfileDependencies() -> AddProfileDependencies {
        let editing = profileBeingEdited
        profileBeingEdited = nil
        return AddProfileDependencies(
            watcher: IOKitUSBWatcher(),
            audioController: CoreAudioController(),
            cameraController: AVFoundationCameraController(),
            configURL: Self.profilesTOMLURL,
            editing: editing,
            onSaved: { [weak self] in
                // Saving any profile is taken as the user being
                // committed — no need to keep showing the welcome
                // window if it was queued.
                self?.dismissWelcome()
                self?.reloadConfig()
            }
        )
    }

    /// Stash the profile to edit + bump the wizard-session token so
    /// SwiftUI tears down any prior wizard view model and rebuilds
    /// it with this profile pre-filled. Call this immediately before
    /// `openWindow(id: addProfileWindowID)`.
    func beginEditingProfile(_ profile: Profile) {
        profileBeingEdited = profile
        wizardOpenToken = UUID()
    }

    /// Prep the wizard for a fresh "add new profile" session — clears
    /// any pending edit and bumps the session token. Mirror of
    /// `beginEditingProfile(_:)`; both should be called immediately
    /// before `openWindow(id: addProfileWindowID)`.
    func beginAddingProfile() {
        profileBeingEdited = nil
        wizardOpenToken = UUID()
    }

    /// Bump the About-scene token so SwiftUI rebuilds the view tree
    /// next time the window is shown. Call immediately before
    /// `openWindow(id: aboutWindowID)`.
    func willOpenAbout() {
        aboutOpenToken = UUID()
    }

    /// Confirm + delete a profile. Shown as a modal alert so the user
    /// can't accidentally lose a configuration. After deletion the
    /// engine reloads against the trimmed config.
    func requestDelete(_ profile: Profile) {
        let alert = NSAlert()
        let pretty = PrettyName.format(profile.name)
        alert.messageText = "Delete “\(pretty)”?"
        alert.informativeText = "This profile won't switch your audio + camera defaults when its USB devices are attached. You can always recapture it later."
        alert.alertStyle = .warning
        // Override the generic-app fallback icon NSAlert picks up when
        // running unbundled (`swift run`, no Info.plist). Setting
        // `alert.icon` makes the pill render in both bundled and
        // unbundled contexts; `.warning` style still overlays its
        // caution badge on top.
        alert.icon = AppIcon.image
        // Cancel first → default (Return) → safe accidental press.
        // Delete second, destructive-styled (red on macOS 11+) so the
        // dangerous action both looks dangerous and requires a
        // deliberate click rather than a stray Return.
        alert.addButton(withTitle: "Cancel")
        let deleteButton = alert.addButton(withTitle: "Delete")
        deleteButton.hasDestructiveAction = true
        let response = alert.runModal()
        guard response == .alertSecondButtonReturn else { return }
        do {
            try ProfileWriter().delete(named: profile.name, in: Self.profilesTOMLURL)
            reloadConfig()
        } catch {
            let failure = NSAlert()
            failure.messageText = "Couldn't delete “\(pretty)”"
            failure.informativeText = "\(error)"
            failure.alertStyle = .critical
            failure.icon = AppIcon.image
            failure.runModal()
        }
    }

    // MARK: - Bootstrap

    private func buildEngine(profiles: [Profile], logger: ApplierLogger) -> Engine {
        let watcher = IOKitUSBWatcher()
        let resolver = ProfileResolver(profiles: profiles)
        let audio = CoreAudioController()
        let camera = AVFoundationCameraController()
        let applier = ProfileApplier(audio: audio, camera: camera, logger: logger)
        return Engine(
            watcher: watcher,
            resolver: resolver,
            applier: applier,
            logger: logger,
            debounceInterval: settings.debounceInterval,
            clock: DispatchClock()
        )
    }

    // MARK: - Convenience surfaces for the menu

    /// Mirror of `settings.profileSwitchCount` exposed on the
    /// AppDelegate so the menu's `@ObservedObject` re-renders without
    /// a separate observer plumbed through the view.
    var profileSwitchCount: Int { settings.profileSwitchCount }

    /// Mirror of `settings.showProfileNameInMenuBar` for the same reason.
    var showProfileNameInMenuBar: Bool { settings.showProfileNameInMenuBar }

    /// Mirror of `settings.showProfileIconInMenuBar` for the same reason.
    var showProfileIconInMenuBar: Bool { settings.showProfileIconInMenuBar }

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
