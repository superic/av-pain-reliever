import AppKit
import SwiftUI

/// Generates the app icon used at runtime — a neutral gray-gradient
/// squircle with a white pill SF Symbol on top. Rendered in memory
/// rather than shipped as a `.icns` so a palette tweak doesn't
/// require regenerating an Xcode asset catalog. The signed `.app`
/// bundle will use a proper Asset Catalog AppIcon when distribution
/// lands; until then this is what shows up in About windows,
/// notifications, and any window's title-bar icon.
///
/// History: an earlier iteration used a magenta→cyan brand gradient
/// matching the Hammerspoon TUI palette. The user reverted that
/// direction (2026-05-02) — the app should look like a plain native
/// macOS utility, no custom accent colors. The icon now uses the
/// same neutral gray you'd see on Apple's own utility apps so it
/// blends with the system rather than shouting brand identity.
///
/// The size is chosen high enough (1024×1024) that macOS's automatic
/// downscaling for menu items, Dock previews, and notifications all
/// stay crisp.
enum AppIcon {
    /// Cached so we only render once per launch — every NSApp icon
    /// read after the first hits the cache.
    private static let _icon: NSImage = makeIcon()

    /// Set as `NSApp.applicationIconImage` from `AppDelegate.applicationDidFinishLaunching`.
    /// Tests can call this without an NSApp present too.
    static var image: NSImage { _icon }

    /// Render the icon at 1024×1024 and return as an `NSImage` whose
    /// representations preserve the original size (so SwiftUI's
    /// `Image(nsImage:)` and AppKit's `NSImageView` both downscale
    /// cleanly).
    static func makeIcon() -> NSImage {
        let size = NSSize(width: 1024, height: 1024)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        guard let ctx = NSGraphicsContext.current?.cgContext else {
            return image
        }

        // 1. Rounded rectangle clip — macOS app icons live inside the
        //    "squircle" mask (~22.5% corner radius for 1024 sq).
        let cornerRadius: CGFloat = size.width * 0.225
        let path = NSBezierPath(
            roundedRect: NSRect(origin: .zero, size: size),
            xRadius: cornerRadius,
            yRadius: cornerRadius
        )
        path.addClip()

        // 2. Linear gradient — neutral grays, light at the top to
        //    mimic the soft top-down lighting Apple uses on its own
        //    utility-style icons. Brighter top → darker bottom gives
        //    just enough depth to feel three-dimensional without
        //    looking branded.
        let topGray = NSColor(red: 0.62, green: 0.62, blue: 0.64, alpha: 1.0)
        let bottomGray = NSColor(red: 0.34, green: 0.34, blue: 0.36, alpha: 1.0)
        if let gradient = NSGradient(colors: [topGray, bottomGray]) {
            gradient.draw(
                in: NSRect(origin: .zero, size: size),
                angle: -90  // top → bottom
            )
        }

        // 3. SF Symbol pill, rendered white, centred. SF Symbols load
        //    as template images (alpha-mask) — drawing one with
        //    `setFill` ignored. The trick is to lock focus on a
        //    fresh NSImage, fill it white, then `destinationIn`-clip
        //    by the symbol's mask. The result is a proper white
        //    symbol image we can composite onto the gradient.
        let symbolPointSize: CGFloat = 540
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .semibold)
        if let template = NSImage(
            systemSymbolName: Theme.Symbol.appIcon,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(symbolConfig) {
            let tinted = NSImage(size: template.size)
            tinted.lockFocus()
            NSColor.white.set()
            NSRect(origin: .zero, size: template.size).fill()
            template.draw(
                in: NSRect(origin: .zero, size: template.size),
                from: .zero,
                operation: .destinationIn,
                fraction: 1.0
            )
            tinted.unlockFocus()

            let origin = NSPoint(
                x: (size.width - tinted.size.width) / 2,
                y: (size.height - tinted.size.height) / 2 - size.height * 0.02
            )

            // Soft shadow under the pill so it lifts off the gradient.
            ctx.saveGState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.30)
            shadow.shadowOffset = NSSize(width: 0, height: -size.height * 0.018)
            shadow.shadowBlurRadius = size.width * 0.06
            shadow.set()
            tinted.draw(
                in: NSRect(origin: origin, size: tinted.size),
                from: .zero,
                operation: .sourceOver,
                fraction: 1.0
            )
            ctx.restoreGState()
        }

        return image
    }
}
