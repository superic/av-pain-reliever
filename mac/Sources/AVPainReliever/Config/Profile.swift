import Foundation

/// A location profile — a named set of USB devices (the "fingerprint")
/// that, when all simultaneously attached, identifies the location, plus
/// the audio + OBS settings the engine should apply when that profile
/// wins.
///
/// Mirrors an entry in `profiles.lua`. All apply-time fields are
/// optional: a profile may switch only audio (no OBS scene), only the
/// scene (rare but legal), or all three.
public struct Profile: Hashable, Sendable {
    /// The slug-cased profile name, e.g. `"home-office"`. Pretty-cased
    /// to "Home Office" at notification time, not here.
    public let name: String

    /// Every device in this list must currently be attached for the
    /// profile to match. An empty fingerprint matches any state with
    /// specificity 0 (the engine's `laptop` fallback works this way).
    public let fingerprint: [USBDevice]

    /// CoreAudio device name to set as system default input, or nil to
    /// leave the current input untouched.
    public let audioInput: String?

    /// CoreAudio device name to set as system default output, or nil
    /// to leave the current output untouched.
    public let audioOutput: String?

    /// OBS scene name to switch to via `obs-cmd scene switch`, or nil
    /// to skip the OBS step (e.g. profiles for locations where OBS
    /// isn't relevant).
    public let obsScene: String?

    public init(
        name: String,
        fingerprint: [USBDevice],
        audioInput: String? = nil,
        audioOutput: String? = nil,
        obsScene: String? = nil
    ) {
        self.name = name
        self.fingerprint = fingerprint
        self.audioInput = audioInput
        self.audioOutput = audioOutput
        self.obsScene = obsScene
    }
}
