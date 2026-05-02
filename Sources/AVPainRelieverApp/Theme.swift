import SwiftUI
import AppKit

/// AV Pain Reliever's small brand surface — kept narrow on purpose.
///
/// Earlier iterations carried a CLI-style palette (magenta primary,
/// cyan highlight) borrowed from the Hammerspoon TUI. The user
/// reverted that direction (2026-05-02): the app should look like a
/// plain native macOS utility, no custom accent colors. So this
/// namespace now exposes only the three semantic system colors the
/// app actually needs (success / warn / error) for status pills and
/// banner-style errors. Everything else (headers, captions, links,
/// button tints) uses SwiftUI's defaults — `.primary` for body text,
/// `.secondary` for hints, the system accent for prominent buttons.
///
/// `Theme.Symbol` and `Theme.Copy` stay as before — those are
/// product identifiers, not stylistic choices.
enum Theme {
    enum Color {
        /// Save-success affordance, "switched" checkmarks. Maps to
        /// the macOS system green so it tracks the OS appearance.
        static let success = SwiftUI.Color.green
        /// Soft warnings — yellow status pills ("Not connected",
        /// "Suggested: untick"). System orange reads as "caution"
        /// without screaming the way a saturated yellow does.
        static let warn = SwiftUI.Color.orange
        /// Fatal errors — banner backgrounds + the inline triangle
        /// icon. System red, same as Apple's own destructive action
        /// styling.
        static let error = SwiftUI.Color.red
    }

    enum Symbol {
        /// SF Symbol used for the menu-bar icon and About-window hero.
        static let appIcon = "pills.fill"
        /// Wizard section icons — keep in lockstep with the section
        /// titles in `AddProfileView`.
        static let nameSection = "tag.fill"
        static let usbSection = "cable.connector"
        static let audioSection = "speaker.wave.2.fill"
        static let cameraSection = "camera.fill"
    }

    enum Copy {
        /// Tagline shown in About + first-run welcome. Keep voice warm,
        /// not corporate; the user-facing personality lives here.
        static let tagline = "Stop fiddling with mic, speakers, and webcam."
        static let appName = "AV Pain Reliever"
    }
}
