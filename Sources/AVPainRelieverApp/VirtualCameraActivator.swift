import Foundation
import AppKit
import AVFoundation
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
    }

    static let extensionBundleID = "com.ericwillis.avpainreliever.CameraExtension"
    static let envVar = "AVPR_ACTIVATE_VIRTUAL_CAMERA"

    /// Stable UUID matching the extension's
    /// `CameraExtensionDeviceSource.deviceUUID`. The host uses this
    /// to find the virtual camera in the CMIO device list.
    static let virtualCameraUID = "B45B7E4D-3F4E-4F4D-9C2A-1B2C3D4E5F60"

    /// Localized name the extension registers — also what
    /// AVFoundation reports for the virtual camera's
    /// `localizedName`. Used as the value of
    /// `preferredCameraOverride` so `ProfileApplier` can set the
    /// system-wide preferred camera to "AV Pain Reliever" when the
    /// virtual camera is live, mirroring what users set in Zoom.
    static let virtualCameraDisplayName = "AV Pain Reliever"

    /// Mirror of the extension's notification names. Kept in sync by
    /// hand — both targets are sandboxed-vs-not separate executables
    /// without a shared Swift module, and three constants is cheaper
    /// than building one. Any change here MUST mirror in
    /// `CameraExtensionStream.swift`.
    private static let consumerActiveNotification =
        "HLH4LEWS9S.com.ericwillis.avpainreliever.consumer-active"
    private static let consumerInactiveNotification =
        "HLH4LEWS9S.com.ericwillis.avpainreliever.consumer-inactive"
    private static let queryConsumerStateNotification =
        "HLH4LEWS9S.com.ericwillis.avpainreliever.query-consumer-state"

    /// Time we keep the host capture pipeline warm after the last
    /// AVCapture client disconnects. Bridges back-to-back Zoom calls
    /// without re-paying the ~300-500 ms AVCaptureSession warmup, and
    /// avoids the green light flickering off-then-on between every
    /// hangup and the next ring.
    private static let stopGraceSeconds: TimeInterval = 30

    @Published private(set) var state: State = .off

    /// True when the env var override forced enable on launch.
    /// Settings UI hides the toggle's persistence-driven semantics
    /// and shows a "debug override active" badge instead so the
    /// user understands why disabling doesn't seem to stick.
    private(set) var isEnvOverride: Bool = false

    private var sinkWriter: CMIOSinkWriter?
    private var captureSession: CameraCaptureSession?

    /// Most recent source-camera name a profile asked us to route.
    /// Held across the "no consumer yet" window so that when lazy
    /// capture finally spins up (consumer connects after a profile
    /// applied), the new `CameraCaptureSession` opens the camera
    /// the profile actually wants — not the system-preferred one,
    /// which post-override is the virtual camera itself and would
    /// close a self-source feedback loop.
    private var pendingSourceName: String?

    /// True after a successful `disable()` until the host process
    /// is relaunched. Re-enabling within the same process hits the
    /// macOS "queued for uninstall on reboot" CMIO quirk where the
    /// host can't find the device even though System Settings shows
    /// it as active. Tracked here so `enable()` can surface the
    /// `.requiresRelaunch` state instead of silently producing a
    /// black feed.
    private var deactivatedThisSession = false

    /// True iff at least one AVCapture client (Zoom, FaceTime, …) is
    /// currently reading the virtual camera's source stream.
    /// Maintained from Darwin notifications posted by the extension.
    private var consumerActive: Bool = false

    /// Set when `endConsumerWatch` would otherwise be called twice
    /// (Sparkle replace re-fires `.completed` while state is already
    /// `.on`). Idempotency flag.
    private var consumerWatchActive: Bool = false

    /// Pending pipeline teardown from the last `consumerInactive`
    /// notification. Cancelled when a new consumer connects within
    /// the grace window so we don't tear down then immediately rebuild.
    private var stopGraceTimer: DispatchSourceTimer?

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

        // Capture pipeline is no longer started eagerly here. It
        // spins up only when `beginConsumerWatch` (called after the
        // extension reaches `.on`) sees a `consumerActive`
        // notification — i.e. when an AVCapture client actually
        // selects the virtual camera. Keeps the macOS green camera
        // light off while the app is idle.
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
        endConsumerWatch()
        stopGraceTimer?.cancel()
        stopGraceTimer = nil
        consumerActive = false
        pendingSourceName = nil
        stopCapturePipeline()
        Self.restoreUserPreferredCameraIfVirtual()

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
        let writer = CMIOSinkWriter(deviceUID: Self.virtualCameraUID)
        let session = CameraCaptureSession(
            sink: writer,
            initialSourceName: pendingSourceName
        )
        session.start()
        sinkWriter = writer
        captureSession = session
        logger.info("Started host-side capture + CMIO sink writer (initialSource=\(self.pendingSourceName ?? "<system-default>", privacy: .public))")
    }

    private func stopCapturePipeline() {
        captureSession?.stop()
        captureSession = nil
        sinkWriter = nil
        logger.info("Stopped host-side capture pipeline")
    }

    // MARK: - VirtualCameraSourceController

    var preferredCameraOverride: String? {
        // Only direct AVFoundation-modern apps at the virtual camera
        // when it's actually live and we've confirmed the host can
        // see it. During `.activating` / `.needsApproval` we don't
        // know whether the device is reachable yet; during
        // `.requiresRelaunch` it's known broken; `.failed` /
        // `.off` — same. In every non-`.on` case, fall back to the
        // profile's literal camera so AVFoundation-modern apps
        // don't hop to a virtual camera that can't deliver frames.
        state == .on ? Self.virtualCameraDisplayName : nil
    }

    func setSource(named: String) -> CameraApplyResult {
        // Always remember — even when the capture pipeline isn't
        // running yet — so a consumer that connects later opens the
        // right camera as its initial source instead of falling
        // through to userPreferredCamera (which is the virtual
        // camera itself under the override semantics).
        pendingSourceName = named
        guard let captureSession else {
            // Toggle off OR mid-activation with capture not yet
            // running. Treat as silent no-op (.ok) so the engine's
            // per-profile log line doesn't claim a failure for what
            // is just "user has the virtual camera disabled."
            return .ok
        }
        return captureSession.setSource(named: named)
    }

    // MARK: - Host-process visibility check

    /// After activation flips to `.on`, AVFoundation in the host
    /// process sometimes doesn't see the newly-published CMIO
    /// device — the discovery cache was warmed before the extension
    /// registered, and stays stale until a fresh process reads CMIO
    /// for the first time. Other apps (Photo Booth, FaceTime) see
    /// the device fine; only this host is blind to it. Detected by
    /// running `AVCaptureDevice.DiscoverySession` and looking for
    /// our extension's UID. If absent, escalate to
    /// `.requiresRelaunch` so Settings can offer the same Restart
    /// affordance the disable→enable path uses.
    private func scheduleHostVisibilityCheck() {
        // ~1.5 s is enough for CMIO to publish after activation on
        // every machine I've measured. Too short and a healthy
        // first-activation gets misclassified; longer adds dead time
        // before the wizard's camera list reflects reality.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, self.state == .on else { return }
            if Self.hostCanSeeVirtualCamera() {
                logger.info("Visibility check: host sees the virtual camera in DiscoverySession")
                return
            }
            logger.error("Visibility check: host process can't see its own Camera Extension — escalating to .requiresRelaunch")
            self.endConsumerWatch()
            self.stopGraceTimer?.cancel()
            self.stopGraceTimer = nil
            self.consumerActive = false
            self.pendingSourceName = nil
            self.stopCapturePipeline()
            self.state = .requiresRelaunch
        }
    }

    /// On disable, if the system-wide preferred camera still points
    /// at our virtual camera (because a recent profile-apply set it
    /// while the toggle was on), redirect AVFoundation-modern apps
    /// to whatever macOS would naturally pick instead. Otherwise
    /// FaceTime / Safari getUserMedia stay stuck on a virtual
    /// camera that's no longer producing frames. AppDelegate
    /// follows up with `engine.reapply()` so the active profile's
    /// real camera is the new explicit preference where applicable.
    private static func restoreUserPreferredCameraIfVirtual() {
        guard
            let user = AVCaptureDevice.userPreferredCamera,
            user.uniqueID == Self.virtualCameraUID
        else { return }
        AVCaptureDevice.userPreferredCamera = AVCaptureDevice.systemPreferredCamera
        logger.info(
            "Cleared userPreferredCamera that was pointing at the virtual camera; system fallback now \(AVCaptureDevice.systemPreferredCamera?.localizedName ?? "(none)", privacy: .public)"
        )
    }

    private static func hostCanSeeVirtualCamera() -> Bool {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInWideAngleCamera,
                .external,
                .continuityCamera,
                .deskViewCamera,
            ],
            mediaType: .video,
            position: .unspecified
        )
        return session.devices.contains { $0.uniqueID == Self.virtualCameraUID }
    }

    // MARK: - Consumer-driven capture lifecycle

    /// Subscribe to the extension's "consumer connected/disconnected"
    /// Darwin notifications and seed the initial state. The capture
    /// pipeline is started/stopped purely from these signals — the
    /// activator no longer eagerly opens an `AVCaptureSession` on
    /// `enable()`. Idempotent.
    private func beginConsumerWatch() {
        guard !consumerWatchActive else {
            logger.info("beginConsumerWatch: already active — no-op")
            return
        }
        let observer = Unmanaged.passUnretained(self).toOpaque()
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let callback: CFNotificationCallback = { _, observer, name, _, _ in
            guard let observer, let name else { return }
            let me = Unmanaged<VirtualCameraActivator>
                .fromOpaque(observer)
                .takeUnretainedValue()
            // CFNotificationName.rawValue is a CFString; bridge to
            // String for ergonomic switching.
            let nameStr = name.rawValue as String
            DispatchQueue.main.async {
                switch nameStr {
                case VirtualCameraActivator.consumerActiveNotification:
                    me.handleConsumerActive()
                case VirtualCameraActivator.consumerInactiveNotification:
                    me.handleConsumerInactive()
                default:
                    break
                }
            }
        }
        CFNotificationCenterAddObserver(
            center, observer, callback,
            Self.consumerActiveNotification as CFString,
            nil, .deliverImmediately
        )
        CFNotificationCenterAddObserver(
            center, observer, callback,
            Self.consumerInactiveNotification as CFString,
            nil, .deliverImmediately
        )
        consumerWatchActive = true

        // Seed initial state. Edge case worth covering: extension was
        // activated by a prior host instance and a Zoom call is
        // already in progress when this host launches. Without the
        // ping, we'd miss the 0→1 transition and the call would see
        // no frames until it disconnects.
        CFNotificationCenterPostNotification(
            center,
            CFNotificationName(Self.queryConsumerStateNotification as CFString),
            nil, nil, true
        )
    }

    private func endConsumerWatch() {
        guard consumerWatchActive else { return }
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterRemoveEveryObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            observer
        )
        consumerWatchActive = false
    }

    private func handleConsumerActive() {
        consumerActive = true
        // A new consumer arrived inside the grace window — keep the
        // pipeline that's already running and cancel the pending stop.
        stopGraceTimer?.cancel()
        stopGraceTimer = nil
        if captureSession == nil {
            logger.info("Consumer connected — starting host capture pipeline")
            startCapturePipeline()
        }
    }

    private func handleConsumerInactive() {
        consumerActive = false
        // Don't tear down immediately. Most users hang up one Zoom
        // call and start another within seconds; a 30-s grace bridges
        // those without re-paying the AVCaptureSession warmup, and
        // collapses the green-light flicker between calls.
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + Self.stopGraceSeconds)
        timer.setEventHandler { [weak self] in
            guard let self, !self.consumerActive else { return }
            logger.info("Stop grace expired — tearing down host capture pipeline")
            self.stopCapturePipeline()
            self.stopGraceTimer = nil
        }
        stopGraceTimer?.cancel()
        stopGraceTimer = timer
        timer.resume()
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
                if self.state != .off {
                    self.state = .on
                    self.scheduleHostVisibilityCheck()
                    self.beginConsumerWatch()
                }
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
