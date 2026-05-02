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
        var currentDefaultsStub: AudioDefaults = .init(inputName: nil, outputName: nil)

        func setDefault(named: String, role: AudioDeviceRole) -> AudioApplyResult {
            calls.append(Call(name: named, role: role))
            return resultsByName[named] ?? defaultResult
        }

        func availableDevices() -> [AudioDeviceSummary] {
            availableDevicesStub
        }

        func currentDefaults() -> AudioDefaults {
            currentDefaultsStub
        }
    }

    final class MockCamera: CameraController {
        struct Call: Equatable {
            let name: String
        }
        private(set) var calls: [Call] = []
        var resultsByName: [String: CameraApplyResult] = [:]
        var defaultResult: CameraApplyResult = .ok
        var availableCamerasStub: [CameraSummary] = []
        var currentPreferredNameStub: String? = nil

        func setPreferred(named: String) -> CameraApplyResult {
            calls.append(Call(name: named))
            return resultsByName[named] ?? defaultResult
        }

        func availableCameras() -> [CameraSummary] { availableCamerasStub }
        func currentPreferredName() -> String? { currentPreferredNameStub }
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
        audioOutput: "CalDigit Thunderbolt 3 Audio"
    )

    static let laptop = Profile(
        name: "laptop",
        fingerprint: [],
        audioInput: "MacBook Pro Microphone",
        audioOutput: "MacBook Pro Speakers"
    )

    // MARK: - Happy path

    @Test("applies audio input and output")
    func appliesBoth() {
        let audio = MockAudio()
        let log = MockLogger()
        let applier = ProfileApplier(audio: audio, logger: log)

        applier.apply(Self.homeOffice)

        #expect(audio.calls == [
            .init(name: "Yeti Stereo Microphone", role: .input),
            .init(name: "CalDigit Thunderbolt 3 Audio", role: .output),
        ])
        #expect(log.warns.isEmpty)
        #expect(log.infos.contains { $0.contains("applying profile: home-office") })
        #expect(log.infos.contains { $0.contains("set default input: Yeti") })
        #expect(log.infos.contains { $0.contains("set default output: CalDigit") })
    }

    // MARK: - Optional fields

    @Test("skips audio input when name is nil")
    func skipsNilInput() {
        let audio = MockAudio()
        let log = MockLogger()
        let applier = ProfileApplier(audio: audio, logger: log)
        let p = Profile(name: "out-only", fingerprint: [], audioInput: nil, audioOutput: "X")

        applier.apply(p)

        #expect(audio.calls == [.init(name: "X", role: .output)])
    }

    @Test("skips audio output when name is nil")
    func skipsNilOutput() {
        let audio = MockAudio()
        let applier = ProfileApplier(audio: audio, logger: MockLogger())
        let p = Profile(name: "in-only", fingerprint: [], audioInput: "X", audioOutput: nil)

        applier.apply(p)

        #expect(audio.calls == [.init(name: "X", role: .input)])
    }

    // MARK: - Audio failure modes

    @Test("warns when audio device is not found")
    func warnsOnNotFound() {
        let audio = MockAudio()
        audio.resultsByName["Yeti Stereo Microphone"] = .notFound
        let log = MockLogger()
        let applier = ProfileApplier(audio: audio, logger: log)

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
        let applier = ProfileApplier(audio: audio, logger: log)

        applier.apply(Self.homeOffice)

        #expect(log.warns.contains { $0.contains("is not an input") })
    }

    @Test("warns with OSStatus when CoreAudio set call fails")
    func warnsOnSetFailure() {
        let audio = MockAudio()
        audio.resultsByName["Yeti Stereo Microphone"] = .setFailed(-1)
        let log = MockLogger()
        let applier = ProfileApplier(audio: audio, logger: log)

        applier.apply(Self.homeOffice)

        #expect(log.warns.contains { $0.contains("OSStatus=-1") })
    }

    // MARK: - Idempotency

    @Test("applying the same profile twice is a logged no-op the second time")
    func dedupesConsecutiveApplies() {
        let audio = MockAudio()
        let log = MockLogger()
        let applier = ProfileApplier(audio: audio, logger: log)

        applier.apply(Self.homeOffice)
        applier.apply(Self.homeOffice)

        // Side effects fired exactly once.
        #expect(audio.calls.count == 2) // input + output, ONE round
        // Second apply was logged as a no-op.
        #expect(log.infos.contains { $0.contains("profile unchanged (home-office)") })
    }

    // MARK: - Camera

    @Test("applies camera when the profile sets one and a CameraController is wired")
    func appliesCamera() {
        let camera = MockCamera()
        let log = MockLogger()
        let applier = ProfileApplier(audio: MockAudio(), camera: camera, logger: log)
        let p = Profile(
            name: "home",
            fingerprint: [],
            camera: "LG UltraFine Display Camera"
        )

        applier.apply(p)

        #expect(camera.calls == [.init(name: "LG UltraFine Display Camera")])
        #expect(log.infos.contains { $0.contains("set preferred camera: LG UltraFine") })
    }

    @Test("warns when camera not currently attached")
    func warnsWhenCameraMissing() {
        let camera = MockCamera()
        camera.resultsByName["LG UltraFine Display Camera"] = .notFound
        let log = MockLogger()
        let applier = ProfileApplier(audio: MockAudio(), camera: camera, logger: log)
        let p = Profile(
            name: "home",
            fingerprint: [],
            camera: "LG UltraFine Display Camera"
        )

        applier.apply(p)

        #expect(log.warns.contains { $0.contains("camera 'LG UltraFine Display Camera' not found") })
    }

    @Test("silently skips camera when no controller is configured")
    func skipsCameraWithoutController() {
        let log = MockLogger()
        let applier = ProfileApplier(audio: MockAudio(), camera: nil, logger: log)
        let p = Profile(
            name: "home",
            fingerprint: [],
            camera: "Some Camera"
        )

        applier.apply(p)

        #expect(!log.warns.contains { $0.contains("camera") })
    }

    @Test("does not touch camera when profile.camera is nil")
    func skipsNilCamera() {
        let camera = MockCamera()
        let applier = ProfileApplier(audio: MockAudio(), camera: camera, logger: MockLogger())
        applier.apply(Self.homeOffice) // no camera field set

        #expect(camera.calls.isEmpty)
    }

    @Test("applying a different profile after a no-op fires side effects again")
    func reAppliesAfterChange() {
        let audio = MockAudio()
        let applier = ProfileApplier(audio: audio, logger: MockLogger())

        applier.apply(Self.homeOffice)
        applier.apply(Self.homeOffice) // no-op
        applier.apply(Self.laptop)     // change

        // 2 input/output calls per non-no-op apply × 2 actual applies = 4
        #expect(audio.calls.count == 4)
    }
}
