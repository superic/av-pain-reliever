import Foundation
import AppKit
import Sparkle
import OSLog

/// Thin wrapper around `SPUStandardUpdaterController` so the rest of
/// the app doesn't import Sparkle directly. Owned by `AppDelegate` as
/// a long-lived stored property — the controller starts the updater
/// at construction and must outlive any "Check for Updates…" click,
/// so dropping it on the floor would silently break auto-updates.
///
/// Update behaviour is driven entirely by `Info.plist`:
///   - `SUFeedURL` points at the Sparkle appcast on
///     raw.githubusercontent.com.
///   - `SUPublicEDKey` is the EdDSA public key Sparkle uses to verify
///     downloaded zips. Filled in once by the maintainer running
///     Sparkle's `generate_keys` (see docs/RELEASING.md).
///
/// We don't override automatic-check defaults — Sparkle's standard
/// behaviour (prompt the user on first launch, then check daily once
/// they've consented) is what we want.
final class Updater {
    private let controller: SPUStandardUpdaterController
    private let settings: SettingsStore
    private static let logger = Logger(
        subsystem: "com.ericwillis.avpainreliever",
        category: "updater"
    )

    /// Bundle ID we expect to see in a real `.app` build. Hardcoded
    /// rather than read from `Bundle.main` so the gate predicate
    /// stays unit-testable and the answer doesn't depend on which
    /// bundle the test runner is launched from.
    static let expectedBundleIdentifier = "com.ericwillis.avpainreliever"

    /// Build-time placeholder string in `Resources/Info.plist`. The
    /// release pipeline expects the maintainer to swap this for the
    /// real `SUPublicEDKey` printed by Sparkle's `generate_keys`
    /// before tagging a signed release — see docs/RELEASING.md §2.
    static let publicKeyPlaceholder = "__SPARKLE_PUBLIC_KEY__"

    /// True iff Sparkle should be wired up for the running binary.
    /// Returns false in three cases that all manifest as the same
    /// "don't try to auto-update" outcome:
    ///   1. No bundle ID (running via `swift run`, no Info.plist).
    ///   2. Bundle ID isn't ours (some other binary linking this code).
    ///   3. `SUPublicEDKey` is missing or still the build-time
    ///      placeholder (an unfinished release would otherwise pop
    ///      Sparkle's "EdDSA invalid" dialog at the user on launch).
    /// Pure function of its inputs so AppDelegate can call it with
    /// `Bundle.main` values and tests can call it with fixtures.
    static func shouldEnable(
        bundleIdentifier: String?,
        publicKey: String?
    ) -> Bool {
        guard bundleIdentifier == expectedBundleIdentifier else { return false }
        guard let key = publicKey, !key.isEmpty, key != publicKeyPlaceholder else {
            return false
        }
        return true
    }

    /// Sparkle holds a weak reference to its delegates, so we keep a
    /// strong one here so the channel-allowlist callback survives.
    private let channelDelegate: ChannelGatingDelegate

    init(settings: SettingsStore) {
        // `startingUpdater: true` kicks off the scheduled-check loop
        // immediately. The delegate's `allowedChannels(for:)` hook is
        // re-queried on every check, so flipping the experimental-
        // updates toggle takes effect on the next scheduled tick or
        // user-initiated check — no Updater rebuild needed.
        self.settings = settings
        let channelDelegate = ChannelGatingDelegate(settings: settings)
        self.channelDelegate = channelDelegate
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: channelDelegate,
            userDriverDelegate: nil
        )
        self.controller = controller
        let feedDescription = controller.updater.feedURL?.absoluteString ?? "nil"
        Self.logger.info("Sparkle updater started; feed=\(feedDescription, privacy: .public)")
        installWindowTitleObserver()
    }

    /// Sparkle's update alert XIB doesn't set a window title, so its
    /// windows render with a blank title bar. We can't override the
    /// XIB without forking Sparkle, but we can name the window at
    /// runtime: when any window keys, check whether its window
    /// controller (or the window itself) is one of Sparkle's
    /// `SU…` / `SPU…` classes and, if so, give it a title.
    /// Heuristic but cheap; a Sparkle internal class rename would
    /// silently drop the title back to blank — acceptable downside.
    private func installWindowTitleObserver() {
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let window = notification.object as? NSWindow else { return }
            guard window.title.isEmpty else { return }
            let controllerClass = window.windowController.map { NSStringFromClass(type(of: $0)) } ?? ""
            let windowClass = NSStringFromClass(type(of: window))
            let looksLikeSparkle =
                controllerClass.hasPrefix("SU") || controllerClass.hasPrefix("SPU") ||
                windowClass.hasPrefix("SU") || windowClass.hasPrefix("SPU")
            if looksLikeSparkle {
                window.title = "Software Update"
            }
        }
    }

    /// User-initiated update check (menu item action). Activate first
    /// so AV Pain Reliever is the frontmost app when Sparkle's window
    /// appears after the feed fetch — without this, an LSUIElement
    /// build's update window can land behind whatever app you've
    /// switched to while the network call was in flight.
    ///
    /// One pre-check intercept: when the user is running an
    /// experimental version (v0.2.x+) AND the experimental-updates
    /// toggle is off, Sparkle would silently filter the appcast to
    /// stable-only and tell the user "you're up to date" while they
    /// run a version newer than the latest stable. That's
    /// technically true (relative to the channels they consume) but
    /// reads as a bug to the user. Show a tailored alert that
    /// explains the situation and offers a one-click path to enable
    /// the experimental channel.
    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        if let version = Self.runningVersion(),
           Self.isExperimentalVersion(version),
           !settings.experimentalUpdates
        {
            showExperimentalNudge(currentVersion: version)
            return
        }
        controller.checkForUpdates(nil)
    }

    /// Bundle's marketing version, e.g. "0.2.0". Falls back to
    /// `CFBundleVersion` if the marketing key is missing — should
    /// never happen in a real release build but keeps the predicate
    /// total in any case.
    private static func runningVersion() -> String? {
        let info = Bundle.main.infoDictionary
        if let s = info?["CFBundleShortVersionString"] as? String, !s.isEmpty {
            return s
        }
        return info?["CFBundleVersion"] as? String
    }

    /// True for versions that ship through the experimental Sparkle
    /// channel. Mirrors the workflow's tag-prefix dispatch: anything
    /// at v0.2.x or higher (including v1.x) is experimental;
    /// v0.0.x and v0.1.x are stable. Prefix-matches the leading
    /// `MAJOR.MINOR` so suffixes like "-iter-m3" or build metadata
    /// don't break the parse.
    static func isExperimentalVersion(_ version: String) -> Bool {
        let parts = version.split(separator: ".")
        guard parts.count >= 2,
              let major = Int(parts[0]),
              // The minor segment may carry suffixes (e.g. "1-rc"),
              // so split it on a non-digit prefix.
              let minor = Int(parts[1].prefix(while: { $0.isNumber }))
        else { return false }
        if major == 0 { return minor >= 2 }
        return major >= 1
    }

    private func showExperimentalNudge(currentVersion: String) {
        let alert = NSAlert()
        alert.messageText = "You're running an experimental version"
        alert.informativeText = """
            AV Pain Reliever \(currentVersion) is from the experimental release channel. To receive future experimental patches automatically, enable Experimental Updates in Settings → General → Updates.

            Otherwise, only stable releases appear when you check for updates — and the latest stable is currently older than what you're running.
            """
        alert.alertStyle = .informational
        alert.icon = NSApp.applicationIconImage
        alert.addButton(withTitle: "Enable Experimental Updates")
        alert.addButton(withTitle: "Check Stable Anyway")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            // Flipping the toggle in-process re-queries the
            // ChannelGatingDelegate on the next check, so we can
            // immediately fire a real Sparkle check that now
            // considers experimental items.
            settings.experimentalUpdates = true
            controller.checkForUpdates(nil)
        case .alertSecondButtonReturn:
            controller.checkForUpdates(nil)
        default:
            break
        }
    }
}

/// Sparkle delegate that controls which release channels the user is
/// willing to receive. Default-empty allow-list means Sparkle only
/// considers feed items WITHOUT a `<sparkle:channel>` tag — i.e.
/// stable. When the user opts in via Settings, we return
/// `["experimental"]` and items tagged with that channel become
/// eligible. Multiple channels can be allowed simultaneously; for
/// now there's only one experimental channel.
///
/// Held strongly by `Updater` because Sparkle stores its delegates
/// as weak references — without our retention, the delegate would
/// deallocate immediately after init and Sparkle would silently fall
/// back to its default (no-channel-filtering) behaviour.
private final class ChannelGatingDelegate: NSObject, SPUUpdaterDelegate {
    private let settings: SettingsStore

    init(settings: SettingsStore) {
        self.settings = settings
        super.init()
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        settings.experimentalUpdates ? ["experimental"] : []
    }
}
