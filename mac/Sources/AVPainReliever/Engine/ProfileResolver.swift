import Foundation

/// Resolves the winning profile for a given set of attached USB devices.
///
/// Algorithm (mirrors `init.lua`'s `resolveProfile`):
///
/// 1. A profile *matches* if every device in its fingerprint is present
///    in the attached set. An empty fingerprint matches any state.
/// 2. Among matching profiles, the one with the most fingerprint
///    entries wins ("most specific").
/// 3. Ties are broken alphabetically by name.
///
/// The resolver is stateless beyond its profile list — call `resolve`
/// with a fresh attached set on every USB-event burst.
public struct ProfileResolver: Sendable {
    public let profiles: [Profile]

    public init(profiles: [Profile]) {
        self.profiles = profiles
    }

    /// Returns the most-specific matching profile, or `nil` if no
    /// profile matches. Callers (e.g. the production `Engine`) layer
    /// their own fallback policy on top — `init.lua` falls back to a
    /// hardcoded `"laptop"` name when nothing matches.
    public func resolve(attached: Set<USBDevice>) -> Profile? {
        // Iterate alphabetically so ties resolve to the
        // earlier-by-name profile (`>` instead of `>=` below makes the
        // first encountered specificity win on ties).
        let sorted = profiles.sorted { $0.name < $1.name }
        var best: Profile?
        var bestSpecificity = -1
        for profile in sorted {
            let matches = profile.fingerprint.allSatisfy { attached.contains($0) }
            guard matches else { continue }
            let specificity = profile.fingerprint.count
            if specificity > bestSpecificity {
                best = profile
                bestSpecificity = specificity
            }
        }
        return best
    }
}
