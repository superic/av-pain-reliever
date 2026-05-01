import Foundation

/// Two-level logger interface for engine components. Production wires
/// this to `os.Logger` + the on-disk log file (matching the Hammerspoon
/// engine's behavior); tests use a recording mock.
public protocol ApplierLogger {
    func info(_ message: String)
    func warn(_ message: String)
}

/// Applies a resolved profile: switches default audio in/out and the
/// OBS scene to match. Idempotent — a re-apply of the *same* profile
/// is a logged no-op (matches `init.lua`'s `lastAppliedProfile` check).
///
/// Owns no policy beyond "did we just apply this?": the caller is
/// responsible for resolving the right profile (`ProfileResolver`),
/// debouncing USB bursts (`Debouncer`), and choosing a fallback when
/// no profile matches. The applier just executes the side effects.
public final class ProfileApplier {
    private let audio: AudioController
    private let obs: OBSController?
    private let logger: ApplierLogger
    private var lastAppliedName: String?

    /// `obs` is optional: when nil (e.g. `obs-cmd` isn't installed),
    /// any profile that requests a scene switch logs a warning and is
    /// otherwise applied normally.
    public init(audio: AudioController, obs: OBSController?, logger: ApplierLogger) {
        self.audio = audio
        self.obs = obs
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
        if let scene = profile.obsScene {
            applyScene(scene)
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

    private func applyScene(_ name: String) {
        guard let obs else {
            logger.warn("OBS scene switch requested ('\(name)') but obs-cmd is not installed — skipping")
            return
        }
        do {
            try obs.switchScene(name)
            logger.info("OBS scene switched: \(name)")
        } catch {
            logger.warn("OBS scene switch failed for '\(name)': \(error)")
        }
    }
}
