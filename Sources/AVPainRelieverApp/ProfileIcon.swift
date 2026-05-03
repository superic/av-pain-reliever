import Foundation

/// Picks the SF Symbol used to represent a profile. Two modes:
///
/// - Auto-mapping (default): the slug picks the symbol. The mapping is
///   case-insensitive and prefix-friendly so common naming patterns
///   (`home-office`, `home-2`, `work-1`, `work-office`) land on
///   recognizable icons without requiring exact slugs.
/// - User override: the wizard exposes a curated picker
///   (`ProfileIcon.catalog`) and stores the choice on the profile's
///   `icon` field. When set, that wins.
///
/// `effectiveSymbol(for:override:)` collapses the two modes into a
/// single resolved symbol; callers (menu rendering, Settings list,
/// wizard preview) all go through it.
enum ProfileIcon {
    /// Resolved SF Symbol for a profile. If `override` is non-nil,
    /// it wins outright — the user explicitly chose this. Otherwise,
    /// fall back to the slug-driven auto-mapper.
    static func effectiveSymbol(for slug: String, override: String?) -> String {
        if let override, !override.isEmpty { return override }
        return symbol(for: slug)
    }

    /// Curated catalog of SF Symbol names the wizard's icon picker
    /// surfaces, in display order (workspaces → home → travel →
    /// education → fitness → content creation → fallbacks). Includes
    /// every symbol the auto-mapper can produce so a manual pick can
    /// match what auto-mapping would have chosen, plus location-themed
    /// extras for variety. ~30 symbols — small enough to render in a
    /// single popover grid, large enough to cover the situations
    /// users name profiles after.
    static let catalog: [String] = [
        // Workspaces
        "house.fill",
        "building.2.fill",
        "building.fill",
        "building.columns.fill",
        "briefcase.fill",
        "person.3.fill",
        "laptopcomputer",
        "desktopcomputer",
        // Home / lifestyle
        "bed.double.fill",
        "sofa.fill",
        "fork.knife",
        "cup.and.saucer.fill",
        "cart.fill",
        // Travel / outdoor
        "suitcase.fill",
        "car.fill",
        "airplane",
        "mountain.2.fill",
        "tent.fill",
        // Education / institution
        "graduationcap.fill",
        "books.vertical.fill",
        "testtube.2",
        // Health / fitness
        "dumbbell.fill",
        // Content creation
        "music.mic",
        "video.fill",
        "camera.fill",
        "headphones",
        "tv",
        // Generic / fallbacks
        "globe",
        "star.fill",
        "mappin.and.ellipse",
    ]

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
