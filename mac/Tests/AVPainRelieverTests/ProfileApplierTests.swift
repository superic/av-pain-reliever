import Testing
import Foundation
@testable import AVPainReliever

@Suite("ProfileApplier")
struct ProfileApplierTests {

    // MARK: - Mocks

    final class MockAudio: AudioController {
        struct Call: Equatable {
            let name: String
            let role: AudioDeviceRole
        }
        private(set) var calls: [Call] = []
        var resultsByName: [String: AudioApplyResult] = [:]
        var defaultResult: AudioApplyResult = .ok
        var availableDevicesStub: [AudioDeviceSummary] = []

        func setDefault(named: String, role: AudioDeviceRole) -> AudioApplyResult {
            calls.append(Call(name: named, role: role))
            return resultsByName[named] ?? defaultResult
        }

        func availableDevices() -> [AudioDeviceSummary] {
            availableDevicesStub
        }
    }

    final class MockOBS: OBSController {
        private(set) var calls: [String] = []
        var error: OBSError?

        func switchScene(_ name: String) throws {
            calls.append(name)
            if let error { throw error }
        }
    }

    final class MockLogger: ApplierLogger {
        private(set) var infos: [String] = []
        private(set) var warns: [String] = []

        func info(_ message: String) { infos.append(message) }
        func warn(_ message: String) { warns.append(message) }
    }

    // MARK: - Fixtures

    static let homeOffice = Profile(
        name: "home-office",
        fingerprint: [],
        audioInput: "Yeti Stereo Microphone",
        audioOutput: "CalDigit Thunderbolt 3 Audio",
        obsScene: "Home Office"
    )

    static let laptop = Profile(
        name: "laptop",
        fingerprint: [],
        audioInput: "MacBook Pro Microphone",
        audioOutput: "MacBook Pro Speakers",
        obsScene: "Laptop"
    )

    // MARK: - Happy path

    @Test("applies audio input, audio output, and OBS scene in order")
    func appliesAllThree() {
        let audio = MockAudio()
        let obs = MockOBS()
        let log = MockLogger()
        let applier = ProfileApplier(audio: audio, obs: obs, logger: log)

        applier.apply(Self.homeOffice)

        #expect(audio.calls == [
            .init(name: "Yeti Stereo Microphone", role: .input),
            .init(name: "CalDigit Thunderbolt 3 Audio", role: .output),
        ])
        #expect(obs.calls == ["Home Office"])
        #expect(log.warns.isEmpty)
        #expect(log.infos.contains { $0.contains("applying profile: home-office") })
        #expect(log.infos.contains { $0.contains("set default input: Yeti") })
        #expect(log.infos.contains { $0.contains("set default output: CalDigit") })
        #expect(log.infos.contains { $0.contains("OBS scene switched: Home Office") })
    }

    // MARK: - Optional fields

    @Test("skips audio input when name is nil")
    func skipsNilInput() {
        let audio = MockAudio()
        let log = MockLogger()
        let applier = ProfileApplier(audio: audio, obs: nil, logger: log)
        let p = Profile(name: "out-only", fingerprint: [], audioInput: nil, audioOutput: "X", obsScene: nil)

        applier.apply(p)

        #expect(audio.calls == [.init(name: "X", role: .output)])
    }

    @Test("skips OBS when scene is nil")
    func skipsNilScene() {
        let obs = MockOBS()
        let applier = ProfileApplier(audio: MockAudio(), obs: obs, logger: MockLogger())
        let p = Profile(name: "audio-only", fingerprint: [], audioInput: "X", audioOutput: "Y", obsScene: nil)

        applier.apply(p)

        #expect(obs.calls.isEmpty)
    }

    @Test("silently skips OBS when no controller is configured")
    func skipsOBSWhenControllerMissing() {
        let log = MockLogger()
        let applier = ProfileApplier(audio: MockAudio(), obs: nil, logger: log)

        applier.apply(Self.homeOffice)

        // The "obs-cmd not installed" announcement is the
        // configuration layer's job (AppDelegate logs it once at
        // startup). The applier silently skips per-profile so users
        // who don't run OBS don't see a warning per dock event.
        #expect(!log.warns.contains { $0.contains("OBS") })
        #expect(!log.warns.contains { $0.contains("Home Office") })
    }

    // MARK: - Audio failure modes

    @Test("warns when audio device is not found")
    func warnsOnNotFound() {
        let audio = MockAudio()
        audio.resultsByName["Yeti Stereo Microphone"] = .notFound
        let log = MockLogger()
        let applier = ProfileApplier(audio: audio, obs: MockOBS(), logger: log)

        applier.apply(Self.homeOffice)

        #expect(log.warns.contains {
            $0.contains("'Yeti Stereo Microphone'") && $0.contains("not found")
        })
    }

    @Test("warns when audio device exists but has wrong scope")
    func warnsOnWrongScope() {
        let audio = MockAudio()
        audio.resultsByName["Yeti Stereo Microphone"] = .wrongScope
        let log = MockLogger()
        let applier = ProfileApplier(audio: audio, obs: MockOBS(), logger: log)

        applier.apply(Self.homeOffice)

        #expect(log.warns.contains { $0.contains("is not an input") })
    }

    @Test("warns with OSStatus when CoreAudio set call fails")
    func warnsOnSetFailure() {
        let audio = MockAudio()
        audio.resultsByName["Yeti Stereo Microphone"] = .setFailed(-1)
        let log = MockLogger()
        let applier = ProfileApplier(audio: audio, obs: MockOBS(), logger: log)

        applier.apply(Self.homeOffice)

        #expect(log.warns.contains { $0.contains("OSStatus=-1") })
    }

    // MARK: - OBS failure modes

    @Test("warns when OBS scene switch throws")
    func warnsOnOBSError() {
        let obs = MockOBS()
        obs.error = .nonZeroExit(code: 1, stdout: "", stderr: "auth failed")
        let log = MockLogger()
        let applier = ProfileApplier(audio: MockAudio(), obs: obs, logger: log)

        applier.apply(Self.homeOffice)

        #expect(log.warns.contains {
            $0.contains("OBS scene switch failed") && $0.contains("Home Office")
        })
    }

    // MARK: - Idempotency

    @Test("applying the same profile twice is a logged no-op the second time")
    func dedupesConsecutiveApplies() {
        let audio = MockAudio()
        let obs = MockOBS()
        let log = MockLogger()
        let applier = ProfileApplier(audio: audio, obs: obs, logger: log)

        applier.apply(Self.homeOffice)
        applier.apply(Self.homeOffice)

        // Side effects fired exactly once.
        #expect(audio.calls.count == 2) // input + output, ONE round
        #expect(obs.calls.count == 1)
        // Second apply was logged as a no-op.
        #expect(log.infos.contains { $0.contains("profile unchanged (home-office)") })
    }

    @Test("applying a different profile after a no-op fires side effects again")
    func reAppliesAfterChange() {
        let audio = MockAudio()
        let obs = MockOBS()
        let applier = ProfileApplier(audio: audio, obs: obs, logger: MockLogger())

        applier.apply(Self.homeOffice)
        applier.apply(Self.homeOffice) // no-op
        applier.apply(Self.laptop)     // change

        // 2 input/output calls per non-no-op apply × 2 actual applies = 4
        #expect(audio.calls.count == 4)
        #expect(obs.calls == ["Home Office", "Laptop"])
    }
}
