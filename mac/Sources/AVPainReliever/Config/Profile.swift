import Foundation

/// A location profile — a named set of USB devices (the "fingerprint")
/// that, when all simultaneously attached, identifies the location.
///
/// Mirrors the resolution-relevant fields of an entry in `profiles.lua`.
/// Apply-time fields (`audioInput`, `audioOutput`, `obsScene`) will land
/// alongside `ProfileApplier`; this struct only carries what
/// `ProfileResolver` needs.
public struct Profile: Hashable, Sendable {
    /// The slug-cased profile name, e.g. `"home-office"`. Pretty-cased
    /// to "Home Office" at notification time, not here.
    public let name: String

    /// Every device in this list must currently be attached for the
    /// profile to match. An empty fingerprint matches any state with
    /// specificity 0 (the engine's `laptop` fallback works this way).
    public let fingerprint: [USBDevice]

    public init(name: String, fingerprint: [USBDevice]) {
        self.name = name
        self.fingerprint = fingerprint
    }
}
