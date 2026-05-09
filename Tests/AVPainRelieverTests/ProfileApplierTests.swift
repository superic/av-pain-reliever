import Testing
import Foundation
@testable import AVPainReliever

@Suite("ProfileApplier")
struct ProfileApplierTests {

    // MARK: - Mocks

    final class MockAudio: AudioApplier {
        struct Call: Equatable {
            let name: String
            let role: AudioDeviceRole
        }
        private(set) var calls: [Call] = []
        var resultsByName: [String: AudioApplyResult] = [:]
        var defaultResult: AudioApplyResult = .ok

        func setDefault(named: String, role: AudioDeviceRole) -> AudioApplyResult {
            calls.append(Call(name: named, role: role))
            return resultsByName[named] ?? defaultResult
        }
    }

    final class MockCamera: CameraApplier {
        struct Call: Equatable {
            let name: String
        }
        private(set) var calls: [Call] = []
        var resultsByName: [String: CameraApplyResult] = [:]
        var defaultResult: CameraApplyResult = .ok

        func setPreferred(named: String) -> CameraApplyResult {
            calls.append(Call(name: named))
            return resultsByName[named] ?? defaultResult
        }
    }

    final class MockVirtualCameraSource: VirtualCameraSourceController {
        struct Call: Equatable {
            let name: String
        }
        private(set) var calls: [Call] = []
        var resultsByName: [String: CameraApplyResult] = [:]
        var defaultResult: CameraApplyResult = .ok
        var preferredCameraOverride: String? = nil

        func setSource(named: String) -> CameraApplyResult {
            calls.append(Call(name: named))
            return resultsByName[named] ?? defaultResult
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

    // MARK: - Virtual camera source

    @Test("drives virtual camera source with the same name as the system camera")
    func appliesVirtualCameraSource() {
        let camera = MockCamera()
        let source = MockVirtualCameraSource()
        let log = MockLogger()
        let applier = ProfileApplier(
            audio: MockAudio(),
            camera: camera,
            virtualCameraSource: source,
            logger: log
        )
        let p = Profile(
            name: "home",
            fingerprint: [],
            camera: "LG UltraFine Display Camera"
        )

        applier.apply(p)

        #expect(camera.calls == [.init(name: "LG UltraFine Display Camera")])
        #expect(source.calls == [.init(name: "LG UltraFine Display Camera")])
        #expect(log.infos.contains { $0.contains("set virtual camera source: LG UltraFine") })
    }

    @Test("warns when virtual camera source is not currently attached")
    func warnsWhenVirtualCameraSourceMissing() {
        let source = MockVirtualCameraSource()
        source.resultsByName["LG UltraFine Display Camera"] = .notFound
        let log = MockLogger()
        let applier = ProfileApplier(
            audio: MockAudio(),
            virtualCameraSource: source,
            logger: log
        )
        let p = Profile(
            name: "home",
            fingerprint: [],
            camera: "LG UltraFine Display Camera"
        )

        applier.apply(p)

        #expect(log.warns.contains {
            $0.contains("virtual camera source") && $0.contains("not found")
        })
    }

    @Test("silently skips virtual camera source when not configured")
    func skipsVirtualCameraSourceWithoutController() {
        let log = MockLogger()
        let applier = ProfileApplier(
            audio: MockAudio(),
            virtualCameraSource: nil,
            logger: log
        )
        let p = Profile(
            name: "home",
            fingerprint: [],
            camera: "Some Camera"
        )

        applier.apply(p)

        #expect(!log.warns.contains { $0.contains("virtual camera source") })
    }

    @Test("does not touch virtual camera source when profile.camera is nil")
    func skipsNilVirtualCameraSource() {
        let source = MockVirtualCameraSource()
        let applier = ProfileApplier(
            audio: MockAudio(),
            virtualCameraSource: source,
            logger: MockLogger()
        )
        applier.apply(Self.homeOffice) // no camera field

        #expect(source.calls.isEmpty)
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

    // MARK: - Preferred-camera override

    @Test("when virtual camera reports an override, system preferred camera uses it; source still gets profile.camera")
    func virtualCameraOverrideRoutesPreferred() {
        let camera = MockCamera()
        let source = MockVirtualCameraSource()
        source.preferredCameraOverride = "AV Pain Reliever"
        let log = MockLogger()
        let applier = ProfileApplier(
            audio: MockAudio(),
            camera: camera,
            virtualCameraSource: source,
            logger: log
        )
        let p = Profile(
            name: "home",
            fingerprint: [],
            camera: "Logitech BRIO"
        )

        applier.apply(p)

        // System-wide preferred goes to the virtual camera so
        // FaceTime/Safari route through it the same way Zoom does.
        #expect(camera.calls == [.init(name: "AV Pain Reliever")])
        // Virtual camera's *source* still gets the real camera —
        // that's the actual webcam frames feed.
        #expect(source.calls == [.init(name: "Logitech BRIO")])
    }

    @Test("nil override falls back to profile.camera for both calls")
    func nilOverridePreservesLegacyBehavior() {
        let camera = MockCamera()
        let source = MockVirtualCameraSource()
        // Override left at default nil — represents virtual camera
        // off / activating / failed.
        let applier = ProfileApplier(
            audio: MockAudio(),
            camera: camera,
            virtualCameraSource: source,
            logger: MockLogger()
        )
        let p = Profile(
            name: "home",
            fingerprint: [],
            camera: "Logitech BRIO"
        )

        applier.apply(p)

        #expect(camera.calls == [.init(name: "Logitech BRIO")])
        #expect(source.calls == [.init(name: "Logitech BRIO")])
    }

    // MARK: - Forced re-apply

    @Test("invalidateLastApplied lets the next apply re-fire side effects on the same profile")
    func invalidateLastAppliedReFiresOnSameProfile() {
        let audio = MockAudio()
        let applier = ProfileApplier(audio: audio, logger: MockLogger())

        applier.apply(Self.homeOffice)
        applier.apply(Self.homeOffice) // dedupe → no-op
        applier.invalidateLastApplied()
        applier.apply(Self.homeOffice) // re-fires

        // 2 calls per real apply × 2 real applies = 4
        #expect(audio.calls.count == 4)
    }
}
