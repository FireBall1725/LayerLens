import Foundation

/// Resolves a 16-bit QMK keycode to a human-readable label, dispatching against
/// the right per-protocol `VIAKeycodeMap` (v10 vs v12+).
///
/// The user's connected device reports its protocol version via
/// `id_get_protocol_version`; the caller passes that in so a v10 board's
/// `0x5CC2` decodes as `RGB` (correct) instead of falling into v12's
/// `QK_LAYER_MOD` range.
public enum QMKKeycodeFormatter {

    public static func label(
        for keycode: UInt16,
        protocolVersion: UInt16 = 12
    ) -> QMKKeycodeLabel? {
        if keycode == 0x0001 { return nil } // KC_TRANSPARENT

        guard let map = VIAKeycodeMap.map(forProtocolVersion: protocolVersion) else {
            // Pre-v10 protocol; we don't know the keycode geometry. Fall back
            // to hex so the caller still sees something deterministic.
            return QMKKeycodeLabel(tap: String(format: "0x%04X", keycode))
        }

        if let basic = map.basicTable[keycode] {
            return basic
        }
        if let layered = layerLabel(for: keycode, ranges: map.ranges) {
            return layered
        }
        if let advanced = advancedLabel(for: keycode, map: map) {
            return advanced
        }
        return QMKKeycodeLabel(tap: String(format: "0x%04X", keycode))
    }

    // MARK: - Layer-range codes

    private static func layerLabel(for kc: UInt16, ranges: VIAKeycodeRanges) -> QMKKeycodeLabel? {
        if ranges.toLayer.contains(kc) {
            let l = Int(kc - ranges.toLayer.lowerBound)
            return QMKKeycodeLabel(tap: "TO(\(l))", layerRef: l)
        }
        if ranges.momentary.contains(kc) {
            let l = Int(kc - ranges.momentary.lowerBound)
            return QMKKeycodeLabel(tap: "MO(\(l))", layerRef: l)
        }
        if ranges.toggleLayer.contains(kc) {
            let l = Int(kc - ranges.toggleLayer.lowerBound)
            return QMKKeycodeLabel(tap: "TG(\(l))", layerRef: l)
        }
        if ranges.oneShotLayer.contains(kc) {
            let l = Int(kc - ranges.oneShotLayer.lowerBound)
            return QMKKeycodeLabel(tap: "OSL(\(l))", layerRef: l)
        }
        if ranges.layerTapToggle.contains(kc) {
            let l = Int(kc - ranges.layerTapToggle.lowerBound)
            return QMKKeycodeLabel(tap: "TT(\(l))", layerRef: l)
        }
        if ranges.defaultLayer.contains(kc) {
            let l = Int(kc - ranges.defaultLayer.lowerBound)
            // DF doesn't activate a layer momentarily, but it's still about
            // layers, so apply the same theme colour as MO/TO/TG for visual
            // consistency.
            return QMKKeycodeLabel(tap: "DF(\(l))", layerRef: l)
        }
        if ranges.kbCustom.contains(kc) {
            let n = Int(kc - ranges.kbCustom.lowerBound)
            return QMKKeycodeLabel(tap: "CUSTOM(\(n))")
        }
        if ranges.macro.contains(kc) {
            let n = Int(kc - ranges.macro.lowerBound)
            return QMKKeycodeLabel(tap: "M\(n)")
        }
        return nil
    }

    // MARK: - Quantum codes (mods, mod-tap, OSM, layer-tap, layer-mod)

    private static func advancedLabel(for kc: UInt16, map: VIAKeycodeMap) -> QMKKeycodeLabel? {
        let ranges = map.ranges
        if ranges.mods.contains(kc) {
            return modsLabel(kc, basicTable: map.basicTable)
        }
        if ranges.modTap.contains(kc) {
            return modTapLabel(kc, ranges: ranges, basicTable: map.basicTable)
        }
        if ranges.layerMod.contains(kc) {
            return layerModLabel(kc, ranges: ranges)
        }
        if ranges.oneShotMod.contains(kc) {
            return oneShotModLabel(kc, ranges: ranges)
        }
        if ranges.layerTap.contains(kc) {
            return layerTapLabel(kc, ranges: ranges, basicTable: map.basicTable)
        }
        return nil
    }

    private static func modsLabel(
        _ kc: UInt16,
        basicTable: [UInt16: QMKKeycodeLabel]
    ) -> QMKKeycodeLabel? {
        let baseKC = kc & 0xFF
        let mods   = kc & 0x1F00
        let baseLabel = basicTable[baseKC]?.tap ?? String(format: "0x%02X", baseKC)

        // VIA-style shortcut: shift-only on a key that has a known shifted glyph
        // renders as the shifted glyph (e.g., LSFT(KC_1) -> "!"). US layout only;
        // non-US shift maps would need a setting later.
        if mods == QMKModBit.lsft || mods == QMKModBit.rsft,
           let shifted = usShiftedGlyphs[baseKC] {
            return QMKKeycodeLabel(tap: shifted, kind: .modifier)
        }

        if let alias = qmkModifierAliases.first(where: { $0.mask == mods }) {
            return QMKKeycodeLabel(tap: "\(alias.name)(\(baseLabel))", kind: .modifier)
        }

        let isRight = (mods & QMKModBit.rmodsMin) != 0
        let candidates = qmkModifierAliases.filter { alias in
            isRight ? alias.mask >= QMKModBit.rmodsMin : alias.mask < QMKModBit.rmodsMin
        }
        let parts = candidates.compactMap { alias -> String? in
            (mods & alias.mask) == alias.mask ? alias.name : nil
        }
        guard !parts.isEmpty else { return nil }

        var nested = ""
        for (i, part) in parts.enumerated() {
            if i > 0 { nested.append("(") }
            nested.append(part)
        }
        nested.append("(")
        nested.append(baseLabel)
        nested.append(String(repeating: ")", count: parts.count))
        return QMKKeycodeLabel(tap: nested, kind: .modifier)
    }

    private static func modTapLabel(
        _ kc: UInt16,
        ranges: VIAKeycodeRanges,
        basicTable: [UInt16: QMKKeycodeLabel]
    ) -> QMKKeycodeLabel {
        let remainder = kc - ranges.modTap.lowerBound
        let modValue  = (remainder >> 8) & 0x1F
        let modStr    = modFlagsString(modValue)
        let baseKC    = remainder & 0xFF
        let baseLabel = basicTable[baseKC]?.tap ?? String(format: "0x%02X", baseKC)
        return QMKKeycodeLabel(tap: "MT(\(modStr),\(baseLabel))", kind: .modifier)
    }

    private static func layerModLabel(_ kc: UInt16, ranges: VIAKeycodeRanges) -> QMKKeycodeLabel {
        let remainder = kc - ranges.layerMod.lowerBound
        let layer = Int(remainder >> 5)
        let modStr = modFlagsString(remainder & 0x1F)
        return QMKKeycodeLabel(tap: "LM(\(layer),\(modStr))", kind: .modifier, layerRef: layer)
    }

    private static func oneShotModLabel(_ kc: UInt16, ranges: VIAKeycodeRanges) -> QMKKeycodeLabel {
        let remainder = kc - ranges.oneShotMod.lowerBound
        return QMKKeycodeLabel(tap: "OSM(\(modFlagsString(remainder)))", kind: .modifier)
    }

    private static func layerTapLabel(
        _ kc: UInt16,
        ranges: VIAKeycodeRanges,
        basicTable: [UInt16: QMKKeycodeLabel]
    ) -> QMKKeycodeLabel {
        let remainder = kc - ranges.layerTap.lowerBound
        let layer = Int(remainder >> 8)
        let baseKC = remainder & 0xFF
        let baseLabel = basicTable[baseKC]?.tap ?? String(format: "0x%02X", baseKC)
        return QMKKeycodeLabel(tap: "LT(\(layer),\(baseLabel))", kind: .modifier, layerRef: layer)
    }

    /// Public accessor for the shifted glyph of a base keycode (US ANSI).
    /// Used by the keymap viewer to draw the alt character above the primary
    /// label, mirroring VIA's two-line legend (`!` over `1`, etc.). Returns
    /// nil for keycodes outside the basic 0x04-0x38 ASCII range.
    public static func usShiftedGlyph(forKeycode kc: UInt16) -> String? {
        usShiftedGlyphs[kc]
    }

    /// US-layout shifted glyph for a base keycode (just the byte, no QK_ prefix).
    /// VIA renders Shift+1 as "!", etc. Letters omitted because they're already
    /// uppercase in our basic table. Shift+A reads "A" either way.
    private static let usShiftedGlyphs: [UInt16: String] = [
        0x001E: "!",   // KC_1
        0x001F: "@",   // KC_2
        0x0020: "#",   // KC_3
        0x0021: "$",   // KC_4
        0x0022: "%",   // KC_5
        0x0023: "^",   // KC_6
        0x0024: "&",   // KC_7
        0x0025: "*",   // KC_8
        0x0026: "(",   // KC_9
        0x0027: ")",   // KC_0
        0x002D: "_",   // KC_MINS
        0x002E: "+",   // KC_EQL
        0x002F: "{",   // KC_LBRC
        0x0030: "}",   // KC_RBRC
        0x0031: "|",   // KC_BSLS
        0x0033: ":",   // KC_SCLN
        0x0034: "\"",  // KC_QUOT
        0x0035: "~",   // KC_GRV
        0x0036: "<",   // KC_COMM
        0x0037: ">",   // KC_DOT
        0x0038: "?",   // KC_SLSH
    ]

    private static func modFlagsString(_ mask: UInt16) -> String {
        var parts: [String] = []
        if mask & QMKModFlag.lctl != 0 { parts.append("MOD_LCTL") }
        if mask & QMKModFlag.lsft != 0 { parts.append("MOD_LSFT") }
        if mask & QMKModFlag.lalt != 0 { parts.append("MOD_LALT") }
        if mask & QMKModFlag.lgui != 0 { parts.append("MOD_LGUI") }
        if mask & QMKModFlag.rctl != 0 { parts.append("MOD_RCTL") }
        if mask & QMKModFlag.rsft != 0 { parts.append("MOD_RSFT") }
        if mask & QMKModFlag.ralt != 0 { parts.append("MOD_RALT") }
        if mask & QMKModFlag.rgui != 0 { parts.append("MOD_RGUI") }
        return parts.isEmpty ? "None" : parts.joined(separator: " | ")
    }
}
