import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Surface a transient banner-style notification to the user.
/// Production picks between `UserNotificationsNotifier` (signed .app
/// bundle — preferred, posts under our app's identity + icon) and
/// `AppleScriptNotifier` (unbundled `swift run` dev binary — no
/// bundle id, so UNUserNotificationCenter rejects it). Tests inject
/// a recording mock.
public protocol Notifier {
    func notify(title: String, body: String?)
}

#if canImport(UserNotifications)
/// Production notifier inside a signed `.app` bundle. Uses
/// `UNUserNotificationCenter` so notifications post under the app's
/// own identity — they show our `Resources/AppIcon.icns` instead of
/// Script Editor's plug, and clicking dismisses cleanly without
/// dragging the user into a file picker the way `osascript`-posted
/// notifications do.
///
/// Authorization is requested at init (best-effort; if the user
/// denies, our `notify` calls become silent no-ops). The
/// `Settings → Send notifications` toggle still gates whether we
/// even *try* to post — denying both layers is intentional.
public final class UserNotificationsNotifier: Notifier {
    public init() {
        // Request alert + sound. We don't ask for badge — the app is
        // a menu-bar agent and has no Dock tile to badge.
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in
                // Outcome is best-effort; failures and denials are
                // surfaced through the toggle being a no-op rather
                // than logged. The system's own Notification Center
                // settings UI is the place to fix this.
            }
    }

    public func notify(title: String, body: String?) {
        let content = UNMutableNotificationContent()
        content.title = title
        if let body { content.body = body }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil  // fire immediately
        )
        UNUserNotificationCenter.current().add(request) { _ in
            // Best-effort — same rationale as init. A delivery error
            // (e.g. the user revoked permission since launch) shouldn't
            // surface to the engine.
        }
    }
}
#endif

/// Production notifier that shells out to `osascript` to display a
/// notification. Works without a bundle identifier — `osascript`
/// posts as itself, which the user has already approved (or will be
/// prompted to approve once) for notifications.
///
/// We'll replace this with `UNUserNotificationCenter` when the menu-
/// bar app ships as a signed `.app` with a `CFBundleIdentifier`.
/// Until then, this gets us "Switched to X" toasts during dev
/// without the bundle/auth dance.
public struct AppleScriptNotifier: Notifier {
    public init() {}

    public func notify(title: String, body: String?) {
        // AppleScript `display notification` requires a non-empty
        // body string; the title is the second clause. If callers
        // pass body=nil we surface just the title in the body slot.
        let bodyText = body ?? title
        let titleClause = " with title \"\(escape(title))\""
        let script = "display notification \"\(escape(bodyText))\"\(titleClause)"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        // Discard stdout/stderr — notifications are best-effort, we
        // don't want the engine to log a noisy warning when osascript
        // fails (sometimes it does on boot when WindowServer isn't
        // ready yet).
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            // Swallow — see comment above.
        }
    }

    private func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
