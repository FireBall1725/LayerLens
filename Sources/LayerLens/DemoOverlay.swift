import SwiftUI
import LayerLensCore

/// Visual classification of each demo key. Maps directly to the same theme
/// colours a real keyboard's keys are tinted with so the user can preview
/// every category at once.
enum DemoKeyKind {
    case basic, modifier, layer, special
}

/// One sample key for the preview overlay. Positions are in "u" (key units)
/// just like `LayoutKey`. `altGlyph` draws above the primary label, mirroring
/// VIA's two-line legend (e.g. "!" over "1").
struct DemoKey: Identifiable {
    let id: Int
    let x: Double
    let y: Double
    let w: Double
    let label: String
    let altGlyph: String?
    let coords: String
    let kind: DemoKeyKind
}

/// Cut-down 60% ANSI demo. Enough keys to exercise every theme colour and
/// the shifted-glyph rendering, without spending the screen real estate on
/// a full-size board.
enum DemoOverlay {
    static let keys: [DemoKey] = {
        var out: [DemoKey] = []
        var id = 0

        func add(_ x: Double, _ y: Double, _ w: Double,
                 _ label: String, _ alt: String? = nil,
                 _ kind: DemoKeyKind = .basic, coords: String) {
            out.append(DemoKey(id: id, x: x, y: y, w: w,
                               label: label, altGlyph: alt,
                               coords: coords, kind: kind))
            id += 1
        }

        // Row 0: number row with shifted glyphs above the digits.
        let numbers: [(String, String)] = [
            ("1","!"), ("2","@"), ("3","#"), ("4","$"), ("5","%"),
            ("6","^"), ("7","&"), ("8","*"), ("9","("), ("0",")"),
        ]
        add(0, 0, 1, "Esc", nil, .basic, coords: "0,0")
        for (i, pair) in numbers.enumerated() {
            add(1.0 + Double(i), 0, 1, pair.0, pair.1, .basic, coords: "0,\(i+1)")
        }
        add(11, 0, 1, "Bksp", nil, .basic, coords: "0,11")

        // Row 1: top alpha row. Trimmed to 12 columns (drop the right
        // bracket) so it fits the demo's 12u panel width.
        let r1 = ["Tab","Q","W","E","R","T","Y","U","I","O","P","["]
        for (i, l) in r1.enumerated() {
            add(Double(i), 1, 1, l, nil, .basic, coords: "1,\(i)")
        }

        // Row 2: home row.
        let r2 = ["Caps","A","S","D","F","G","H","J","K","L",";","Enter"]
        for (i, l) in r2.enumerated() {
            let kind: DemoKeyKind = (l == "Caps" || l == "Enter") ? .basic : .basic
            add(Double(i), 2, 1, l, nil, kind, coords: "2,\(i)")
        }

        // Row 3: bottom alpha row, framed by Shifts (modifier colour).
        let r3: [(String, DemoKeyKind, String?)] = [
            ("LShft", .modifier, nil), ("Z", .basic, nil), ("X", .basic, nil),
            ("C", .basic, nil), ("V", .basic, nil), ("B", .basic, nil),
            ("N", .basic, nil), ("M", .basic, nil),
            (",", .basic, "<"), (".", .basic, ">"), ("/", .basic, "?"),
            ("RShft", .modifier, nil),
        ]
        for (i, t) in r3.enumerated() {
            add(Double(i), 3, 1, t.0, t.2, t.1, coords: "3,\(i)")
        }

        // Row 4: modifiers, layer keys, space, special media keys.
        add(0, 4, 1,    "LCtl",  nil, .modifier, coords: "4,0")
        add(1, 4, 1,    "LAlt",  nil, .modifier, coords: "4,1")
        add(2, 4, 1,    "MO(1)", nil, .layer,    coords: "4,2")
        add(3, 4, 6,    "Space", nil, .basic,    coords: "4,3")
        add(9, 4, 1,    "TO(2)", nil, .layer,    coords: "4,9")
        add(10, 4, 1,   "RGB",   nil, .special,  coords: "4,10")
        add(11, 4, 1,   "Mute",  nil, .special,  coords: "4,11")

        return out
    }()

    static let widthInUnits: Double = 12
    static let heightInUnits: Double = 5
}

/// SwiftUI rendering of `DemoOverlay.keys` using the user's current overlay
/// preferences (size, opacity, theme, font, matrix-coords toggle). Used for
/// the live preview panel that the Settings window pops while the user is
/// on an overlay-affecting tab.
struct DemoOverlayView: View {
    @Environment(Preferences.self) private var preferences

    var body: some View {
        let scale = preferences.overlayScale
        let width  = DemoOverlay.widthInUnits  * scale
        let height = DemoOverlay.heightInUnits * scale

        // Match the real overlay's layout: layer-name capsule above the keys,
        // no surrounding backdrop. The NSPanel itself handles transparency.
        VStack(spacing: 6) {
            Text("Demo Layer")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(preferences.colourText)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(preferences.colourRegular.opacity(0.85))
                )

            ZStack(alignment: .topLeading) {
                ForEach(DemoOverlay.keys) { k in
                    demoKey(k)
                        .frame(
                            width: max(1, k.w * scale - 4),
                            height: max(1, scale - 4)
                        )
                        .offset(x: k.x * scale + 2, y: k.y * scale + 2)
                }
            }
            .frame(width: width, height: height, alignment: .topLeading)
        }
        .padding(12)
        .opacity(preferences.overlayOpacity)
    }

    private func demoKey(_ k: DemoKey) -> some View {
        let primarySize = preferences.labelFontSize
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(fill(for: k.kind))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(.white.opacity(0.10), lineWidth: 1)
                )
            VStack(alignment: .leading, spacing: 1) {
                if let alt = k.altGlyph {
                    Text(alt)
                        .font(preferences.font(size: primarySize - 1))
                        .foregroundStyle(preferences.colourText.opacity(0.65))
                }
                Text(k.label)
                    .font(preferences.font(size: primarySize))
                    .foregroundStyle(preferences.colourText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if preferences.showMatrixCoords {
                    Text(k.coords)
                        .font(.system(size: max(8, primarySize - 2), design: .monospaced))
                        .foregroundStyle(preferences.colourText.opacity(0.55))
                }
            }
            .padding(6)
        }
    }

    private func fill(for kind: DemoKeyKind) -> Color {
        switch kind {
        case .basic:    return preferences.colourRegular
        case .modifier: return preferences.colourModifier
        case .layer:    return preferences.colourLayer
        case .special:  return preferences.colourSpecial
        }
    }
}
