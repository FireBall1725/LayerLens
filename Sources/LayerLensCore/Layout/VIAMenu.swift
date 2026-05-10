import Foundation

/// Parsed VIA `menus` definition. Lives alongside the layout JSON and tells
/// us how to render the keyboard's lighting / config UI: which sections,
/// which control types (range/dropdown/color), and what (channel, value_id)
/// each control reads from / writes to via VIA's custom-value commands.
public enum VIAMenuNode: Sendable, Hashable, Identifiable {
    case section(VIAMenuSection)
    case control(VIAMenuControl)

    public var id: String {
        switch self {
        case .section(let s): return "section:\(s.label)"
        case .control(let c): return "control:\(c.identifier)"
        }
    }
}

public struct VIAMenuSection: Sendable, Hashable {
    public let label: String
    public let children: [VIAMenuNode]
}

public struct VIAMenuControl: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable {
        case range, dropdown
        // Raw value stays "color" because VIA's JSON spec uses the American
        // spelling, our Swift API uses Canadian.
        case colour = "color"
        case unknown
    }

    public let label: String
    public let kind: Kind
    /// VIA-defined identifier like `id_qmk_rgblight_brightness`. Used for
    /// `showIf` substitutions and as the SwiftUI list id.
    public let identifier: String
    public let channel: UInt8
    public let valueID: UInt8
    /// For `range`: [min, max]. For `dropdown`: usually [count] (the number
    /// of options); the actual labels live in `dropdownOptions`.
    public let options: [Int]
    public let dropdownOptions: [String]
    /// Optional simple expression: `{id_qmk_rgblight_effect} != 0`. Evaluated
    /// at render time using current control values.
    public let showIf: String?
    /// True when this control should be transmitted via the legacy
    /// `id_lighting_set_value` shape: `[cmd, value_id, ...bytes]` with no
    /// channel byte. VIA uses this for keyboards whose JSON declares
    /// `lighting.extends` (i.e., older Keychron-style firmware that predates
    /// VIA's channel-routed custom-value system). When false, the control
    /// uses `[cmd, channel, value_id, ...bytes]` (modern format).
    public let useLegacyLighting: Bool
}

public enum VIAMenuParser {

    /// Pull and parse the keyboard's lighting controls out of its VIA JSON
    /// definition. Two formats are supported:
    ///
    /// 1. `"menus": [...]`: fully-custom menu definitions (Micro Pad style).
    ///    Whatever the JSON says, we render verbatim.
    ///
    /// 2. `"lighting": { "extends": "qmk_rgblight", ... }`: the keyboard
    ///    references one of VIA's built-in lighting menu types and supplies
    ///    its specific effect list. We synthesize the equivalent menu
    ///    structure (channel/value IDs hardcoded by VIA convention).
    ///
    /// Returns an empty array when neither field is present.
    public static func parse(viaDefinition root: Any) -> [VIAMenuNode] {
        guard let dict = root as? [String: Any] else { return [] }

        if let menus = dict["menus"] as? [Any] {
            return menus.compactMap { parseNode($0) }
        }
        if let lighting = dict["lighting"] as? [String: Any],
           let extends = lighting["extends"] as? String {
            return synthesizeBuiltInLightingMenu(extends: extends, lighting: lighting)
        }
        return []
    }

    // MARK: - Built-in lighting synthesis

    /// VIA's standard channel IDs (matches QMK's `via.h` enum).
    private enum BuiltInChannel: UInt8 {
        case backlight = 1
        case rgblight  = 2
        case rgbMatrix = 3
    }

    private static func synthesizeBuiltInLightingMenu(
        extends: String,
        lighting: [String: Any]
    ) -> [VIAMenuNode] {
        switch extends {
        case "qmk_rgblight":
            return [.section(rgblightSection(lighting: lighting))]
        case "qmk_rgb_matrix":
            return [.section(rgbMatrixSection(lighting: lighting))]
        case "qmk_backlight":
            return [.section(backlightSection())]
        case "qmk_backlight_rgblight":
            return [
                .section(backlightSection()),
                .section(rgblightSection(lighting: lighting))
            ]
        default:
            return []
        }
    }

    /// VIA's legacy `id_lighting_*` value IDs used when the keyboard JSON
    /// declares `"lighting": {"extends": ...}`. These predate the channel-
    /// routed custom-value system and live in the 0x80+ space so a single
    /// firmware can route them via byte position alone.
    private enum LegacyLightingValue: UInt8 {
        case backlightBrightness  = 0x09
        case backlightEffect      = 0x0A
        case rgblightBrightness   = 0x80
        case rgblightEffect       = 0x81
        case rgblightEffectSpeed  = 0x82
        case rgblightColour        = 0x83
    }

    private static func rgblightSection(lighting: [String: Any]) -> VIAMenuSection {
        let effects = effectNames(from: lighting["underglowEffects"])
        let prefix  = "id_qmk_rgblight"
        let effectId = "\(prefix)_effect"
        return VIAMenuSection(
            label: "Underglow",
            children: [
                .control(VIAMenuControl(
                    label: "Brightness", kind: .range,
                    identifier: "\(prefix)_brightness",
                    channel: BuiltInChannel.rgblight.rawValue,
                    valueID: LegacyLightingValue.rgblightBrightness.rawValue,
                    options: [0, 255], dropdownOptions: [], showIf: nil,
                    useLegacyLighting: true
                )),
                .control(VIAMenuControl(
                    label: "Effect", kind: .dropdown,
                    identifier: effectId,
                    channel: BuiltInChannel.rgblight.rawValue,
                    valueID: LegacyLightingValue.rgblightEffect.rawValue,
                    options: effects.isEmpty ? [1] : [],
                    dropdownOptions: effects, showIf: nil,
                    useLegacyLighting: true
                )),
                .control(VIAMenuControl(
                    label: "Effect Speed", kind: .range,
                    identifier: "\(prefix)_effect_speed",
                    channel: BuiltInChannel.rgblight.rawValue,
                    valueID: LegacyLightingValue.rgblightEffectSpeed.rawValue,
                    options: [0, 255], dropdownOptions: [],
                    showIf: "{\(effectId)} != 0",
                    useLegacyLighting: true
                )),
                .control(VIAMenuControl(
                    label: "Colour", kind: .colour,
                    identifier: "\(prefix)_color",
                    channel: BuiltInChannel.rgblight.rawValue,
                    valueID: LegacyLightingValue.rgblightColour.rawValue,
                    options: [], dropdownOptions: [],
                    showIf: "{\(effectId)} != 0",
                    useLegacyLighting: true
                ))
            ]
        )
    }

    private static func rgbMatrixSection(lighting: [String: Any]) -> VIAMenuSection {
        // RGB Matrix predates legacy lighting. No 0x80-range value IDs ever
        // existed for it. Use the modern channel-routed format.
        let raw = lighting["effects"] ?? lighting["rgbMatrixEffects"]
        let effects = effectNames(from: raw)
        let prefix  = "id_qmk_rgb_matrix"
        let effectId = "\(prefix)_effect"
        return VIAMenuSection(
            label: "RGB Matrix",
            children: [
                .control(VIAMenuControl(
                    label: "Brightness", kind: .range,
                    identifier: "\(prefix)_brightness",
                    channel: BuiltInChannel.rgbMatrix.rawValue,
                    valueID: 1, options: [0, 255],
                    dropdownOptions: [], showIf: nil,
                    useLegacyLighting: false
                )),
                .control(VIAMenuControl(
                    label: "Effect", kind: .dropdown,
                    identifier: effectId,
                    channel: BuiltInChannel.rgbMatrix.rawValue,
                    valueID: 2, options: effects.isEmpty ? [1] : [],
                    dropdownOptions: effects, showIf: nil,
                    useLegacyLighting: false
                )),
                .control(VIAMenuControl(
                    label: "Effect Speed", kind: .range,
                    identifier: "\(prefix)_effect_speed",
                    channel: BuiltInChannel.rgbMatrix.rawValue,
                    valueID: 3, options: [0, 255],
                    dropdownOptions: [], showIf: "{\(effectId)} != 0",
                    useLegacyLighting: false
                )),
                .control(VIAMenuControl(
                    label: "Colour", kind: .colour,
                    identifier: "\(prefix)_color",
                    channel: BuiltInChannel.rgbMatrix.rawValue,
                    valueID: 4, options: [],
                    dropdownOptions: [], showIf: "{\(effectId)} != 0",
                    useLegacyLighting: false
                ))
            ]
        )
    }

    private static func backlightSection() -> VIAMenuSection {
        let prefix = "id_qmk_backlight"
        return VIAMenuSection(
            label: "Backlight",
            children: [
                .control(VIAMenuControl(
                    label: "Brightness", kind: .range,
                    identifier: "\(prefix)_brightness",
                    channel: BuiltInChannel.backlight.rawValue,
                    valueID: LegacyLightingValue.backlightBrightness.rawValue,
                    options: [0, 255], dropdownOptions: [], showIf: nil,
                    useLegacyLighting: true
                )),
                .control(VIAMenuControl(
                    label: "Effect", kind: .dropdown,
                    identifier: "\(prefix)_effect",
                    channel: BuiltInChannel.backlight.rawValue,
                    valueID: LegacyLightingValue.backlightEffect.rawValue,
                    options: [], dropdownOptions: ["None", "Breathing"],
                    showIf: nil, useLegacyLighting: true
                ))
            ]
        )
    }

    /// VIA's effect lists ship as `[[name, colourModifierFlag], ...]`. We just
    /// want the name; the array index becomes the dropdown's selected value.
    private static func effectNames(from raw: Any?) -> [String] {
        guard let array = raw as? [Any] else { return [] }
        return array.compactMap { entry -> String? in
            if let pair = entry as? [Any] {
                return pair.first as? String
            }
            return entry as? String
        }
    }

    private static func parseNode(_ raw: Any) -> VIAMenuNode? {
        guard let obj = raw as? [String: Any] else { return nil }
        if let type = obj["type"] as? String {
            return parseControl(obj, typeKey: type).map { .control($0) }
        }
        // Section: has `label` + nested `content` array of child nodes.
        guard let label = obj["label"] as? String,
              let content = obj["content"] as? [Any] else {
            return nil
        }
        let children = content.compactMap { parseNode($0) }
        return .section(VIAMenuSection(label: label, children: children))
    }

    private static func parseControl(_ obj: [String: Any], typeKey: String) -> VIAMenuControl? {
        let kind = VIAMenuControl.Kind(rawValue: typeKey) ?? .unknown
        guard let label = obj["label"] as? String else { return nil }

        // `content` is a 3-tuple: ["id_qmk_rgblight_brightness", channel, value_id].
        let content = obj["content"] as? [Any] ?? []
        guard content.count >= 3,
              let identifier = content[0] as? String,
              let channelRaw = (content[1] as? NSNumber)?.intValue,
              let valueRaw   = (content[2] as? NSNumber)?.intValue else {
            return nil
        }

        // `options` flavours:
        //   range:    [min, max]                    -> Int array
        //   dropdown: [optionCount]                 -> Int array
        //             OR ["Off", "Solid", ...]      -> string list
        var ints: [Int] = []
        var strings: [String] = []
        if let opts = obj["options"] as? [Any] {
            for value in opts {
                if let n = (value as? NSNumber)?.intValue {
                    ints.append(n)
                } else if let s = value as? String {
                    strings.append(s)
                }
            }
        }

        return VIAMenuControl(
            label: label,
            kind: kind,
            identifier: identifier,
            channel: UInt8(truncatingIfNeeded: channelRaw),
            valueID: UInt8(truncatingIfNeeded: valueRaw),
            options: ints,
            dropdownOptions: strings,
            showIf: obj["showIf"] as? String,
            useLegacyLighting: false
        )
    }
}
