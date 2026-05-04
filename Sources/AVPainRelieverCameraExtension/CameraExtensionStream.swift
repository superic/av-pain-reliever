import Foundation
import CoreMediaIO
import CoreMedia

/// The .source direction stream — what AVCapture clients (Zoom,
/// FaceTime, Slack, …) read from. Pure relay endpoint: frames are
/// pushed in by `CameraExtensionDeviceSource` after it consumes
/// them from the sibling sink stream. The host app writes frames
/// to the sink; the device source forwards each consumed frame
/// here via `stream.send(...)`.
final class CameraExtensionStreamSource: NSObject, CMIOExtensionStreamSource {
    private(set) var stream: CMIOExtensionStream!
    private let streamFormat: CMIOExtensionStreamFormat
    weak var device: CameraExtensionDeviceSource?

    /// Number of currently-active CMIO clients reading this stream.
    /// `device` checks this before forwarding consumed frames so we
    /// don't waste cycles encoding when no one's watching.
    private(set) var streamingCounter: UInt32 = 0

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
        streamingCounter += 1
    }

    func stopStream() throws {
        if streamingCounter > 0 { streamingCounter -= 1 }
    }
}
