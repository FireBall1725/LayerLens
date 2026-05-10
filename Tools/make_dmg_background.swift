#!/usr/bin/env swift
//
// One-shot generator for the .dmg installer background image. Run when the
// design needs updating; commit the resulting Tools/Assets/dmg-background.png
// so CI doesn't have to regenerate it on every release.
//
//     swift Tools/make_dmg_background.swift
//
// Targets a 540×380 window: matches the create-dmg call in Tools/build_dmg.sh
// and looks well-proportioned next to two 128pt icons + an arrow.

import AppKit
import Foundation

let size = NSSize(width: 540, height: 380)
let outputDir = URL(fileURLWithPath: "Tools/Assets", isDirectory: true)
try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

let image = NSImage(size: size)
image.lockFocus()

// Light, neutral background. Finder draws icon labels in their default
// (dark) colour, which is unreadable on dark backgrounds. A near-white
// gradient lets the labels be visible without overriding Finder defaults.
let gradient = NSGradient(colors: [
    NSColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1),
    NSColor(red: 0.91, green: 0.92, blue: 0.94, alpha: 1),
])!
gradient.draw(in: NSRect(origin: .zero, size: size), angle: -90)

// Headline: "Drag LayerLens to Applications".
let title = "Drag LayerLens to your Applications folder"
let titleAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
    .foregroundColor: NSColor(white: 0.10, alpha: 1),
]
let titleSize = (title as NSString).size(withAttributes: titleAttrs)
let titlePoint = NSPoint(
    x: (size.width - titleSize.width) / 2,
    y: size.height - 56
)
(title as NSString).draw(at: titlePoint, withAttributes: titleAttrs)

// Subhead: small reassuring follow-up.
let subtitle = "Then launch from the menu bar to get started."
let subtitleAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 12, weight: .regular),
    .foregroundColor: NSColor(white: 0.40, alpha: 1),
]
let subtitleSize = (subtitle as NSString).size(withAttributes: subtitleAttrs)
let subtitlePoint = NSPoint(
    x: (size.width - subtitleSize.width) / 2,
    y: size.height - 80
)
(subtitle as NSString).draw(at: subtitlePoint, withAttributes: subtitleAttrs)

// Arrow between the (eventual) two icon positions. create-dmg places icons
// at y=200 from the *top*, which in CG (bottom-left origin) is y=180. We
// nudge a touch above that so the arrow lines up with the squircle's visual
// centre rather than the icon area's geometric centre (the area is taller
// because of the label below the squircle).
let arrowColor = NSColor(red: 0.30, green: 0.55, blue: 0.85, alpha: 1.0)
arrowColor.setFill()
arrowColor.setStroke()

let arrowPath = NSBezierPath()
let baseY: CGFloat = 180
let shaftLeft: CGFloat = 215
let shaftRight: CGFloat = 305
let shaftHalfHeight: CGFloat = 6
let headWidth: CGFloat = 18

// Shaft (rectangle).
arrowPath.move(to: NSPoint(x: shaftLeft, y: baseY - shaftHalfHeight))
arrowPath.line(to: NSPoint(x: shaftRight, y: baseY - shaftHalfHeight))
arrowPath.line(to: NSPoint(x: shaftRight, y: baseY + shaftHalfHeight))
arrowPath.line(to: NSPoint(x: shaftLeft, y: baseY + shaftHalfHeight))
arrowPath.close()
arrowPath.fill()

// Head (triangle).
let headPath = NSBezierPath()
headPath.move(to: NSPoint(x: shaftRight, y: baseY - headWidth))
headPath.line(to: NSPoint(x: shaftRight + headWidth + 4, y: baseY))
headPath.line(to: NSPoint(x: shaftRight, y: baseY + headWidth))
headPath.close()
headPath.fill()

image.unlockFocus()

// Encode + write.
guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("Failed to render PNG.\n", stderr)
    exit(1)
}
let outputURL = outputDir.appendingPathComponent("dmg-background.png")
try png.write(to: outputURL)
print("Wrote \(outputURL.path) (\(png.count) bytes)")
