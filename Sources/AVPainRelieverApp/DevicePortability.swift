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

    /// Short label for high-priority "this defines a location"
    /// devices — microphones, speakers, cameras, capture cards,
    /// audio interfaces, displays. Mirror of `portabilityCategory`
    /// but for the OTHER end of the importance scale: the wizard's
    /// device-list sort floats these to the top so a user adding a
    /// profile sees the hardware that distinguishes their dock
    /// before they see anything generic.
    ///
    /// Conservative same as the portability matcher — only words
    /// that are reliably tied to location-defining hardware
    /// regardless of brand. "Microphone" is safer than "blue"
    /// (could be a vendor name); "audio" is safer than "stream"
    /// (Stream Deck is a control deck, not audio).
    static func priorityCategory(deviceName: String?) -> String? {
        guard let name = deviceName?.lowercased(), !name.isEmpty else {
            return nil
        }
        if name.contains("microphone") || name.contains("podcast") {
            return "microphone"
        }
        if name.contains("camera") || name.contains("capture") || name.contains("webcam") {
            return "camera"
        }
        if name.contains("speaker") {
            return "speaker"
        }
        // "audio" is broad — covers "Audio Interface", "Display Audio",
        // "Thunderbolt 3 Audio". Useful but means we group docks-with-
        // audio in with mics/speakers. Acceptable for sort priority;
        // the alternative (more specific keywords) misses too many
        // real-world products.
        if name.contains("audio") || name.contains("dac") {
            return "audio"
        }
        if name.contains("display") || name.contains("monitor") {
            return "display"
        }
        return nil
    }
}
