import SwiftUI
import AppKit

/// AV Pain Reliever's brand surface for SwiftUI views.
///
/// The palette is locked in `SWIFT_PORT.md` → "Visual identity" — the
/// six hex codes here mirror the Hammerspoon wizard's gum/ANSI palette
/// so the CLI tooling and the Swift app feel like the same product.
/// Views never hard-code colors; they reach through `Theme` so a future
/// dark-mode override or accessibility tweak lands in one place.
///
/// **Light vs dark mode**: the canonical hex codes are tuned for dark
/// backgrounds (the Hammerspoon TUI palette assumes a dark terminal,
/// and macOS menu bars + dark-mode windows are the most common surface
/// for brand pops). On light backgrounds the same colors wash out —
/// `#00FFFF` cyan on white is unreadable. Theme uses adaptive
/// variants: the dark-mode value is the canonical brand color; the
/// light-mode value is a darker, more saturated cousin that matches
/// the brand intent without sacrificing contrast.
///
/// Use `Theme.Color.primary` for headers + CTA buttons, `.highlight`
/// for taglines and links, `.success` for confirmations, `.warn` /
/// `.error` for trouble states, and `.chrome` for hint text and
/// borders. Color sparingly — the contrast between native chrome and
/// brand-color pops is what makes the accents feel intentional.
enum Theme {
    enum Color {
        /// Magenta — primary CTAs, hero text, the active accent
        /// throughout the app. Dark-mode = `#FF87D7` (canonical).
        /// Light-mode = `#C4429A` (darker magenta), which preserves
        /// the brand vibe while staying readable on white.
        static let primary = adaptive(
            light: SwiftUI.Color(red: 0.769, green: 0.259, blue: 0.604),
            dark:  SwiftUI.Color(red: 1.000, green: 0.529, blue: 0.843)
        )
        /// Cyan — taglines and link text. Dark-mode = `#00FFFF`.
        /// Light-mode = `#0F8FA8` (deep teal) so cyan-on-white
        /// remains legible.
        static let highlight = adaptive(
            light: SwiftUI.Color(red: 0.059, green: 0.561, blue: 0.659),
            dark:  SwiftUI.Color(red: 0.000, green: 1.000, blue: 1.000)
        )
        /// Green — save-success affordance, "switched" checkmarks.
        /// Dark-mode = `#00FF00`; light-mode = `#1F8A2E` (forest).
        static let success = adaptive(
            light: SwiftUI.Color(red: 0.122, green: 0.541, blue: 0.180),
            dark:  SwiftUI.Color(red: 0.000, green: 1.000, blue: 0.000)
        )
        /// Yellow `#FFAF00` — soft warnings. Light + dark are close
        /// enough at this saturation that one value works for both.
        static let warn = SwiftUI.Color(red: 1.00, green: 0.686, blue: 0.00)
        /// Red — fatal errors. Dark-mode = `#FF0000`; light-mode =
        /// `#C42727` (slightly desaturated to avoid the "alarm bell"
        /// pure-red of light-mode dialogs).
        static let error = adaptive(
            light: SwiftUI.Color(red: 0.769, green: 0.153, blue: 0.153),
            dark:  SwiftUI.Color(red: 1.000, green: 0.000, blue: 0.000)
        )
        /// Gray `#8A8A8A` — secondary text, hint captions, separators.
        /// SwiftUI's `.secondary` is fine for most cases; reach for
        /// this when we need the brand's specific gray.
        static let chrome = SwiftUI.Color(red: 0.541, green: 0.541, blue: 0.541)

        /// Wrap a (light, dark) pair into a SwiftUI Color that
        /// adapts to the current effective appearance. macOS 14's
        /// `Color(NSColor)` initializer + an NSColor dynamic
        /// provider is the cleanest way to do this without a custom
        /// view modifier on every consumer.
        private static func adaptive(
            light: SwiftUI.Color,
            dark: SwiftUI.Color
        ) -> SwiftUI.Color {
            SwiftUI.Color(NSColor(name: nil) { appearance in
                let match = appearance.bestMatch(from: [.aqua, .darkAqua])
                switch match {
                case .darkAqua: return NSColor(dark)
                default:        return NSColor(light)
                }
            })
        }
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
