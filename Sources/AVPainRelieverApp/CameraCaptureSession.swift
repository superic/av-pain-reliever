import Foundation
import AVFoundation
import CoreVideo

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

    init(sink: CMIOSinkWriter) {
        self.sink = sink
        super.init()
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
        switch status {
        case .authorized:
            installAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                self?.captureQueue.async {
                    if granted {
                        self?.installAndStart()
                    } else {
                        NSLog("[AVPR-host] camera access denied; virtual camera will see no frames")
                    }
                }
            }
        case .denied, .restricted:
            NSLog("[AVPR-host] camera access denied/restricted; virtual camera will see no frames")
        @unknown default:
            NSLog("[AVPR-host] unknown camera authorization status")
        }
    }

    private func installAndStart() {
        guard !session.isRunning else { return }

        guard
            let device = AVCaptureDevice.default(
                .builtInWideAngleCamera,
                for: .video,
                position: .unspecified
            )
        else {
            NSLog("[AVPR-host] no built-in wide-angle camera found")
            return
        }

        session.beginConfiguration()
        session.sessionPreset = .hd1280x720

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                NSLog("[AVPR-host] cannot add camera input")
                session.commitConfiguration()
                return
            }
            session.addInput(input)
        } catch {
            NSLog("[AVPR-host] AVCaptureDeviceInput failed: \(error)")
            session.commitConfiguration()
            return
        }

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            // IOSurface backing — the kernel CMIO subsystem will
            // share these by reference across processes.
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: captureQueue)

        guard session.canAddOutput(output) else {
            NSLog("[AVPR-host] cannot add video output")
            session.commitConfiguration()
            return
        }
        session.addOutput(output)
        session.commitConfiguration()

        session.startRunning()
        NSLog("[AVPR-host] capture session started")

        // Open the sink AFTER the capture session is running, so
        // the first attempt to enqueue has a real frame ready.
        // Retried by the delegate path below if it fails initially
        // (extension may not be activated/enabled yet).
        sinkStarted = sink.start()
    }
}

extension CameraCaptureSession: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // If sink wasn't ready when capture started (extension not
        // yet active), retry every few frames. Cheap — finds the
        // device by UID, opens the stream, primes the queue.
        if !sinkStarted {
            sinkStarted = sink.start()
            if !sinkStarted { return }
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }

        let hostTime = CMClockGetTime(CMClockGetHostTimeClock())
        let hostTimeNs = UInt64(hostTime.seconds * Double(NSEC_PER_SEC))
        sink.enqueue(pixelBuffer: pixelBuffer, hostTimeNs: hostTimeNs)
    }
}
