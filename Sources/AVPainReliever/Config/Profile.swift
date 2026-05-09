import Foundation

/// A location profile — a named set of USB devices (the "fingerprint")
/// that, when all simultaneously attached, identifies the location,
/// plus the audio + camera settings the engine should apply when that
/// profile wins. All apply-time fields are optional.
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
    /// (Zoom, Slack) maintain their own selection independently. For
    /// those, the V2 native virtual camera (`VirtualCameraSourceController`)
    /// covers them — they select "AV Pain Reliever" once and the
    /// active profile drives which real camera the virtual one
    /// streams from.
    public let camera: String?

    /// User-picked SF Symbol name to display next to this profile's
    /// label in the menu and Settings list. `nil` means "use the
    /// auto-mapper's pick" — the wizard exposes a curated picker
    /// (`ProfileIcon.catalog`) that lets users override the
    /// auto-pick. Never causes a parse failure for older app
    /// versions: missing field → `nil` → auto-mapper. Excluded from
    /// `Hashable` / `Equatable` so semantically-identical profiles
    /// stay equal regardless of the cosmetic override.
    public let icon: String?

    /// Display-only names for fingerprint devices, keyed by
    /// `(vid, pid, serial)` USBDevice. Populated by `ConfigLoader`
    /// from the `name = "..."` field on each fingerprint entry in
    /// the source TOML. The resolver and
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
        icon: String? = nil,
        fingerprintNames: [USBDevice: String] = [:]
    ) {
        self.name = name
        self.fingerprint = fingerprint
        self.audioInput = audioInput
        self.audioOutput = audioOutput
        self.camera = camera
        self.icon = icon
        self.fingerprintNames = fingerprintNames
    }

    // Manual Hashable / Equatable that excludes both
    // `fingerprintNames` and `icon`. They're display-only metadata,
    // so two semantically-identical profiles compare equal whether
    // or not one carries names or a custom icon. Per-field rationale
    // lives on each field's own doc comment; the operator just
    // mirrors that policy.
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
