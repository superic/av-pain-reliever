import Foundation

/// Two-level logger interface for engine components. Production wires
/// this to `os.Logger` + the on-disk log file (matching the Hammerspoon
/// engine's behavior); tests use a recording mock.
public protocol ApplierLogger {
    func info(_ message: String)
    func warn(_ message: String)
}

/// Applies a resolved profile: switches default audio in/out and the
/// system preferred camera to match. Idempotent — a re-apply of the
/// *same* profile is a logged no-op (matches `init.lua`'s
/// `lastAppliedProfile` check).
///
/// Owns no policy beyond "did we just apply this?": the caller is
/// responsible for resolving the right profile (`ProfileResolver`),
/// debouncing USB bursts (`Debouncer`), and choosing a fallback when
/// no profile matches. The applier just executes the side effects.
///
/// OBS scene-switching is intentionally not part of V1; planned for
/// V2. When it lands, it'll arrive as a separate optional injectable
/// alongside `AudioController` and `CameraController`.
public final class ProfileApplier {
    private let audio: AudioController
    private let camera: CameraController?
    private let virtualCameraSource: VirtualCameraSourceController?
    private let logger: ApplierLogger
    private var lastAppliedName: String?

    public init(
        audio: AudioController,
        camera: CameraController? = nil,
        virtualCameraSource: VirtualCameraSourceController? = nil,
        logger: ApplierLogger
    ) {
        self.audio = audio
        self.camera = camera
        self.virtualCameraSource = virtualCameraSource
        self.logger = logger
    }

    public func apply(_ profile: Profile) {
        if profile.name == lastAppliedName {
            logger.info("profile unchanged (\(profile.name)), no-op")
            return
        }
        logger.info("applying profile: \(profile.name)")

        if let input = profile.audioInput {
            applyAudio(input, role: .input)
        }
        if let output = profile.audioOutput {
            applyAudio(output, role: .output)
        }
        if let cameraName = profile.camera {
            applyCamera(cameraName)
            applyVirtualCameraSource(cameraName)
        }

        lastAppliedName = profile.name
    }

    private func applyAudio(_ name: String, role: AudioDeviceRole) {
        switch audio.setDefault(named: name, role: role) {
        case .ok:
            logger.info("set default \(role.rawValue): \(name)")
        case .notFound:
            logger.warn("audio \(role.rawValue) device '\(name)' not found — skipping")
        case .wrongScope:
            logger.warn("audio device '\(name)' exists but is not an \(role.rawValue) — skipping")
        case .setFailed(let status):
            logger.warn("setDefault\(role.rawValue) failed for: \(name) (OSStatus=\(status))")
        }
    }

    private func applyCamera(_ name: String) {
        // No CameraController configured (e.g., older macOS, or
        // construction-time decision). Same convention as the V1
        // OBS removal: the configuration layer announces the
        // limitation; per-profile we silently skip.
        guard let camera else { return }
        switch camera.setPreferred(named: name) {
        case .ok:
            logger.info("set preferred camera: \(name)")
        case .notFound:
            logger.warn("camera '\(name)' not found — skipping (it may not be currently attached)")
        }
    }

    private func applyVirtualCameraSource(_ name: String) {
        // Silently skipped on v0.1.x builds (no virtual camera
        // bundled) and on v0.2.x launches without
        // AVPR_ACTIVATE_VIRTUAL_CAMERA=1. Both paths inject nil.
        guard let virtualCameraSource else { return }
        switch virtualCameraSource.setSource(named: name) {
        case .ok:
            logger.info("set virtual camera source: \(name)")
        case .notFound:
            logger.warn("virtual camera source '\(name)' not found — skipping (it may not be currently attached)")
        }
    }
}
