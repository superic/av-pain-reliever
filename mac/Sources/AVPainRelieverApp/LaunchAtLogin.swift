import Foundation
import ServiceManagement
import OSLog

/// Wraps `SMAppService.mainApp` so SettingsStore can flip the
/// "launch at login" preference without taking a hard dependency on
/// SMAppService throughout the codebase.
///
/// Caveats during dev (`swift run`-built binary):
///   - SMAppService.mainApp registers the *current bundle*. An SPM-
///     built binary doesn't have a proper Info.plist with
///     LSBackgroundOnly, so the registration usually fails or
///     misregisters the launcher. This helper logs the failure but
///     never throws — the user sees the toggle flip back to off in
///     the next launch (since the registration didn't stick).
///   - The signed `.app` bundle (when distribution lands) will
///     register cleanly. The same code path here will start
///     working with no app-side changes.
///
/// macOS 13+ deprecates the older SMLoginItemSetEnabled API; using
/// SMAppService keeps us on the supported surface.
enum LaunchAtLogin {
    private static let logger = Logger(
        subsystem: "com.ericwillis.avpainreliever",
        category: "launch-at-login"
    )

    /// Bring the system login-item registration in line with the
    /// requested boolean. Idempotent — registering an already-
    /// registered service or unregistering an already-stopped one is
    /// a no-op (besides a small log line).
    static func apply(enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
                logger.info("registered as login item")
            } else {
                try service.unregister()
                logger.info("unregistered as login item")
            }
        } catch {
            // SMAppService throws for unsupported bundles, denied
            // approval, etc. Log and move on — the toggle in
            // Settings will remain in its requested state from the
            // user's perspective until they next inspect/restart.
            logger.warning("login-item update failed (enabled=\(enabled)): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Best-effort read of whether the system currently considers us
    /// a login item. Useful for surfacing the truth in Settings if a
    /// register call silently failed (e.g. unsigned dev binary).
    /// Returns nil when SMAppService can't tell.
    static func isRegistered() -> Bool? {
        let status = SMAppService.mainApp.status
        switch status {
        case .enabled: return true
        case .notRegistered, .notFound, .requiresApproval: return false
        @unknown default: return nil
        }
    }
}
