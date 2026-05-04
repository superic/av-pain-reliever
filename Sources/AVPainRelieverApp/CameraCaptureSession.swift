import Foundation
import AVFoundation
import CoreVideo
import os.log

private let logger = Logger(
    subsystem: "com.ericwillis.avpainreliever",
    category: "CameraCaptureSession"
)

/// Captures from the built-in webcam (hardcoded for M2 dev) and
/// hands each frame to `CMIOSinkWriter`, which enqueues it on the
/// virtual camera's sink stream.
///
/// The host app is a normal user-process AVFoundation client — no
/// sandbox, no recursion through CMIO. TCC permission for the
/// camera is granted to the host on first use; the extension never
/// touches AVFoundation.
///
/// M3 will replace the hardcoded `.builtInWideAngleCamera` lookup
/// with profile-driven source-camera switching. M4 will add
/// "should we be capturing right now" lifecycle awareness so the
/// camera light only comes on when an AVCapture client actually
/// has the virtual camera open.
final class CameraCaptureSession: NSObject {
    private let session = AVCaptureSession()
    private let captureQueue = DispatchQueue(
        label: "com.ericwillis.avpainreliever.host.capture",
        qos: .userInteractive
    )
    private let sink: CMIOSinkWriter
    private var sinkStarted = false
    private var capturedFrameCount: UInt64 = 0

    init(sink: CMIOSinkWriter) {
        self.sink = sink
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
    /// Failures are logged; M2 doesn't surface them through any UI.
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

        guard
            let device = AVCaptureDevice.default(
                .builtInWideAngleCamera,
                for: .video,
                position: .unspecified
            )
        else {
            logger.error("No built-in wide-angle camera found")
            return
        }
        logger.info("Found capture device: \(device.localizedName, privacy: .public) (\(device.uniqueID, privacy: .public))")

        session.beginConfiguration()
        session.sessionPreset = .hd1280x720

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                logger.error("Cannot add camera input")
                session.commitConfiguration()
                return
            }
            session.addInput(input)
        } catch {
            logger.error("AVCaptureDeviceInput failed: \(error.localizedDescription, privacy: .public)")
            session.commitConfiguration()
            return
        }

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
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
        session.commitConfiguration()

        logger.info("Calling session.startRunning()")
        session.startRunning()
        logger.info("session.isRunning=\(self.session.isRunning, privacy: .public)")

        sinkStarted = sink.start()
        logger.info("sink.start() returned \(self.sinkStarted, privacy: .public)")
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
