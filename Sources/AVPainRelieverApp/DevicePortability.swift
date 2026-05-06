import Foundation

/// Heuristic classification of attached USB devices into "this almost
/// certainly travels with you" vs "this almost certainly stays at this
/// location". Drives the wizard's "Suggested: untick" badge so users
/// don't have to recognize their own keyboard from a vid/pid line.
///
/// The heuristic is name-based and intentionally conservative — when
/// in doubt, we DON'T flag (so the user has to look at the row but
/// won't be misled into unticking a docked-only peripheral that
/// happened to share a generic word). Wrong-positive rate matters more
/// than recall; if the user wants to untick a peripheral we didn't
/// flag, they always can.
///
/// Categories that should be unticked because they travel:
///   - Keyboards (especially Bluetooth/Magic Keyboards)
///   - Mice / trackpads
///   - Phones / tablets (iOS, Android)
///   - Headphones (BT headsets paired across multiple locations)
///
/// Anything that smells like a dock, monitor, microphone, audio
/// interface, webcam, or display = location-specific, don't flag.
enum DevicePortability {
    /// True if the device's name suggests it's a portable peripheral
    /// the user probably carries between locations. Returns false
    /// when uncertain.
    static func isLikelyPortable(deviceName: String?) -> Bool {
        guard let name = deviceName?.lowercased(), !name.isEmpty else {
            // Unnamed devices (hub legs) are stable parts of a dock,
            // not portable peripherals. Don't flag.
            return false
        }
        for keyword in portableKeywords {
            if name.contains(keyword) { return true }
        }
        return false
    }

    /// Short label shown next to a flagged row to hint why we
    /// suggest unticking it. Returns nil when the device isn't
    /// flagged. Phrased as a category, not an instruction — the
    /// "Suggested: untick" header makes the action obvious.
    static func portabilityCategory(deviceName: String?) -> String? {
        guard let name = deviceName?.lowercased(), !name.isEmpty else {
            return nil
        }
        if name.contains("keyboard") || name.contains("magic keyboard") {
            return "keyboard"
        }
        if name.contains("mouse") || name.contains("trackpad") || name.contains("magic trackpad") {
            return "pointing device"
        }
        if name.contains("iphone") || name.contains("ipad") || name.contains("airpods") {
            return "phone / wearable"
        }
        if name.contains("android") || name.contains("pixel") {
            return "phone / wearable"
        }
        if name.contains("headphones") || name.contains("headset") || name.contains("buds") {
            return "headphones"
        }
        if name.contains("watch") {
            return "watch"
        }
        return nil
    }

    /// Lowercased substrings that mark a device as "probably travels
    /// with you". Order doesn't matter — first match wins.
    private static let portableKeywords: [String] = [
        // Pointing devices
        "magic mouse", "magic trackpad", "trackpad", "mouse",
        // Keyboards
        "keyboard", "magic keyboard",
        // Phones / tablets
        "iphone", "ipad", "android", "pixel",
        // Wearables
        "airpods", "watch", "headphones", "headset", "earbuds", "buds",
    ]

    /// Short label for "headline hardware" — the standalone,
    /// dedicated devices a user is most likely to pick as their
    /// audio in/out/camera defaults at this location. Drives the
    /// wizard's green "Important: \(category)" pill. Mirror of
    /// `portabilityCategory` but on the opposite end of the
    /// importance scale.
    ///
    /// Specifically excludes display sub-components (LG UltraFine
    /// Display Audio / Camera / Controls). Those are real,
    /// functional USB devices — a Thunderbolt monitor exposes its
    /// built-in camera, audio, and HID controls as separate USB
    /// endpoints — but they're sub-components of a larger display,
    /// not the dedicated hardware most users default to. A user
    /// with the LG UltraFine plus an external webcam almost
    /// always picks the external. Keeping display sub-components
    /// off the Important list preserves the pill's signal value.
    /// Users who DO default to a display's built-in camera can
    /// still tick it manually — the pill is informational, not
    /// gating.
    static func importantCategory(deviceName: String?) -> String? {
        guard let name = deviceName?.lowercased(), !name.isEmpty else {
            return nil
        }
        // Display / monitor hub-leg sub-components: skip even when
        // they technically contain audio / camera keywords. The
        // "ultrafine" check catches the LG UltraFine line whose
        // camera/audio/controls all contain "UltraFine" in their
        // product names; future monitors with similar branding
        // would need their brand added here.
        if name.contains("display") || name.contains("ultrafine") {
            return nil
        }
        if name.contains("microphone") || name.contains("mic") || name.contains("podcast") {
            return "mic"
        }
        // "video" intentionally covers cameras, webcams, AND HDMI
        // capture cards. Capture cards aren't really cameras but
        // they ARE video sources from the user's perspective; one
        // unified label keeps the pill vocabulary tight.
        if name.contains("camera") || name.contains("webcam") || name.contains("capture") {
            return "video"
        }
        if name.contains("speaker") {
            return "speaker"
        }
        // Catch-all for dedicated audio gear that isn't obviously a
        // mic or speaker — audio interfaces (CalDigit Thunderbolt
        // 3 Audio, RME, Apollo), DACs, etc. The display/ultrafine
        // exclusion above keeps display-audio sub-components out.
        if name.contains("audio") || name.contains("dac") {
            return "audio"
        }
        return nil
    }
}
