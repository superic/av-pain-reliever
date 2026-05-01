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
            self?.evaluateAndApply()
        }
        self.debouncer = debouncer

        watcher.start { [weak self] in
            self?.debouncer?.bump()
        }

        evaluateAndApply()
    }

    /// Stop observing and cancel any pending evaluate-and-apply.
    /// Idempotent; safe to call from a parent's `deinit`.
    public func stop() {
        guard started else { return }
        started = false
        debouncer?.cancel()
        debouncer = nil
        watcher.stop()
    }

    private func evaluateAndApply() {
        let attached = watcher.currentDevices()
        guard let profile = resolver.resolve(attached: attached) else {
            logger.warn("no profile matched the current USB state — skipping apply")
            return
        }
        logger.info("evaluation → \(profile.name)")
        applier.apply(profile)
    }
}
