import Foundation
import AVFoundation
import CoreVideo
import AVPainReliever
import os.log

private let logger = Logger(
    subsystem: "com.ericwillis.avpainreliever",
    category: "CameraCaptureSession"
)

/// Captures from a webcam and hands each frame to `CMIOSinkWriter`,
/// which enqueues it on the virtual camera's sink stream. The host
/// app is a normal user-process AVFoundation client — no sandbox,
/// no recursion through CMIO. TCC permission for the camera is
/// granted to the host on first use; the extension never touches
/// AVFoundation.
///
/// Source selection:
///
/// - First start picks the system's preferred camera (`userPreferredCamera`
///   → `systemPreferredCamera` → first discovered) so the virtual
///   camera shows *something* before the engine has resolved a
///   profile.
/// - `setSource(named:)` swaps inputs on the running session at
///   runtime. The active profile drives this through
///   `VirtualCameraSourceController` from `ProfileApplier`.
///
/// Switching uses `beginConfiguration` / `commitConfiguration` so
/// the session keeps running across the swap — the only gap is the
/// ~500 ms it takes the new device to start delivering frames. The
/// extension covers that gap by holding the last frame.
final class CameraCaptureSession: NSObject {
    private let session = AVCaptureSession()
    private let captureQueue = DispatchQueue(
        label: "com.ericwillis.avpainreliever.host.capture",
        qos: .userInteractive
    )
    private let sink: CMIOSinkWriter
    private var sinkStarted = false
    private var capturedFrameCount: UInt64 = 0
    private var output: AVCaptureVideoDataOutput?
    private var currentInput: AVCaptureDeviceInput?
    private var currentDeviceUniqueID: String?

    /// Camera the active profile wanted as the source at session-
    /// boot time. The activator remembers the most recent
    /// `setSource(named:)` request and passes it here so that when
    /// lazy capture starts up late (a Zoom client connects after a
    /// profile-driven setSource fired against a then-nil session),
    /// we open the right device on the first attempt instead of
    /// falling through to `userPreferredCamera` — which under the
    /// new override semantics is the virtual camera itself, and
    /// would create a self-source feedback loop.
    private let initialSourceName: String?

    init(sink: CMIOSinkWriter, initialSourceName: String? = nil) {
        self.sink = sink
        self.initialSourceName = initialSourceName
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRuntimeError(_:)),
            name: .AVCaptureSessionRuntimeError,
            object: session
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionStarted(_:)),
            name: .AVCaptureSessionDidStartRunning,
            object: session
        )
    }

    @objc private func handleRuntimeError(_ notification: Notification) {
        let error = notification.userInfo?[AVCaptureSessionErrorKey] as? Error
        logger.error("AVCaptureSession runtime error: \(error?.localizedDescription ?? "unknown", privacy: .public)")
    }

    @objc private func handleSessionStarted(_ notification: Notification) {
        logger.info("AVCaptureSession reported running")
    }

    /// Boots up capture asynchronously. Returns immediately.
    /// Failures are logged; the menu bar doesn't surface them today.
    func start() {
        captureQueue.async { [weak self] in
            self?.bootIfAuthorized()
        }
    }

    func stop() {
        captureQueue.async { [weak self] in
            guard let self else { return }
            self.session.stopRunning()
            if self.sinkStarted {
                self.sink.stop()
                self.sinkStarted = false
            }
        }
    }

    private func bootIfAuthorized() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        logger.info("Camera authorization status: \(status.rawValue, privacy: .public) (0=notDetermined 1=restricted 2=denied 3=authorized)")
        switch status {
        case .authorized:
            installAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                logger.info("Camera access request: granted=\(granted, privacy: .public)")
                self?.captureQueue.async {
                    if granted {
                        self?.installAndStart()
                    } else {
                        logger.error("Camera access denied; virtual camera will see no frames")
                    }
                }
            }
        case .denied, .restricted:
            logger.error("Camera access denied/restricted; virtual camera will see no frames")
        @unknown default:
            logger.error("Unknown camera authorization status")
        }
    }

    private func installAndStart() {
        guard !session.isRunning else {
            logger.info("installAndStart: session already running")
            return
        }

        guard let device = pickInitialDevice() else {
            logger.error("No video capture devices available")
            return
        }
        logger.info("Initial capture device: \(device.localizedName, privacy: .public) (\(device.uniqueID, privacy: .public))")

        session.beginConfiguration()
        session.sessionPreset = .hd1280x720

        guard installInput(device: device) else {
            session.commitConfiguration()
            return
        }

        let output = AVCaptureVideoDataOutput()
        // Deliver the device's NATIVE pixel format and dimensions.
        // M2 forced 1280×720 BGRA via `videoSettings`, which works
        // for the FaceTime HD camera but silently produces zero
        // frames on USB capture cards (HDMI to U3 capture
        // 0x1e4e/0x701f is the user's known case — it advertises
        // BGRA in `availableVideoPixelFormatTypes` but the actual
        // delivery path drops every frame). Letting the device
        // pick its own format makes the AVCaptureSession work for
        // every camera; `CMIOSinkWriter` then converts to
        // 1280×720 BGRA via `VTPixelTransferSession` before
        // enqueueing — that's the format the extension's source
        // stream advertises to AVCapture clients.
        output.videoSettings = [
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: captureQueue)

        guard session.canAddOutput(output) else {
            logger.error("Cannot add video output")
            session.commitConfiguration()
            return
        }
        session.addOutput(output)
        self.output = output
        session.commitConfiguration()

        logger.info("Calling session.startRunning()")
        session.startRunning()
        logger.info("session.isRunning=\(self.session.isRunning, privacy: .public)")

        sinkStarted = sink.start()
        logger.info("sink.start() returned \(self.sinkStarted, privacy: .public)")
    }

    /// Initial source pick. Priority:
    ///
    /// 1. `initialSourceName` if the activator passed one — i.e. the
    ///    active profile already named a source camera before the
    ///    consumer connected and we'd otherwise have lost it.
    /// 2. Fallback chain: userPreferred → systemPreferred → first
    ///    discovered.
    ///
    /// In every case, the embedded virtual camera is rejected. If
    /// the host opened its own output as a source we'd close a
    /// feedback loop — host writes whatever it just read, the
    /// extension forwards it back, frozen frame forever. Under the
    /// `preferredCameraOverride` semantics `userPreferredCamera`
    /// regularly *is* the virtual camera, which is exactly what we
    /// want for AVFoundation-modern apps but exactly what we don't
    /// want here.
    private func pickInitialDevice() -> AVCaptureDevice? {
        if let name = initialSourceName,
           let device = Self.findDevice(named: name)
        {
            return device
        }
        if let user = AVCaptureDevice.userPreferredCamera,
           !Self.isVirtualCamera(user)
        {
            return user
        }
        if let system = AVCaptureDevice.systemPreferredCamera,
           !Self.isVirtualCamera(system)
        {
            return system
        }
        return Self.discoverySession().devices
            .first { !Self.isVirtualCamera($0) }
    }

    /// True iff `device` is the embedded AV Pain Reliever virtual
    /// camera. Used to keep the host from ever opening its own
    /// output as a capture source.
    private static func isVirtualCamera(_ device: AVCaptureDevice) -> Bool {
        device.uniqueID == VirtualCameraActivator.virtualCameraUID
    }

    /// Add an `AVCaptureDeviceInput` for `device` to the session.
    /// Caller is responsible for `beginConfiguration` /
    /// `commitConfiguration`. Updates `currentInput` and
    /// `currentDeviceUniqueID` on success.
    private func installInput(device: AVCaptureDevice) -> Bool {
        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                logger.error("Cannot add input for \(device.localizedName, privacy: .public)")
                return false
            }
            session.addInput(input)
            currentInput = input
            currentDeviceUniqueID = device.uniqueID
            return true
        } catch {
            logger.error("AVCaptureDeviceInput failed for \(device.localizedName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Swap the running session's input to the camera with the given
    /// `localizedName`. No-ops when the source is already that
    /// device. Runs on `captureQueue` so it serializes with frame
    /// delivery.
    func switchSource(toLocalizedName name: String) {
        captureQueue.async { [weak self] in
            self?.swapInputLocked(toLocalizedName: name)
        }
    }

    private func swapInputLocked(toLocalizedName name: String) {
        guard let device = Self.findDevice(named: name) else {
            logger.error("switchSource: no camera with localizedName '\(name, privacy: .public)' — skipping")
            return
        }
        if device.uniqueID == currentDeviceUniqueID {
            logger.info("switchSource: already on '\(name, privacy: .public)' — no-op")
            return
        }

        logger.info("switchSource: '\(self.currentDeviceUniqueID ?? "<none>", privacy: .public)' → '\(device.uniqueID, privacy: .public)' (\(name, privacy: .public))")

        session.beginConfiguration()
        if let currentInput {
            session.removeInput(currentInput)
            self.currentInput = nil
            self.currentDeviceUniqueID = nil
        }
        _ = installInput(device: device)
        session.commitConfiguration()

        if !session.isRunning {
            // installAndStart never finished (e.g. initial discovery
            // returned nil). Start now that we have a real source.
            logger.info("switchSource: session was not running — starting")
            session.startRunning()
        }

        if !sinkStarted {
            sinkStarted = sink.start()
            if sinkStarted {
                logger.info("switchSource: sink started after source swap")
            }
        }
    }

    private static func findDevice(named name: String) -> AVCaptureDevice? {
        discoverySession().devices.first {
            $0.localizedName == name && !isVirtualCamera($0)
        }
    }

    private static func discoverySession() -> AVCaptureDevice.DiscoverySession {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInWideAngleCamera,
                .external,
                .continuityCamera,
                .deskViewCamera,
            ],
            mediaType: .video,
            position: .unspecified
        )
    }
}

extension CameraCaptureSession: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        capturedFrameCount += 1
        if capturedFrameCount == 1, let pb = CMSampleBufferGetImageBuffer(sampleBuffer) {
            let w = CVPixelBufferGetWidth(pb)
            let h = CVPixelBufferGetHeight(pb)
            let pf = CVPixelBufferGetPixelFormatType(pb)
            // Pretty-print FourCC
            let fourcc = String(bytes: [
                UInt8((pf >> 24) & 0xFF),
                UInt8((pf >> 16) & 0xFF),
                UInt8((pf >> 8) & 0xFF),
                UInt8(pf & 0xFF)
            ], encoding: .ascii) ?? "????"
            logger.info("First frame from webcam: \(w, privacy: .public)x\(h, privacy: .public) format=\(fourcc, privacy: .public)")
        }

        // If sink wasn't ready when capture started (extension not
        // yet active), retry every few frames.
        if !sinkStarted {
            sinkStarted = sink.start()
            if sinkStarted {
                logger.info("Sink writer connected on retry (after \(self.capturedFrameCount, privacy: .public) frames)")
            } else if capturedFrameCount % 90 == 1 {
                logger.error("Sink writer still not ready after \(self.capturedFrameCount, privacy: .public) frames")
            }
            if !sinkStarted { return }
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }

        let hostTime = CMClockGetTime(CMClockGetHostTimeClock())
        let hostTimeNs = UInt64(hostTime.seconds * Double(NSEC_PER_SEC))
        sink.enqueue(pixelBuffer: pixelBuffer, hostTimeNs: hostTimeNs)
    }
}

extension CameraCaptureSession: VirtualCameraSourceController {
    func setSource(named: String) -> CameraApplyResult {
        guard Self.findDevice(named: named) != nil else {
            return .notFound
        }
        switchSource(toLocalizedName: named)
        return .ok
    }
}
