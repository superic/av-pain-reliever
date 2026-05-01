import Testing
import Foundation
@testable import AVPainReliever

@Suite("ConfigImporter")
struct ConfigImporterTests {
    let importer = ConfigImporter()

    // MARK: - Minimal parse

    @Test("a single profile with all fields parses correctly")
    func minimalSingleProfile() throws {
        let lua = """
        return {
          ["home-office"] = {
            fingerprint = {
              { vendorID = 0x2188, productID = 0x6533, name = "CalDigit dock" },
              { vendorID = 0x043e, productID = 0x9a68, name = "LG camera" },
            },
            audioInput  = "Yeti Stereo Microphone",
            audioOutput = "CalDigit Thunderbolt 3 Audio",
            obsScene    = "Home Office",
          },
        }
        """
        let profiles = try importer.parse(lua)
        #expect(profiles.count == 1)
        let p = profiles[0]
        #expect(p.name == "home-office")
        #expect(p.audioInput == "Yeti Stereo Microphone")
        #expect(p.audioOutput == "CalDigit Thunderbolt 3 Audio")
        #expect(p.obsScene == "Home Office")
        #expect(Set(p.fingerprint) == [
            USBDevice(vendorID: 0x2188, productID: 0x6533),
            USBDevice(vendorID: 0x043e, productID: 0x9a68),
        ])
    }

    @Test("a profile with empty fingerprint parses to an empty list")
    func emptyFingerprint() throws {
        let lua = """
        return {
          ["laptop"] = {
            fingerprint = { },
            audioInput  = "MacBook Pro Microphone",
            audioOutput = "MacBook Pro Speakers",
            obsScene    = "Laptop",
          },
        }
        """
        let profiles = try importer.parse(lua)
        #expect(profiles.first?.fingerprint.isEmpty == true)
    }

    @Test("multiple profiles all parse and are independent")
    func multipleProfiles() throws {
        let lua = """
        return {
          ["laptop"] = {
            fingerprint = { },
            audioInput  = "MacBook Pro Microphone",
            audioOutput = "MacBook Pro Speakers",
            obsScene    = "Laptop",
          },
          ["home-office"] = {
            fingerprint = {
              { vendorID = 0x2188, productID = 0x6533 },
            },
            audioInput  = "Yeti",
            audioOutput = "CalDigit",
            obsScene    = "Home Office",
          },
        }
        """
        let profiles = try importer.parse(lua)
        #expect(profiles.count == 2)
        let byName = Dictionary(uniqueKeysWithValues: profiles.map { ($0.name, $0) })
        #expect(byName["laptop"]?.audioInput == "MacBook Pro Microphone")
        #expect(byName["home-office"]?.fingerprint.count == 1)
    }

    // MARK: - Lua syntax tolerance

    @Test("hex and decimal vendor/product IDs both parse to the same Int")
    func hexAndDecimalIDs() throws {
        let lua = """
        return {
          ["hex"] = {
            fingerprint = { { vendorID = 0x2188, productID = 0x6533 } },
            obsScene = "Hex",
          },
          ["dec"] = {
            fingerprint = { { vendorID = 8584, productID = 25907 } },
            obsScene = "Dec",
          },
        }
        """
        let profiles = try importer.parse(lua)
        let hex = profiles.first { $0.name == "hex" }!
        let dec = profiles.first { $0.name == "dec" }!
        #expect(hex.fingerprint == dec.fingerprint)
    }

    @Test("comments anywhere are ignored")
    func commentsIgnored() throws {
        let lua = """
        -- top-level comment
        return {                             -- inline at brace
          -- before profile
          ["laptop"] = {                     -- inline at profile open
            fingerprint = {
              -- inside fingerprint
            },
            audioInput  = "MacBook Pro Microphone", -- trailing comment
            -- between fields
            obsScene    = "Laptop",
          }, -- after profile close
        } -- end
        """
        let profiles = try importer.parse(lua)
        #expect(profiles.count == 1)
        #expect(profiles.first?.audioInput == "MacBook Pro Microphone")
        #expect(profiles.first?.obsScene == "Laptop")
    }

    @Test("string values containing `--` are not treated as comments")
    func dashesInsideStrings() throws {
        let lua = """
        return {
          ["weird"] = {
            fingerprint = { },
            audioInput = "My Mic -- with dashes",
          },
        }
        """
        let profiles = try importer.parse(lua)
        #expect(profiles.first?.audioInput == "My Mic -- with dashes")
    }

    @Test("profiles with only some fields present have nils for the rest")
    func partialFields() throws {
        let lua = """
        return {
          ["audio-only"] = {
            fingerprint = { },
            audioInput = "Yeti",
          },
        }
        """
        let profiles = try importer.parse(lua)
        let p = profiles.first!
        #expect(p.audioInput == "Yeti")
        #expect(p.audioOutput == nil)
        #expect(p.obsScene == nil)
    }

    // MARK: - End-to-end (importer → TOML → ConfigLoader → Profile)

    @Test("Lua → TOML → ConfigLoader round-trip preserves engine-relevant data")
    func luaToTomlRoundTrip() throws {
        let lua = """
        return {
          ["laptop"] = {
            fingerprint = { },
            audioInput  = "MacBook Pro Microphone",
            audioOutput = "MacBook Pro Speakers",
            obsScene    = "Laptop",
          },
          ["home-office"] = {
            fingerprint = {
              { vendorID = 0x2188, productID = 0x6533, name = "CalDigit dock" },
              { vendorID = 0x043e, productID = 0x9a68, name = "LG camera" },
            },
            audioInput  = "Yeti Stereo Microphone",
            audioOutput = "CalDigit Thunderbolt 3 Audio",
            obsScene    = "Home Office",
          },
        }
        """
        let toml = try importer.convertToTOML(lua)
        let loaded = try ConfigLoader().parseProfiles(toml)
        let direct = try importer.parse(lua)

        #expect(Set(loaded.map(\.name)) == Set(direct.map(\.name)))
        let loadedByName = Dictionary(uniqueKeysWithValues: loaded.map { ($0.name, $0) })
        let directByName = Dictionary(uniqueKeysWithValues: direct.map { ($0.name, $0) })
        for name in loadedByName.keys {
            let l = loadedByName[name]!
            let d = directByName[name]!
            #expect(l.audioInput == d.audioInput)
            #expect(l.audioOutput == d.audioOutput)
            #expect(l.obsScene == d.obsScene)
            #expect(Set(l.fingerprint) == Set(d.fingerprint))
        }
    }

    @Test("emitted TOML preserves fingerprint device names")
    func tomlPreservesNames() throws {
        let lua = """
        return {
          ["home-office"] = {
            fingerprint = {
              { vendorID = 0x2188, productID = 0x6533, name = "CalDigit dock" },
            },
            obsScene = "Home Office",
          },
        }
        """
        let toml = try importer.convertToTOML(lua)
        #expect(toml.contains("name = \"CalDigit dock\""))
    }

    // MARK: - Real-world profiles.lua from this repo

    @Test("the wizard's profiles.lua at the repo root parses cleanly")
    func realWorldProfilesLua() throws {
        // Find the repo root from the test bundle. Tests run from
        // `mac/.build/...`, so walk up to the repo and read the
        // profiles.lua there. If the layout ever moves, this test will
        // fail loudly.
        let here = URL(fileURLWithPath: #filePath)
        // ConfigImporterTests.swift → AVPainRelieverTests/ → Tests/ → mac/ → repo root
        let repoRoot = here
            .deletingLastPathComponent() // AVPainRelieverTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // mac/
            .deletingLastPathComponent() // repo root
        let profilesLua = repoRoot.appendingPathComponent("profiles.lua")

        let lua = try String(contentsOf: profilesLua, encoding: .utf8)
        let profiles = try importer.parse(lua)

        // The wizard ships with four named profile slots; verify they
        // all arrived. (Some have empty fingerprints — those are
        // user-pending entries the wizard generated, not data
        // corruption.)
        let names = Set(profiles.map(\.name))
        #expect(names.contains("laptop"))
        #expect(names.contains("home-office"))
        #expect(names.contains("work-office"))
        #expect(names.contains("conference-room"))

        // home-office should carry the dock + camera fingerprint that
        // matches Eric's actual setup (per the engine's snapshot log).
        let homeOffice = profiles.first { $0.name == "home-office" }!
        #expect(Set(homeOffice.fingerprint) == [
            USBDevice(vendorID: 0x2188, productID: 0x6533),
            USBDevice(vendorID: 0x043e, productID: 0x9a68),
        ])
        #expect(homeOffice.audioInput == "Yeti Stereo Microphone")
        #expect(homeOffice.audioOutput == "CalDigit Thunderbolt 3 Audio")
        #expect(homeOffice.obsScene == "Home Office")
    }

    // MARK: - encodeTOML directly (no Lua input)

    @Test("encodeTOML(profiles:) emits parseable TOML for the engine model")
    func encodeProfilesDirectly() throws {
        let profiles = [
            Profile(
                name: "laptop",
                fingerprint: [],
                audioInput: "MacBook Pro Microphone",
                audioOutput: "MacBook Pro Speakers",
                obsScene: "Laptop"
            ),
            Profile(
                name: "home-office",
                fingerprint: [
                    USBDevice(vendorID: 0x2188, productID: 0x6533),
                ],
                audioInput: "Yeti",
                audioOutput: "CalDigit",
                obsScene: "Home Office"
            ),
        ]
        let toml = importer.encodeTOML(profiles)
        let reloaded = try ConfigLoader().parseProfiles(toml)
        #expect(Set(reloaded.map(\.name)) == ["laptop", "home-office"])
    }

    @Test("encodeTOML output is sorted by profile name for deterministic diffs")
    func encodeIsSorted() {
        let profiles = [
            Profile(name: "zebra", fingerprint: []),
            Profile(name: "alpha", fingerprint: []),
            Profile(name: "mango", fingerprint: []),
        ]
        let toml = importer.encodeTOML(profiles)
        let alphaIdx = toml.range(of: "[profiles.alpha]")!.lowerBound
        let mangoIdx = toml.range(of: "[profiles.mango]")!.lowerBound
        let zebraIdx = toml.range(of: "[profiles.zebra]")!.lowerBound
        #expect(alphaIdx < mangoIdx)
        #expect(mangoIdx < zebraIdx)
    }

    // MARK: - Errors

    @Test("source with no `return` keyword raises a syntax error")
    func missingReturn() {
        do {
            _ = try importer.parse("local x = 1")
            Issue.record("expected parse to throw")
        } catch ImporterError.syntax {
            // success
        } catch {
            Issue.record("expected .syntax but got \(error)")
        }
    }

    @Test("a fingerprint entry missing vendorID raises a missing-field error")
    func missingFingerprintField() {
        let lua = """
        return {
          ["broken"] = {
            fingerprint = {
              { productID = 0x6533 },
            },
          },
        }
        """
        do {
            _ = try importer.parse(lua)
            Issue.record("expected parse to throw")
        } catch let ImporterError.missingFingerprintField(profile, field) {
            #expect(profile == "broken")
            #expect(field == "vendorID")
        } catch {
            Issue.record("expected .missingFingerprintField but got \(error)")
        }
    }
}
