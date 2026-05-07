import Foundation
import Combine
import AVPainReliever

/// User-tunable behavior toggles. Persisted to `UserDefaults` under the
/// app's domain so settings survive relaunches without us writing
/// anything to the canonical TOML config (which is reserved for
/// profiles).
///
/// Tests inject an `UserDefaults(suiteName:)` instance to keep
/// production defaults clean.
final class SettingsStore: ObservableObject {
    /// Stable keys, public so tests can assert on them.
    enum Key {
        static let notificationsEnabled = "notificationsEnabled"
        static let debounceInterval = "debounceInterval"
        static let showProfileNameInMenuBar = "showProfileNameInMenuBar"
        static let showProfileIconInMenuBar = "showProfileIconInMenuBar"
        static let menuBarIconSymbol = "menuBarIconSymbol"
        static let profileSwitchCount = "profileSwitchCount"
        static let suppressedWelcome = "suppressedWelcome"
        static let launchAtLogin = "launchAtLogin"
        static let virtualCameraEnabled = "virtualCameraEnabled"
        static let experimentalUpdates = "experimentalUpdates"
        static let statsTrackingEnabled = "statsTrackingEnabled"
        static let statsStartDate = "statsStartDate"
        static let perProfileCounts = "perProfileCounts"
        static let lastSwitchSlug = "lastSwitchSlug"
        static let lastSwitchDate = "lastSwitchDate"
        static let manualOverrideCount = "manualOverrideCount"
        static let currentStreakDays = "currentStreakDays"
        static let longestStreakDays = "longestStreakDays"
        static let activeDaysCount = "activeDaysCount"
        static let uniqueDeviceFingerprints = "uniqueDeviceFingerprints"
    }

    /// Toast on profile change?  Default on — the at-a-glance signal
    /// is the whole point. Users running back-to-back location changes
    /// or doing demos sometimes want to mute it.
    @Published var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Key.notificationsEnabled) }
    }

    /// USB debounce window in seconds. 1.5s is the validated default
    /// (see docs/decisions.md → Validated decisions). Slider exposes
    /// a 0.5–5.0 range; persisted as Double for the UI.
    @Published var debounceInterval: Double {
        didSet { defaults.set(debounceInterval, forKey: Key.debounceInterval) }
    }

    /// Show the active profile name next to the menu bar pill icon.
    /// Default on — users get the at-a-glance "where am I" signal
    /// without opening the menu. Off renders just the icon for a
    /// minimal status item.
    @Published var showProfileNameInMenuBar: Bool {
        didSet { defaults.set(showProfileNameInMenuBar, forKey: Key.showProfileNameInMenuBar) }
    }

    /// Swap the menu bar's `pills.fill` glyph for the active profile's
    /// SF Symbol (resolved through `ProfileIcon.effectiveSymbol`).
    /// Default off — the pill icon is the product's identity at a
    /// glance, so opting in is what users do when they want the menu
    /// bar to track location instead.
    @Published var showProfileIconInMenuBar: Bool {
        didSet { defaults.set(showProfileIconInMenuBar, forKey: Key.showProfileIconInMenuBar) }
    }

    /// SF Symbol used in the menu bar when no per-profile icon is
    /// active (i.e. when `showProfileIconInMenuBar` is off, or it's
    /// on but no profile has been resolved yet). Default is
    /// `MenuBarIcon.defaultSymbol` so existing installs see no change.
    @Published var menuBarIconSymbol: String {
        didSet { defaults.set(menuBarIconSymbol, forKey: Key.menuBarIconSymbol) }
    }

    /// Lifetime count of profile applications. Drives the easter-egg
    /// stats line. Bumped from `AppDelegate.handleProfileApplied`.
    @Published var profileSwitchCount: Int {
        didSet { defaults.set(profileSwitchCount, forKey: Key.profileSwitchCount) }
    }

    /// Set to true the first time the user dismisses the welcome
    /// window OR adds their first profile. Prevents the welcome from
    /// reappearing on subsequent launches.
    @Published var suppressedWelcome: Bool {
        didSet { defaults.set(suppressedWelcome, forKey: Key.suppressedWelcome) }
    }

    /// Whether the app should auto-launch at login. Default off so a
    /// fresh user has to opt in (per macOS background-task etiquette).
    /// `LaunchAtLogin.apply(enabled:)` mirrors this state into the
    /// system's launch services.
    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Key.launchAtLogin)
            LaunchAtLogin.apply(enabled: launchAtLogin)
        }
    }

    /// Opt-in toggle for the V2 virtual camera. Default off. When on,
    /// the app installs/activates its CMIO Camera Extension and the
    /// active profile drives the virtual camera's source. When off,
    /// the extension is deactivated and the host capture pipeline is
    /// torn down — keeping the camera light off and AVCapture clients
    /// like Zoom from seeing a stale "AV Pain Reliever" device.
    /// `VirtualCameraActivator` reads this on launch and observes
    /// changes; `AppDelegate.applyVirtualCameraEnabled(_:)` mediates
    /// the actual state transitions.
    @Published var virtualCameraEnabled: Bool {
        didSet { defaults.set(virtualCameraEnabled, forKey: Key.virtualCameraEnabled) }
    }

    /// Opt-in to updates from the `experimental` Sparkle channel.
    /// Default off — only stable releases reach the user. When on,
    /// the Updater's allowedChannels delegate hook returns
    /// `["experimental"]`, so feed items tagged
    /// `<sparkle:channel>experimental</sparkle:channel>` become
    /// eligible upgrades. Used to gate the v0.2.x virtual-camera
    /// builds behind a deliberate user choice while the feature is
    /// still maturing.
    @Published var experimentalUpdates: Bool {
        didSet { defaults.set(experimentalUpdates, forKey: Key.experimentalUpdates) }
    }

    /// Master gate for usage-stats tracking. **Default: off.** With
    /// this false, every `record*` / `increment*` method early-returns
    /// — no fields update, no `UserDefaults` writes happen, no menu
    /// counters advance. Existing values stay frozen and visible (the
    /// user can flip the toggle off after some history without losing
    /// what was already collected). Surfaced in Settings → Advanced.
    @Published var statsTrackingEnabled: Bool {
        didSet {
            defaults.set(statsTrackingEnabled, forKey: Key.statsTrackingEnabled)
            // Stamp the start date the *first* time the user opts in.
            // Off → on → off → on must NOT reset it; the user's
            // intent is "I started keeping notes a while back" and
            // the streak / activeDays math relies on a stable origin.
            if statsTrackingEnabled, statsStartDate == nil {
                statsStartDate = Date()
            }
        }
    }

    /// Captured the first time the user enables `statsTrackingEnabled`.
    /// Drives the "Tracking since N days ago" line in Advanced.
    @Published var statsStartDate: Date? {
        didSet { defaults.set(statsStartDate, forKey: Key.statsStartDate) }
    }

    /// Count of how many times each profile (by slug) has been
    /// applied since tracking was enabled. Powers the "most-used
    /// location" highlight + the per-profile rankings.
    @Published var perProfileCounts: [String: Int] {
        didSet { defaults.set(perProfileCounts, forKey: Key.perProfileCounts) }
    }

    /// Slug of the most recently applied profile (set alongside
    /// `lastSwitchDate`). Renders as "Last switched 2h ago to Home
    /// Office" in Advanced.
    @Published var lastSwitchSlug: String? {
        didSet { defaults.set(lastSwitchSlug, forKey: Key.lastSwitchSlug) }
    }

    /// Wall-clock time of the most recent recorded switch. Used to
    /// drive the relative-time rendering AND the streak / activeDays
    /// day-bucket math.
    @Published var lastSwitchDate: Date? {
        didSet { defaults.set(lastSwitchDate, forKey: Key.lastSwitchDate) }
    }

    /// How many times the user has forced a profile from the menu's
    /// "Switch to …" submenu (vs. the resolver auto-picking one in
    /// response to a USB event). A high count is a soft signal that
    /// the user's profiles aren't quite matching reality and might
    /// want adjustment.
    @Published var manualOverrideCount: Int {
        didSet { defaults.set(manualOverrideCount, forKey: Key.manualOverrideCount) }
    }

    /// Consecutive calendar days with at least one recorded switch,
    /// counting today (or the day of the most recent switch).
    @Published var currentStreakDays: Int {
        didSet { defaults.set(currentStreakDays, forKey: Key.currentStreakDays) }
    }

    /// All-time maximum value `currentStreakDays` has reached. Never
    /// decreases except via `resetStats()`.
    @Published var longestStreakDays: Int {
        didSet { defaults.set(longestStreakDays, forKey: Key.longestStreakDays) }
    }

    /// Total count of distinct calendar days on which at least one
    /// switch was recorded. Diverges from `currentStreakDays` once
    /// any gap appears — a 50-active-day user with an interrupted
    /// streak still has activeDays = 50 even if the current streak
    /// is back to 1.
    @Published var activeDaysCount: Int {
        didSet { defaults.set(activeDaysCount, forKey: Key.activeDaysCount) }
    }

    /// Backing storage for the unique-device set. Each entry is the
    /// `(vendorID, productID)` pair as `"<vid>:<pid>"` lowercase hex.
    /// `[String]` so it round-trips cleanly through UserDefaults
    /// without custom encoding. Surfaced as
    /// `uniqueDevicesSeenCount` for the UI.
    @Published var uniqueDeviceFingerprints: [String] {
        didSet { defaults.set(uniqueDeviceFingerprints, forKey: Key.uniqueDeviceFingerprints) }
    }

    /// Convenience for the Advanced view — the count is what the UI
    /// actually wants. Computed so it tracks the array without an
    /// extra published field.
    var uniqueDevicesSeenCount: Int { uniqueDeviceFingerprints.count }

    /// True iff there's user-meaningful stats data (counters
    /// non-zero, dictionaries / arrays non-empty, a last-switch
    /// recorded). Drives both the Reset Stats section's visibility
    /// AND the on-disable "also reset?" prompt.
    ///
    /// `statsStartDate` is intentionally NOT counted here — it's
    /// internal bookkeeping (set on first opt-in, re-stamped on
    /// reset) and a fresh opt-in / opt-out cycle leaves it set
    /// without any data the user would recognize as "stats."
    var hasRecordedStats: Bool {
        profileSwitchCount > 0
            || !perProfileCounts.isEmpty
            || lastSwitchSlug != nil
            || manualOverrideCount > 0
            || activeDaysCount > 0
            || !uniqueDeviceFingerprints.isEmpty
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Default-on toggles use `object(forKey:) == nil` to distinguish
        // "never set" (use default) from "set to false" (respect
        // user's choice). `bool(forKey:)` returns false for missing
        // keys, which would silently flip our defaults.
        self.notificationsEnabled = (defaults.object(forKey: Key.notificationsEnabled) as? Bool) ?? true
        self.debounceInterval = (defaults.object(forKey: Key.debounceInterval) as? Double) ?? 1.5
        self.showProfileNameInMenuBar = (defaults.object(forKey: Key.showProfileNameInMenuBar) as? Bool) ?? true
        self.showProfileIconInMenuBar = (defaults.object(forKey: Key.showProfileIconInMenuBar) as? Bool) ?? false
        self.menuBarIconSymbol = (defaults.object(forKey: Key.menuBarIconSymbol) as? String) ?? MenuBarIcon.defaultSymbol
        self.profileSwitchCount = (defaults.object(forKey: Key.profileSwitchCount) as? Int) ?? 0
        self.suppressedWelcome = (defaults.object(forKey: Key.suppressedWelcome) as? Bool) ?? false
        self.launchAtLogin = (defaults.object(forKey: Key.launchAtLogin) as? Bool) ?? false
        self.virtualCameraEnabled = (defaults.object(forKey: Key.virtualCameraEnabled) as? Bool) ?? false
        self.experimentalUpdates = (defaults.object(forKey: Key.experimentalUpdates) as? Bool) ?? false
        // Stats tracking ships off by default for privacy. Every
        // record / increment method early-returns when this is false.
        self.statsTrackingEnabled = (defaults.object(forKey: Key.statsTrackingEnabled) as? Bool) ?? false
        self.statsStartDate = defaults.object(forKey: Key.statsStartDate) as? Date
        self.perProfileCounts = (defaults.object(forKey: Key.perProfileCounts) as? [String: Int]) ?? [:]
        self.lastSwitchSlug = defaults.object(forKey: Key.lastSwitchSlug) as? String
        self.lastSwitchDate = defaults.object(forKey: Key.lastSwitchDate) as? Date
        self.manualOverrideCount = (defaults.object(forKey: Key.manualOverrideCount) as? Int) ?? 0
        self.currentStreakDays = (defaults.object(forKey: Key.currentStreakDays) as? Int) ?? 0
        self.longestStreakDays = (defaults.object(forKey: Key.longestStreakDays) as? Int) ?? 0
        self.activeDaysCount = (defaults.object(forKey: Key.activeDaysCount) as? Int) ?? 0
        self.uniqueDeviceFingerprints = (defaults.object(forKey: Key.uniqueDeviceFingerprints) as? [String]) ?? []
    }

    /// Bump the lifetime switch counter that drives the easter-egg
    /// menu line. Gated by `statsTrackingEnabled` — when off, the
    /// counter freezes at its current value (typically 0 on a fresh
    /// install).
    func incrementSwitchCount() {
        guard statsTrackingEnabled else { return }
        profileSwitchCount += 1
    }

    /// Bump the count of menu-driven manual overrides. Gated.
    func incrementManualOverrideCount() {
        guard statsTrackingEnabled else { return }
        manualOverrideCount += 1
    }

    /// Record one applied profile. Updates per-profile counts,
    /// last-switched fields, and the daily streak / activeDays math.
    /// Gated by `statsTrackingEnabled`.
    ///
    /// Streak rule, evaluated against `lastSwitchDate`'s calendar day
    /// (in the user's local timezone):
    ///
    /// - same day → no streak/activeDays change (just refresh
    ///   `lastSwitchDate` so the relative-time UI stays current)
    /// - exactly one day later → `currentStreakDays += 1`,
    ///   `activeDaysCount += 1`
    /// - older or never → `currentStreakDays = 1`,
    ///   `activeDaysCount += 1`
    ///
    /// `longestStreakDays` is `max(longestStreakDays, currentStreakDays)`
    /// after each update.
    func recordSwitch(toSlug slug: String, at date: Date = Date()) {
        guard statsTrackingEnabled else { return }
        perProfileCounts[slug, default: 0] += 1
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)
        if let last = lastSwitchDate {
            let lastDay = calendar.startOfDay(for: last)
            let delta = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0
            if delta == 0 {
                // Same calendar day — no streak change.
            } else if delta == 1 {
                currentStreakDays += 1
                activeDaysCount += 1
            } else {
                currentStreakDays = 1
                activeDaysCount += 1
            }
        } else {
            currentStreakDays = 1
            activeDaysCount = 1
        }
        if currentStreakDays > longestStreakDays {
            longestStreakDays = currentStreakDays
        }
        lastSwitchSlug = slug
        lastSwitchDate = date
    }

    /// Insert any never-seen `(vendorID, productID)` fingerprints into
    /// the unique-devices set. Gated. Writes back to UserDefaults
    /// only when the set actually grew, so a typical USB-quiet stretch
    /// doesn't touch defaults at all.
    func recordDevicesSeen(_ devices: Set<USBDevice>) {
        guard statsTrackingEnabled else { return }
        let existing = Set(uniqueDeviceFingerprints)
        var grown = existing
        for device in devices {
            grown.insert(Self.fingerprint(for: device))
        }
        if grown.count != existing.count {
            uniqueDeviceFingerprints = grown.sorted()
        }
    }

    /// Wipe every stats counter / dictionary / last-switched field.
    /// Does NOT touch `statsTrackingEnabled` — that's a separate
    /// privacy choice. If tracking is currently on, `statsStartDate`
    /// is reset to "now" so future records have a fresh origin; if
    /// tracking is off, it's set to nil (it'll re-stamp on next
    /// opt-in). Wired to the Advanced tab's "Reset stats…" button.
    func resetStats() {
        profileSwitchCount = 0
        perProfileCounts = [:]
        lastSwitchSlug = nil
        lastSwitchDate = nil
        manualOverrideCount = 0
        currentStreakDays = 0
        longestStreakDays = 0
        activeDaysCount = 0
        uniqueDeviceFingerprints = []
        statsStartDate = statsTrackingEnabled ? Date() : nil
    }

    /// Stable string fingerprint for a USB device — `"<vid>:<pid>"`
    /// in lowercase 4-char hex. Used as the entry value in
    /// `uniqueDeviceFingerprints`.
    static func fingerprint(for device: USBDevice) -> String {
        String(format: "%04x:%04x", device.vendorID, device.productID)
    }
}
