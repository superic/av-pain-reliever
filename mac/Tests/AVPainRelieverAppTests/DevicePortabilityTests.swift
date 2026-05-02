import Testing
@testable import AVPainRelieverApp

@Suite("DevicePortability")
struct DevicePortabilityTests {
    @Test("Magic Keyboard / Magic Mouse are flagged as portable")
    func magicAccessoriesFlagged() {
        #expect(DevicePortability.isLikelyPortable(deviceName: "Magic Keyboard"))
        #expect(DevicePortability.isLikelyPortable(deviceName: "Magic Mouse"))
        #expect(DevicePortability.isLikelyPortable(deviceName: "Magic Trackpad 2"))
    }

    @Test("phones and wearables are flagged")
    func phonesFlagged() {
        #expect(DevicePortability.isLikelyPortable(deviceName: "Eric's iPhone"))
        #expect(DevicePortability.isLikelyPortable(deviceName: "iPad Pro"))
        #expect(DevicePortability.isLikelyPortable(deviceName: "AirPods Pro"))
        #expect(DevicePortability.isLikelyPortable(deviceName: "Apple Watch"))
    }

    @Test("docks, monitors, and audio interfaces are NOT flagged")
    func locationStableNotFlagged() {
        #expect(!DevicePortability.isLikelyPortable(deviceName: "CalDigit Thunderbolt 3 Audio"))
        #expect(!DevicePortability.isLikelyPortable(deviceName: "LG UltraFine Display Camera"))
        #expect(!DevicePortability.isLikelyPortable(deviceName: "Yeti Stereo Microphone"))
        #expect(!DevicePortability.isLikelyPortable(deviceName: "Shure MV7"))
        #expect(!DevicePortability.isLikelyPortable(deviceName: "External DAC"))
    }

    @Test("nil and empty names are not flagged (hub legs stay in)")
    func nilOrEmptyStaysIn() {
        #expect(!DevicePortability.isLikelyPortable(deviceName: nil))
        #expect(!DevicePortability.isLikelyPortable(deviceName: ""))
    }

    @Test("category labels classify correctly")
    func categoryLabels() {
        #expect(DevicePortability.portabilityCategory(deviceName: "Magic Keyboard") == "keyboard")
        #expect(DevicePortability.portabilityCategory(deviceName: "Magic Mouse") == "pointing device")
        #expect(DevicePortability.portabilityCategory(deviceName: "iPhone") == "phone / wearable")
        #expect(DevicePortability.portabilityCategory(deviceName: "AirPods") == "phone / wearable")
        #expect(DevicePortability.portabilityCategory(deviceName: "Sony WH-1000XM headphones") == "headphones")
        #expect(DevicePortability.portabilityCategory(deviceName: "Apple Watch") == "watch")
        #expect(DevicePortability.portabilityCategory(deviceName: "CalDigit") == nil)
    }
}
