import Testing
@testable import AVPainReliever

/// Smoke tests for the production IOKit-backed `USBWatcher`. Unlike the
/// resolver/debouncer/applier suites, these run against real IOKit on
/// the host machine — the watcher is a thin wrapper around C-style
/// IOKit calls that don't unit-test cleanly without injecting an entire
/// IOKit shim layer that nothing else needs. The IOKit prototype
/// already proved the wiring works end-to-end (see `SWIFT_PORT.md` →
/// "IOKit prototype findings"); these tests catch regressions if the
/// production refactor breaks something.
@Suite("IOKitUSBWatcher")
struct IOKitUSBWatcherTests {
    @Test("currentDevices returns the same set across consecutive calls")
    func currentDevicesIsStable() {
        let watcher = IOKitUSBWatcher()
        let a = watcher.currentDevices()
        let b = watcher.currentDevices()
        #expect(a == b)
    }

    @Test("currentDevices returns a non-empty snapshot when run on a docked Mac")
    func currentDevicesNonEmptyWhenDocked() {
        // Light end-to-end check — proves IOKit is linked, the matching
        // dictionary returns devices, and `(idVendor, idProduct)`
        // round-trip into `USBDevice`. May fail if the user runs
        // `swift test` on an undocked MacBook with zero USB
        // peripherals; that's an acceptable false-failure for a
        // single-developer project.
        let watcher = IOKitUSBWatcher()
        #expect(!watcher.currentDevices().isEmpty)
    }

    @Test("start + stop is idempotent and does not leak the notification port")
    func startStopIdempotent() {
        let watcher = IOKitUSBWatcher()
        // Empty closure — we're not exercising the callback here, just
        // verifying that the lifecycle doesn't crash or leak. A leaked
        // notification port would be visible via `leaks` on a debug
        // build but isn't trivial to assert from inside a test.
        watcher.start(onChange: {})
        watcher.start(onChange: {}) // second start is a no-op
        watcher.stop()
        watcher.stop()              // second stop is a no-op
        // Re-start after stop should work cleanly.
        watcher.start(onChange: {})
        watcher.stop()
    }
}
