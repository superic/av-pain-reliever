import Foundation
import CoreMediaIO
import IOKit.audio

/// The single virtual camera device registered by this extension.
/// Identifier and name are stable so reinstalls don't churn the
/// device registry — apps that remember "AV Pain Reliever" by
/// uniqueID continue to find it after a v0.2.x → v0.2.y upgrade.
final class CameraExtensionDeviceSource: NSObject, CMIOExtensionDeviceSource {
    private(set) var device: CMIOExtensionDevice!
    private(set) var streamSource: CameraExtensionStreamSource!

    // Stable UUIDs. Generated once for the lifetime of the project;
    // never regenerate without a clear migration story.
    private static let deviceUUID = UUID(
        uuidString: "B45B7E4D-3F4E-4F4D-9C2A-1B2C3D4E5F60"
    )!
    private static let streamUUID = UUID(
        uuidString: "C7E8F901-2A3B-4C5D-6E7F-8091A2B3C4D5"
    )!

    init(localizedName: String) {
        super.init()
        self.device = CMIOExtensionDevice(
            localizedName: localizedName,
            deviceID: Self.deviceUUID,
            legacyDeviceID: nil,
            source: self
        )
        self.streamSource = CameraExtensionStreamSource(
            localizedName: "\(localizedName).video",
            streamID: Self.streamUUID,
            streamFormat: CameraExtensionStreamSource.standardFormat()
        )
        do {
            try device.addStream(streamSource.stream)
        } catch {
            fatalError("addStream failed: \(error)")
        }
    }

    var availableProperties: Set<CMIOExtensionProperty> {
        [.deviceTransportType, .deviceModel]
    }

    func deviceProperties(forProperties properties: Set<CMIOExtensionProperty>)
        throws -> CMIOExtensionDeviceProperties
    {
        let p = CMIOExtensionDeviceProperties(dictionary: [:])
        if properties.contains(.deviceTransportType) {
            // 'virt' FourCC. The constant is named for audio but is
            // the conventional value for any virtual CMIO device —
            // CMIO doesn't ship a video-specific equivalent.
            p.transportType = kIOAudioDeviceTransportTypeVirtual
        }
        if properties.contains(.deviceModel) {
            p.model = "AV Pain Reliever Virtual Camera"
        }
        return p
    }

    func setDeviceProperties(_ deviceProperties: CMIOExtensionDeviceProperties)
        throws {}
}
