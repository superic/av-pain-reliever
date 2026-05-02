import Foundation
import Combine

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
        static let showAudioCameraInMenu = "showAudioCameraInMenu"
        static let profileSwitchCount = "profileSwitchCount"
        static let suppressedWelcome = "suppressedWelcome"
        static let launchAtLogin = "launchAtLogin"
    }

    /// Toast on profile change?  Default on — the at-a-glance signal
    /// is the whole point. Users running back-to-back location changes
    /// or doing demos sometimes want to mute it.
    @Published var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Key.notificationsEnabled) }
    }

    /// USB debounce window in seconds. 1.5s is the validated default
    /// (see SWIFT_PORT.md → Validated decisions). Slider exposes a
    /// 0.5–5.0 range; persisted as Double for the UI.
    @Published var debounceInterval: Double {
        didSet { defaults.set(debounceInterval, forKey: Key.debounceInterval) }
    }

    /// Show the audio + camera summary line under each profile in the
    /// "Switch to" submenu. Default on; users who want a tighter menu
    /// can hide it.
    @Published var showAudioCameraInMenu: Bool {
        didSet { defaults.set(showAudioCameraInMenu, forKey: Key.showAudioCameraInMenu) }
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

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Default-on toggles use `object(forKey:) == nil` to distinguish
        // "never set" (use default) from "set to false" (respect
        // user's choice). `bool(forKey:)` returns false for missing
        // keys, which would silently flip our defaults.
        self.notificationsEnabled = (defaults.object(forKey: Key.notificationsEnabled) as? Bool) ?? true
        self.debounceInterval = (defaults.object(forKey: Key.debounceInterval) as? Double) ?? 1.5
        self.showAudioCameraInMenu = (defaults.object(forKey: Key.showAudioCameraInMenu) as? Bool) ?? true
        self.profileSwitchCount = (defaults.object(forKey: Key.profileSwitchCount) as? Int) ?? 0
        self.suppressedWelcome = (defaults.object(forKey: Key.suppressedWelcome) as? Bool) ?? false
        self.launchAtLogin = (defaults.object(forKey: Key.launchAtLogin) as? Bool) ?? false
    }

    func incrementSwitchCount() {
        profileSwitchCount += 1
    }
}
