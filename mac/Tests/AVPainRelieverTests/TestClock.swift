import Foundation
@testable import AVPainReliever

/// In-memory `DebouncerClock` for tests — schedule blocks against a
/// virtual `now` and fire them by calling `advance(by:)`. No real time
/// elapses, no `Thread.sleep`, no flaky tests.
final class TestClock: DebouncerClock {
    private struct Pending {
        let id: Int
        let fireAt: TimeInterval
        let block: () -> Void
        var cancelled: Bool
    }

    private var queue: [Pending] = []
    private var nextID = 0
    private(set) var now: TimeInterval = 0

    func schedule(after delay: TimeInterval, _ block: @escaping () -> Void) -> () -> Void {
        let id = nextID
        nextID += 1
        queue.append(Pending(id: id, fireAt: now + delay, block: block, cancelled: false))
        return { [weak self] in
            guard let self else { return }
            if let i = self.queue.firstIndex(where: { $0.id == id }) {
                self.queue[i].cancelled = true
            }
        }
    }

    /// Advance virtual time by `delta`. Any non-cancelled blocks whose
    /// deadline has passed fire in scheduled order (FIFO).
    func advance(by delta: TimeInterval) {
        now += delta
        // Fire and remove anything ready, repeatedly — a fired block
        // may schedule another that is also ready in the same tick.
        while let i = queue.firstIndex(where: { !$0.cancelled && $0.fireAt <= now }) {
            let item = queue.remove(at: i)
            item.block()
        }
        // Drop cancelled entries we've now passed; keeps the queue small.
        queue.removeAll { $0.cancelled && $0.fireAt <= now }
    }

    /// Pending (non-cancelled) blocks. Tests use this to assert
    /// "nothing is scheduled" or "exactly one fire is pending".
    var pendingCount: Int {
        queue.filter { !$0.cancelled }.count
    }
}
