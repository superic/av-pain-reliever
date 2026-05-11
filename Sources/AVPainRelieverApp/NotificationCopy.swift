import Foundation

/// Picks a friendly notification title for a given profile slug.
///
/// Default behavior is "use the pretty-cased name" — that's the safe,
/// trustworthy macOS default. Common slug families (home, work, café)
/// get 2-4 warmer alternates rotated deterministically by day-of-year
/// so the toast varies between days but doesn't whiplash within a
/// single dock-undock cycle.
///
/// The randomness is *deterministic on day-of-year* on purpose: across
/// a single workday, every dock event for the same location gives the
/// same title. Tomorrow it might rotate to a different one. This keeps
/// the personality from feeling glitchy or attention-grabbing.
enum NotificationCopy {
    /// Pretty title for the toast that announces a profile change.
    /// `body` should stay constant ("Audio + camera switched") — the
    /// title is where personality lives.
    static func title(forSlug slug: String, dayOfYear: Int) -> String {
        let pretty = PrettyName.format(slug)
        let alternates = alternates(forSlug: slug.lowercased(), pretty: pretty)
        guard !alternates.isEmpty else { return pretty }
        let index = abs(dayOfYear) % alternates.count
        return alternates[index]
    }

    /// Convenience using today's day-of-year. Falls back to the pretty
    /// name if the calendar can't produce a day-of-year (shouldn't
    /// happen on macOS).
    static func title(forSlug slug: String) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let day = calendar.ordinality(of: .day, in: .year, for: Date()) ?? 0
        return title(forSlug: slug, dayOfYear: day)
    }

    /// Title for the "your profiles.toml was corrupt; we moved it to
    /// the Trash" toast. Operational, not playful: the user needs to
    /// know what happened so they can recover.
    static let configCorruptedTitle = "Couldn't read profiles.toml"

    /// Body for the same toast. The Show in Finder action button
    /// reveals the file in the Trash; the body explains the rest.
    static let configCorruptedBody = "Moved the broken copy to the Trash. Started fresh from defaults."

    /// Title for the worst-case branch: parse failed AND we couldn't
    /// move the file aside (filesystem error, read-only parent).
    /// Engine runs with an empty profile list until the user resolves
    /// it.
    static let configUnrecoverableTitle = "Couldn't recover profiles.toml"

    /// Body for the worst-case branch. Points at the Advanced menu's
    /// Save Logs for Support entry.
    static let configUnrecoverableBody = "Use Advanced > Save Logs for Support and send us the log."

    /// Body text for the "new location detected" toast — warmer than
    /// the bare "N USB devices attached" version, while still telling
    /// the user the next concrete action they can take.
    static func unknownLocationBody(deviceCount: Int) -> String {
        switch deviceCount {
        case 0:
            return "Open the menu to set it up."
        case 1:
            return "1 USB device joined the party. Open the menu to teach me this spot."
        default:
            return "\(deviceCount) USB devices joined the party. Open the menu to teach me this spot."
        }
    }

    private static func alternates(forSlug slug: String, pretty: String) -> [String] {
        if slug.hasPrefix("home") {
            return [pretty, "Home, sweet home", "Welcome back home", "Home base"]
        }
        if slug.hasPrefix("work") || slug.contains("office") {
            return [pretty, "Work mode", "At the office", "Hello, work"]
        }
        if slug.contains("cafe") || slug.contains("coffee") {
            return [pretty, "Coffee shop vibes", "Café mode"]
        }
        if slug.hasPrefix("studio") {
            return [pretty, "Studio time", "Tracking now"]
        }
        if slug == "laptop" || slug.hasPrefix("laptop") || slug.hasPrefix("undocked") {
            return [pretty, "Untethered", "Laptop life"]
        }
        if slug.hasPrefix("conference") || slug.contains("meeting") {
            return [pretty, "Meeting mode", "Conference room"]
        }
        return [pretty]
    }
}
