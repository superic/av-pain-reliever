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
            audioOutput: "CalDigit Thunderbolt 3 Audio"
        )
        try writer.append(profile: homeOffice, to: url)

        let loaded = try ConfigLoader().loadProfiles(from: url)
        #expect(Set(loaded.map(\.name)) == ["laptop", "home-office"])
        let ho = loaded.first { $0.name == "home-office" }!
        #expect(ho.audioInput == "Yeti Stereo Microphone")
        #expect(ho.audioOutput == "CalDigit Thunderbolt 3 Audio")
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
                audioOutput: nil
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

    @Test("replace swaps an existing section in place, preserving the rest")
    func replacePreservesRest() throws {
        let url = tempTOMLURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try """
        # Top-level comment.
        [profiles.laptop]
        audioInput = "MacBook Pro Microphone"

        [profiles.home-office]
        audioInput = "Old Yeti"
        fingerprint = [
          { vendorID = 0x1, productID = 0x1 },
        ]

        [profiles.studio]
        audioInput = "Studio Mic"
        """.write(to: url, atomically: true, encoding: .utf8)

        let updated = Profile(
            name: "home-office",
            fingerprint: [
                USBDevice(vendorID: 0x2188, productID: 0x6533, serialNumber: "ABC"),
            ],
            audioInput: "New Yeti",
            audioOutput: "CalDigit"
        )
        try writer.replace(profile: updated, in: url)

        let written = try String(contentsOf: url, encoding: .utf8)
        // Top-level comment + neighboring sections stay verbatim.
        #expect(written.contains("# Top-level comment."))
        #expect(written.contains("audioInput = \"MacBook Pro Microphone\""))
        #expect(written.contains("audioInput  = \"Studio Mic\"") ||
                written.contains("audioInput = \"Studio Mic\""))
        // The home-office section reflects the new payload.
        #expect(written.contains("audioInput  = \"New Yeti\""))
        #expect(written.contains("audioOutput = \"CalDigit\""))
        #expect(written.contains("serialNumber = \"ABC\""))
        // The old "Old Yeti" string is gone.
        #expect(!written.contains("Old Yeti"))

        // Round-trip: ConfigLoader picks up exactly three profiles.
        let loaded = try ConfigLoader().loadProfiles(from: url)
        #expect(Set(loaded.map(\.name)) == ["laptop", "home-office", "studio"])
        let homeOffice = loaded.first { $0.name == "home-office" }!
        #expect(homeOffice.audioInput == "New Yeti")
        #expect(homeOffice.audioOutput == "CalDigit")
    }

    @Test("nextAvailableName finds the lowest unused suffix")
    func nextAvailableNameSuffixes() throws {
        let url = tempTOMLURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try """
        [profiles.home-office]
        audioInput = "X"

        [profiles.home-office-2]
        audioInput = "Y"
        """.write(to: url, atomically: true, encoding: .utf8)

        #expect(writer.nextAvailableName(base: "home-office", in: url) == "home-office-3")
        #expect(writer.nextAvailableName(base: "studio", in: url) == "studio")
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

    @Test("delete removes the named section, preserving everything else")
    func deleteRemovesSection() throws {
        let url = tempTOMLURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let prior = """
        # User-added top comment.

        [profiles.laptop]
        audioInput = "MacBook Pro Microphone"

        [profiles.home-office]
        audioInput  = "Yeti Stereo Microphone"
        audioOutput = "External DAC"
        fingerprint = [
          { vendorID = 0x2188, productID = 0x6533 },
        ]

        [profiles.studio]
        audioInput = "Shure MV7"
        """
        try prior.write(to: url, atomically: true, encoding: .utf8)

        try writer.delete(named: "home-office", in: url)

        let after = try String(contentsOf: url, encoding: .utf8)
        #expect(after.contains("[profiles.laptop]"))
        #expect(after.contains("[profiles.studio]"))
        #expect(!after.contains("[profiles.home-office]"))
        #expect(after.contains("# User-added top comment."))

        // The remaining file should still parse cleanly through the loader.
        let loaded = try ConfigLoader().loadProfiles(from: url)
        #expect(Set(loaded.map(\.name)) == ["laptop", "studio"])
    }

    @Test("delete on a missing section raises duplicateProfile")
    func deleteOnMissingSectionThrows() throws {
        let url = tempTOMLURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try """
        [profiles.laptop]
        audioInput = "MacBook Pro Microphone"
        """.write(to: url, atomically: true, encoding: .utf8)

        do {
            try writer.delete(named: "home-office", in: url)
            Issue.record("expected duplicateProfile for missing section")
        } catch ProfileWriteError.duplicateProfile {
            // expected
        } catch {
            Issue.record("expected duplicateProfile, got \(error)")
        }
    }

    @Test("delete on a missing file raises writeFailed")
    func deleteOnMissingFileThrows() throws {
        let url = tempTOMLURL()
        // Don't create the file.
        do {
            try writer.delete(named: "laptop", in: url)
            Issue.record("expected writeFailed for missing file")
        } catch ProfileWriteError.writeFailed {
            // expected
        } catch {
            Issue.record("expected writeFailed, got \(error)")
        }
    }

    @Test("icon field round-trips through writer + ConfigLoader")
    func iconRoundTrips() throws {
        let url = tempTOMLURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let withIcon = Profile(
            name: "studio",
            fingerprint: [],
            audioInput: "Shure MV7",
            icon: "music.mic"
        )
        try writer.append(profile: withIcon, to: url)

        let written = try String(contentsOf: url, encoding: .utf8)
        #expect(written.contains("icon        = \"music.mic\""))

        let loaded = try ConfigLoader().loadProfiles(from: url)
        let studio = loaded.first { $0.name == "studio" }!
        #expect(studio.icon == "music.mic")
    }

    @Test("a profile without an icon writes no icon line")
    func iconAbsentWritesNothing() throws {
        let url = tempTOMLURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let plain = Profile(
            name: "laptop",
            fingerprint: [],
            audioInput: "MacBook Pro Microphone"
        )
        try writer.append(profile: plain, to: url)

        let written = try String(contentsOf: url, encoding: .utf8)
        #expect(!written.contains("icon"))

        // ConfigLoader should leave .icon nil when the field is absent.
        let loaded = try ConfigLoader().loadProfiles(from: url)
        #expect(loaded.first { $0.name == "laptop" }?.icon == nil)
    }

    @Test("replace preserves an icon override on a partial update")
    func replaceCarriesIconForward() throws {
        let url = tempTOMLURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try """
        [profiles.home-office]
        audioInput = "Old Yeti"
        icon       = "star.fill"
        """.write(to: url, atomically: true, encoding: .utf8)

        // Caller passes a fresh Profile with the updated icon (the
        // wizard always re-supplies the full profile).
        let updated = Profile(
            name: "home-office",
            fingerprint: [],
            audioInput: "New Yeti",
            icon: "house.fill"
        )
        try writer.replace(profile: updated, in: url)

        let loaded = try ConfigLoader().loadProfiles(from: url)
        let homeOffice = loaded.first { $0.name == "home-office" }!
        #expect(homeOffice.audioInput == "New Yeti")
        #expect(homeOffice.icon == "house.fill")
    }

    @Test("deleted profile can be re-added")
    func deleteThenAppendRoundTrips() throws {
        let url = tempTOMLURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try """
        [profiles.home-office]
        audioInput = "Yeti Stereo Microphone"
        """.write(to: url, atomically: true, encoding: .utf8)

        try writer.delete(named: "home-office", in: url)
        try writer.append(
            profile: Profile(
                name: "home-office",
                fingerprint: [],
                audioInput: "New Mic"
            ),
            to: url
        )
        let loaded = try ConfigLoader().loadProfiles(from: url)
        #expect(loaded.first { $0.name == "home-office" }?.audioInput == "New Mic")
    }

    // MARK: - helpers

    private func tempTOMLURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("profile-writer-\(UUID().uuidString).toml")
    }
}
