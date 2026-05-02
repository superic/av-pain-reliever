import Testing
import Foundation
@testable import AVPainReliever

@Suite("ProfileWriter")
struct ProfileWriterTests {
    let writer = ProfileWriter()

    @Test("appended profile round-trips through ConfigLoader")
    func appendRoundTrips() throws {
        let url = tempTOMLURL()
        defer { try? FileManager.default.removeItem(at: url) }

        // Seed with an existing laptop profile (mimics the
        // app's starter config).
        try """
        [profiles.laptop]
        audioInput  = "MacBook Pro Microphone"
        audioOutput = "MacBook Pro Speakers"
        """.write(to: url, atomically: true, encoding: .utf8)

        let homeOffice = Profile(
            name: "home-office",
            fingerprint: [
                USBDevice(vendorID: 0x2188, productID: 0x6533),
                USBDevice(vendorID: 0x043e, productID: 0x9a68),
            ],
            audioInput: "Yeti Stereo Microphone",
            audioOutput: "CalDigit Thunderbolt 3 Audio",
            obsScene: "Home Office"
        )
        try writer.append(profile: homeOffice, to: url)

        let loaded = try ConfigLoader().loadProfiles(from: url)
        #expect(Set(loaded.map(\.name)) == ["laptop", "home-office"])
        let ho = loaded.first { $0.name == "home-office" }!
        #expect(ho.audioInput == "Yeti Stereo Microphone")
        #expect(ho.audioOutput == "CalDigit Thunderbolt 3 Audio")
        #expect(ho.obsScene == "Home Office")
        #expect(Set(ho.fingerprint) == [
            USBDevice(vendorID: 0x2188, productID: 0x6533),
            USBDevice(vendorID: 0x043e, productID: 0x9a68),
        ])
    }

    @Test("appended file preserves prior comments and whitespace")
    func preservesPriorContent() throws {
        let url = tempTOMLURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let prior = """
        # User-added comment at the top.
        [profiles.laptop]
        # Internal comment explaining a choice.
        audioInput = "MacBook Pro Microphone"
        """
        try prior.write(to: url, atomically: true, encoding: .utf8)

        try writer.append(
            profile: Profile(name: "studio", fingerprint: []),
            to: url
        )

        let written = try String(contentsOf: url, encoding: .utf8)
        #expect(written.contains("# User-added comment at the top."))
        #expect(written.contains("# Internal comment explaining a choice."))
        #expect(written.contains("[profiles.studio]"))
    }

    @Test("appending a duplicate profile name raises duplicateProfile")
    func duplicateProfileError() throws {
        let url = tempTOMLURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try """
        [profiles.laptop]
        audioInput = "MacBook Pro Microphone"
        """.write(to: url, atomically: true, encoding: .utf8)

        do {
            try writer.append(
                profile: Profile(name: "laptop", fingerprint: []),
                to: url
            )
            Issue.record("expected append to throw")
        } catch let ProfileWriteError.duplicateProfile(name) {
            #expect(name == "laptop")
        } catch {
            Issue.record("expected .duplicateProfile, got \(error)")
        }
    }

    @Test("appending creates the file (and parent dir) when missing")
    func createsMissingFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("av-pain-reliever-test-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("profiles.toml")
        defer { try? FileManager.default.removeItem(at: dir) }

        try writer.append(
            profile: Profile(
                name: "laptop",
                fingerprint: [],
                audioInput: "Yeti",
                audioOutput: nil,
                obsScene: nil
            ),
            to: url,
            startingHeader: "# Header banner.\n\n"
        )

        let written = try String(contentsOf: url, encoding: .utf8)
        #expect(written.hasPrefix("# Header banner."))
        #expect(written.contains("[profiles.laptop]"))
        #expect(written.contains("audioInput  = \"Yeti\""))
    }

    @Test("serial numbers are emitted into fingerprint entries when present")
    func writesSerialNumbers() throws {
        let url = tempTOMLURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let pinned = USBDevice(
            vendorID: 0x2188,
            productID: 0x6533,
            serialNumber: "HOME-ABC123"
        )
        let loose = USBDevice(vendorID: 0x043e, productID: 0x9a68)
        try writer.append(
            profile: Profile(name: "home", fingerprint: [pinned, loose]),
            to: url
        )

        let written = try String(contentsOf: url, encoding: .utf8)
        #expect(written.contains("serialNumber = \"HOME-ABC123\""))
        // The unpinned entry stays serial-less.
        #expect(written.range(of: "vendorID = 0x043e[^\\n]*serialNumber", options: .regularExpression) == nil)

        // Round-trip the file and verify the serial survives.
        let reloaded = try ConfigLoader().loadProfiles(from: url)
        let reloadedPinned = reloaded.first!.fingerprint.first { $0.serialNumber != nil }!
        let reloadedLoose = reloaded.first!.fingerprint.first { $0.serialNumber == nil }!
        #expect(reloadedPinned.serialNumber == "HOME-ABC123")
        #expect(reloadedLoose.serialNumber == nil)
    }

    @Test("device names are rendered into fingerprint entries when supplied")
    func writesDeviceNames() throws {
        let url = tempTOMLURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let dock = USBDevice(vendorID: 0x2188, productID: 0x6533)
        let camera = USBDevice(vendorID: 0x043e, productID: 0x9a68)
        try writer.append(
            profile: Profile(name: "home", fingerprint: [dock, camera]),
            deviceNames: [dock: "CalDigit Dock", camera: "LG Camera"],
            to: url
        )

        let written = try String(contentsOf: url, encoding: .utf8)
        #expect(written.contains("name = \"CalDigit Dock\""))
        #expect(written.contains("name = \"LG Camera\""))
    }

    @Test("invalid profile names are rejected")
    func invalidNameError() throws {
        let url = tempTOMLURL()
        defer { try? FileManager.default.removeItem(at: url) }
        for bad in ["has spaces", "has.dots", "with/slash", ""] {
            do {
                try writer.append(
                    profile: Profile(name: bad, fingerprint: []),
                    to: url
                )
                Issue.record("expected .invalidName for '\(bad)'")
            } catch ProfileWriteError.invalidName {
                // success
            } catch {
                Issue.record("expected .invalidName for '\(bad)', got \(error)")
            }
        }
    }

    // MARK: - helpers

    private func tempTOMLURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("profile-writer-\(UUID().uuidString).toml")
    }
}
