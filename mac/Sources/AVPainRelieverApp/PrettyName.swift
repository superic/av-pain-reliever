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
