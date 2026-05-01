import Testing
import Foundation
@testable import AVPainReliever

/// Engine tests run against an integration-style fixture: real
/// `Debouncer` (with `TestClock`), real `ProfileResolver` (with
/// fixture profiles), and real `ProfileApplier` against
/// recording-mock `AudioController` / `OBSController`. Only
/// `USBWatcher` itself is faked, since IOKit can't deliver simulated
/// events.
///
/// Each test reads as a small scenario: "given a docked setup, when X
/// happens, the engine applies Y". This catches wiring bugs across the
/// engine's four layers without re-testing the algorithms each layer
/// already has dedicated unit tests for.
@Suite("Engine")
struct EngineTests {

    // MARK: - Fixtures

    static let caldigit = USBDevice(vendorID: 0x2188, productID: 0x6533)
    static let lgCamera = USBDevice(vendorID: 0x043e, productID: 0x9a68)
    static let yetiMic = USBDevice(vendorID: 0x046d, productID: 0x0ab7)

    static let laptop = Profile(
        name: "laptop",
        fingerprint: [],
        audioInput: "MacBook Pro Microphone",
        audioOutput: "MacBook Pro Speakers",
        obsScene: "Laptop"
    )

    static let homeOffice = Profile(
        name: "home-office",
        fingerprint: [caldigit, lgCamera],
        audioInput: "Yeti Stereo Microphone",
        audioOutput: "CalDigit Thunderbolt 3 Audio",
        obsScene: "Home Office"
    )

    /// Builds a fully-wired engine plus handles to every fake the test
    /// will assert against. Lets the per-test setup boilerplate
    /// collapse to one line.
    private struct Harness {
        let engine: Engine
        let watcher: RecordingUSBWatcher
        let audio: ProfileApplierTests.MockAudio
        let obs: ProfileApplierTests.MockOBS
        let logger: ProfileApplierTests.MockLogger
        let clock: TestClock
    }

    private func makeHarness(
        profiles: [Profile] = [laptop, homeOffice]
    ) -> Harness {
        let watcher = RecordingUSBWatcher()
        let resolver = ProfileResolver(profiles: profiles)
        let audio = ProfileApplierTests.MockAudio()
        let obs = ProfileApplierTests.MockOBS()
        let logger = ProfileApplierTests.MockLogger()
        let applier = ProfileApplier(audio: audio, obs: obs, logger: logger)
        let clock = TestClock()
        let engine = Engine(
            watcher: watcher,
            resolver: resolver,
            applier: applier,
            logger: logger,
            debounceInterval: 1.5,
            clock: clock
        )
        return Harness(
            engine: engine,
            watcher: watcher,
            audio: audio,
            obs: obs,
            logger: logger,
            clock: clock
        )
    }

    // MARK: - Initial application on start

    @Test("start applies the matching profile immediately, no debounce")
    func startAppliesImmediately() {
        let h = makeHarness()
        h.watcher.devices = [Self.caldigit, Self.lgCamera]
        h.engine.start()

        // The home-office profile fired on startup — no clock advance
        // required.
        #expect(h.obs.calls == ["Home Office"])
        #expect(h.audio.calls.count == 2)
        #expect(h.logger.infos.contains { $0.contains("evaluation → home-office") })
    }

    @Test("start falls back to empty-fingerprint profile when nothing else matches")
    func startWithUndockedFallsBackToLaptop() {
        let h = makeHarness()
        h.watcher.devices = [] // not docked
        h.engine.start()

        #expect(h.obs.calls == ["Laptop"])
        #expect(h.logger.infos.contains { $0.contains("evaluation → laptop") })
    }

    @Test("start logs a warning when the resolver returns nil and no fallback profile exists")
    func startWithNoMatchAndNoFallback() {
        // Only home-office is configured — no empty-fingerprint
        // fallback. Undocked → resolver returns nil.
        let h = makeHarness(profiles: [Self.homeOffice])
        h.watcher.devices = []
        h.engine.start()

        #expect(h.obs.calls.isEmpty)
        #expect(h.audio.calls.isEmpty)
        #expect(h.logger.warns.contains { $0.contains("no profile matched") })
    }

    // MARK: - Watcher events drive re-evaluation

    @Test("a USB event triggers a re-evaluation after the debounce window")
    func watcherEventTriggersReEvaluation() {
        let h = makeHarness()
        h.watcher.devices = []
        h.engine.start()
        // Initial: laptop.
        #expect(h.obs.calls == ["Laptop"])

        // User docks. New devices appear; watcher fires onChange.
        h.watcher.devices = [Self.caldigit, Self.lgCamera]
        h.watcher.triggerChange()

        // Within debounce window — no re-eval yet.
        h.clock.advance(by: 1.0)
        #expect(h.obs.calls == ["Laptop"])

        // Past debounce window → home-office applies.
        h.clock.advance(by: 0.6)
        #expect(h.obs.calls == ["Laptop", "Home Office"])
    }

    @Test("a 14-event dock burst coalesces into a single re-evaluation")
    func burstCoalesces() {
        let h = makeHarness()
        h.watcher.devices = []
        h.engine.start()
        #expect(h.obs.calls == ["Laptop"])

        // Simulate a real CalDigit dock burst — devices appear in
        // pieces, each delivering a watcher onChange.
        h.watcher.devices = [Self.caldigit, Self.lgCamera, Self.yetiMic]
        for _ in 0..<14 {
            h.watcher.triggerChange()
            h.clock.advance(by: 0.07) // ~1 s of bursts, all under 1.5 s
        }
        // Still inside the debounce window since the LAST event.
        #expect(h.obs.calls == ["Laptop"])

        h.clock.advance(by: 1.5)
        // One — exactly one — apply for the entire burst.
        #expect(h.obs.calls == ["Laptop", "Home Office"])
    }

    @Test("re-applying the same profile is a no-op via ProfileApplier dedup")
    func sameProfileIsNoOp() {
        let h = makeHarness()
        h.watcher.devices = [Self.caldigit, Self.lgCamera]
        h.engine.start()
        let initialAudioCalls = h.audio.calls.count
        let initialObsCalls = h.obs.calls.count

        // Trigger a change without changing the device set.
        h.watcher.triggerChange()
        h.clock.advance(by: 1.5)

        // Side effects should not have fired again.
        #expect(h.audio.calls.count == initialAudioCalls)
        #expect(h.obs.calls.count == initialObsCalls)
        #expect(h.logger.infos.contains { $0.contains("profile unchanged (home-office)") })
    }

    // MARK: - Lifecycle

    @Test("stop cancels a pending re-evaluation")
    func stopCancelsPending() {
        let h = makeHarness()
        h.watcher.devices = []
        h.engine.start()
        // Clear startup state so the assertion is unambiguous.
        let baselineObsCalls = h.obs.calls.count

        h.watcher.devices = [Self.caldigit, Self.lgCamera]
        h.watcher.triggerChange()
        h.clock.advance(by: 0.5)

        h.engine.stop()
        h.clock.advance(by: 10.0)

        #expect(h.obs.calls.count == baselineObsCalls)
        #expect(h.watcher.isStarted == false)
    }

    @Test("start is idempotent")
    func startIdempotent() {
        let h = makeHarness()
        h.watcher.devices = [Self.caldigit, Self.lgCamera]
        h.engine.start()
        h.engine.start() // second call must not double-apply
        // One initial apply: 2 audio + 1 OBS.
        #expect(h.audio.calls.count == 2)
        #expect(h.obs.calls.count == 1)
        #expect(h.watcher.startCount == 1)
    }

    @Test("stop is idempotent")
    func stopIdempotent() {
        let h = makeHarness()
        h.engine.start()
        h.engine.stop()
        h.engine.stop()
        #expect(h.watcher.stopCount == 1)
    }

    // MARK: - Manual evaluate

    @Test("evaluate() runs an immediate pass and cancels pending debounced ones")
    func evaluateRunsImmediatelyAndCancelsPending() {
        let h = makeHarness()
        h.watcher.devices = []
        h.engine.start() // initial: laptop
        let baselineObsCalls = h.obs.calls.count

        // Schedule a debounced eval, then immediately call evaluate().
        h.watcher.devices = [Self.caldigit, Self.lgCamera]
        h.watcher.triggerChange()
        h.engine.evaluate() // should fire NOW

        // home-office applied without advancing the clock.
        #expect(h.obs.calls == ["Laptop", "Home Office"])

        // Pending debounced eval should be cancelled — advancing the
        // clock past the window should not produce another apply.
        h.clock.advance(by: 5)
        #expect(h.obs.calls.count == baselineObsCalls + 1)
    }

    @Test("evaluate() before start() is a no-op")
    func evaluateBeforeStartIsNoop() {
        let h = makeHarness()
        h.watcher.devices = [Self.caldigit, Self.lgCamera]
        h.engine.evaluate()
        #expect(h.obs.calls.isEmpty)
        #expect(h.audio.calls.isEmpty)
    }

    // MARK: - Unknown-location detection

    @Test("onUnknownLocation fires when fallback profile resolves with devices attached")
    func onUnknownLocationFiresOnUnrecognizedDock() {
        let h = makeHarness()
        let unknownDevice = USBDevice(vendorID: 0x1111, productID: 0x2222)
        h.watcher.devices = [unknownDevice]
        var observed: [Set<USBDevice>] = []
        h.engine.onUnknownLocation = { observed.append($0) }

        h.engine.start()

        // Resolved to laptop (empty fingerprint) but devices ARE
        // attached → unknown location.
        #expect(observed == [[unknownDevice]])
    }

    @Test("onUnknownLocation does NOT fire when undocked")
    func onUnknownLocationSkipsUndocked() {
        let h = makeHarness()
        h.watcher.devices = []
        var observed = 0
        h.engine.onUnknownLocation = { _ in observed += 1 }

        h.engine.start()

        // Empty attached set + fallback resolution = normal "at the
        // laptop" state, not a new location.
        #expect(observed == 0)
    }

    @Test("onUnknownLocation does NOT fire when a specific fingerprint matches")
    func onUnknownLocationSkipsKnownDock() {
        let h = makeHarness()
        h.watcher.devices = [Self.caldigit, Self.lgCamera]
        var observed = 0
        h.engine.onUnknownLocation = { _ in observed += 1 }

        h.engine.start()

        // home-office matches → known location, not new.
        #expect(observed == 0)
    }

    @Test("onProfileApplied fires after each evaluation, including no-op re-applies")
    func onProfileAppliedFires() {
        let h = makeHarness()
        h.watcher.devices = [Self.caldigit, Self.lgCamera]
        var observed: [String] = []
        h.engine.onProfileApplied = { observed.append($0.name) }

        h.engine.start() // initial: home-office
        // Trigger a re-eval that resolves to the same profile (no-op apply).
        h.watcher.triggerChange()
        h.clock.advance(by: 1.5)

        // Both passes saw the same profile; the callback fires both
        // times (the StatusItem wants ALL evaluations, even no-ops,
        // to refresh its display).
        #expect(observed == ["home-office", "home-office"])
    }

    @Test("engine reflects current state when restarted after a state change")
    func restartAfterStop() {
        let h = makeHarness()
        h.watcher.devices = [Self.caldigit, Self.lgCamera]

        h.engine.start() // applies home-office
        h.engine.stop()

        // State changes while the engine is stopped — user undocked.
        h.watcher.devices = []

        h.engine.start() // must re-evaluate and apply laptop
        #expect(h.obs.calls == ["Home Office", "Laptop"])
        #expect(h.watcher.startCount == 2)
    }
}
