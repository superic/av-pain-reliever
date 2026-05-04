import Foundation
import CoreMediaIO
import CoreMedia
import CoreVideo

/// Opens the AV Pain Reliever virtual camera as a CMIO consumer
/// and writes frames into its sink stream's `CMSimpleQueue`. The
/// kernel's CMIO subsystem passes those frames (including the
/// underlying IOSurfaces) through to the extension process — no
/// XPC, no sockets, no shared memory plumbing on our side.
///
/// Why raw CMIO instead of AVFoundation: AVFoundation only exposes
/// cameras as *inputs*. The sink stream we're writing to looks
/// like a camera to the system but accepts frames as if it were
/// an output device. The CMIO C API is the only public way to do
/// this writing today.
///
/// Mirrors the pattern OBS uses in its mac-virtualcam plugin
/// (referenced for architecture, not code).
final class CMIOSinkWriter {
    private let deviceUID: String
    private let formatDescription: CMFormatDescription
    private var deviceID: CMIODeviceID = 0
    private var streamID: CMIOStreamID = 0
    private var queue: CMSimpleQueue?

    init(deviceUID: String, width: Int32, height: Int32) {
        self.deviceUID = deviceUID
        var fmt: CMFormatDescription?
        CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCVPixelFormatType_32BGRA,
            width: width,
            height: height,
            extensions: nil,
            formatDescriptionOut: &fmt
        )
        // Force-unwrap is fine — CMVideoFormatDescriptionCreate
        // doesn't fail for legal pixel format / dimensions.
        self.formatDescription = fmt!
    }

    /// Discovers the device, opens its sink stream, primes the
    /// buffer queue, and starts streaming. Returns true on success.
    /// All failures log to stderr and return false — caller decides
    /// whether to retry.
    func start() -> Bool {
        guard let device = findDevice(matchingUID: deviceUID) else {
            NSLog("[AVPR-host] CMIO device with UID \(deviceUID) not found")
            return false
        }
        deviceID = device

        guard let sink = findSinkStream(deviceID: device) else {
            NSLog("[AVPR-host] sink stream not found on device")
            return false
        }
        streamID = sink

        var unmanaged: Unmanaged<CMSimpleQueue>?
        let copyStatus = CMIOStreamCopyBufferQueue(sink, { _, _, _ in }, nil, &unmanaged)
        guard copyStatus == noErr, let unmanaged else {
            NSLog("[AVPR-host] CMIOStreamCopyBufferQueue failed: \(copyStatus)")
            return false
        }
        self.queue = unmanaged.takeRetainedValue()

        let startStatus = CMIODeviceStartStream(device, sink)
        guard startStatus == noErr else {
            NSLog("[AVPR-host] CMIODeviceStartStream failed: \(startStatus)")
            return false
        }

        NSLog("[AVPR-host] CMIOSinkWriter started")
        return true
    }

    func stop() {
        if deviceID != 0 && streamID != 0 {
            CMIODeviceStopStream(deviceID, streamID)
        }
        deviceID = 0
        streamID = 0
        queue = nil
    }

    /// Wraps an incoming pixel buffer in a CMSampleBuffer and
    /// enqueues it. Caller owns the pixel buffer; this method does
    /// NOT retain it long-term — `CMSampleBufferCreateForImageBuffer`
    /// retains internally.
    func enqueue(pixelBuffer: CVPixelBuffer, hostTimeNs: UInt64) {
        guard let queue else { return }

        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMTime(
                value: CMTimeValue(hostTimeNs),
                timescale: CMTimeScale(NSEC_PER_SEC)
            ),
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        guard status == noErr, let sampleBuffer else { return }

        // CMSimpleQueue takes ownership of the enqueued ref. Pass
        // a retained pointer so the queue can release after the
        // consumer takes it.
        let retained = Unmanaged.passRetained(sampleBuffer).toOpaque()
        let enqueueStatus = CMSimpleQueueEnqueue(queue, element: retained)
        if enqueueStatus != noErr {
            // Queue full or otherwise rejected. Reclaim the retain
            // we just gave it so the buffer doesn't leak.
            Unmanaged<CMSampleBuffer>.fromOpaque(retained).release()
        }
    }

    // MARK: - CMIO discovery

    private func findDevice(matchingUID uid: String) -> CMIODeviceID? {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var dataSize: UInt32 = 0
        guard
            CMIOObjectGetPropertyDataSize(
                CMIOObjectID(kCMIOObjectSystemObject),
                &address, 0, nil,
                &dataSize
            ) == noErr,
            dataSize > 0
        else { return nil }

        let count = Int(dataSize) / MemoryLayout<CMIOObjectID>.size
        var devices = [CMIOObjectID](repeating: 0, count: count)
        var dataUsed: UInt32 = 0
        guard
            CMIOObjectGetPropertyData(
                CMIOObjectID(kCMIOObjectSystemObject),
                &address, 0, nil,
                dataSize, &dataUsed,
                &devices
            ) == noErr
        else { return nil }

        for device in devices {
            guard let candidate = copyDeviceUID(deviceID: device) else { continue }
            if candidate.caseInsensitiveCompare(uid) == .orderedSame {
                return device
            }
        }
        return nil
    }

    private func copyDeviceUID(deviceID: CMIODeviceID) -> String? {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceUID),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var size: UInt32 = UInt32(MemoryLayout<CFString>.size)
        var uid: Unmanaged<CFString>?
        let status = CMIOObjectGetPropertyData(
            deviceID, &address, 0, nil, size, &size, &uid
        )
        guard status == noErr, let unmanaged = uid else { return nil }
        return unmanaged.takeRetainedValue() as String
    }

    private func findSinkStream(deviceID: CMIODeviceID) -> CMIOStreamID? {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyStreams),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var dataSize: UInt32 = 0
        guard
            CMIOObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
                == noErr,
            dataSize >= 2 * UInt32(MemoryLayout<CMIOStreamID>.size)
        else { return nil }

        let count = Int(dataSize) / MemoryLayout<CMIOStreamID>.size
        var streams = [CMIOStreamID](repeating: 0, count: count)
        var dataUsed: UInt32 = 0
        guard
            CMIOObjectGetPropertyData(
                deviceID, &address, 0, nil,
                dataSize, &dataUsed, &streams
            ) == noErr
        else { return nil }

        // Index 0 = source (what Zoom reads), index 1 = sink. The
        // extension adds them in this order in
        // `CameraExtensionDeviceSource.init`.
        return streams[1]
    }
}
