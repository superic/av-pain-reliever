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
        /// Quiet, informational pills — "Travels with you" tag on
        /// portable peripherals in the wizard. Lower visual volume
        /// than the warn / success / error tints so the
        /// informational signal doesn't compete with the actionable
        /// pills (green Important, yellow error banners). System
        /// gray adapts to light/dark mode automatically.
        static let muted = SwiftUI.Color.gray
    }

    enum Symbol {
        /// SF Symbol used for the menu-bar icon and About-window hero.
        static let appIcon = "pills.fill"
        /// Wizard section icons — keep in lockstep with the section
        /// titles in `AddProfileView`.
        static let nameSection = "tag.fill"
        // Was `cable.connector` — that glyph reads as a stick figure
        // at small sizes (the USB-A connector silhouette is genuinely
        // person-shaped). `externaldrive.connected.to.line.below` is
        // unambiguously "peripheral connected to host" and reads cleanly
        // at caption size.
        static let usbSection = "externaldrive.connected.to.line.below"
        static let audioSection = "speaker.wave.2.fill"
        static let cameraSection = "camera.fill"
    }

    enum Copy {
        /// Tagline shown under the welcome greeting. Keep voice warm,
        /// not corporate; the user-facing personality lives here.
        static let tagline = "Your audio and camera, dialed in automatically."
        /// The app's display name. Use sparingly in user-facing copy
        /// — see the rule below before adding a new reference.
        ///
        /// **Self-naming rule for user-facing strings:**
        /// - **Inside a Settings tab, sheet, alert, or any in-app
        ///   surface** → don't name the app; the frame already
        ///   implies it. *"Enable virtual camera"* not *"Enable
        ///   AV Pain Reliever as a virtual camera."*
        /// - **In a button label that performs an action ON the app
        ///   itself** (Restart, Quit) → name it; "Restart" alone
        ///   could read as "restart macOS" — explicit target wins.
        /// - **When telling the user to do something in ANOTHER
        ///   app** ("Pick X in Zoom") → name it (in quotes); the
        ///   user needs to recognize the exact string in the other
        ///   app's picker.
        /// - **About / Welcome / menu bar / login items /
        ///   notifications** → name it; these are external or
        ///   system-level surfaces where the brand is the point.
        static let appName = "AV Pain Reliever"
    }
}
