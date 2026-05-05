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

    // MARK: - Important pill classifier
    //
    // The headline-hardware classifier the wizard uses to render
    // its green "Important: <category>" pill. Tighter than
    // "anything that could matter" — display sub-components are
    // explicitly excluded so the pill stays visually distinct on
    // sophisticated docks.

    @Test("standalone mics, cameras, capture cards, and audio interfaces are flagged")
    func importantHeadlineHardware() {
        #expect(DevicePortability.importantCategory(deviceName: "Yeti Stereo Microphone") == "microphone")
        #expect(DevicePortability.importantCategory(deviceName: "Shure MV7 podcast mic") == "microphone")
        #expect(DevicePortability.importantCategory(deviceName: "FaceTime HD Camera") == "camera")
        #expect(DevicePortability.importantCategory(deviceName: "Logitech webcam") == "camera")
        #expect(DevicePortability.importantCategory(deviceName: "HDMI to U3 capture") == "capture card")
        #expect(DevicePortability.importantCategory(deviceName: "CalDigit Thunderbolt 3 Audio") == "audio interface")
        #expect(DevicePortability.importantCategory(deviceName: "External DAC") == "audio interface")
    }

    @Test("display sub-components are NOT flagged as Important")
    func importantExcludesDisplaySubcomponents() {
        // The LG UltraFine line exposes its built-in audio,
        // camera, and HID controls as separate USB devices. They
        // are real, functional devices but they're not the
        // dedicated hardware most users default to. Excluding
        // them keeps the Important pill exclusive on docks
        // where the user has both a monitor and dedicated
        // peripherals.
        #expect(DevicePortability.importantCategory(deviceName: "LG UltraFine Display Audio") == nil)
        #expect(DevicePortability.importantCategory(deviceName: "LG UltraFine Display Camera") == nil)
        #expect(DevicePortability.importantCategory(deviceName: "LG UltraFine Display Controls") == nil)
        // Generic "Display" prefixing also excludes:
        #expect(DevicePortability.importantCategory(deviceName: "Pro Display XDR Speakers") == nil)
    }

    @Test("Important and portability classifiers are mutually exclusive")
    func importantAndPortableMutuallyExclusive() {
        // A device that's flagged portable (Magic Trackpad,
        // iPhone, etc.) must NOT also be flagged Important.
        // The pill UI assumes mutual exclusivity — the row's
        // pill slot only holds one tag.
        let portableNames = ["Magic Keyboard", "Magic Trackpad", "iPhone", "AirPods", "Apple Watch"]
        for name in portableNames {
            #expect(DevicePortability.portabilityCategory(deviceName: name) != nil)
            #expect(DevicePortability.importantCategory(deviceName: name) == nil)
        }
    }

    @Test("nil and empty names yield nil Important")
    func importantNilEmpty() {
        #expect(DevicePortability.importantCategory(deviceName: nil) == nil)
        #expect(DevicePortability.importantCategory(deviceName: "") == nil)
    }

    @Test("hub legs and generic peripherals don't get the Important pill")
    func importantSkipsGenericPeripherals() {
        #expect(DevicePortability.importantCategory(deviceName: "USB2.1 Hub") == nil)
        #expect(DevicePortability.importantCategory(deviceName: "Stream Deck MK.2") == nil)
        #expect(DevicePortability.importantCategory(deviceName: "Card Reader") == nil)
    }
}
