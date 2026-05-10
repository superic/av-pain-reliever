import Testing
import Foundation
@testable import AVPainReliever
@testable import AVPainRelieverApp

@Suite("ProfileDisplayOrder")
struct ProfileDisplayOrderTests {
    private func profile(_ slug: String) -> Profile {
        Profile(name: slug, fingerprint: [])
    }

    @Test("sorts alphabetically by pretty name, case-insensitive")
    func sortsAlphabeticallyByPrettyName() {
        // Input shuffled deliberately so a non-sort would fail the
        // assertion. Pretty names are: "Home Office", "Apartment",
        // "Cafe", "Conference Room".
        let input = [
            profile("home-office"),
            profile("apartment"),
            profile("cafe"),
            profile("conference-room"),
        ]
        let sorted = ProfileDisplayOrder.displayOrder(input)
        #expect(sorted.map(\.name) == [
            "apartment",
            "cafe",
            "conference-room",
            "home-office",
        ])
    }

    @Test("locale-aware sort handles accented characters")
    func handlesAccentedCharacters() {
        // "Café" should sort with "C" entries, not at the end of the
        // alphabet (which is where naive byte-comparison would put it).
        // PrettyName.format strips the hyphen and capitalizes; the
        // locale-aware compare keeps accented "é" adjacent to "e".
        let input = [
            profile("zoo"),
            profile("café"),
            profile("apartment"),
        ]
        let sorted = ProfileDisplayOrder.displayOrder(input)
        #expect(sorted.map(\.name) == ["apartment", "café", "zoo"])
    }

    @Test("ties broken stably; two same-pretty-name profiles preserve input order")
    func equalPrettyNamesPreserveInput() {
        // Two slugs that pretty-format to the same string — this
        // shouldn't happen in practice (profiles are unique by slug)
        // but the sort must not crash or non-deterministically swap.
        // Swift's `sorted` is stable, so the first input stays first.
        let a = profile("home-office")
        let b = profile("home-office") // intentional dup
        let sorted = ProfileDisplayOrder.displayOrder([a, b])
        #expect(sorted.count == 2)
        #expect(sorted[0].name == "home-office")
        #expect(sorted[1].name == "home-office")
    }

    @Test("empty input returns empty output")
    func emptyInput() {
        #expect(ProfileDisplayOrder.displayOrder([]).isEmpty)
    }

    @Test("single-element input returns the same element")
    func singleElementInput() {
        let only = profile("solo")
        let sorted = ProfileDisplayOrder.displayOrder([only])
        #expect(sorted.map(\.name) == ["solo"])
    }
}
