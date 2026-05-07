import AppKit
import SwiftUI

/// Generates the app icon used at runtime — a pale icy squircle with
/// a centered USB-fingerprint glyph in flat Apple-system-blue.
///
/// The aesthetic borrows from Sparkle's update-icon style: light-blue
/// → white linear gradient chrome with a subtle top highlight, a
/// medium-dark inset rim that gives the squircle real depth, and a
/// crisp single-color mark at the center. The glyph itself is the
/// `externaldrive.connected.to.line.below` SF Symbol — the same one
/// the in-app "USB fingerprint" section header uses, so the Dock,
/// the About window, and the wizard's section vocabulary all line
/// up.
///
/// Rendered in memory rather than shipped as a `.icns` so a tweak to
/// the drawing doesn't require regenerating an asset. The signed
/// `.app` bundle still ships `Resources/AppIcon.icns` for Finder /
/// Spotlight / Dock-on-activate; that file is regenerated from this
/// drawing via `scripts/regen-icon.sh` whenever the design changes.
///
/// The size is chosen high enough (1024×1024) that macOS's automatic
/// downscaling for menu items, Dock previews, and notifications all
/// stay crisp.
///
/// Keep the drawing routine here in sync with
/// `scripts/render-app-icon.swift` (used by the regen script to
/// produce the `.icns`).
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

        let cornerRadius: CGFloat = size.width * 0.225
        let canvasRect = NSRect(origin: .zero, size: size)
        let squircle = NSBezierPath(
            roundedRect: canvasRect,
            xRadius: cornerRadius,
            yRadius: cornerRadius
        )

        // 1. Squircle clip + icy light-blue gradient. Top is near-white
        //    with a hint of cool tint; bottom is a soft cornflower blue.
        ctx.saveGState()
        squircle.addClip()
        let topIce = NSColor(red: 0.965, green: 0.985, blue: 1.000, alpha: 1.0)
        let bottomIce = NSColor(red: 0.840, green: 0.905, blue: 0.975, alpha: 1.0)
        if let gradient = NSGradient(colors: [topIce, bottomIce]) {
            gradient.draw(in: canvasRect, angle: -90)
        }

        // 2. Top-edge highlight — a faint white-to-clear gradient over
        //    the upper 45% of the chrome. Reads as glossy, not flat.
        if let highlight = NSGradient(colorsAndLocations:
            (NSColor.white.withAlphaComponent(0.22), 0.0),
            (NSColor.white.withAlphaComponent(0.0), 0.45)
        ) {
            highlight.draw(in: canvasRect, angle: -90)
        }
        ctx.restoreGState()

        // 3. Mark — `externaldrive.connected.to.line.below` SF Symbol,
        //    flat-filled in Apple-system-blue. Drawn into a separate
        //    NSImage so the soft drop shadow lands once on the
        //    silhouette rather than separately on each stroke.
        let mark = symbolMark(canvasSize: size)
        ctx.saveGState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.10)
        shadow.shadowOffset = NSSize(width: 0, height: -size.height * 0.006)
        shadow.shadowBlurRadius = size.width * 0.012
        shadow.set()
        mark.draw(in: canvasRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        ctx.restoreGState()

        // 4. Inset rim — 16% black stroke that defines the squircle
        //    edge. Modeled after the Sparkle-update-icon reference;
        //    gives the chrome depth against light wallpapers without
        //    competing with the mark.
        let rimInset = size.width * 0.014
        let rimWidth = size.width * 0.0094
        let rim = NSBezierPath(
            roundedRect: canvasRect.insetBy(dx: rimInset, dy: rimInset),
            xRadius: cornerRadius - rimInset,
            yRadius: cornerRadius - rimInset
        )
        rim.lineWidth = rimWidth
        NSColor.black.withAlphaComponent(0.16).setStroke()
        rim.stroke()

        return image
    }

    /// SF Symbol mark filled in Apple-system-blue, returned as an
    /// `NSImage` the size of the canvas so the parent draw can apply
    /// a single shadow pass to the whole silhouette.
    ///
    /// Two-step composite: render the symbol white onto a transparent
    /// canvas to get a precise alpha mask, then paint the mask with
    /// the brand color via `.sourceIn` blend mode.
    private static func symbolMark(canvasSize: NSSize) -> NSImage {
        let image = NSImage(size: canvasSize)
        image.lockFocus()
        defer { image.unlockFocus() }

        guard
            let ctx = NSGraphicsContext.current?.cgContext,
            let sym = NSImage(
                systemSymbolName: "externaldrive.connected.to.line.below",
                accessibilityDescription: nil
            )
        else {
            return image
        }

        // Empirically tuned for `externaldrive.connected.to.line.below`
        // — a wide glyph that fills ~55% of canvas height comfortably.
        let pt = canvasSize.width * 0.55
        let baseCfg = NSImage.SymbolConfiguration(pointSize: pt, weight: .regular)
        let whiteCfg = baseCfg.applying(
            NSImage.SymbolConfiguration(paletteColors: [NSColor.white])
        )
        guard let whiteSym = sym.withSymbolConfiguration(whiteCfg) else {
            return image
        }

        let symRect = NSRect(
            x: (canvasSize.width - whiteSym.size.width) / 2,
            y: (canvasSize.height - whiteSym.size.height) / 2,
            width: whiteSym.size.width,
            height: whiteSym.size.height
        )
        whiteSym.draw(in: symRect, from: .zero, operation: .sourceOver, fraction: 1.0)

        ctx.setBlendMode(.sourceIn)
        NSColor(red: 0.000, green: 0.478, blue: 1.000, alpha: 1.0).setFill()
        NSRect(origin: .zero, size: canvasSize).fill()
        ctx.setBlendMode(.normal)

        return image
    }
}
