#!/usr/bin/env swift
// Renders the AV Pain Reliever app-icon (a neutral gray squircle with
// a white pills.fill SF Symbol on top) into all the iconset PNG sizes
// macOS expects, in the directory passed as $1 (defaults to
// AppIcon.iconset/ in CWD). One-shot tool — re-run only when the icon
// design changes.
//
// The drawing logic mirrors AVPainRelieverApp/AppIcon.swift but is
// intentionally inlined here so this script has zero source dependencies
// and runs as a one-file `swift` invocation.

import AppKit
import Foundation

let iconsetPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "AppIcon.iconset"

let iconsetURL = URL(fileURLWithPath: iconsetPath)
try? FileManager.default.createDirectory(
    at: iconsetURL,
    withIntermediateDirectories: true
)

func drawIcon(in rect: NSRect) {
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }
    let size = rect.size

    let cornerRadius: CGFloat = size.width * 0.225
    let path = NSBezierPath(
        roundedRect: rect,
        xRadius: cornerRadius,
        yRadius: cornerRadius
    )
    path.addClip()

    let topGray = NSColor(red: 0.62, green: 0.62, blue: 0.64, alpha: 1.0)
    let bottomGray = NSColor(red: 0.34, green: 0.34, blue: 0.36, alpha: 1.0)
    if let gradient = NSGradient(colors: [topGray, bottomGray]) {
        gradient.draw(in: rect, angle: -90)
    }

    let symbolPointSize: CGFloat = size.width * 0.527
    let symbolConfig = NSImage.SymbolConfiguration(
        pointSize: symbolPointSize,
        weight: .semibold
    )
    guard let template = NSImage(
        systemSymbolName: "pills.fill",
        accessibilityDescription: nil
    )?.withSymbolConfiguration(symbolConfig) else {
        FileHandle.standardError.write(Data("error: pills.fill SF Symbol unavailable\n".utf8))
        return
    }

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

func renderPNG(size pixelSize: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 32
    ) else {
        return nil
    }

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let rect = NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize)
    drawIcon(in: rect)

    return rep.representation(using: .png, properties: [:])
}

// Apple's iconutil-expected filenames + pixel dimensions.
let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16",       16),
    ("icon_16x16@2x",    32),
    ("icon_32x32",       32),
    ("icon_32x32@2x",    64),
    ("icon_128x128",    128),
    ("icon_128x128@2x", 256),
    ("icon_256x256",    256),
    ("icon_256x256@2x", 512),
    ("icon_512x512",    512),
    ("icon_512x512@2x", 1024),
]

for variant in variants {
    guard let data = renderPNG(size: variant.pixels) else {
        FileHandle.standardError.write(Data("error: failed to render \(variant.name)\n".utf8))
        exit(1)
    }
    let url = iconsetURL.appendingPathComponent("\(variant.name).png")
    do {
        try data.write(to: url)
        print("wrote \(url.path) (\(variant.pixels)×\(variant.pixels))")
    } catch {
        FileHandle.standardError.write(Data("error: \(url.path): \(error)\n".utf8))
        exit(1)
    }
}
