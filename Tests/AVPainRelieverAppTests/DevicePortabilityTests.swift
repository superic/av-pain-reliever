import Testing
@testable import AVPainRelieverApp

@Suite("DevicePortability")
struct DevicePortabilityTests {
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

    @Test("standalone mics, video sources, speakers, and audio gear are flagged with the right pill label")
    func importantHeadlineHardware() {
        // Mics
        #expect(DevicePortability.importantCategory(deviceName: "Yeti Stereo Microphone") == "mic")
        #expect(DevicePortability.importantCategory(deviceName: "Shure MV7 podcast mic") == "mic")
        // Video — cameras AND capture cards both show "video" so the
        // pill vocabulary stays tight (capture cards aren't really
        // cameras but they're video sources from the user's POV).
        #expect(DevicePortability.importantCategory(deviceName: "FaceTime HD Camera") == "video")
        #expect(DevicePortability.importantCategory(deviceName: "Logitech webcam") == "video")
        #expect(DevicePortability.importantCategory(deviceName: "HDMI to U3 capture") == "video")
        // Speakers
        #expect(DevicePortability.importantCategory(deviceName: "Audioengine A2+ Speakers") == "speaker")
        // Catch-all "audio" — dedicated audio gear that isn't
        // obviously a mic/speaker.
        #expect(DevicePortability.importantCategory(deviceName: "CalDigit Thunderbolt 3 Audio") == "audio")
        #expect(DevicePortability.importantCategory(deviceName: "External DAC") == "audio")
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
