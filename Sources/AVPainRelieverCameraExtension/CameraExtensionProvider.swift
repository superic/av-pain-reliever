import Foundation
import CoreMediaIO

/// Top-level CMIO Camera Extension provider. Owns exactly one
/// device ("AV Pain Reliever"), which in turn owns one source and
/// one sink stream. macOS instantiates this once per extension
/// process.
final class CameraExtensionProviderSource: NSObject, CMIOExtensionProviderSource {
    private(set) var provider: CMIOExtensionProvider!
    let deviceSource: CameraExtensionDeviceSource

    init(clientQueue: DispatchQueue?) {
        self.deviceSource = CameraExtensionDeviceSource(
            localizedName: "AV Pain Reliever"
        )
        super.init()
        self.provider = CMIOExtensionProvider(source: self, clientQueue: clientQueue)
        do {
            try provider.addDevice(deviceSource.device)
        } catch {
            fatalError("addDevice failed: \(error)")
        }
    }

    func connect(to client: CMIOExtensionClient) throws {}

    func disconnect(from client: CMIOExtensionClient) {}

    var availableProperties: Set<CMIOExtensionProperty> {
        [.providerManufacturer]
    }

    func providerProperties(forProperties properties: Set<CMIOExtensionProperty>)
        throws -> CMIOExtensionProviderProperties
    {
        let p = CMIOExtensionProviderProperties(dictionary: [:])
        if properties.contains(.providerManufacturer) {
            p.manufacturer = "Eric Willis"
        }
        return p
    }

    func setProviderProperties(_ providerProperties: CMIOExtensionProviderProperties)
        throws {}
}
