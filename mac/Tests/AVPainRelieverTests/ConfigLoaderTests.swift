import Testing
import Foundation
@testable import AVPainReliever

@Suite("ConfigLoader")
struct ConfigLoaderTests {
    let loader = ConfigLoader()

    // MARK: - Empty / minimal

    @Test("empty TOML parses to empty profile list")
    func emptyConfig() throws {
        let profiles = try loader.parseProfiles("")
        #expect(profiles.isEmpty)
    }

    @Test("config with no [profiles.*] tables returns empty list")
    func noProfilesTable() throws {
        let profiles = try loader.parseProfiles("# just a comment\n")
        #expect(profiles.isEmpty)
    }

    @Test("a profile with an empty body is loaded with all-nil fields and an empty fingerprint")
    func minimalProfile() throws {
        let profiles = try loader.parseProfiles("""
        [profiles.bare]
        """)
        #expect(profiles.count == 1)
        let p = profiles.first!
        #expect(p.name == "bare")
        #expect(p.fingerprint.isEmpty)
        #expect(p.audioInput == nil)
        #expect(p.audioOutput == nil)
    }

    // MARK: - Full profile

    @Test("a profile with all fields and a fingerprint round-trips into the engine model")
    func fullProfile() throws {
        let profiles = try loader.parseProfiles("""
        [profiles.home-office]
        audioInput  = "Yeti Stereo Microphone"
        audioOutput = "CalDigit Thunderbolt 3 Audio"
        fingerprint = [
          { vendorID = 0x2188, productID = 0x6533, name = "CalDigit Thunderbolt 3 Audio (dock)" },
          { vendorID = 0x043e, productID = 0x9a68, name = "LG UltraFine Display Camera" },
        ]
        """)
        #expect(profiles.count == 1)
        let p = profiles.first!
        #expect(p.name == "home-office")
        #expect(p.audioInput == "Yeti Stereo Microphone")
        #expect(p.audioOutput == "CalDigit Thunderbolt 3 Audio")
        #expect(Set(p.fingerprint) == [
            USBDevice(vendorID: 0x2188, productID: 0x6533),
            USBDevice(vendorID: 0x043e, productID: 0x9a68),
        ])
    }

    @Test("hyphenated profile names round-trip correctly (TOML bare keys allow hyphens)")
    func hyphenatedNames() throws {
        let profiles = try loader.parseProfiles("""
        [profiles.work-office]
        audioInput = "Work Mic"

        [profiles.conference-room]
        audioInput = "Conference Mic"
        """)
        let names = Set(profiles.map(\.name))
        #expect(names == ["work-office", "conference-room"])
    }

    @Test("legacy obsScene field in existing TOML is silently ignored")
    func ignoresUnknownObsSceneField() throws {
        // Users migrated from the Hammerspoon Phase 1 setup may have
        // obsScene fields persisted in their TOML. The V1 Swift app
        // doesn't support OBS — Codable's "unknown keys are tolerated"
        // default means we read past those without error.
        let profiles = try loader.parseProfiles("""
        [profiles.home-office]
        audioInput = "Yeti"
        obsScene   = "Home Office"
        """)
        #expect(profiles.count == 1)
        #expect(profiles.first?.audioInput == "Yeti")
    }

    @Test("serialNumber is read from TOML when present and stays nil when absent")
    func serialNumberFromTOML() throws {
        let profiles = try loader.parseProfiles("""
        [profiles.home-office]
        fingerprint = [
          { vendorID = 0x1, productID = 0x2, serialNumber = "HOME-ABC" },
          { vendorID = 0x3, productID = 0x4 },
        ]
        """)
        let p = profiles.first!
        let pinned = p.fingerprint.first { $0.serialNumber != nil }!
        let loose = p.fingerprint.first { $0.serialNumber == nil }!
        #expect(pinned.serialNumber == "HOME-ABC")
        #expect(loose.vendorID == 0x3 && loose.productID == 0x4)
    }

    @Test("decimal vendor/product IDs parse to the same integers as hex")
    func decimalIDs() throws {
        let profiles = try loader.parseProfiles("""
        [profiles.docked]
        fingerprint = [
          { vendorID = 8584, productID = 25907 },
        ]
        """)
        // 0x2188 = 8584, 0x6533 = 25907 — same numbers, different syntax.
        #expect(profiles.first!.fingerprint == [
            USBDevice(vendorID: 0x2188, productID: 0x6533),
        ])
    }

    // MARK: - Multiple profiles

    @Test("multiple profiles all load and are independent")
    func multipleProfiles() throws {
        let profiles = try loader.parseProfiles("""
        [profiles.laptop]
        audioInput  = "MacBook Pro Microphone"
        audioOutput = "MacBook Pro Speakers"

        [profiles.home-office]
        audioInput  = "Yeti Stereo Microphone"
        fingerprint = [
          { vendorID = 0x2188, productID = 0x6533 },
        ]
        """)
        #expect(profiles.count == 2)
        let byName = Dictionary(uniqueKeysWithValues: profiles.map { ($0.name, $0) })
        #expect(byName["laptop"]?.audioInput == "MacBook Pro Microphone")
        #expect(byName["laptop"]?.fingerprint.isEmpty == true)
        #expect(byName["home-office"]?.fingerprint.count == 1)
    }

    // MARK: - Schema tolerance

    @Test("unknown top-level keys are ignored (forward compatibility)")
    func unknownTopLevelKeys() throws {
        let profiles = try loader.parseProfiles("""
        debounceSeconds = 1.5            # not part of the schema yet
        logPath = "/tmp/whatever.log"

        [profiles.laptop]
        audioInput = "MacBook Pro Microphone"
        """)
        #expect(profiles.count == 1)
        #expect(profiles.first?.name == "laptop")
    }

    @Test("unknown keys inside a profile body are ignored")
    func unknownProfileKeys() throws {
        let profiles = try loader.parseProfiles("""
        [profiles.future]
        audioInput = "Yeti"
        wallpaper  = "/path/to/cool.jpg"  # hypothetical future field
        """)
        #expect(profiles.count == 1)
        #expect(profiles.first?.audioInput == "Yeti")
    }

    @Test("config drives the resolver end-to-end (loaded profiles match correctly)")
    func resolverIntegration() throws {
        let profiles = try loader.parseProfiles("""
        [profiles.laptop]
        # implicit fallback: empty fingerprint matches anything

        [profiles.home-office]
        fingerprint = [
          { vendorID = 0x2188, productID = 0x6533 },
          { vendorID = 0x043e, productID = 0x9a68 },
        ]
        """)
        let resolver = ProfileResolver(profiles: profiles)
        let docked: Set<USBDevice> = [
            USBDevice(vendorID: 0x2188, productID: 0x6533),
            USBDevice(vendorID: 0x043e, productID: 0x9a68),
        ]
        #expect(resolver.resolve(attached: docked)?.name == "home-office")
        #expect(resolver.resolve(attached: [])?.name == "laptop")
    }

    // MARK: - Error paths

    @Test("malformed TOML raises a malformed error with a useful message")
    func malformedTOML() {
        do {
            _ = try loader.parseProfiles("[profiles.broken")
            Issue.record("expected parseProfiles to throw")
        } catch let ConfigError.malformed(reason) {
            #expect(!reason.isEmpty)
        } catch {
            Issue.record("expected .malformed but got \(error)")
        }
    }

    @Test("a fingerprint entry missing vendorID raises a schema-violation error")
    func missingFingerprintField() {
        do {
            _ = try loader.parseProfiles("""
            [profiles.broken]
            fingerprint = [
              { productID = 0x6533 },   # missing vendorID
            ]
            """)
            Issue.record("expected parseProfiles to throw")
        } catch ConfigError.schemaViolation {
            // success
        } catch {
            Issue.record("expected .schemaViolation but got \(error)")
        }
    }

    @Test("loadProfiles(from:) reads a file and parses it")
    func loadFromFile() throws {
        let toml = """
        [profiles.from-disk]
        audioInput = "MacBook Pro Microphone"
        """
        let url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("profiles-test-\(UUID().uuidString).toml")
        try toml.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let profiles = try loader.loadProfiles(from: url)
        #expect(profiles.count == 1)
        #expect(profiles.first?.audioInput == "MacBook Pro Microphone")
    }

    @Test("loadProfiles(from:) on a missing file raises an unreadable error")
    func loadFromMissingFile() {
        let url = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString).toml")
        do {
            _ = try loader.loadProfiles(from: url)
            Issue.record("expected loadProfiles to throw")
        } catch ConfigError.unreadable {
            // success
        } catch {
            Issue.record("expected .unreadable but got \(error)")
        }
    }
}
