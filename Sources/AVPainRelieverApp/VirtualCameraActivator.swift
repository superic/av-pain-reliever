import Foundation
import AppKit
import SystemExtensions
import AVPainReliever
import os.log

private let logger = Logger(
    subsystem: "com.ericwillis.avpainreliever",
    category: "Activator"
)

/// Owns the lifecycle of the embedded Camera Extension AND the
/// host-side capture pipeline that feeds it. Driven by the
/// `SettingsStore.virtualCameraEnabled` toggle, with
/// `AVPR_ACTIVATE_VIRTUAL_CAMERA=1` as a debug-only override that
/// forces enable on launch regardless of the persisted setting.
///
/// State machine:
///
/// ```
/// .off ──enable()──▶ .activating ──didFinishWithResult──▶ .on
///   ▲                       │                              │
///   │                       └─didFailWithError──▶ .failed   │
///   │                                                       │
///   └────────────────disable()──────────────────────────────┘
/// ```
///
/// `.activating` covers both submitted-and-waiting and
/// needs-user-approval — they're indistinguishable from the host's
/// perspective until macOS fires didFinishWithResult.
///
/// SwiftUI surfaces the state via the `@Published state` property;
/// the Settings view shows a status row that mirrors it.
final class VirtualCameraActivator: NSObject, ObservableObject,
    OSSystemExtensionRequestDelegate, VirtualCameraSourceController
{
    enum State: Equatable {
        case off
        case activating
        case needsApproval
        case on
        case failed(String)
        /// Special "the user toggled off then back on in the same
        /// process" state. macOS marks the extension
        /// `[terminated waiting to uninstall on reboot]` after
        /// deactivation; re-enabling without a host-process restart
        /// hands the host a stale CMIO device registration that
        /// can't be queried successfully. Detected by tracking the
        /// in-session deactivation; resolved by relaunching the
        /// app from a fresh process.
        case requiresRelaunch

        var isLive: Bool {
            switch self {
            case .activating, .needsApproval, .on: return true
            case .off, .failed, .requiresRelaunch: return false
            }
        }
    }

    static let extensionBundleID = "com.ericwillis.avpainreliever.CameraExtension"
    static let envVar = "AVPR_ACTIVATE_VIRTUAL_CAMERA"

    /// Stable UUID matching the extension's
    /// `CameraExtensionDeviceSource.deviceUUID`. The host uses this
    /// to find the virtual camera in the CMIO device list.
    static let virtualCameraUID = "B45B7E4D-3F4E-4F4D-9C2A-1B2C3D4E5F60"

    @Published private(set) var state: State = .off

    /// True when the env var override forced enable on launch.
    /// Settings UI hides the toggle's persistence-driven semantics
    /// and shows a "debug override active" badge instead so the
    /// user understands why disabling doesn't seem to stick.
    private(set) var isEnvOverride: Bool = false

    private var sinkWriter: CMIOSinkWriter?
    private var captureSession: CameraCaptureSession?

    /// True after a successful `disable()` until the host process
    /// is relaunched. Re-enabling within the same process hits the
    /// macOS "queued for uninstall on reboot" CMIO quirk where the
    /// host can't find the device even though System Settings shows
    /// it as active. Tracked here so `enable()` can surface the
    /// `.requiresRelaunch` state instead of silently producing a
    /// black feed.
    private var deactivatedThisSession = false

    /// Returns true if launch should auto-enable: env-var debug
    /// override OR the user's persisted toggle is on. The env var
    /// is checked first so a developer can force-enable without
    /// touching the persisted setting.
    static func shouldAutoEnable(persistedToggle: Bool) -> Bool {
        if ProcessInfo.processInfo.environment[envVar] == "1" { return true }
        return persistedToggle
    }

    /// Begin activation. Idempotent: subsequent calls while in any
    /// non-`.off`/`.failed` state are silent no-ops.
    func enable(envOverride: Bool = false) {
        switch state {
        case .activating, .needsApproval, .on:
            logger.info("enable() called while already \(String(describing: self.state), privacy: .public) — no-op")
            return
        case .requiresRelaunch:
            logger.info("enable() called while .requiresRelaunch — keeping that state until relaunch")
            return
        case .off, .failed:
            break
        }
        if deactivatedThisSession {
            logger.info("enable() blocked: in-session deactivation requires a host relaunch")
            state = .requiresRelaunch
            return
        }
        isEnvOverride = envOverride
        state = .activating
        logger.info("Submitting Camera Extension activation request (envOverride=\(envOverride, privacy: .public))")

        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: Self.extensionBundleID,
            queue: .main
        )
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)

        startCapturePipeline()
    }

    /// Tear down the capture pipeline and submit a deactivation
    /// request. Idempotent: a call while `.off` is a no-op.
    func disable() {
        switch state {
        case .off:
            logger.info("disable() called while already off — no-op")
            return
        default:
            break
        }
        logger.info("Disabling: stopping capture pipeline + deactivating extension")
        stopCapturePipeline()

        let request = OSSystemExtensionRequest.deactivationRequest(
            forExtensionWithIdentifier: Self.extensionBundleID,
            queue: .main
        )
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)

        state = .off
        isEnvOverride = false
        deactivatedThisSession = true
    }

    /// Quit + relaunch the host. The fresh process auto-enables
    /// from the persisted toggle and gets a clean CMIO context that
    /// finds the activated extension immediately. Wired to the
    /// "Restart" button on the Settings UI's `.requiresRelaunch`
    /// state.
    func relaunch() {
        let bundleURL = Bundle.main.bundleURL
        logger.info("Relaunching host: \(bundleURL.path, privacy: .public)")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = [bundleURL.path]
        do {
            try task.run()
        } catch {
            logger.error("relaunch open failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        DispatchQueue.main.async {
            NSApplication.shared.terminate(nil)
        }
    }

    private func startCapturePipeline() {
        guard captureSession == nil else { return }
        let writer = CMIOSinkWriter(
            deviceUID: Self.virtualCameraUID,
            width: 1280,
            height: 720
        )
        let session = CameraCaptureSession(sink: writer)
        session.start()
        sinkWriter = writer
        captureSession = session
        logger.info("Started host-side capture + CMIO sink writer")
    }

    private func stopCapturePipeline() {
        captureSession?.stop()
        captureSession = nil
        sinkWriter = nil
        logger.info("Stopped host-side capture pipeline")
    }

    // MARK: - VirtualCameraSourceController

    func setSource(named: String) -> CameraApplyResult {
        guard let captureSession else {
            // Toggle off OR mid-activation with capture not yet
            // running. Treat as silent no-op (.ok) so the engine's
            // per-profile log line doesn't claim a failure for what
            // is just "user has the virtual camera disabled."
            return .ok
        }
        return captureSession.setSource(named: named)
    }

    // MARK: - OSSystemExtensionRequestDelegate

    func request(
        _ request: OSSystemExtensionRequest,
        actionForReplacingExtension existing: OSSystemExtensionProperties,
        withExtension ext: OSSystemExtensionProperties
    ) -> OSSystemExtensionRequest.ReplacementAction {
        // Always replace. Sparkle-installed upgrades will hit this
        // path for every v0.2.x → v0.2.y bump.
        .replace
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        logger.info("Camera Extension needs user approval — open System Settings → Login Items & Extensions")
        DispatchQueue.main.async { [weak self] in
            // Don't override .on — a Sparkle-driven upgrade-replace
            // flow can fire needs-user-approval AFTER the original
            // is already running, and we don't want to regress the
            // status badge in that case.
            guard let self, self.state != .on else { return }
            self.state = .needsApproval
        }
    }

    func request(
        _ request: OSSystemExtensionRequest,
        didFinishWithResult result: OSSystemExtensionRequest.Result
    ) {
        logger.info("Camera Extension request finished: result=\(result.rawValue, privacy: .public)")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch result {
            case .completed:
                // Activation OR deactivation completed. Distinguish
                // by current state: if we were already heading off
                // (disable() set state=.off), leave it. Otherwise
                // this is a successful activation → .on.
                if self.state != .off { self.state = .on }
            case .willCompleteAfterReboot:
                // Rare path — extension upgrade queued for next
                // reboot. Mark as failed so the user knows the new
                // version isn't live yet.
                self.state = .failed("Upgrade pending — reboot required")
            @unknown default:
                self.state = .failed("Unknown activation result")
            }
        }
    }

    func request(
        _ request: OSSystemExtensionRequest,
        didFailWithError error: Error
    ) {
        let message = error.localizedDescription
        logger.error("Camera Extension request failed: \(message, privacy: .public)")
        DispatchQueue.main.async { [weak self] in
            self?.stopCapturePipeline()
            self?.state = .failed(message)
        }
    }
}
