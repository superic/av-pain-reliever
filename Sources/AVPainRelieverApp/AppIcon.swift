import AppKit
import SwiftUI

/// Generates the app icon used at runtime — a cool-charcoal gradient
/// squircle with a single hand-drawn pharmaceutical capsule on top.
///
/// The capsule is two-tone (near-white "cap", soft warm-gray "body"
/// with a thin seam where they meet) and tilted ~25° downward to the
/// right. This is the "system utility" register: monochrome,
/// composed, the same family as Activity Monitor / Console / Disk
/// Utility — keeping the pills metaphor that matches the product
/// name without the kitchen-medicine-cabinet feel of the SF-Symbol
/// dual-pill glyph this replaces.
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

        // 1. Squircle clip + cool charcoal gradient. The hue shifts
        //    very slightly toward blue (cooler) so the icon reads as
        //    a "pro tool" rather than a generic gray rectangle, but
        //    stays well within the system-utility palette.
        ctx.saveGState()
        let cornerRadius: CGFloat = size.width * 0.225
        let squircle = NSBezierPath(
            roundedRect: NSRect(origin: .zero, size: size),
            xRadius: cornerRadius,
            yRadius: cornerRadius
        )
        squircle.addClip()

        let topGray = NSColor(red: 0.478, green: 0.486, blue: 0.510, alpha: 1.0)
        let bottomGray = NSColor(red: 0.180, green: 0.188, blue: 0.204, alpha: 1.0)
        if let gradient = NSGradient(colors: [topGray, bottomGray]) {
            gradient.draw(
                in: NSRect(origin: .zero, size: size),
                angle: -90  // top → bottom
            )
        }

        // 2. Capsule artwork. Drawn into a separate NSImage so the
        //    soft shadow lands once on the silhouette, not separately
        //    on each fill (which would compound and look muddy).
        let capsule = capsuleArtwork(canvasSize: size)
        ctx.saveGState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
        shadow.shadowOffset = NSSize(width: 0, height: -size.height * 0.010)
        shadow.shadowBlurRadius = size.width * 0.030
        shadow.set()
        capsule.draw(
            in: NSRect(origin: .zero, size: size),
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0
        )
        ctx.restoreGState()

        // 3. Subtle inner-edge highlight at ~4% white. Adds a hairline
        //    rim that helps the icon separate from a dark Dock or
        //    menu-bar background. Drawn last so it sits on top of
        //    both the gradient and the capsule shadow's spread.
        let edgePath = NSBezierPath(
            roundedRect: NSRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2),
            xRadius: cornerRadius - 2,
            yRadius: cornerRadius - 2
        )
        edgePath.lineWidth = 2
        NSColor.white.withAlphaComponent(0.04).setStroke()
        edgePath.stroke()

        ctx.restoreGState()
        return image
    }

    /// Two-tone pharmaceutical capsule, tilted ~25° down-to-the-right,
    /// rendered in its own image so the parent draw can apply a
    /// single shadow pass to the whole silhouette.
    private static func capsuleArtwork(canvasSize: NSSize) -> NSImage {
        let image = NSImage(size: canvasSize)
        image.lockFocus()
        defer { image.unlockFocus() }

        guard let ctx = NSGraphicsContext.current?.cgContext else {
            return image
        }

        // Capsule dimensions in local (unrotated) coords.
        let capsuleLength = canvasSize.width * 0.62
        let capsuleWidth = canvasSize.width * 0.20

        // Origin → centre, then rotate. -25° (radians) tilts the right
        // end down, so the cap (left half, near-white) sits up-and-to-
        // the-left — the canonical pharmaceutical-capsule pose.
        ctx.translateBy(x: canvasSize.width / 2, y: canvasSize.height / 2)
        ctx.rotate(by: -25 * .pi / 180)

        let capsuleRect = NSRect(
            x: -capsuleLength / 2,
            y: -capsuleWidth / 2,
            width: capsuleLength,
            height: capsuleWidth
        )
        let capsulePath = NSBezierPath(
            roundedRect: capsuleRect,
            xRadius: capsuleWidth / 2,
            yRadius: capsuleWidth / 2
        )

        // Clip subsequent fills to the capsule silhouette so the
        // half-fills land cleanly inside the rounded ends.
        NSGraphicsContext.current?.saveGraphicsState()
        capsulePath.addClip()

        // Cap — left half, near-white.
        NSColor(red: 0.957, green: 0.961, blue: 0.969, alpha: 1.0).set()
        NSRect(
            x: -capsuleLength / 2,
            y: -capsuleWidth / 2,
            width: capsuleLength / 2,
            height: capsuleWidth
        ).fill()

        // Body — right half, soft warm gray.
        NSColor(red: 0.765, green: 0.773, blue: 0.792, alpha: 1.0).set()
        NSRect(
            x: 0,
            y: -capsuleWidth / 2,
            width: capsuleLength / 2,
            height: capsuleWidth
        ).fill()

        // Seam — the thin band where cap and body meet on a real
        // pharma capsule. Slightly darker than either half so it
        // reads as a recess rather than a gap.
        let seamWidth = canvasSize.width * 0.012
        NSColor(red: 0.659, green: 0.667, blue: 0.686, alpha: 1.0).set()
        NSRect(
            x: -seamWidth / 2,
            y: -capsuleWidth / 2,
            width: seamWidth,
            height: capsuleWidth
        ).fill()

        // Highlight along the top edge of the upper half — a soft
        // white-to-clear gradient gives the capsule a glassy quality
        // without going skeuomorphic.
        if let highlight = NSGradient(colorsAndLocations:
            (NSColor.white.withAlphaComponent(0.16), 0.0),
            (NSColor.white.withAlphaComponent(0.0), 1.0)
        ) {
            let highlightRect = NSRect(
                x: -capsuleLength / 2,
                y: 0,
                width: capsuleLength,
                height: capsuleWidth / 2
            )
            highlight.draw(in: highlightRect, angle: 90)
        }

        NSGraphicsContext.current?.restoreGraphicsState()
        return image
    }
}
