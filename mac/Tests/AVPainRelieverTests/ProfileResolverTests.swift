import Testing
@testable import AVPainReliever

@Suite("ProfileResolver")
struct ProfileResolverTests {
    // MARK: - Fixture devices (drawn from the engine's actual snapshot)

    static let caldigitDock = USBDevice(vendorID: 0x2188, productID: 0x6533)
    static let lgUltraFineCamera = USBDevice(vendorID: 0x043e, productID: 0x9a68)
    static let yetiMic = USBDevice(vendorID: 0x046d, productID: 0x0ab7)
    static let streamDeck = USBDevice(vendorID: 0x0fd9, productID: 0x0080)

    // MARK: - Fixture profiles

    static let laptop = Profile(name: "laptop", fingerprint: [])

    static let homeOffice = Profile(name: "home-office", fingerprint: [
        caldigitDock,
        lgUltraFineCamera,
    ])

    /// Same-prefix profile sharing the dock signature, deliberately
    /// alphabetically *after* `home-office`. Used to exercise the
    /// "more specific wins regardless of name" rule.
    static let homeOfficeStudio = Profile(name: "home-office-studio", fingerprint: [
        caldigitDock,
        lgUltraFineCamera,
        yetiMic,
        streamDeck,
    ])

    /// Conference room shares the dock with home-office (1 device);
    /// ties on specificity should resolve to `conference-room`
    /// alphabetically.
    static let conferenceRoom = Profile(name: "conference-room", fingerprint: [
        caldigitDock,
    ])

    // MARK: - Tests

    @Test("returns nil when no profiles configured")
    func emptyProfileList() {
        let resolver = ProfileResolver(profiles: [])
        #expect(resolver.resolve(attached: []) == nil)
        #expect(resolver.resolve(attached: [Self.caldigitDock]) == nil)
    }

    @Test("empty fingerprint matches any state with specificity 0")
    func emptyFingerprintAlwaysMatches() {
        let resolver = ProfileResolver(profiles: [Self.laptop])
        #expect(resolver.resolve(attached: [])?.name == "laptop")
        #expect(resolver.resolve(attached: [Self.yetiMic])?.name == "laptop")
    }

    @Test("a more specific match beats the empty-fingerprint fallback")
    func specificBeatsFallback() {
        let resolver = ProfileResolver(profiles: [Self.laptop, Self.homeOffice])
        let attached: Set<USBDevice> = [Self.caldigitDock, Self.lgUltraFineCamera]
        #expect(resolver.resolve(attached: attached)?.name == "home-office")
    }

    @Test("falls back to empty-fingerprint profile when nothing else matches")
    func fallbackWhenNoSpecificMatch() {
        let resolver = ProfileResolver(profiles: [Self.laptop, Self.homeOffice])
        // Only the dock is attached — home-office needs the LG camera too.
        #expect(resolver.resolve(attached: [Self.caldigitDock])?.name == "laptop")
    }

    @Test("a profile only matches when ALL fingerprint devices are present")
    func partialMatchDoesNotCount() {
        let resolver = ProfileResolver(profiles: [Self.homeOffice])
        // Missing the LG camera → home-office must NOT match.
        #expect(resolver.resolve(attached: [Self.caldigitDock]) == nil)
    }

    @Test("the most-specific match wins, regardless of alphabetical order")
    func mostSpecificWinsOverAlphabetical() {
        // home-office (2 devices) sorts BEFORE home-office-studio (4
        // devices) alphabetically. With both fully present, the studio
        // profile must still win because it's more specific.
        let resolver = ProfileResolver(profiles: [Self.homeOffice, Self.homeOfficeStudio])
        let attached: Set<USBDevice> = [
            Self.caldigitDock,
            Self.lgUltraFineCamera,
            Self.yetiMic,
            Self.streamDeck,
        ]
        #expect(resolver.resolve(attached: attached)?.name == "home-office-studio")
    }

    @Test("ties on specificity break alphabetically by name")
    func alphabeticalTiebreak() {
        // home-office and conference-room both have specificity 1 when
        // only the dock is attached. conference-room wins
        // alphabetically.
        let oneDeviceHomeOffice = Profile(name: "home-office", fingerprint: [Self.caldigitDock])
        let resolver = ProfileResolver(profiles: [oneDeviceHomeOffice, Self.conferenceRoom])
        #expect(resolver.resolve(attached: [Self.caldigitDock])?.name == "conference-room")
    }

    // MARK: - Serial-number disambiguation

    @Test("a fingerprint entry with a serial only matches that exact serial")
    func serialPinningRestrictsMatch() {
        let pinned = Profile(
            name: "home",
            fingerprint: [USBDevice(vendorID: 0x1, productID: 0x1, serialNumber: "HOME")]
        )
        let resolver = ProfileResolver(profiles: [pinned])

        let workMonitor = USBDevice(vendorID: 0x1, productID: 0x1, serialNumber: "WORK")
        #expect(resolver.resolve(attached: [workMonitor]) == nil)

        let homeMonitor = USBDevice(vendorID: 0x1, productID: 0x1, serialNumber: "HOME")
        #expect(resolver.resolve(attached: [homeMonitor])?.name == "home")
    }

    @Test("a serial-less fingerprint entry matches any unit of the model")
    func serialNilEntryMatchesAnyUnit() {
        let loose = Profile(
            name: "any-dock",
            fingerprint: [USBDevice(vendorID: 0x1, productID: 0x1)]
        )
        let resolver = ProfileResolver(profiles: [loose])

        let attached: Set<USBDevice> = [
            USBDevice(vendorID: 0x1, productID: 0x1, serialNumber: "WHATEVER"),
        ]
        #expect(resolver.resolve(attached: attached)?.name == "any-dock")
    }

    @Test("serial disambiguates two locations with the same model")
    func serialDisambiguatesLocations() {
        let home = Profile(
            name: "home-office",
            fingerprint: [USBDevice(vendorID: 0x1, productID: 0x1, serialNumber: "HOME-SERIAL")]
        )
        let work = Profile(
            name: "work-office",
            fingerprint: [USBDevice(vendorID: 0x1, productID: 0x1, serialNumber: "WORK-SERIAL")]
        )
        let resolver = ProfileResolver(profiles: [home, work])

        let homeAttached: Set<USBDevice> = [
            USBDevice(vendorID: 0x1, productID: 0x1, serialNumber: "HOME-SERIAL")
        ]
        let workAttached: Set<USBDevice> = [
            USBDevice(vendorID: 0x1, productID: 0x1, serialNumber: "WORK-SERIAL")
        ]

        #expect(resolver.resolve(attached: homeAttached)?.name == "home-office")
        #expect(resolver.resolve(attached: workAttached)?.name == "work-office")
    }

    @Test("evaluation result is independent of input ordering")
    func orderingIsIrrelevant() {
        // Same data, two construction orders → same result. Guards
        // against accidental dependency on the caller's array order.
        let a = ProfileResolver(profiles: [Self.laptop, Self.homeOffice, Self.homeOfficeStudio])
        let b = ProfileResolver(profiles: [Self.homeOfficeStudio, Self.homeOffice, Self.laptop])
        let attached: Set<USBDevice> = [
            Self.caldigitDock,
            Self.lgUltraFineCamera,
            Self.yetiMic,
            Self.streamDeck,
        ]
        #expect(a.resolve(attached: attached)?.name == b.resolve(attached: attached)?.name)
        #expect(a.resolve(attached: attached)?.name == "home-office-studio")
    }
}
