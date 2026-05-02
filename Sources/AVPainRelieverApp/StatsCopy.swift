import Foundation

/// Copy for the optional stats line that appears under the menu's
/// title when the user holds Option while the menu is open. One-shot
/// easter egg — see `MenuContentView`.
enum StatsCopy {
    /// Friendly stat line. Pluralizes correctly and stays warm — no
    /// "you have switched profiles 47 times" — and varies a tiny bit
    /// at low counts so the first launch doesn't read as broken.
    static func line(for count: Int) -> String {
        switch count {
        case 0: return "Patiently waiting for your first dock"
        case 1: return "1 switch so far — welcome aboard"
        default: return "Switched \(count) times. Saving your sanity since plug-in #1."
        }
    }
}
