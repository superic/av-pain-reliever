import Foundation

/// Three-level logger interface for engine components. Production
/// wires this to `os.Logger` (Apple's unified logging); tests use a
/// recording mock. `error` exists for unrecoverable failures
/// (CMIO/AVFoundation hard errors); `warn` for recoverable issues
/// the engine logged-and-continued through.
public protocol ApplierLogger {
    func info(_ message: String)
    func warn(_ message: String)
    func error(_ message: String)
}

public extension ApplierLogger {
    /// Default routes `error` to `warn` so existing two-level
    /// conformers stay source-compatible. Conformers that can
    /// distinguish severities (the production `ConsoleLogger`)
    /// implement `error` directly.
    func error(_ message: String) { warn(message) }
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
public final class ProfileApplier {
    private let audio: AudioApplier
    private let camera: CameraApplier?
    private let virtualCameraSource: VirtualCameraSourceController?
    private let logger: ApplierLogger
    private var lastAppliedName: String?

    public init(
        audio: AudioApplier,
        camera: CameraApplier? = nil,
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
            // When the virtual camera is the active routing layer,
            // the *system-wide* preferred camera should point at the
            // virtual camera itself: that's what FaceTime, Safari,
            // and any AVFoundation-modern client picks up, mirroring
            // what Zoom/Slack/Teams see once the user has manually
            // selected "AV Pain Reliever". The profile's literal
            // camera name still drives the virtual camera's *source*
            // (the real webcam frames feed in there).
            //
            // Failure-mode note: if `setSource` returns `.notFound`
            // (transient unplug between override-publish and source-
            // apply), the system preference still points at the
            // virtual camera while the virtual camera has no live
            // source. The Camera Extension holds the last frame, so
            // the symptom is a frozen frame rather than no video.
            // Next `apply()` cycle re-resolves and recovers.
            let preferredName = virtualCameraSource?.preferredCameraOverride
                ?? cameraName
            applyCamera(preferredName)
            applyVirtualCameraSource(cameraName)
        }

        lastAppliedName = profile.name
    }

    /// Forget the dedupe key so the next `apply(profile)` re-fires
    /// every side effect even when the profile name hasn't changed.
    /// Used by the host when a config change (e.g. flipping the
    /// virtual-camera toggle) means the same profile name should
    /// resolve to a different set of system-state writes.
    public func invalidateLastApplied() {
        lastAppliedName = nil
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
        // CameraApplier is optional in the init: callers can wire
        // the engine without one (audio-only configurations).
        // Per-profile we silently skip; the configuration layer is
        // responsible for announcing the limitation if it matters.
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
