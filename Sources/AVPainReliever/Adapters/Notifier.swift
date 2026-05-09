import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif
#if canImport(AppKit)
import AppKit
#endif

/// Surface a transient banner-style notification to the user.
/// Production picks between `UserNotificationsNotifier` (signed .app
/// bundle — preferred, posts under our app's identity + icon, can
/// render action buttons) and `AppleScriptNotifier` (unbundled
/// `swift run` dev binary — no bundle id, so UNUserNotificationCenter
/// rejects it; action buttons silently degrade). Tests inject a
/// recording mock.
public protocol Notifier {
    /// Post a notification with an optional thumbnail icon and inline
    /// action button.
    ///
    /// `iconSymbol` is an optional SF Symbol name; when supplied,
    /// backends that support it render the symbol as a thumbnail
    /// attached to the notification (the macOS `.app`-bundle path
    /// does, the `osascript` dev path does not). Backends that can't
    /// surface a thumbnail simply post the title + body unchanged.
    ///
    /// `actionTitle` becomes the button label; `onAction` fires when
    /// the user clicks the button (NOT when they click the body).
    /// Both are best-effort: backends that can't render an action
    /// button drop it and `onAction` never fires.
    func notify(
        title: String,
        body: String?,
        iconSymbol: String?,
        actionTitle: String?,
        onAction: (() -> Void)?
    )
}

extension Notifier {
    /// Convenience for action-less, icon-less notifications. Forwards
    /// to the full method so backends only have to implement one
    /// signature.
    public func notify(title: String, body: String?) {
        notify(title: title, body: body, iconSymbol: nil, actionTitle: nil, onAction: nil)
    }

    /// Convenience for a notification with just an icon thumbnail.
    public func notify(title: String, body: String?, iconSymbol: String?) {
        notify(title: title, body: body, iconSymbol: iconSymbol, actionTitle: nil, onAction: nil)
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
        iconSymbol: String?,
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

        // When the caller supplied an SF Symbol name, render it to a
        // temp PNG and attach it. macOS shows the attachment as a
        // thumbnail next to the title — gives the toast a per-profile
        // visual signal alongside the standard app icon. UN moves the
        // file into its own storage on `add(...)`, so we don't have
        // to clean up the temp path ourselves.
        if let iconSymbol, let url = Self.renderIconAttachment(symbol: iconSymbol) {
            if let attachment = try? UNNotificationAttachment(
                identifier: "icon",
                url: url,
                options: nil
            ) {
                content.attachments = [attachment]
            }
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

    /// Render an SF Symbol on a charcoal circular background to a
    /// temp PNG file and return its URL. Sized 256×256 — macOS
    /// downscales for the actual notification thumbnail. Returns nil
    /// on the unhappy path (symbol not found, encode/write failure);
    /// callers fall back to a plain notification.
    private static func renderIconAttachment(symbol: String) -> URL? {
        #if canImport(AppKit)
        let size = NSSize(width: 256, height: 256)
        let image = NSImage(size: size)
        image.lockFocus()

        // Charcoal disc — same hue family as the new app icon's
        // background gradient stop, so the thumbnail reads as part of
        // the same visual system.
        NSColor(red: 0.180, green: 0.188, blue: 0.204, alpha: 1.0).set()
        NSBezierPath(ovalIn: NSRect(origin: .zero, size: size)).fill()

        // White SF Symbol centred at ~50% of canvas.
        let config = NSImage.SymbolConfiguration(pointSize: 130, weight: .semibold)
        if let template = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(config) {
            // SF Symbols come as template (alpha-mask) images. Tint by
            // filling a fresh image with white, then `destinationIn`
            // through the symbol mask to get a proper white symbol.
            let tinted = NSImage(size: template.size)
            tinted.lockFocus()
            NSColor.white.set()
            NSRect(origin: .zero, size: template.size).fill()
            template.draw(
                in: NSRect(origin: .zero, size: template.size),
                from: .zero,
                operation: .destinationIn,
                fraction: 1.0
            )
            tinted.unlockFocus()

            let origin = NSPoint(
                x: (size.width - tinted.size.width) / 2,
                y: (size.height - tinted.size.height) / 2
            )
            tinted.draw(
                at: origin,
                from: .zero,
                operation: .sourceOver,
                fraction: 1.0
            )
        }

        image.unlockFocus()

        guard
            let tiff = image.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff),
            let png = rep.representation(using: .png, properties: [:])
        else {
            return nil
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("av-notify-icon-\(UUID().uuidString).png")
        do {
            try png.write(to: url)
            return url
        } catch {
            return nil
        }
        #else
        return nil
        #endif
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

/// `swift run` dev fallback notifier that shells out to `osascript`
/// to display a notification. Works without a bundle identifier —
/// `osascript` posts as itself, which the user has already approved
/// (or will be prompted to approve once) for notifications.
///
/// `UNUserNotificationCenter` (the production path in
/// `UserNotificationsNotifier` above) requires a bundle id, so it
/// rejects unbundled processes outright. AppDelegate picks this
/// implementation when `Bundle.main.bundleIdentifier` is nil — i.e.
/// the `swift run AVPainRelieverApp` dev-loop case. The signed
/// `.app` always uses `UserNotificationsNotifier`. Action buttons,
/// custom icons, and `onAction` callbacks aren't supported here —
/// `osascript` only renders title + body.
public struct AppleScriptNotifier: Notifier {
    public init() {}

    public func notify(
        title: String,
        body: String?,
        iconSymbol: String?,
        actionTitle: String?,
        onAction: (() -> Void)?
    ) {
        // osascript notifications can't render an action button or a
        // custom thumbnail — ignore `iconSymbol`, `actionTitle`, and
        // `onAction` and post a plain toast. Dev users see the
        // message; the equivalent action is also reachable from the
        // menu's "Set Up This Location…" button when in
        // unknown-location state.
        _ = (iconSymbol, actionTitle, onAction)
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
