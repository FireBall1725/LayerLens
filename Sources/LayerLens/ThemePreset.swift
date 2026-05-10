import SwiftUI

/// A named theme preset that maps to LayerLens's five colour slots
/// (regular / modifier / layer / special / text). Hex strings keep the
/// declarations compact and easy to eyeball-compare against the source
/// palettes (Dracula, Solarized, etc.).
struct ThemePreset: Identifiable, Hashable {
    enum Kind: String, Hashable { case dark, light }

    let id: String
    let name: String
    let kind: Kind
    let regular: String
    let modifier: String
    let layer: String
    let special: String
    let text: String

    /// Apply every colour slot to the user's preferences. Overlay opacity is
    /// left untouched. That's a usability choice, not a theme choice.
    @MainActor
    func apply(to preferences: Preferences) {
        preferences.colourRegular  = Color(hex: regular)
        preferences.colourModifier = Color(hex: modifier)
        preferences.colourLayer    = Color(hex: layer)
        preferences.colourSpecial  = Color(hex: special)
        preferences.colourText     = Color(hex: text)
    }
}

extension ThemePreset {
    /// Curated list of common programmer themes, grouped dark-first. Color
    /// slot mapping follows the same logic across each preset:
    ///   regular: a "background"-ish key fill (dimmest)
    ///   modifier: the palette's purple/violet
    ///   layer: the palette's blue/cyan
    ///   special: the palette's orange/red accent
    ///   text: the palette's foreground / body text
    // Each palette below uses *muted UI-tone* variants of each kind's
    // signature hue, not the full-saturation syntax accents. The palettes are
    // designed for accents-on-bg (purple text on a dark editor); reusing
    // those accents as key fills would put fg on accent and lose contrast.
    // Hand-tuned so each kind's fill has similar luminance to `regular`,
    // keeping the single `text` colour readable everywhere.
    static let all: [ThemePreset] = [
        // MARK: Dark
        ThemePreset(
            id: "layerlens", name: "LayerLens", kind: .dark,
            regular: "#2D3340", modifier: "#5B5184", layer: "#3D6B8C",
            special: "#704030", text: "#FFFFFF"
        ),
        ThemePreset(
            id: "dracula", name: "Dracula", kind: .dark,
            regular: "#44475A", modifier: "#5C4A85", layer: "#345F7A",
            special: "#7E4866", text: "#F8F8F2"
        ),
        ThemePreset(
            id: "solarized-dark", name: "Solarized Dark", kind: .dark,
            regular: "#073642", modifier: "#3F4880", layer: "#0F557F",
            special: "#7A3415", text: "#EEE8D5"
        ),
        ThemePreset(
            id: "monokai", name: "Monokai", kind: .dark,
            regular: "#3E3D32", modifier: "#6F4FA0", layer: "#36707C",
            special: "#A66218", text: "#F8F8F2"
        ),
        ThemePreset(
            id: "nord", name: "Nord", kind: .dark,
            regular: "#3B4252", modifier: "#705C7A", layer: "#4A7C8C",
            special: "#8A5A47", text: "#ECEFF4"
        ),
        ThemePreset(
            id: "tokyo-night", name: "Tokyo Night", kind: .dark,
            regular: "#292E42", modifier: "#594380", layer: "#33558A",
            special: "#9C5E40", text: "#C0CAF5"
        ),
        ThemePreset(
            id: "one-dark", name: "One Dark", kind: .dark,
            regular: "#3E4451", modifier: "#74519A", layer: "#3B70A8",
            special: "#9D4148", text: "#ABB2BF"
        ),
        ThemePreset(
            id: "gruvbox-dark", name: "Gruvbox Dark", kind: .dark,
            regular: "#3C3836", modifier: "#75395A", layer: "#2F5A5C",
            special: "#84461F", text: "#EBDBB2"
        ),
        ThemePreset(
            id: "github-dark", name: "GitHub Dark", kind: .dark,
            regular: "#21262D", modifier: "#5A3F8A", layer: "#1F4D87",
            special: "#7A5326", text: "#C9D1D9"
        ),

        // MARK: Light
        ThemePreset(
            id: "solarized-light", name: "Solarized Light", kind: .light,
            regular: "#EEE8D5", modifier: "#D5CFE8", layer: "#B6D4EE",
            special: "#F0CAA8", text: "#586E75"
        ),
        ThemePreset(
            id: "github-light", name: "GitHub Light", kind: .light,
            regular: "#F0F2F6", modifier: "#E0CDFF", layer: "#BFDBFB",
            special: "#FFC9CC", text: "#1F2328"
        ),
        ThemePreset(
            id: "one-light", name: "One Light", kind: .light,
            regular: "#E5E5E6", modifier: "#E8C5E5", layer: "#CCDCFA",
            special: "#F5C7BE", text: "#383A42"
        ),
        ThemePreset(
            id: "gruvbox-light", name: "Gruvbox Light", kind: .light,
            regular: "#EBDBB2", modifier: "#E0AFC4", layer: "#B6CDCF",
            special: "#F0C18B", text: "#3C3836"
        ),
    ]

    static var darkPresets:  [ThemePreset] { all.filter { $0.kind == .dark } }
    static var lightPresets: [ThemePreset] { all.filter { $0.kind == .light } }
}

/// Grid of preset swatches. Each card shows the four key-fill colours as
/// rounded chips plus the preset name; clicking applies the preset to
/// the user's preferences.
struct ThemePresetGrid: View {
    @Environment(Preferences.self) private var preferences

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            section("Dark", presets: ThemePreset.darkPresets)
            section("Light", presets: ThemePreset.lightPresets)
        }
    }

    private func section(_ title: String, presets: [ThemePreset]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(presets) { preset in
                    presetCard(preset)
                }
            }
        }
    }

    private func presetCard(_ preset: ThemePreset) -> some View {
        Button {
            preset.apply(to: preferences)
        } label: {
            HStack(spacing: 8) {
                swatches(preset)
                Text(preset.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.background.secondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isActive(preset) ? Color.accentColor : Color.gray.opacity(0.3),
                            lineWidth: isActive(preset) ? 2 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Apply \(preset.name)")
    }

    private func swatches(_ preset: ThemePreset) -> some View {
        HStack(spacing: 2) {
            chip(preset.regular)
            chip(preset.modifier)
            chip(preset.layer)
            chip(preset.special)
        }
    }

    private func chip(_ hex: String) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Color(hex: hex))
            .frame(width: 12, height: 16)
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(.black.opacity(0.15), lineWidth: 0.5)
            )
    }

    /// True when the user's current colours exactly match this preset. Gives
    /// the active card a highlighted border so the user can see where they
    /// last clicked.
    private func isActive(_ preset: ThemePreset) -> Bool {
        preferences.colourRegular.toHex().caseInsensitiveCompare(preset.regular) == .orderedSame &&
        preferences.colourModifier.toHex().caseInsensitiveCompare(preset.modifier) == .orderedSame &&
        preferences.colourLayer.toHex().caseInsensitiveCompare(preset.layer) == .orderedSame &&
        preferences.colourSpecial.toHex().caseInsensitiveCompare(preset.special) == .orderedSame &&
        preferences.colourText.toHex().caseInsensitiveCompare(preset.text) == .orderedSame
    }
}
