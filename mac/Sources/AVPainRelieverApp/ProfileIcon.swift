import Foundation

/// Maps a profile's slug to an SF Symbol name. V1 is fully automatic —
/// the user can't pick the icon, the slug picks it. The mapping is
/// intentionally case-insensitive and prefix-friendly so common naming
/// patterns (`home-office`, `home-2`, `work-1`, `work-office`) land on
/// recognizable icons without requiring exact slugs.
///
/// V2 will let users override the icon per-profile; until then this
/// keeps the menu's "Switch to" submenu glanceable without any user
/// configuration.
enum ProfileIcon {
    /// SF Symbol name for `slug`. Always returns a valid symbol — when
    /// nothing matches, falls back to `mappin.and.ellipse` (a generic
    /// "this is a place" pin).
    static func symbol(for slug: String) -> String {
        let lower = slug.lowercased()

        // Order matters: more-specific patterns are checked first so a
        // slug like `conference-home` lands on `person.3.fill` rather
        // than `house.fill`. Each entry is `(predicate, symbol)`.
        // Predicates use prefix/contains semantics; the slug character
        // set is constrained to alphanumerics + hyphens so substring
        // matching is safe (no Unicode normalization surprises).
        for (matches, symbol) in mapping {
            if matches(lower) { return symbol }
        }
        return "mappin.and.ellipse"
    }

    /// Pattern table. Each entry pairs a predicate against a slug with
    /// the SF Symbol to use when it matches. Re-ordered by intuition
    /// about how often each pattern shows up in real profile names.
    private static let mapping: [(@Sendable (String) -> Bool, String)] = [
        // Specifics first.
        ({ $0.hasPrefix("conference") || $0.contains("meeting") }, "person.3.fill"),
        ({ $0.hasPrefix("studio") || $0.contains("podcast") }, "music.mic"),
        ({ $0.contains("library") }, "books.vertical.fill"),
        ({ $0.contains("garage") }, "car.fill"),
        ({ $0.contains("lab") }, "testtube.2"),
        ({ $0.contains("cafe") || $0.contains("coffee") }, "cup.and.saucer.fill"),
        ({ $0.contains("hotel") || $0.contains("travel") }, "suitcase.fill"),
        ({ $0.contains("school") || $0.contains("class") }, "graduationcap.fill"),

        // Generic locations.
        ({ $0.hasPrefix("home") }, "house.fill"),
        ({ $0.hasPrefix("work") || $0.contains("office") }, "building.2.fill"),

        // Implicit fallback — a bare laptop slug is the always-matches
        // profile most users keep.
        ({ $0 == "laptop" || $0.hasPrefix("laptop") || $0.hasPrefix("undocked") || $0.hasPrefix("mobile") }, "laptopcomputer"),
    ]

    /// Suggests a profile name slug based on the names of currently-
    /// attached USB devices. Returns the best-guess slug or nil when
    /// nothing recognizable is plugged in. The wizard uses this to
    /// pre-fill the Name field on first open — the user can always
    /// rename before saving.
    ///
    /// Heuristics are deliberately broad: a CalDigit dock is almost
    /// always a "home office" or "work office" setup; an LG monitor
    /// or generic dock is "office". When multiple signals match,
    /// the more specific one wins.
    static func suggestedName(forDeviceNames names: [String]) -> String? {
        let lower = names.map { $0.lowercased() }
        let hasCaldigit = lower.contains { $0.contains("caldigit") }
        let hasLG = lower.contains { $0.contains("lg ") || $0.contains("ultrafine") }
        let hasYeti = lower.contains { $0.contains("yeti") || $0.contains("blue mic") }
        let hasShure = lower.contains { $0.contains("shure") || $0.contains("mv7") }
        let hasGoPro = lower.contains { $0.contains("gopro") }

        if hasCaldigit { return "home-office" }
        if hasLG { return "office" }
        if hasYeti || hasShure { return "studio" }
        if hasGoPro { return "studio" }
        return nil
    }
}
