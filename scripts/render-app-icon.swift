#!/usr/bin/env swift
// Render the AV Pain Reliever app icon to a 1024×1024 PNG.
//
// Standalone Swift script invoked by `scripts/regen-icon.sh` whenever
// the design in `Sources/AVPainRelieverApp/AppIcon.swift` changes.
// The drawing routine here is a direct copy of `AppIcon.makeIcon()`
// (and its `symbolMark()` helper) so the regen path doesn't require
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

    let cornerRadius: CGFloat = size.width * 0.225
    let canvasRect = NSRect(origin: .zero, size: size)
    let squircle = NSBezierPath(
        roundedRect: canvasRect,
        xRadius: cornerRadius,
        yRadius: cornerRadius
    )

    ctx.saveGState()
    squircle.addClip()
    let topIce = NSColor(red: 0.965, green: 0.985, blue: 1.000, alpha: 1.0)
    let bottomIce = NSColor(red: 0.840, green: 0.905, blue: 0.975, alpha: 1.0)
    if let gradient = NSGradient(colors: [topIce, bottomIce]) {
        gradient.draw(in: canvasRect, angle: -90)
    }
    if let highlight = NSGradient(colorsAndLocations:
        (NSColor.white.withAlphaComponent(0.22), 0.0),
        (NSColor.white.withAlphaComponent(0.0), 0.45)
    ) {
        highlight.draw(in: canvasRect, angle: -90)
    }
    ctx.restoreGState()

    let mark = symbolMark(canvasSize: size)
    ctx.saveGState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.10)
    shadow.shadowOffset = NSSize(width: 0, height: -size.height * 0.006)
    shadow.shadowBlurRadius = size.width * 0.012
    shadow.set()
    mark.draw(in: canvasRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    ctx.restoreGState()

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

func symbolMark(canvasSize: NSSize) -> NSImage {
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
