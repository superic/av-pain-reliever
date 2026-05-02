import AppKit
import SwiftUI

/// Generates the app icon used at runtime — a magenta-to-cyan radial
/// gradient with a white pill SF Symbol on top. We render this in
/// memory rather than ship a `.icns` so a v1 palette tweak doesn't
/// require regenerating an Xcode asset catalog. The signed `.app`
/// bundle will use a proper Asset Catalog AppIcon when distribution
/// lands; until then this is what shows up in About windows,
/// notifications (`os_log`-routed), and any window's title-bar icon.
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

        // 2. Radial gradient — magenta core, cyan rim. Tunes the
        //    magenta intensity by mixing in slightly desaturated
        //    pinks at the centre so the symbol on top still pops.
        let magenta = NSColor(red: 1.00, green: 0.529, blue: 0.843, alpha: 1.0)
        let deepMagenta = NSColor(red: 0.85, green: 0.30, blue: 0.70, alpha: 1.0)
        let cyan = NSColor(red: 0.00, green: 1.00, blue: 1.00, alpha: 1.0)
        if let gradient = NSGradient(colors: [magenta, deepMagenta, cyan]) {
            gradient.draw(
                fromCenter: NSPoint(x: size.width / 2, y: size.height * 0.62),
                radius: 0,
                toCenter: NSPoint(x: size.width / 2, y: size.height * 0.45),
                radius: size.width * 0.65,
                options: []
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
