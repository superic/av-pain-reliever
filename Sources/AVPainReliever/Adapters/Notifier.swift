import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Surface a transient banner-style notification to the user.
/// Production picks between `UserNotificationsNotifier` (signed .app
/// bundle — preferred, posts under our app's identity + icon, can
/// render action buttons) and `AppleScriptNotifier` (unbundled
/// `swift run` dev binary — no bundle id, so UNUserNotificationCenter
/// rejects it; action buttons silently degrade). Tests inject a
/// recording mock.
public protocol Notifier {
    /// Post a notification with an optional inline action button.
    /// `actionTitle` becomes the button label; `onAction` fires when
    /// the user clicks the button (NOT when they click the body).
    /// Both are best-effort: backends that can't render an action
    /// button drop it and `onAction` never fires.
    func notify(
        title: String,
        body: String?,
        actionTitle: String?,
        onAction: (() -> Void)?
    )
}

extension Notifier {
    /// Convenience for action-less notifications. Forwards to the
    /// full method so backends only have to implement one signature.
    public func notify(title: String, body: String?) {
        notify(title: title, body: body, actionTitle: nil, onAction: nil)
    }
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
public final class UserNotificationsNotifier: NSObject, Notifier, UNUserNotificationCenterDelegate {
    /// Identifier for the lone category we register at startup. It
    /// carries a single "Open Wizard" action so the unknown-location
    /// toast can offer a one-click jump into Add Profile.
    private static let actionCategoryID = "av-pain-reliever.action"
    private static let actionID = "av-pain-reliever.openWizard"

    /// Open-action handler keyed by request UUID. We hold each
    /// closure until the corresponding notification is dismissed or
    /// acted on; expired entries get pruned via Notification
    /// Center's didReceive callback.
    private var actionHandlers: [String: () -> Void] = [:]
    private let handlersQueue = DispatchQueue(label: "com.ericwillis.avpainreliever.notifier.handlers")

    public override init() {
        super.init()
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        // Request alert + sound. We don't ask for badge — the app is
        // a menu-bar agent and has no Dock tile to badge.
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in
            // Outcome is best-effort; failures and denials are
            // surfaced through the toggle being a no-op rather
            // than logged. The system's own Notification Center
            // settings UI is the place to fix this.
        }
        // Register one category with one action. Per Apple's API,
        // categories must be set up-front; you can't attach
        // arbitrary buttons per-notification. The actionTitle the
        // caller passes is rendered via the per-notification
        // `actions[].title` only when we use the
        // `customDismissAction`-less form, so we keep a fixed action
        // for now. If we add more action types, register more
        // categories here.
        let openAction = UNNotificationAction(
            identifier: Self.actionID,
            title: "Open Wizard",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: Self.actionCategoryID,
            actions: [openAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    public func notify(
        title: String,
        body: String?,
        actionTitle: String?,
        onAction: (() -> Void)?
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        if let body { content.body = body }
        content.sound = .default

        // Attach an action when the caller provided one. The button
        // label rendered to the user is the registered category's
        // action title ("Open Wizard"); `actionTitle` is currently
        // accepted for API symmetry but ignored at the UN layer.
        if onAction != nil {
            content.categoryIdentifier = Self.actionCategoryID
        }

        let identifier = UUID().uuidString
        if let onAction {
            handlersQueue.sync { actionHandlers[identifier] = onAction }
        }

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil  // fire immediately
        )
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if error != nil {
                // Drop the stashed handler so we don't leak it forever.
                self?.handlersQueue.sync { _ = self?.actionHandlers.removeValue(forKey: identifier) }
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
            @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show banner + play sound while the app is foregrounded.
        // Without this delegate method, foreground notifications
        // are silently swallowed by the system.
        completionHandler([.banner, .sound])
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = response.notification.request.identifier
        let handler = handlersQueue.sync { actionHandlers.removeValue(forKey: identifier) }
        if response.actionIdentifier == Self.actionID, let handler {
            // Hop to main since the handler typically opens a SwiftUI
            // window. UN delivers on a private queue.
            DispatchQueue.main.async {
                handler()
            }
        }
        // For default tap (UNNotificationDefaultActionIdentifier) and
        // dismiss (UNNotificationDismissActionIdentifier), do nothing
        // — the OS will activate the app for default-action, which
        // for our LSUIElement agent is a no-op surface.
        completionHandler()
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

    public func notify(
        title: String,
        body: String?,
        actionTitle: String?,
        onAction: (() -> Void)?
    ) {
        // osascript notifications can't render an action button —
        // ignore both `actionTitle` and `onAction` and post a plain
        // toast. Dev users see the message; the equivalent action
        // is also reachable from the menu's "Set Up This Location…"
        // button when in unknown-location state.
        _ = (actionTitle, onAction)
        notifyPlain(title: title, body: body)
    }

    private func notifyPlain(title: String, body: String?) {
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
