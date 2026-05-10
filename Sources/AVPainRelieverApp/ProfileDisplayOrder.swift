import Foundation
import AVPainReliever

/// Single source of truth for the order profiles render in the
/// menu bar's Switch to submenu and the Settings → Profiles tab.
///
/// `ConfigLoader` returns profiles in whatever order Swift's
/// Dictionary iteration produces, which is hash-randomized per
/// process launch. That made both UI surfaces shuffle between
/// sessions. `AppDelegate.bootEngine()` runs this once at load
/// time so every consumer reads `availableProfiles` directly.
///
/// Sorts alphabetically by *pretty* name (not slug) using
/// `localizedCaseInsensitiveCompare`, so "Café 2" sorts after
/// "Café 1" the way a reader expects and accented characters
/// follow the user's locale.
enum ProfileDisplayOrder {
    static func displayOrder(_ profiles: [Profile]) -> [Profile] {
        profiles.sorted {
            PrettyName.format($0.name)
                .localizedCaseInsensitiveCompare(PrettyName.format($1.name))
                == .orderedAscending
        }
    }
}
