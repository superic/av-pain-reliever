import Testing
import Foundation
@testable import AVPainRelieverApp

/// Coverage for the dedupe gate that suppresses watcher callbacks
/// echoing an app-originated write. The watcher's own tests prove
/// it fires; these tests prove the wizard's force-apply flow isn't
/// undone by a 250 ms-later echo.
@Suite("ConfigReloadGate")
struct ConfigReloadGateTests {
    @Test("fresh gate reloads on a nil current mtime")
    func freshGateNilMTime() {
        let gate = ConfigReloadGate()
        #expect(gate.shouldReload(currentMTime: nil))
    }

    @Test("fresh gate reloads on any current mtime")
    func freshGateWithMTime() {
        let gate = ConfigReloadGate()
        #expect(gate.shouldReload(currentMTime: Date()))
    }

    @Test("stamped gate suppresses an echo at the stamped mtime")
    func suppressesEcho() {
        var gate = ConfigReloadGate()
        let t = Date()
        gate.stamp(t)
        #expect(!gate.shouldReload(currentMTime: t))
    }

    @Test("stamped gate reloads when the current mtime is strictly newer")
    func reloadsOnNewerMTime() {
        var gate = ConfigReloadGate()
        let t = Date()
        gate.stamp(t)
        #expect(gate.shouldReload(currentMTime: t.addingTimeInterval(1)))
    }

    @Test("stamped gate reloads when the file has vanished")
    func reloadsOnVanishedFile() {
        // File vanished between stamp and watcher callback: reload
        // anyway so loadOrBootstrap can re-seed from defaults.
        var gate = ConfigReloadGate()
        gate.stamp(Date())
        #expect(gate.shouldReload(currentMTime: nil))
    }

    @Test("restamping advances the gate so a follow-up echo is also suppressed")
    func restampSuppressesNextEcho() {
        var gate = ConfigReloadGate()
        let t1 = Date()
        let t2 = t1.addingTimeInterval(1)
        gate.stamp(t1)
        gate.stamp(t2)
        #expect(!gate.shouldReload(currentMTime: t2))
        #expect(gate.shouldReload(currentMTime: t2.addingTimeInterval(0.5)))
    }
}
