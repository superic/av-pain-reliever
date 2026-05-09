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
    ///
    /// `logger`, when supplied, receives `.debug` lines describing the
    /// candidate set and the winner. Useful when diagnosing
    /// "why did THAT profile win?" reports. Default `nil` keeps the
    /// existing call sites source-compatible and tests quiet.
    public func resolve(attached: Set<USBDevice>, logger: ApplierLogger? = nil) -> Profile? {
        // Iterate alphabetically so ties resolve to the
        // earlier-by-name profile (`>` instead of `>=` below makes the
        // first encountered specificity win on ties).
        let sorted = profiles.sorted { $0.name < $1.name }
        var best: Profile?
        var bestSpecificity = -1
        for profile in sorted {
            // Asymmetric matching: each fingerprint entry must match
            // *some* attached device. Entries with nil serial match
            // any unit of (vid, pid); entries with a serial match only
            // that exact unit. See USBDevice.matchesAttachedDevice.
            let matches = profile.fingerprint.allSatisfy { entry in
                attached.contains { device in entry.matchesAttachedDevice(device) }
            }
            let specificity = profile.fingerprint.count
            logger?.debug("resolver: candidate \(profile.name) specificity=\(specificity) matches=\(matches)")
            guard matches else { continue }
            if specificity > bestSpecificity {
                best = profile
                bestSpecificity = specificity
            }
        }
        if let best {
            logger?.debug("resolver: winner=\(best.name) specificity=\(bestSpecificity)")
        } else {
            logger?.debug("resolver: no profile matched (\(profiles.count) candidates considered)")
        }
        return best
    }
}
