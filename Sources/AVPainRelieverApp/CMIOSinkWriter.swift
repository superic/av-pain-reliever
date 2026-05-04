import Foundation
import CoreMediaIO
import CoreMedia
import CoreVideo
import os.log

private let logger = Logger(
    subsystem: "com.ericwillis.avpainreliever",
    category: "CMIOSinkWriter"
)

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
    /// All failures log via os.log; caller decides whether to retry.
    func start() -> Bool {
        guard let device = findDevice(matchingUID: deviceUID) else {
            logger.error("CMIO device with UID \(self.deviceUID) not found")
            return false
        }
        deviceID = device
        logger.info("Found device id=\(device, privacy: .public)")

        guard let sink = findSinkStream(deviceID: device) else {
            logger.error("sink stream not found on device")
            return false
        }
        streamID = sink
        logger.info("Picked sink stream id=\(sink, privacy: .public)")

        var unmanaged: Unmanaged<CMSimpleQueue>?
        let copyStatus = CMIOStreamCopyBufferQueue(sink, { _, _, _ in }, nil, &unmanaged)
        guard copyStatus == noErr, let unmanaged else {
            logger.error("CMIOStreamCopyBufferQueue failed: \(copyStatus)")
            return false
        }
        self.queue = unmanaged.takeRetainedValue()

        let startStatus = CMIODeviceStartStream(device, sink)
        guard startStatus == noErr else {
            logger.error("CMIODeviceStartStream failed: \(startStatus)")
            return false
        }

        logger.info("CMIOSinkWriter started successfully")
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

    private var enqueueCount: UInt64 = 0
    private var enqueueRejectCount: UInt64 = 0

    /// Wraps an incoming pixel buffer in a CMSampleBuffer and
    /// enqueues it. Caller owns the pixel buffer; this method does
    /// NOT retain it long-term — `CMSampleBufferCreateForImageBuffer`
    /// retains internally.
    func enqueue(pixelBuffer: CVPixelBuffer, hostTimeNs: UInt64) {
        guard let queue else {
            if enqueueCount == 0 {
                logger.error("enqueue called before queue ready — dropping")
            }
            return
        }

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
        guard status == noErr, let sampleBuffer else {
            logger.error("CMSampleBufferCreateForImageBuffer failed: \(status)")
            return
        }

        // CMSimpleQueue takes ownership of the enqueued ref. Pass
        // a retained pointer so the queue can release after the
        // consumer takes it.
        let retained = Unmanaged.passRetained(sampleBuffer).toOpaque()
        let enqueueStatus = CMSimpleQueueEnqueue(queue, element: retained)
        if enqueueStatus != noErr {
            // Queue full or otherwise rejected. Reclaim the retain
            // we just gave it so the buffer doesn't leak.
            Unmanaged<CMSampleBuffer>.fromOpaque(retained).release()
            enqueueRejectCount += 1
            if enqueueRejectCount % 30 == 1 {
                logger.error(
                    "CMSimpleQueueEnqueue rejected (rejects=\(self.enqueueRejectCount)/\(self.enqueueCount), status=\(enqueueStatus))"
                )
            }
            return
        }

        enqueueCount += 1
        if enqueueCount == 1 || enqueueCount % 60 == 0 {
            logger.info(
                "Enqueued frame #\(self.enqueueCount, privacy: .public) (rejects=\(self.enqueueRejectCount, privacy: .public))"
            )
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
            dataSize > 0
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

        logger.info("Device exposes \(count, privacy: .public) stream(s): \(streams.map(String.init).joined(separator: ", "), privacy: .public)")

        // Don't trust ordering — query each stream's direction
        // property and return the first sink. CMIO assigns IDs in
        // its own order which may not match the order
        // CameraExtensionDeviceSource.init added them.
        for stream in streams {
            if let direction = streamDirection(streamID: stream) {
                logger.info("Stream \(stream, privacy: .public) direction=\(direction, privacy: .public)")
                // direction 0 = output (host → device, i.e. sink)
                // direction 1 = input  (device → host, i.e. source)
                if direction == 0 {
                    return stream
                }
            }
        }
        return nil
    }

    private func streamDirection(streamID: CMIOStreamID) -> UInt32? {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOStreamPropertyDirection),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var direction: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var used: UInt32 = 0
        let status = CMIOObjectGetPropertyData(
            streamID, &address, 0, nil, size, &used, &direction
        )
        return status == noErr ? direction : nil
    }
}
