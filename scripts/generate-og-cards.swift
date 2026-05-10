#!/usr/bin/env swift
//
// generate-og-cards.swift
//
// Renders three GitHub social-preview ("OG card") options as PNG into
// docs/og/og-card-{1,2,3}.png. Run from the repo root:
//
//     swift scripts/generate-og-cards.swift
//
// Each card is 1280×640 (the size GitHub serves from the repo's
// "Social preview" setting). All visible content stays inside a 40pt
// safe margin per GitHub's published template, so nothing important
// crops at smaller renders (Twitter cards, Slack unfurls).
//
// Drawing language matches Sources/AVPainRelieverApp/AppIcon.swift —
// pale icy-blue palette, Apple-system-blue glyph, plain native macOS
// look (no brand colors per the 2026-05-02 aesthetic pivot).
//
// To upload after generation: GitHub repo → Settings → General →
// Social preview → Edit → upload one of the three PNGs.

import AppKit
import Foundation

// MARK: - Constants

let canvas = NSSize(width: 1280, height: 640)
let safeMargin: CGFloat = 40

let topIce = NSColor(red: 0.965, green: 0.985, blue: 1.000, alpha: 1.0)
let bottomIce = NSColor(red: 0.840, green: 0.905, blue: 0.975, alpha: 1.0)
let appleSystemBlue = NSColor(red: 0.000, green: 0.478, blue: 1.000, alpha: 1.0)
let inkPrimary = NSColor(white: 0.10, alpha: 1.0)
let inkSecondary = NSColor(white: 0.35, alpha: 1.0)

// MARK: - Bitmap render helper

func render(_ drawer: (CGContext) -> Void) -> Data? {
    let width = Int(canvas.width)
    let height = Int(canvas.height)
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 4 * width,
        bitsPerPixel: 32
    ) else { return nil }

    let ctx = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    drawer(ctx.cgContext)
    NSGraphicsContext.restoreGraphicsState()

    return bitmap.representation(using: .png, properties: [:])
}

// MARK: - App-icon squircle

/// Draws the app's pale-ice squircle with the centered USB-fingerprint
/// glyph. Mirrors `AppIcon.makeIcon`'s recipe but parameterized by
/// rect so it can sit anywhere on the canvas.
func drawAppIcon(in rect: NSRect, ctx: CGContext) {
    let cornerRadius: CGFloat = rect.width * 0.225
    let path = NSBezierPath(
        roundedRect: rect,
        xRadius: cornerRadius,
        yRadius: cornerRadius
    )

    ctx.saveGState()
    path.addClip()
    if let gradient = NSGradient(colors: [topIce, bottomIce]) {
        gradient.draw(in: rect, angle: -90)
    }
    if let highlight = NSGradient(colorsAndLocations:
        (NSColor.white.withAlphaComponent(0.22), 0.0),
        (NSColor.white.withAlphaComponent(0.0), 0.45)
    ) {
        highlight.draw(in: rect, angle: -90)
    }
    ctx.restoreGState()

    // Glyph: white masked into Apple-system-blue.
    let glyphSize = NSSize(width: rect.width, height: rect.height)
    let glyph = NSImage(size: glyphSize)
    glyph.lockFocus()
    if
        let gctx = NSGraphicsContext.current?.cgContext,
        let sym = NSImage(
            systemSymbolName: "externaldrive.connected.to.line.below",
            accessibilityDescription: nil
        )
    {
        let pt = rect.width * 0.55
        let baseCfg = NSImage.SymbolConfiguration(pointSize: pt, weight: .regular)
        let whiteCfg = baseCfg.applying(
            NSImage.SymbolConfiguration(paletteColors: [NSColor.white])
        )
        if let whiteSym = sym.withSymbolConfiguration(whiteCfg) {
            let symRect = NSRect(
                x: (glyphSize.width - whiteSym.size.width) / 2,
                y: (glyphSize.height - whiteSym.size.height) / 2,
                width: whiteSym.size.width,
                height: whiteSym.size.height
            )
            whiteSym.draw(in: symRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            gctx.setBlendMode(.sourceIn)
            appleSystemBlue.setFill()
            NSRect(origin: .zero, size: glyphSize).fill()
            gctx.setBlendMode(.normal)
        }
    }
    glyph.unlockFocus()
    glyph.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)

    // Edge stroke.
    NSBezierPath(
        roundedRect: rect,
        xRadius: cornerRadius,
        yRadius: cornerRadius
    ).also { p in
        p.lineWidth = rect.width * 0.0040
        NSColor.black.withAlphaComponent(0.18).setStroke()
        p.stroke()
    }
}

extension NSObject {
    @discardableResult
    func also(_ block: (Self) -> Void) -> Self { block(self); return self }
}

// MARK: - SF Symbol image (single color)

func sfSymbol(_ name: String, point: CGFloat, color: NSColor) -> NSImage? {
    guard let sym = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
        return nil
    }
    let cfg = NSImage.SymbolConfiguration(pointSize: point, weight: .regular)
        .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
    return sym.withSymbolConfiguration(cfg)
}

// MARK: - Text drawing

/// Draw a single line of text with `point.y` as the baseline. Fonts in
/// AppKit on a non-flipped graphics context use `.draw(at:)` with the
/// point as the baseline-bottom-left of the rendered text.
func drawText(
    _ string: String,
    at point: NSPoint,
    font: NSFont,
    color: NSColor
) {
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .kern: -0.5
    ]
    NSAttributedString(string: string, attributes: attrs).draw(at: point)
}

func textSize(_ string: String, font: NSFont) -> NSSize {
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .kern: -0.5]
    return NSAttributedString(string: string, attributes: attrs).size()
}

/// X coordinate that horizontally centers `string` in `width`.
func centerX(_ string: String, font: NSFont, in width: CGFloat) -> CGFloat {
    (width - textSize(string, font: font).width) / 2
}

// MARK: - Card 1 — Hero (centered)

/// App icon centered at the top, name centered below, tagline below
/// that. Pale icy gradient background — feels like a continuation of
/// the app icon. Most "official product card" of the three.
func renderCard1() -> Data? {
    return render { _ in
        // Background: same pale-ice gradient as the icon.
        if let bg = NSGradient(colors: [topIce, bottomIce]) {
            bg.draw(in: NSRect(origin: .zero, size: canvas), angle: -90)
        }

        // Icon — 220pt squircle, horizontally centered, upper portion.
        let iconSize: CGFloat = 220
        let iconRect = NSRect(
            x: (canvas.width - iconSize) / 2,
            y: 380,
            width: iconSize,
            height: iconSize
        )
        drawAppIcon(in: iconRect, ctx: NSGraphicsContext.current!.cgContext)

        // Title — baseline at y=260 (room below icon).
        let title = "AV Pain Reliever"
        let titleFont = NSFont.systemFont(ofSize: 92, weight: .bold)
        drawText(
            title,
            at: NSPoint(x: centerX(title, font: titleFont, in: canvas.width), y: 240),
            font: titleFont,
            color: inkPrimary
        )

        // Tagline — baseline at y=160.
        let tagline = "Audio and camera that follow your dock."
        let taglineFont = NSFont.systemFont(ofSize: 32, weight: .regular)
        drawText(
            tagline,
            at: NSPoint(x: centerX(tagline, font: taglineFont, in: canvas.width), y: 160),
            font: taglineFont,
            color: inkSecondary
        )
    }
}

// MARK: - Card 2 — Asymmetric (icon left, text right)

/// Large app icon on the left half, name + tagline stacked on the
/// right half. White background. Cleaner / more modern feel; reads
/// well at every social-preview size.
func renderCard2() -> Data? {
    return render { _ in
        // Background: pure white.
        NSColor.white.setFill()
        NSRect(origin: .zero, size: canvas).fill()

        // Icon — 420pt squircle, vertically centered, on the left.
        let iconSize: CGFloat = 420
        let iconX: CGFloat = 90
        let iconRect = NSRect(
            x: iconX,
            y: (canvas.height - iconSize) / 2,
            width: iconSize,
            height: iconSize
        )
        drawAppIcon(in: iconRect, ctx: NSGraphicsContext.current!.cgContext)

        // Right column starts after the icon + breathing room.
        let textX = iconX + iconSize + 70

        // Title — baseline at y=380 (above vertical midpoint).
        let title = "AV Pain Reliever"
        let titleFont = NSFont.systemFont(ofSize: 78, weight: .bold)
        drawText(
            title,
            at: NSPoint(x: textX, y: 380),
            font: titleFont,
            color: inkPrimary
        )

        // Tagline — two lines, drawn separately. First line baseline
        // at y=290, second at y=234 (line spacing ≈ 56pt for 38pt font).
        let taglineFont = NSFont.systemFont(ofSize: 38, weight: .regular)
        drawText(
            "Plug in. Unplug.",
            at: NSPoint(x: textX, y: 290),
            font: taglineFont,
            color: inkSecondary
        )
        drawText(
            "Don't think about it.",
            at: NSPoint(x: textX, y: 234),
            font: taglineFont,
            color: inkSecondary
        )
    }
}

// MARK: - Card 3 — Story (workflow row)

/// Three SF Symbols in a row showing the value prop visually:
/// USB device → audio → camera. Light background. Title + tagline
/// below. The "what does this app actually do" card.
func renderCard3() -> Data? {
    return render { _ in
        // Background: very pale neutral.
        NSColor(white: 0.97, alpha: 1.0).setFill()
        NSRect(origin: .zero, size: canvas).fill()

        // Three symbols centered horizontally, sitting in the upper half.
        let symbolPoint: CGFloat = 130
        let chevronPoint: CGFloat = 60
        let symbols: [String] = [
            "externaldrive.connected.to.line.below",
            "speaker.wave.2.fill",
            "camera.fill"
        ]
        let chevronGap: CGFloat = 60
        let rowY: CGFloat = canvas.height - 280

        // Compute total row width.
        var rowWidth: CGFloat = 0
        var pieces: [(NSImage, CGFloat)] = [] // image, width
        for (i, name) in symbols.enumerated() {
            if let s = sfSymbol(name, point: symbolPoint, color: appleSystemBlue) {
                pieces.append((s, s.size.width))
                rowWidth += s.size.width
            }
            if i < symbols.count - 1 {
                rowWidth += chevronGap * 2
                if let chev = sfSymbol("chevron.right", point: chevronPoint, color: NSColor(white: 0.65, alpha: 1.0)) {
                    rowWidth += chev.size.width
                }
            }
        }

        var x = (canvas.width - rowWidth) / 2
        for (i, piece) in pieces.enumerated() {
            let (img, w) = piece
            let pieceRect = NSRect(
                x: x,
                y: rowY - img.size.height / 2,
                width: w,
                height: img.size.height
            )
            img.draw(in: pieceRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            x += w
            if i < pieces.count - 1 {
                x += chevronGap
                if let chev = sfSymbol("chevron.right", point: chevronPoint, color: NSColor(white: 0.65, alpha: 1.0)) {
                    let chevRect = NSRect(
                        x: x,
                        y: rowY - chev.size.height / 2,
                        width: chev.size.width,
                        height: chev.size.height
                    )
                    chev.draw(in: chevRect, from: .zero, operation: .sourceOver, fraction: 1.0)
                    x += chev.size.width + chevronGap
                }
            }
        }

        // Title — baseline at y=180 (below the symbols row).
        let title = "AV Pain Reliever"
        let titleFont = NSFont.systemFont(ofSize: 76, weight: .bold)
        drawText(
            title,
            at: NSPoint(x: centerX(title, font: titleFont, in: canvas.width), y: 180),
            font: titleFont,
            color: inkPrimary
        )

        // Tagline — baseline at y=110.
        let tagline = "Your laptop knows where it is."
        let taglineFont = NSFont.systemFont(ofSize: 32, weight: .regular)
        drawText(
            tagline,
            at: NSPoint(x: centerX(tagline, font: taglineFont, in: canvas.width), y: 110),
            font: taglineFont,
            color: inkSecondary
        )
    }
}

// MARK: - Main

let outDir = "docs/og"
try? FileManager.default.createDirectory(
    atPath: outDir,
    withIntermediateDirectories: true
)

let outputs: [(String, () -> Data?)] = [
    ("\(outDir)/og-card-1.png", renderCard1),
    ("\(outDir)/og-card-2.png", renderCard2),
    ("\(outDir)/og-card-3.png", renderCard3)
]

for (path, render) in outputs {
    guard let data = render() else {
        FileHandle.standardError.write("error: render failed for \(path)\n".data(using: .utf8)!)
        exit(1)
    }
    try data.write(to: URL(fileURLWithPath: path))
    print("wrote \(path) (\(data.count) bytes)")
}
