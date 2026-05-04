#!/usr/bin/env swift
// Render the AV Pain Reliever app icon to a 1024×1024 PNG.
//
// Standalone Swift script invoked by `scripts/regen-icon.sh` whenever
// the design in `Sources/AVPainRelieverApp/AppIcon.swift` changes.
// The drawing routine here is a direct copy of `AppIcon.makeIcon()`
// (and its `capsuleArtwork` helper) so the regen path doesn't require
// linking the main module — keep the two in sync by hand. The
// duplication is small (~80 lines of Core Graphics) and the regen
// script is the only consumer.
//
// Usage:
//   swift scripts/render-app-icon.swift <output-png-path>
//
// Exits non-zero if the destination can't be written.

import AppKit
import Foundation

func makeIcon() -> NSImage {
    let size = NSSize(width: 1024, height: 1024)
    let image = NSImage(size: size)
    image.lockFocus()
    defer { image.unlockFocus() }

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        return image
    }

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
        gradient.draw(in: NSRect(origin: .zero, size: size), angle: -90)
    }

    let capsule = capsuleArtwork(canvasSize: size)
    ctx.saveGState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    shadow.shadowOffset = NSSize(width: 0, height: -size.height * 0.010)
    shadow.shadowBlurRadius = size.width * 0.030
    shadow.set()
    capsule.draw(in: NSRect(origin: .zero, size: size),
                 from: .zero,
                 operation: .sourceOver,
                 fraction: 1.0)
    ctx.restoreGState()

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

func capsuleArtwork(canvasSize: NSSize) -> NSImage {
    let image = NSImage(size: canvasSize)
    image.lockFocus()
    defer { image.unlockFocus() }

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        return image
    }

    let capsuleLength = canvasSize.width * 0.62
    let capsuleWidth = canvasSize.width * 0.20

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

    NSGraphicsContext.current?.saveGraphicsState()
    capsulePath.addClip()

    NSColor(red: 0.957, green: 0.961, blue: 0.969, alpha: 1.0).set()
    NSRect(x: -capsuleLength / 2, y: -capsuleWidth / 2,
           width: capsuleLength / 2, height: capsuleWidth).fill()

    NSColor(red: 0.765, green: 0.773, blue: 0.792, alpha: 1.0).set()
    NSRect(x: 0, y: -capsuleWidth / 2,
           width: capsuleLength / 2, height: capsuleWidth).fill()

    let seamWidth = canvasSize.width * 0.012
    NSColor(red: 0.659, green: 0.667, blue: 0.686, alpha: 1.0).set()
    NSRect(x: -seamWidth / 2, y: -capsuleWidth / 2,
           width: seamWidth, height: capsuleWidth).fill()

    if let highlight = NSGradient(colorsAndLocations:
        (NSColor.white.withAlphaComponent(0.16), 0.0),
        (NSColor.white.withAlphaComponent(0.0), 1.0)
    ) {
        let highlightRect = NSRect(
            x: -capsuleLength / 2, y: 0,
            width: capsuleLength, height: capsuleWidth / 2
        )
        highlight.draw(in: highlightRect, angle: 90)
    }

    NSGraphicsContext.current?.restoreGraphicsState()
    return image
}

// MARK: - script entry point

let args = CommandLine.arguments
guard args.count == 2 else {
    FileHandle.standardError.write(Data("usage: render-app-icon.swift <output-png>\n".utf8))
    exit(2)
}

let outputPath = args[1]
let image = makeIcon()
guard
    let tiff = image.tiffRepresentation,
    let rep = NSBitmapImageRep(data: tiff),
    let png = rep.representation(using: .png, properties: [:])
else {
    FileHandle.standardError.write(Data("error: failed to encode PNG\n".utf8))
    exit(1)
}

let url = URL(fileURLWithPath: outputPath)
do {
    try png.write(to: url)
    FileHandle.standardError.write(Data("wrote \(outputPath) (\(png.count) bytes)\n".utf8))
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
