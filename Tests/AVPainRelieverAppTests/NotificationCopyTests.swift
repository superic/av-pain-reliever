import Testing
@testable import AVPainRelieverApp

@Suite("NotificationCopy")
struct NotificationCopyTests {
    @Test("title rotates deterministically by day-of-year")
    func rotatesByDay() {
        // home alternates: ["Home", "Home, sweet home", "Welcome back home", "Home base"]
        // (4 entries — index = abs(day) % 4).
        let day0 = NotificationCopy.title(forSlug: "home", dayOfYear: 0)
        let day1 = NotificationCopy.title(forSlug: "home", dayOfYear: 1)
        let day4 = NotificationCopy.title(forSlug: "home", dayOfYear: 4)

        // Determinism: same day → same title.
        #expect(NotificationCopy.title(forSlug: "home", dayOfYear: 0) == day0)
        // Day 0 wraps to day 4 (4 % 4 == 0 — same alternate).
        #expect(day0 == day4)
        // Different days within one cycle pick different alternates.
        #expect(day0 != day1)
    }

    @Test("home titles are warm, not bare")
    func homeAlternatesIncludeWarmth() {
        let warm = (0..<8).map { NotificationCopy.title(forSlug: "home", dayOfYear: $0) }
        #expect(warm.contains("Home, sweet home"))
        #expect(warm.contains("Home base"))
        #expect(warm.contains("Welcome back home"))
    }

    @Test("work / office titles read like actual humans wrote them")
    func workAlternates() {
        let lines = (0..<8).map { NotificationCopy.title(forSlug: "work-office", dayOfYear: $0) }
        #expect(lines.contains("Work mode"))
        #expect(lines.contains("At the office"))
        #expect(lines.contains("Hello, work"))
    }

    @Test("café slugs trigger café-specific copy")
    func cafeAlternates() {
        let lines = (0..<6).map { NotificationCopy.title(forSlug: "cafe", dayOfYear: $0) }
        #expect(lines.contains("Café mode"))
        #expect(lines.contains("Coffee shop vibes"))
    }

    @Test("unrecognized slugs fall back to the pretty name")
    func unknownFallsBackToPretty() {
        let title = NotificationCopy.title(forSlug: "rooftop-deck", dayOfYear: 100)
        #expect(title == "Rooftop Deck")
    }

    @Test("convenience overload resolves a real title for today")
    func convenienceOverloadWorks() {
        let title = NotificationCopy.title(forSlug: "studio")
        // Just check it's non-empty and one of the alternates — the
        // exact value depends on today's day-of-year.
        #expect(!title.isEmpty)
        let valid: Set<String> = ["Studio", "Studio time", "Tracking now"]
        #expect(valid.contains(title))
    }

    @Test("unknown-location body pluralizes correctly")
    func unknownLocationBodyPluralizes() {
        let zero = NotificationCopy.unknownLocationBody(deviceCount: 0)
        let one = NotificationCopy.unknownLocationBody(deviceCount: 1)
        let many = NotificationCopy.unknownLocationBody(deviceCount: 5)
        #expect(zero.contains("Open the menu"))
        #expect(one.contains("1 USB device"))
        #expect(!one.contains("devices"))
        #expect(many.contains("5 USB devices"))
    }
}
