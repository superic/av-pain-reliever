import Testing
import Foundation
@testable import AVPainReliever

@Suite("Debouncer")
struct DebouncerTests {
    /// Lightweight thread-safe counter for tests. Tests run on a single
    /// thread (TestClock fires synchronously inside `advance`), so a
    /// simple class with mutable state is sufficient.
    final class FireCounter {
        private(set) var count = 0
        func bump() { count += 1 }
    }

    @Test("does not fire before the interval elapses")
    func quietBeforeDeadline() {
        let clock = TestClock()
        let counter = FireCounter()
        let debouncer = Debouncer(interval: 1.5, clock: clock, action: counter.bump)

        debouncer.bump()
        clock.advance(by: 1.4)
        #expect(counter.count == 0)
    }

    @Test("fires exactly once after a single bump")
    func firesAfterDeadline() {
        let clock = TestClock()
        let counter = FireCounter()
        let debouncer = Debouncer(interval: 1.5, clock: clock, action: counter.bump)

        debouncer.bump()
        clock.advance(by: 1.5)
        #expect(counter.count == 1)
    }

    @Test("multiple bumps within the interval coalesce into one fire")
    func bumpsWithinIntervalCoalesce() {
        let clock = TestClock()
        let counter = FireCounter()
        let debouncer = Debouncer(interval: 1.5, clock: clock, action: counter.bump)

        // 14 USB add/remove events arriving at ~70ms intervals — same
        // shape as a real CalDigit dock burst.
        for _ in 0..<14 {
            debouncer.bump()
            clock.advance(by: 0.07)
        }
        // Total elapsed inside the loop: ~0.98s. Still inside the 1.5s
        // window since the last bump.
        #expect(counter.count == 0)

        // Push past the last bump's deadline.
        clock.advance(by: 1.5)
        #expect(counter.count == 1)
    }

    @Test("a bump after a fire schedules a new fire")
    func consecutiveFiresAfterReBump() {
        let clock = TestClock()
        let counter = FireCounter()
        let debouncer = Debouncer(interval: 1.5, clock: clock, action: counter.bump)

        debouncer.bump()
        clock.advance(by: 1.5)
        #expect(counter.count == 1)

        debouncer.bump()
        clock.advance(by: 1.5)
        #expect(counter.count == 2)
    }

    @Test("cancel suppresses a pending fire")
    func cancelPrevents() {
        let clock = TestClock()
        let counter = FireCounter()
        let debouncer = Debouncer(interval: 1.5, clock: clock, action: counter.bump)

        debouncer.bump()
        clock.advance(by: 1.0)
        debouncer.cancel()
        clock.advance(by: 10.0)
        #expect(counter.count == 0)
    }

    @Test("cancel after fire is a no-op")
    func cancelAfterFireIsHarmless() {
        let clock = TestClock()
        let counter = FireCounter()
        let debouncer = Debouncer(interval: 1.5, clock: clock, action: counter.bump)

        debouncer.bump()
        clock.advance(by: 1.5)
        #expect(counter.count == 1)

        debouncer.cancel() // must not throw, must not change state
        #expect(counter.count == 1)
    }

    @Test("each bump cancels exactly one prior pending block")
    func bumpReleasesPriorPending() {
        let clock = TestClock()
        let debouncer = Debouncer(interval: 1.5, clock: clock, action: {})

        debouncer.bump()
        #expect(clock.pendingCount == 1)
        debouncer.bump()
        // Old pending was cancelled, new one scheduled — still one
        // *active* pending.
        #expect(clock.pendingCount == 1)
        debouncer.bump()
        #expect(clock.pendingCount == 1)
    }
}
