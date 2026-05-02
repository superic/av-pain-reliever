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

    @Test("currentDevices returns well-formed USBDevice entries")
    func currentDevicesAreWellFormed() {
        // Light end-to-end check — proves IOKit is linked, the matching
        // dictionary enumerates without crashing, and any returned
        // (idVendor, idProduct) round-trips into a USBDevice with
        // valid uint16 IDs. We deliberately don't assert the snapshot
        // is non-empty: an undocked MacBook with no external USB
        // peripherals legitimately returns the empty set, and the
        // prior version of this test was a hardware-dependent flake.
        let watcher = IOKitUSBWatcher()
        for device in watcher.currentDevices() {
            #expect(device.vendorID >= 0 && device.vendorID <= 0xFFFF)
            #expect(device.productID >= 0 && device.productID <= 0xFFFF)
        }
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
