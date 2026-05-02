import Foundation

/// Slug-cased profile name → display name. Mirrors `init.lua`'s
/// `prettyName()`: replaces hyphens with spaces and capitalizes the
/// first letter of each word.
///
/// `"home-office"` → `"Home Office"`
/// `"laptop"`      → `"Laptop"`
enum PrettyName {
    static func format(_ slug: String) -> String {
        slug
            .split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }
}

/// Human input → canonical slug. The wizard accepts any name the user
/// wants to type ("Home Office", "MOM'S HOUSE", "café-2") and stores
/// the slugified form internally so:
///
/// - The TOML key (`[profiles.<slug>]`) is always a valid bare key.
/// - The resolver matches consistently regardless of capitalization
///   or whitespace.
/// - The display form (via `PrettyName.format`) always renders cleanly.
///
/// Algorithm:
/// 1. Apply Latin transliteration to strip diacritics ("café" → "cafe").
/// 2. Lowercase.
/// 3. Replace any non-alphanumeric run with a single hyphen.
/// 4. Trim leading/trailing hyphens.
enum Slug {
    static func format(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // Strip diacritics: "Café" → "Cafe", "Mañana" → "Manana".
        // applyingTransform is a Foundation/CFString shim; on macOS
        // it falls through to ICU. Returning nil shouldn't happen
        // for valid Strings but guard defensively.
        let folded = trimmed
            .applyingTransform(.stripCombiningMarks, reverse: false)
            ?? trimmed

        // Map any non-alphanumeric ASCII to "-", lowercase the rest.
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789")
        var result = ""
        var lastWasHyphen = false
        for char in folded.lowercased() {
            if allowed.contains(char) {
                result.append(char)
                lastWasHyphen = false
            } else if !lastWasHyphen && !result.isEmpty {
                result.append("-")
                lastWasHyphen = true
            }
        }
        // Strip trailing hyphen produced by the loop above.
        while result.hasSuffix("-") { result.removeLast() }
        return result
    }
}
