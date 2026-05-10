#!/usr/bin/env swift
//
// One-shot generator for the LayerLens app icon. Renders the SF Symbol
// "keyboard" on a slate-blue squircle at every size macOS expects, then
// runs `iconutil` to package the result as Tools/Assets/AppIcon.icns.
//
//     swift Tools/make_app_icon.swift
//
// Commit the resulting Tools/Assets/AppIcon.icns so CI doesn't regenerate
// on every release. Re-run only when redesigning the icon.

import AppKit
import Foundation

let assetsDir = URL(fileURLWithPath: "Tools/Assets", isDirectory: true)
let iconsetDir = assetsDir.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try? FileManager.default.removeItem(at: iconsetDir)
try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

/// macOS app-icon corner radius scales with size. Apple's squircle uses
/// roughly 22.5% of the icon edge. 230/1024 matches the standard Big Sur+
/// app-icon shape.
func cornerRadius(for size: CGFloat) -> CGFloat {
    size * (230.0 / 1024.0)
}

/// Render the icon at one specific edge size and return the PNG data.
func render(size: CGFloat) -> Data {
    let pixels = Int(size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 32
    ),
    let context = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("Failed to create bitmap context for \(pixels)pt")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let mask = NSBezierPath(
        roundedRect: rect,
        xRadius: cornerRadius(for: size),
        yRadius: cornerRadius(for: size)
    )
    mask.addClip()

    let gradient = NSGradient(colors: [
        NSColor(red: 0.20, green: 0.30, blue: 0.50, alpha: 1),
        NSColor(red: 0.30, green: 0.42, blue: 0.65, alpha: 1),
    ])!
    gradient.draw(in: rect, angle: -90)

    let symbolSize = size * 0.62
    let config = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .medium)
    if let symbol = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let imgSize = symbol.size
        // Tint the glyph white by re-rendering it with a colour overlay.
        let tinted = NSImage(size: imgSize)
        tinted.lockFocus()
        symbol.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1.0)
        NSColor.white.set()
        NSRect(origin: .zero, size: imgSize).fill(using: .sourceAtop)
        tinted.unlockFocus()

        let drawRect = NSRect(
            x: (size - imgSize.width) / 2,
            y: (size - imgSize.height) / 2,
            width: imgSize.width,
            height: imgSize.height
        )
        tinted.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 0.95)
    }

    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("Failed to encode PNG for \(pixels)pt")
    }
    return png
}

// macOS .iconset expects these specific filenames. Each is rendered at the
// matching pixel dimension; @2x variants render at double the base size.
struct Variant {
    let edgeSize: CGFloat
    let filename: String
}
let variants: [Variant] = [
    .init(edgeSize: 16,   filename: "icon_16x16.png"),
    .init(edgeSize: 32,   filename: "icon_16x16@2x.png"),
    .init(edgeSize: 32,   filename: "icon_32x32.png"),
    .init(edgeSize: 64,   filename: "icon_32x32@2x.png"),
    .init(edgeSize: 128,  filename: "icon_128x128.png"),
    .init(edgeSize: 256,  filename: "icon_128x128@2x.png"),
    .init(edgeSize: 256,  filename: "icon_256x256.png"),
    .init(edgeSize: 512,  filename: "icon_256x256@2x.png"),
    .init(edgeSize: 512,  filename: "icon_512x512.png"),
    .init(edgeSize: 1024, filename: "icon_512x512@2x.png"),
]

for variant in variants {
    let png = render(size: variant.edgeSize)
    let url = iconsetDir.appendingPathComponent(variant.filename)
    try png.write(to: url)
}

// `iconutil --convert icns` packages the iconset folder into a single .icns.
let icnsURL = assetsDir.appendingPathComponent("AppIcon.icns")
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["--convert", "icns", "--output", icnsURL.path, iconsetDir.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    fputs("iconutil failed (status \(process.terminationStatus))\n", stderr)
    exit(1)
}

// Clean up the intermediate iconset folder; we only ship the .icns.
try FileManager.default.removeItem(at: iconsetDir)
print("Wrote \(icnsURL.path)")
