import SwiftUI
import AppKit

/// Hex round-trip for `Color` so user-picked theme colours can persist to
/// UserDefaults as plain strings.
extension Color {
    /// Parse `#RRGGBB` or `#RRGGBBAA`. Falls back to black on a malformed input.
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }

        var raw: UInt64 = 0
        Scanner(string: s).scanHexInt64(&raw)

        let r, g, b, a: Double
        switch s.count {
        case 6:
            r = Double((raw >> 16) & 0xFF) / 255
            g = Double((raw >>  8) & 0xFF) / 255
            b = Double( raw        & 0xFF) / 255
            a = 1
        case 8:
            r = Double((raw >> 24) & 0xFF) / 255
            g = Double((raw >> 16) & 0xFF) / 255
            b = Double((raw >>  8) & 0xFF) / 255
            a = Double( raw        & 0xFF) / 255
        default:
            r = 0; g = 0; b = 0; a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    /// Stable `#RRGGBB` (or `#RRGGBBAA` when alpha < 1) representation.
    func toHex() -> String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor.black
        let r = Int((ns.redComponent   * 255).rounded())
        let g = Int((ns.greenComponent * 255).rounded())
        let b = Int((ns.blueComponent  * 255).rounded())
        let a = Int((ns.alphaComponent * 255).rounded())
        if a < 255 {
            return String(format: "#%02X%02X%02X%02X", r, g, b, a)
        }
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
