import SwiftUI
import LayerLensCore

extension View {
    /// Apply a transform only when `condition` is true. Used to skip the
    /// rename context menu/alert in the floating overlay (interactive=false).
    @ViewBuilder
    fileprivate func `if`<Content: View>(
        _ condition: Bool,
        transform: (Self) -> Content
    ) -> some View {
        if condition { transform(self) } else { self }
    }
}

/// Renders a `KeyboardLayout` as positioned, axis-aligned rectangles, with
/// the keycode for each (row, col) drawn inside.
struct KeyboardLayoutView: View {
    let layout: KeyboardLayout
    /// Keycodes for the visible layer, indexed `[row][col]`. May be empty if
    /// the keymap hasn't been read yet.
    let layerKeycodes: [[UInt16]]
    /// Points per "u" (one standard key unit).
    let scale: Double
    /// VIA protocol version reported by the connected device. Determines
    /// which keycode-byte mapping the formatter uses (v10 vs v11+).
    let protocolVersion: UInt16
    /// True in the main window (right-click context menu enabled), false in
    /// the floating overlay (no interaction needed).
    var interactive: Bool = false
    /// When true, draws the matrix coordinate under each key regardless of
    /// `Preferences.showMatrixCoords`. The Configure window uses this so the
    /// keymap viewer is always self-describing; the overlay leaves it false
    /// and respects the user's preference.
    var forceShowMatrixCoords: Bool = false
    /// When true, key labels honor `Preferences.labelFontName` /
    /// `labelFontSize`. The overlay sets this; the Configure window leaves
    /// it false so the editor stays on the system font even when the user
    /// picks a wild face for their on-screen overlay.
    var useOverlayFont: Bool = false
    /// When true, key fills + label colour come from the user's theme
    /// (`Preferences.colourRegular`, `colourModifier`, ...). The overlay
    /// sets this; the Configure window leaves it false so the editor stays
    /// on a neutral default palette regardless of which theme the user picks
    /// for their on-screen overlay.
    var useOverlayTheme: Bool = false
    /// Set of HID keyboard-page (`0x07`) usage codes currently held down.
    /// Comparable to `layerKeycodes` for the basic-key range. When a key
    /// in the visible layer has a keycode in this set, it lights up. Pass
    /// an empty set (default) to disable the live highlight.
    var pressedKeycodes: Set<UInt16> = []

    var body: some View {
        let bounds = computeBounds()
        let width  = (bounds.maxX - bounds.minX) * scale
        let height = (bounds.maxY - bounds.minY) * scale

        ZStack(alignment: .topLeading) {
            ForEach(Array(layout.keys.enumerated()), id: \.offset) { _, key in
                KeyView(
                    keycode: keycode(for: key),
                    matrixLabel: "\(key.row),\(key.col)",
                    protocolVersion: protocolVersion,
                    interactive: interactive,
                    forceShowMatrixCoords: forceShowMatrixCoords,
                    useOverlayFont: useOverlayFont,
                    useOverlayTheme: useOverlayTheme,
                    isPressed: isPressed(key)
                )
                .frame(
                    width: max(1, key.w * scale - 4),
                    height: max(1, key.h * scale - 4)
                )
                .rotationEffect(.degrees(key.rotation), anchor: .center)
                .offset(
                    x: (key.x - bounds.minX) * scale + 2,
                    y: (key.y - bounds.minY) * scale + 2
                )
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }

    /// True when this key's layer keycode is in the live pressed-keys set.
    /// Skips placeholder slots (`KC_NO` / `KC_TRNS`) so transparent keys
    /// don't light up just because their numeric value happened to coincide
    /// with a HID usage.
    private func isPressed(_ key: LayoutKey) -> Bool {
        guard !pressedKeycodes.isEmpty else { return false }
        guard let kc = keycode(for: key), kc != 0x0000, kc != 0x0001 else { return false }
        return pressedKeycodes.contains(kc)
    }

    private func keycode(for key: LayoutKey) -> UInt16? {
        guard key.row < layerKeycodes.count,
              key.col < layerKeycodes[key.row].count else {
            return nil
        }
        return layerKeycodes[key.row][key.col]
    }

    private func computeBounds() -> (minX: Double, minY: Double, maxX: Double, maxY: Double) {
        guard !layout.keys.isEmpty else { return (0, 0, 1, 1) }
        var minX =  Double.infinity
        var minY =  Double.infinity
        var maxX = -Double.infinity
        var maxY = -Double.infinity
        for k in layout.keys {
            // Take the AABB of the rotated rectangle, not just the un-rotated
            // (x, y, w, h). For rotated thumb-cluster keys (Kyria etc.) the
            // rotated corners can stick out past the un-rotated rect, and the
            // overall window would clip them otherwise.
            for corner in rotatedCorners(of: k) {
                minX = min(minX, corner.x)
                minY = min(minY, corner.y)
                maxX = max(maxX, corner.x)
                maxY = max(maxY, corner.y)
            }
        }
        return (minX, minY, maxX, maxY)
    }

    /// Four corners of a key's rectangle in layout space, rotated about its
    /// own centre. Returns the un-rotated corners when `rotation == 0`.
    private func rotatedCorners(of key: LayoutKey) -> [(x: Double, y: Double)] {
        let cx = key.x + key.w / 2
        let cy = key.y + key.h / 2
        let halfW = key.w / 2
        let halfH = key.h / 2
        let local: [(Double, Double)] = [
            (-halfW, -halfH), ( halfW, -halfH),
            ( halfW,  halfH), (-halfW,  halfH),
        ]
        if abs(key.rotation) <= .ulpOfOne {
            return local.map { (cx + $0.0, cy + $0.1) }
        }
        let radians = key.rotation * .pi / 180
        let cosA = cos(radians)
        let sinA = sin(radians)
        return local.map { p in
            let rx = p.0 * cosA - p.1 * sinA
            let ry = p.0 * sinA + p.1 * cosA
            return (cx + rx, cy + ry)
        }
    }
}

private struct KeyView: View {
    @Environment(Preferences.self) private var preferences

    let keycode: UInt16?
    let matrixLabel: String
    let protocolVersion: UInt16
    let interactive: Bool
    let forceShowMatrixCoords: Bool
    let useOverlayFont: Bool
    let useOverlayTheme: Bool
    let isPressed: Bool

    @State private var renameSheetActive: Bool = false
    @State private var renameDraft: String = ""

    private var resolved: QMKKeycodeLabel? {
        guard let kc = keycode else { return nil }
        return QMKKeycodeFormatter.label(for: kc, protocolVersion: protocolVersion)
    }

    private var override: String? {
        guard let kc = keycode, kc != 0x0000, kc != 0x0001 else { return nil }
        return preferences.labelOverride(for: kc, protocolVersion: protocolVersion)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(fillStyle)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(
                            isPressed
                                ? AnyShapeStyle(Color.accentColor)
                                : AnyShapeStyle(Color.primary.opacity(isPlaceholderKey ? 0.18 : 0.10)),
                            lineWidth: isPressed ? 2 : 1
                        )
                )
                .shadow(
                    color: isPressed ? .accentColor.opacity(0.55) : .clear,
                    radius: isPressed ? 5 : 0
                )
                .scaleEffect(isPressed ? 1.04 : 1.0)
                .animation(.easeOut(duration: 0.08), value: isPressed)

            VStack(alignment: .leading, spacing: 1) {
                // Configure window stays on system 11pt; the overlay honors
                // the user's font + size preference.
                let primarySize: Double = useOverlayFont ? preferences.labelFontSize : 11
                let textColour = palette.text
                if let alt = shiftedGlyph {
                    Text(alt)
                        .font(primaryFont(size: primarySize - 1))
                        .foregroundStyle(textColour.opacity(0.65))
                }
                Text(primaryText)
                    .font(primaryFont(size: primarySize))
                    .foregroundStyle(textColour)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                if forceShowMatrixCoords || preferences.showMatrixCoords {
                    Text(matrixLabel)
                        .font(.system(size: max(8, primarySize - 2), design: .monospaced))
                        .foregroundStyle(textColour.opacity(0.55))
                }
            }
            .padding(6)
        }
        .help(tooltip)
        .if(interactive && keycode != nil && keycode != 0 && keycode != 1) { view in
            view.contextMenu {
                Button("Rename label…") {
                    renameDraft = override ?? defaultLabel
                    renameSheetActive = true
                }
                if override != nil {
                    Button("Reset to default") {
                        if let kc = keycode {
                            preferences.setLabelOverride(nil, for: kc, protocolVersion: protocolVersion)
                        }
                    }
                }
            }
            .alert("Rename label", isPresented: $renameSheetActive, actions: {
                TextField("Label", text: $renameDraft)
                Button("Save") {
                    if let kc = keycode {
                        preferences.setLabelOverride(renameDraft, for: kc, protocolVersion: protocolVersion)
                    }
                }
                Button("Cancel", role: .cancel) {}
            }, message: {
                if let kc = keycode {
                    Text("Custom label for keycode \(String(format: "0x%04X", kc)) (default: “\(defaultLabel)”).")
                }
            })
        }
    }

    private var defaultLabel: String {
        guard let kc = keycode else { return "" }
        if let l = resolved, !l.tap.isEmpty { return l.tap }
        return String(format: "0x%04X", kc)
    }

    private func primaryFont(size: Double) -> Font {
        useOverlayFont
            ? preferences.font(size: size)
            : .system(size: size, weight: .semibold)
    }

    /// Alt-glyph (e.g. "!") for keys that have a shifted variant, drawn
    /// above the primary label like VIA does. Suppressed when the user has
    /// set a custom override; they expect their text exactly.
    private var shiftedGlyph: String? {
        guard let kc = keycode, override == nil else { return nil }
        return QMKKeycodeFormatter.usShiftedGlyph(forKeycode: kc)
    }

    private var primaryText: String {
        guard let kc = keycode else { return "-" }
        if kc == 0x0001 { return "▽" }       // KC_TRANSPARENT
        if kc == 0x0000 { return "" }        // KC_NO; leave empty so the empty fill reads "nothing"
        if let o = override, !o.isEmpty {
            return o
        }
        if let l = resolved, !l.tap.isEmpty {
            return l.tap
        }
        return preferences.showHexFallback ? String(format: "0x%04X", kc) : ""
    }

    private var tooltip: String {
        guard let kc = keycode else { return "" }
        let hex = String(format: "0x%04X", kc)
        if let o = override, !o.isEmpty {
            let base = resolved?.tap ?? hex
            return "\(o)  ←  \(base) (\(hex))"
        }
        if let l = resolved, !l.tap.isEmpty {
            return "\(l.tap) (\(hex))"
        }
        return hex
    }

    /// Resolved palette: the user's overlay theme when this view is part of
    /// the floating overlay, or the LayerLens stock dark defaults when it's
    /// embedded in the Configure window. Keeps the editor visually neutral
    /// regardless of how wild a theme the user picks for their HUD.
    private struct Palette {
        let regular: Color
        let modifier: Color
        let layer: Color
        let special: Color
        let text: Color
    }

    private var palette: Palette {
        if useOverlayTheme {
            return Palette(
                regular: preferences.colourRegular,
                modifier: preferences.colourModifier,
                layer: preferences.colourLayer,
                special: preferences.colourSpecial,
                text: preferences.colourText
            )
        }
        return Palette(
            regular: Color(hex: "#2D3340"),
            modifier: Color(hex: "#5B5184"),
            layer: Color(hex: "#3D6B8C"),
            special: Color(hex: "#704030"),
            text: Color.white
        )
    }

    /// True for keys with no keycode programmed (`KC_NO`) or the
    /// inherit-from-below placeholder (`KC_TRNS`). These render with a
    /// frosted-glass `Material` backdrop instead of a flat tinted fill,
    /// so they read as "empty / pass-through" rather than "dim coloured key."
    private var isPlaceholderKey: Bool {
        guard let kc = keycode else { return true }
        return kc == 0x0000 || kc == 0x0001
    }

    /// Resolved fill as a type-erased `ShapeStyle`. Solid keys use the
    /// theme `Color`; placeholder keys use `.ultraThinMaterial` for a
    /// glass look that picks up the wallpaper / window background through
    /// SwiftUI's blur backdrop.
    private var fillStyle: AnyShapeStyle {
        if isPlaceholderKey {
            return AnyShapeStyle(.ultraThinMaterial)
        }
        if let l = resolved {
            switch l.kind {
            case .modifier:
                return AnyShapeStyle(palette.modifier)
            case .special:
                return AnyShapeStyle(palette.special)
            case .basic:
                if l.layerRef != nil { return AnyShapeStyle(palette.layer) }
                return AnyShapeStyle(palette.regular)
            }
        }
        return AnyShapeStyle(palette.regular)
    }
}
