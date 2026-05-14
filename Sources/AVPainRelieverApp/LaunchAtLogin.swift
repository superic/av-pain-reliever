import Foundation
import ServiceManagement
import OSLog

/// Closure signature for "apply the login-item state for `enabled`."
/// `SettingsStore` takes one of these so tests can inject a no-op
/// instead of letting `SMAppService.mainApp.register()` run from
/// inside `swiftpm-testing-helper` (which would register the test
/// runner as a login item — see `LaunchAtLogin.swift`'s `apply` doc
/// for the gory details).
typealias LoginItemApplier = (Bool) -> Void

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
///   - **Under `swift test`,** `SMAppService.mainApp` resolves to
///     the SPM test runner (`swiftpm-testing-helper`), so calling
///     `apply` from a test registers that binary as a system login
///     item. `SettingsStore` injects this via `LoginItemApplier` so
///     tests can pass a no-op closure; production always uses the
///     real `apply` below.
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
                logger.notice("registered as login item")
            } else {
                try service.unregister()
                logger.notice("unregistered as login item")
            }
        } catch {
            // SMAppService throws for unsupported bundles, denied
            // approval, etc. Log and move on — the toggle in
            // Settings will remain in its requested state from the
            // user's perspective until they next inspect/restart.
            logger.warning("login-item update failed (enabled=\(enabled)): \(error.localizedDescription, privacy: .public)")
        }
    }
}
