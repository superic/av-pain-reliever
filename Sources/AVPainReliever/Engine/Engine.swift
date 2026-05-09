import Foundation

/// Top-level coordinator that wires the engine together.
///
/// Pipeline:
///
/// ```
/// USBWatcher.onChange ──▶ Debouncer.bump
///                                    │ (1.5 s of quiet)
///                                    ▼
///                       evaluate-and-apply
///                                    │
///                                    ├─▶ resolver.resolve(attached:)
///                                    └─▶ applier.apply(_)
/// ```
///
/// On `start()`, the engine immediately runs an evaluate-and-apply pass
/// so reloads/relaunches re-sync the system without waiting for the
/// next dock event (matches `init.lua`'s
/// `applyProfile(resolveProfile())` at module load).
///
/// The "fallback profile" model is implicit: include a profile with an
/// empty fingerprint (specificity 0) in the resolver's list, and it
/// will match whenever nothing more specific does. If the resolver
/// returns nil — i.e., the profile list is empty or no profile has an
/// empty fingerprint — the engine logs a warning and skips the apply.
public final class Engine {
    private let watcher: USBWatcher
    private let resolver: ProfileResolver
    private let applier: ProfileApplier
    private let logger: ApplierLogger
    private let debounceInterval: TimeInterval
    private let clock: DebouncerClock

    private var debouncer: Debouncer?
    private var started = false

    /// Fires after every successful evaluate-and-apply pass with the
    /// resolved profile, *including* passes the applier no-op'd
    /// because the profile was unchanged. The status-bar UI uses this
    /// to keep its title in sync — even no-op evaluations carry useful
    /// signal (the user just plugged in a Yeti, evaluation still ran,
    /// the profile didn't change). Always fires on the same thread the
    /// debouncer/initial start were invoked on (main thread in
    /// production).
    public var onProfileApplied: ((Profile) -> Void)?

    /// Fires when the resolver picks the empty-fingerprint fallback
    /// profile (specificity 0, matches anything) but the user has USB
    /// devices attached. That state means the user is plugged into
    /// SOME hardware we don't have a profile for — a "new location"
    /// the menu-bar app should prompt the user to set up. The closure
    /// receives the current set of attached devices so the UI can
    /// describe what was seen.
    ///
    /// Does not fire when undocked (empty attached set + fallback
    /// resolution is the normal "I'm at the laptop" state, not new).
    /// Does not fire when a specific-fingerprint profile matches
    /// (that's a known location, not a new one).
    public var onUnknownLocation: ((Set<USBDevice>) -> Void)?

    /// Fires on every successful evaluate-and-apply pass with the full
    /// set of currently-attached USB devices, regardless of which
    /// profile resolved or whether it changed. Used by the host's
    /// stats tracking to maintain a "unique devices ever seen" set
    /// without spinning up a second `USBWatcher` instance.
    public var onDevicesEvaluated: ((Set<USBDevice>) -> Void)?

    public init(
        watcher: USBWatcher,
        resolver: ProfileResolver,
        applier: ProfileApplier,
        logger: ApplierLogger,
        debounceInterval: TimeInterval = 1.5,
        clock: DebouncerClock = DispatchClock()
    ) {
        self.watcher = watcher
        self.resolver = resolver
        self.applier = applier
        self.logger = logger
        self.debounceInterval = debounceInterval
        self.clock = clock
    }

    /// Wire the watcher into the debouncer, begin observing, and run
    /// an initial evaluate-and-apply against the current attached set.
    /// Idempotent — subsequent calls are no-ops until `stop()` runs.
    public func start() {
        guard !started else { return }
        started = true

        let debouncer = Debouncer(interval: debounceInterval, clock: clock) { [weak self] in
            self?.logger.debug("engine: debounce window elapsed, firing evaluation")
            self?.evaluateAndApply()
        }
        self.debouncer = debouncer

        watcher.start { [weak self] in
            self?.logger.debug("engine: USB change observed, bumping debouncer")
            self?.debouncer?.bump()
        }

        logger.debug("engine: started (debounce=\(debounceInterval)s)")
        evaluateAndApply()
    }

    /// Stop observing and cancel any pending evaluate-and-apply.
    /// Idempotent; safe to call from a parent's `deinit`.
    public func stop() {
        guard started else { return }
        logger.debug("engine: stopping")
        started = false
        debouncer?.cancel()
        debouncer = nil
        watcher.stop()
    }

    /// Force an immediate evaluate-and-apply pass, bypassing the
    /// debounce window. Cancels any pending debounced evaluation
    /// first so we don't fire twice in quick succession. Useful for
    /// menu-bar "Re-evaluate Now" actions and for tests that want a
    /// deterministic trigger without driving the debouncer.
    /// No-op when the engine isn't started.
    public func evaluate() {
        guard started else { return }
        debouncer?.cancel()
        evaluateAndApply()
    }

    /// Force a re-apply of the current profile, even if the profile
    /// name hasn't changed. Bypasses the applier's "skip if same
    /// name" dedupe by clearing its last-applied state first. Used
    /// when a config change (virtual camera toggle flip, settings
    /// edit) means the same profile name now produces different
    /// system-state writes — the engine has to re-run the side
    /// effects with the new context.
    public func reapply() {
        guard started else { return }
        debouncer?.cancel()
        applier.invalidateLastApplied()
        evaluateAndApply()
    }

    /// Apply a specific profile, bypassing the resolver entirely.
    /// Used by the menu bar's "Switch to" UI when the user wants to
    /// force a profile that doesn't match the current USB state — for
    /// example, applying the home-office profile while undocked to
    /// pre-set audio defaults before plugging in. The next genuine
    /// USB event re-runs the resolver normally; this override is
    /// one-shot, not sticky.
    public func applyManually(_ profile: Profile) {
        guard started else { return }
        debouncer?.cancel()
        logger.info("manual override → \(profile.name)")
        applier.apply(profile)
        onProfileApplied?(profile)
    }

    private func evaluateAndApply() {
        let attached = watcher.currentDevices()
        logger.debug("engine: evaluateAndApply attached=\(attached.count) devices")
        onDevicesEvaluated?(attached)
        guard let profile = resolver.resolve(attached: attached, logger: logger) else {
            logger.warn("no profile matched the current USB state — skipping apply")
            return
        }
        logger.info("evaluation → \(profile.name)")
        applier.apply(profile)
        onProfileApplied?(profile)

        // Empty-fingerprint resolution + non-empty attached set =
        // "user is at a dock we don't have a profile for". See
        // `onUnknownLocation` doc comment.
        if profile.fingerprint.isEmpty && !attached.isEmpty {
            logger.debug("engine: unknown-location signal (fallback profile + \(attached.count) attached)")
            onUnknownLocation?(attached)
        }
    }
}
