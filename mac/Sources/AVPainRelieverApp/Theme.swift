import SwiftUI

/// AV Pain Reliever's brand surface for SwiftUI views.
///
/// The palette is locked in `SWIFT_PORT.md` → "Visual identity" — the
/// six hex codes here mirror the Hammerspoon wizard's gum/ANSI palette
/// so the CLI tooling and the Swift app feel like the same product.
/// Views never hard-code colors; they reach through `Theme` so a future
/// dark-mode override or accessibility tweak lands in one place.
///
/// Use `Theme.Color.primary` for headers + CTA buttons, `.highlight`
/// for taglines and links, `.success` for confirmations, `.warn` /
/// `.error` for trouble states, and `.chrome` for hint text and
/// borders. Color sparingly — the contrast between native chrome and
/// brand-color pops is what makes the accents feel intentional.
enum Theme {
    enum Color {
        /// Magenta `#FF87D7` — primary CTAs, hero text, the active
        /// accent throughout the app. The "this is AV Pain Reliever"
        /// signal.
        static let primary = SwiftUI.Color(red: 1.00, green: 0.529, blue: 0.843)
        /// Cyan `#00FFFF` — taglines and link text. Always paired
        /// with primary, never used alone for emphasis on a CTA.
        static let highlight = SwiftUI.Color(red: 0.00, green: 1.00, blue: 1.00)
        /// Green `#00FF00` — save-success affordance, "switched"
        /// checkmarks. Use briefly; never for chrome.
        static let success = SwiftUI.Color(red: 0.00, green: 1.00, blue: 0.00)
        /// Yellow `#FFAF00` — soft warnings (config oddities, missing
        /// optional dependencies).
        static let warn = SwiftUI.Color(red: 1.00, green: 0.686, blue: 0.00)
        /// Red `#FF0000` — fatal errors only (save failed, file
        /// unreadable). Use sparingly so the user takes it seriously
        /// when it appears.
        static let error = SwiftUI.Color(red: 1.00, green: 0.00, blue: 0.00)
        /// Gray `#8A8A8A` — secondary text, hint captions, separators.
        /// SwiftUI's `.secondary` is fine for most cases; reach for
        /// this when we need the brand's specific gray.
        static let chrome = SwiftUI.Color(red: 0.541, green: 0.541, blue: 0.541)
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
