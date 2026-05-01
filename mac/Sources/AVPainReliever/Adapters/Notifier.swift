import Foundation

/// Surface a transient banner-style notification to the user.
/// Production wires this to `AppleScriptNotifier` for the unbundled
/// SPM dev binary (UserNotifications requires a real bundle id, which
/// `swift run` doesn't provide); we'll switch to
/// `UNUserNotificationCenter` once the .app bundle ships. Tests inject
/// a recording mock.
public protocol Notifier {
    func notify(title: String, body: String?)
}

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
