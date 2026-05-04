import Foundation
import CoreMediaIO
import CoreMedia

/// The .sink direction stream — what the host app writes to via
/// `CMSimpleQueueEnqueue`. Despite the protocol name
/// `CMIOExtensionStreamSource`, this stream is a sink (consumer of
/// frames), not a source. Naming inherited from CMIO.
///
/// The host opens "AV Pain Reliever" as a CMIO device, finds this
/// stream, gets its `CMSimpleQueue` via `CMIOStreamCopyBufferQueue`,
/// then calls `CMIODeviceStartStream` and starts enqueueing
/// `CMSampleBuffer`s. The kernel's CMIO subsystem handles
/// cross-process IOSurface sharing — no XPC needed.
///
/// `CameraExtensionDeviceSource` reads frames out of here via
/// `stream.consumeSampleBuffer(from: client)` and forwards each
/// to the source stream that AVCapture clients watch.
final class CameraExtensionStreamSink: NSObject, CMIOExtensionStreamSource {
    private(set) var stream: CMIOExtensionStream!
    private let streamFormat: CMIOExtensionStreamFormat
    weak var device: CameraExtensionDeviceSource?

    /// The CMIO client that started this sink. Captured in
    /// `authorizedToStartStream` so the device source can pass it
    /// to `consumeSampleBuffer(from:)`.
    var client: CMIOExtensionClient?

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
            direction: .sink,
            clockType: .hostTime,
            source: self
        )
    }

    var formats: [CMIOExtensionStreamFormat] { [streamFormat] }

    var availableProperties: Set<CMIOExtensionProperty> {
        [
            .streamActiveFormatIndex,
            .streamFrameDuration,
            .streamSinkBufferQueueSize,
            .streamSinkBuffersRequiredForStartup,
            .streamSinkBufferUnderrunCount,
            .streamSinkEndOfData,
        ]
    }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>)
        throws -> CMIOExtensionStreamProperties
    {
        let p = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) {
            p.activeFormatIndex = 0
        }
        if properties.contains(.streamFrameDuration) {
            p.frameDuration = CameraExtensionStreamSource.frameDuration
        }
        // Queue size of 1 keeps latency minimal — we drain on every
        // consume tick, no need to buffer more.
        if properties.contains(.streamSinkBufferQueueSize) {
            p.sinkBufferQueueSize = 1
        }
        if properties.contains(.streamSinkBuffersRequiredForStartup) {
            p.sinkBuffersRequiredForStartup = 1
        }
        return p
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties)
        throws {}

    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
        self.client = client
        return true
    }

    func startStream() throws {
        guard let client else { return }
        device?.sinkStartedStreaming(client: client)
    }

    func stopStream() throws {
        device?.sinkStoppedStreaming()
        client = nil
    }
}
