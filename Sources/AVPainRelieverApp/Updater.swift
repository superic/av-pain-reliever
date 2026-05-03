import Foundation
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

    init() {
        // `startingUpdater: true` kicks off the scheduled-check loop
        // immediately. Delegates are nil — Sparkle's defaults are
        // fine for a single-channel public release: it'll fetch the
        // appcast, prompt the user on first launch, and run
        // background checks per the Info.plist's SUScheduledCheckInterval
        // (omitted = 24h default).
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.controller = controller
        let feedDescription = controller.updater.feedURL?.absoluteString ?? "nil"
        Self.logger.info("Sparkle updater started; feed=\(feedDescription, privacy: .public)")
    }

    /// User-initiated update check (menu item action). Sparkle shows
    /// its own progress + "you're up to date" UI — nothing for us
    /// to render.
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
