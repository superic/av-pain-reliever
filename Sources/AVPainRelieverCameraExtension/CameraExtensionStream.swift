import Foundation
import CoreMediaIO
import CoreMedia
import CoreVideo

/// Vends video frames downstream to whichever AVCapture client has
/// the virtual camera open (Zoom, FaceTime, Slack, etc.).
///
/// Current implementation: emits a black 1280×720 BGRA frame at
/// 30 fps. The pixel buffer pool is allocated once per
/// stream-start and reused for every frame.
///
/// Why no AVCaptureSession in this file: a CMIO Camera Extension
/// CANNOT use AVFoundation to capture from physical cameras
/// without triggering an IOKit-level deadlock — AVFoundation's
/// device enumeration walks the CMIO device list, which includes
/// the very extension making the call, and concurrent client apps
/// (e.g. Photo Booth) wedge waiting on the loop. The supported
/// pattern (used by OBS, mmhmm, Hand Mirror, Camo, etc.) is to
/// capture in the host app and forward frames to the extension
/// over XPC. That work lives in M3 of the V2 plan; until M3
/// lands, this stream stays a black-frame placeholder.
final class CameraExtensionStreamSource: NSObject, CMIOExtensionStreamSource {
    private(set) var stream: CMIOExtensionStream!
    private let streamFormat: CMIOExtensionStreamFormat

    private var timer: DispatchSourceTimer?
    private let timerQueue = DispatchQueue(
        label: "com.ericwillis.avpainreliever.cameraext.framepump",
        qos: .userInteractive
    )
    private var pixelBufferPool: CVPixelBufferPool?
    private var sequenceNumber: UInt64 = 0

    static let frameWidth: Int32 = 1280
    static let frameHeight: Int32 = 720
    static let frameDuration = CMTime(value: 1, timescale: 30)

    static func standardFormat() -> CMIOExtensionStreamFormat {
        var formatDescription: CMFormatDescription?
        CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCVPixelFormatType_32BGRA,
            width: frameWidth,
            height: frameHeight,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )
        return CMIOExtensionStreamFormat(
            formatDescription: formatDescription!,
            maxFrameDuration: frameDuration,
            minFrameDuration: frameDuration,
            validFrameDurations: nil
        )
    }

    init(
        localizedName: String,
        streamID: UUID,
        streamFormat: CMIOExtensionStreamFormat
    ) {
        self.streamFormat = streamFormat
        super.init()
        self.stream = CMIOExtensionStream(
            localizedName: localizedName,
            streamID: streamID,
            direction: .source,
            clockType: .hostTime,
            source: self
        )
    }

    var formats: [CMIOExtensionStreamFormat] { [streamFormat] }

    var availableProperties: Set<CMIOExtensionProperty> {
        [.streamActiveFormatIndex, .streamFrameDuration]
    }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>)
        throws -> CMIOExtensionStreamProperties
    {
        let p = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) {
            p.activeFormatIndex = 0
        }
        if properties.contains(.streamFrameDuration) {
            p.frameDuration = Self.frameDuration
        }
        return p
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties)
        throws {}

    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool { true }

    func startStream() throws {
        try ensurePixelBufferPool()
        sequenceNumber = 0

        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: timerQueue)
        let interval = DispatchTimeInterval.nanoseconds(
            Int(1_000_000_000.0 / 30.0)
        )
        timer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in
            self?.emitFrame()
        }
        self.timer = timer
        timer.resume()
    }

    func stopStream() throws {
        timer?.cancel()
        timer = nil
    }

    private func ensurePixelBufferPool() throws {
        if pixelBufferPool != nil { return }
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Self.frameWidth,
            kCVPixelBufferHeightKey as String: Self.frameHeight,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ]
        var pool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            nil,
            attrs as CFDictionary,
            &pool
        )
        guard status == kCVReturnSuccess, let pool else {
            throw NSError(
                domain: "AVPainRelieverCameraExtension",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "CVPixelBufferPoolCreate failed"]
            )
        }
        self.pixelBufferPool = pool
    }

    private func emitFrame() {
        guard let pool = pixelBufferPool else { return }
        var pixelBuffer: CVPixelBuffer?
        guard
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
                == kCVReturnSuccess,
            let pixelBuffer
        else { return }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            memset(base, 0, bytesPerRow * height)
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

        var formatDescription: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        guard let formatDescription else { return }

        let timestamp = CMClockGetTime(CMClockGetHostTimeClock())
        var timing = CMSampleTimingInfo(
            duration: Self.frameDuration,
            presentationTimeStamp: timestamp,
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        let createStatus = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        guard createStatus == noErr, let sampleBuffer else { return }

        sequenceNumber &+= 1
        stream.send(
            sampleBuffer,
            discontinuity: [],
            hostTimeInNanoseconds: UInt64(timestamp.seconds * Double(NSEC_PER_SEC))
        )
    }
}
