import Foundation

/// A location profile — a named set of USB devices (the "fingerprint")
/// that, when all simultaneously attached, identifies the location,
/// plus the audio + camera settings the engine should apply when that
/// profile wins.
///
/// All apply-time fields are optional. OBS scene-switching is
/// intentionally omitted from V1; planned for V2.
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

    /// AVFoundation camera localizedName to set as the system's
    /// `userPreferredCamera` (macOS 14+ system-wide preferred camera),
    /// or nil to leave camera selection untouched. AVFoundation-modern
    /// apps (FaceTime, browser getUserMedia, native AVCapture clients)
    /// pick this up automatically; apps with their own camera UI
    /// (Zoom, Slack) maintain their own selection independently — the
    /// engine intentionally does NOT try to drive those (no plist
    /// hacks, no UI-scripting). For users who want Zoom/Slack to
    /// follow the profile too, V2's planned OBS support will let them
    /// route through OBS Virtual Camera.
    public let camera: String?

    /// Display-only names for fingerprint devices, keyed by
    /// `(vid, pid, serial)` USBDevice. Populated by `ConfigLoader`
    /// and `ConfigImporter` from the `name = "..."` field on each
    /// fingerprint entry in the source TOML / Lua. The resolver and
    /// applier ignore this — match logic is `(vid, pid, serial)`-only.
    /// The wizard's edit form reads this to keep saved-but-currently-
    /// disconnected devices visible (with a "Not connected" hint)
    /// rather than silently dropping them when the user is away from
    /// the location they configured. Excluded from `Hashable` /
    /// `Equatable` so two semantically-identical profiles stay equal
    /// regardless of whether one carries names.
    public let fingerprintNames: [USBDevice: String]

    public init(
        name: String,
        fingerprint: [USBDevice],
        audioInput: String? = nil,
        audioOutput: String? = nil,
        camera: String? = nil,
        fingerprintNames: [USBDevice: String] = [:]
    ) {
        self.name = name
        self.fingerprint = fingerprint
        self.audioInput = audioInput
        self.audioOutput = audioOutput
        self.camera = camera
        self.fingerprintNames = fingerprintNames
    }

    // Manual Hashable / Equatable that excludes `fingerprintNames`.
    // The names are display-only metadata; a profile loaded from a
    // TOML with `name = "..."` annotations should compare equal to
    // the same profile loaded without them, so existing tests + any
    // semantic identity check stays unaffected by this addition.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name == rhs.name
            && lhs.fingerprint == rhs.fingerprint
            && lhs.audioInput == rhs.audioInput
            && lhs.audioOutput == rhs.audioOutput
            && lhs.camera == rhs.camera
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(fingerprint)
        hasher.combine(audioInput)
        hasher.combine(audioOutput)
        hasher.combine(camera)
    }
}
