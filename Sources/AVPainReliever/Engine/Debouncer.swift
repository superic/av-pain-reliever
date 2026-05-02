import Foundation

/// Time source for the `Debouncer`. Production uses `DispatchClock`
/// (real `DispatchQueue.asyncAfter`); tests inject a manual clock so
/// they can advance time without sleeping.
///
/// `schedule(after:_:)` returns a cancellation closure — call it to
/// cancel the pending block before it fires. Calling it after the block
/// has fired is a no-op.
public protocol DebouncerClock {
    func schedule(after delay: TimeInterval, _ block: @escaping () -> Void) -> () -> Void
}

/// Real-clock `DebouncerClock` implementation backed by
/// `DispatchQueue.asyncAfter`. Defaults to the main queue, matching the
/// engine's "everything is main-thread" execution model.
public struct DispatchClock: DebouncerClock {
    public let queue: DispatchQueue

    public init(queue: DispatchQueue = .main) {
        self.queue = queue
    }

    public func schedule(after delay: TimeInterval, _ block: @escaping () -> Void) -> () -> Void {
        let item = DispatchWorkItem(block: block)
        queue.asyncAfter(deadline: .now() + delay, execute: item)
        return { item.cancel() }
    }
}

/// Coalesces bursts of events into a single trailing-edge action. Each
/// `bump()` cancels any pending fire and re-arms the timer; the action
/// runs once `interval` seconds elapse with no further bumps.
///
/// Mirrors `init.lua`'s `scheduleEvaluate` /
/// `pendingTimer = hs.timer.doAfter(DEBOUNCE_SECONDS, evaluateAndApply)`
/// pattern. A USB dock burst typically delivers ~14 add/remove events
/// over ~1 second; the 1.5 s window collapses them into one
/// `evaluateAndApply` call.
///
/// Not thread-safe — assumes all `bump()` / `cancel()` calls happen on
/// the same queue the clock dispatches on (the main queue, by default).
public final class Debouncer {
    private let interval: TimeInterval
    private let clock: DebouncerClock
    private let action: () -> Void
    private var cancelPending: (() -> Void)?

    public init(
        interval: TimeInterval,
        clock: DebouncerClock = DispatchClock(),
        action: @escaping () -> Void
    ) {
        self.interval = interval
        self.clock = clock
        self.action = action
    }

    /// Restart the timer. Each call cancels the prior pending fire (if
    /// any) and re-schedules; the action runs `interval` seconds after
    /// the *last* `bump()`.
    public func bump() {
        cancelPending?()
        cancelPending = clock.schedule(after: interval) { [weak self] in
            guard let self else { return }
            self.cancelPending = nil
            self.action()
        }
    }

    /// Cancel the pending fire (if any) without invoking the action.
    public func cancel() {
        cancelPending?()
        cancelPending = nil
    }
}
