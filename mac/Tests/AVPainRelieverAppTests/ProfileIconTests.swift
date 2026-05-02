import Testing
@testable import AVPainRelieverApp

@Suite("ProfileIcon")
struct ProfileIconTests {
    @Test("home* slugs map to house.fill")
    func homeFamilyMapsToHouse() {
        #expect(ProfileIcon.symbol(for: "home") == "house.fill")
        #expect(ProfileIcon.symbol(for: "home-office") == "house.fill")
        #expect(ProfileIcon.symbol(for: "home-2") == "house.fill")
        #expect(ProfileIcon.symbol(for: "Home-Office") == "house.fill")
    }

    @Test("work + office slugs map to building.2.fill")
    func workFamilyMapsToBuilding() {
        #expect(ProfileIcon.symbol(for: "work") == "building.2.fill")
        #expect(ProfileIcon.symbol(for: "work-office") == "building.2.fill")
        #expect(ProfileIcon.symbol(for: "office") == "building.2.fill")
        #expect(ProfileIcon.symbol(for: "downtown-office") == "building.2.fill")
    }

    @Test("conference and meeting slugs map to person.3.fill")
    func conferenceMapsToPeople() {
        #expect(ProfileIcon.symbol(for: "conference") == "person.3.fill")
        #expect(ProfileIcon.symbol(for: "conference-room") == "person.3.fill")
        #expect(ProfileIcon.symbol(for: "team-meeting") == "person.3.fill")
    }

    @Test("studio + podcast slugs map to music.mic")
    func studioMapsToMic() {
        #expect(ProfileIcon.symbol(for: "studio") == "music.mic")
        #expect(ProfileIcon.symbol(for: "podcast-room") == "music.mic")
    }

    @Test("café and coffee slugs map to cup.and.saucer.fill")
    func cafeMapsToCup() {
        #expect(ProfileIcon.symbol(for: "cafe") == "cup.and.saucer.fill")
        #expect(ProfileIcon.symbol(for: "morning-coffee") == "cup.and.saucer.fill")
    }

    @Test("library, garage, and lab map to their dedicated icons")
    func nicheLocationsMap() {
        #expect(ProfileIcon.symbol(for: "library") == "books.vertical.fill")
        #expect(ProfileIcon.symbol(for: "garage") == "car.fill")
        #expect(ProfileIcon.symbol(for: "lab") == "testtube.2")
        #expect(ProfileIcon.symbol(for: "research-lab") == "testtube.2")
    }

    @Test("laptop + undocked map to laptopcomputer")
    func laptopMapsToLaptop() {
        #expect(ProfileIcon.symbol(for: "laptop") == "laptopcomputer")
        #expect(ProfileIcon.symbol(for: "undocked") == "laptopcomputer")
        #expect(ProfileIcon.symbol(for: "mobile") == "laptopcomputer")
    }

    @Test("specific patterns win over generic ones")
    func specificityOrdering() {
        // "conference-home" hits conference (specific) before home
        // (generic) — order matters in the mapping table.
        #expect(ProfileIcon.symbol(for: "conference-home") == "person.3.fill")
        // "home-office" hits home before work/office.
        #expect(ProfileIcon.symbol(for: "home-office") == "house.fill")
    }

    @Test("unknown slugs fall back to mappin.and.ellipse")
    func unknownFallsBack() {
        #expect(ProfileIcon.symbol(for: "elsewhere") == "mappin.and.ellipse")
        #expect(ProfileIcon.symbol(for: "xyz123") == "mappin.and.ellipse")
        #expect(ProfileIcon.symbol(for: "") == "mappin.and.ellipse")
    }

    @Test("name suggestion picks home-office for a CalDigit dock")
    func suggestsHomeOfficeForCalDigit() {
        let suggested = ProfileIcon.suggestedName(forDeviceNames: [
            "CalDigit Thunderbolt 3 Audio",
            "Some Generic Hub"
        ])
        #expect(suggested == "home-office")
    }

    @Test("name suggestion picks office for an LG monitor without CalDigit")
    func suggestsOfficeForLG() {
        let suggested = ProfileIcon.suggestedName(forDeviceNames: [
            "LG UltraFine Display Camera",
            "Some Hub"
        ])
        #expect(suggested == "office")
    }

    @Test("name suggestion picks studio for a Yeti microphone")
    func suggestsStudioForYeti() {
        let suggested = ProfileIcon.suggestedName(forDeviceNames: [
            "Yeti Stereo Microphone"
        ])
        #expect(suggested == "studio")
    }

    @Test("name suggestion returns nil when nothing recognizable is attached")
    func suggestsNilForUnknownDevices() {
        let suggested = ProfileIcon.suggestedName(forDeviceNames: [
            "Generic USB Keyboard",
            "Random Mouse"
        ])
        #expect(suggested == nil)
    }
}
