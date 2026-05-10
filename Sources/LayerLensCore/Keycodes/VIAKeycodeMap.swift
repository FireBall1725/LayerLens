import Foundation

/// Per-VIA-protocol keycode geometry: where each quantum range (mods, mod-tap,
/// layer-tap, MO/TO/TG/etc., macro, custom KB) starts and ends in the 16-bit
/// keycode space. v10 and v12 disagree on most of these values, so we carry
/// both and dispatch at runtime against the connected device's reported
/// `id_get_protocol_version`.
public struct VIAKeycodeRanges: Sendable, Hashable {
    public let mods: Range<UInt16>
    public let modTap: Range<UInt16>
    public let layerTap: Range<UInt16>
    public let layerMod: Range<UInt16>
    public let toLayer: Range<UInt16>
    public let momentary: Range<UInt16>
    public let defaultLayer: Range<UInt16>
    public let toggleLayer: Range<UInt16>
    public let oneShotLayer: Range<UInt16>
    public let oneShotMod: Range<UInt16>
    public let layerTapToggle: Range<UInt16>
    public let macro: Range<UInt16>
    public let kbCustom: Range<UInt16>

    public init(
        mods: Range<UInt16>,
        modTap: Range<UInt16>,
        layerTap: Range<UInt16>,
        layerMod: Range<UInt16>,
        toLayer: Range<UInt16>,
        momentary: Range<UInt16>,
        defaultLayer: Range<UInt16>,
        toggleLayer: Range<UInt16>,
        oneShotLayer: Range<UInt16>,
        oneShotMod: Range<UInt16>,
        layerTapToggle: Range<UInt16>,
        macro: Range<UInt16>,
        kbCustom: Range<UInt16>
    ) {
        self.mods = mods
        self.modTap = modTap
        self.layerTap = layerTap
        self.layerMod = layerMod
        self.toLayer = toLayer
        self.momentary = momentary
        self.defaultLayer = defaultLayer
        self.toggleLayer = toggleLayer
        self.oneShotLayer = oneShotLayer
        self.oneShotMod = oneShotMod
        self.layerTapToggle = layerTapToggle
        self.macro = macro
        self.kbCustom = kbCustom
    }
}

/// A keycode-decoder table: the flat `value -> label` map for "concrete"
/// keycodes (KC_A, RGB_TOG, BL_ON, ...) plus the range geometry for
/// computed keycodes (MO(N), MT(mods,kc), ...).
public struct VIAKeycodeMap: Sendable {
    public let basicTable: [UInt16: QMKKeycodeLabel]
    public let ranges: VIAKeycodeRanges

    public init(basicTable: [UInt16: QMKKeycodeLabel], ranges: VIAKeycodeRanges) {
        self.basicTable = basicTable
        self.ranges = ranges
    }

    /// Pick the right map for the given VIA `id_get_protocol_version` reply,
    /// or `nil` if the protocol version is older than what VIA itself supports
    /// (< 10). VIA's app ships separate key-to-byte tables per protocol
    /// version (v10, v11, v12) with subtly different range starts. Most
    /// notably `_QK_TO` shifted from 0x5010 (legacy) to 0x5200 in v11+ to
    /// match modern QMK firmware. Anything beyond v12 falls through to the
    /// v12 table on the assumption new versions extend rather than rebase.
    public static func map(forProtocolVersion version: UInt16) -> VIAKeycodeMap? {
        switch version {
        case ..<9:   return nil  // unsupported (predates VIA's stable mapping)
        case 9:      return .v12 // Vial sentinel. Recent vial-qmk (post-2023)
                                 // uses VIA v12-shaped quantum keycodes,
                                 // notably `QK_MOMENTARY = 0x5220..0x523F`
                                 // and `QK_LAYER_MOD = 0x5000..0x51FF`.
                                 // Older Vial firmware was v10-shaped; users
                                 // on really old builds may see some keycodes
                                 // decode as hex. Real Vial protocol support
                                 // is task #25 / future phases.
        case 10:     return .v10
        case 11:     return .v11
        default:     return .v12
        }
    }

    public static let minSupportedProtocolVersion: UInt16 = 9

    public static let v10 = VIAKeycodeMap(basicTable: v10BasicTable, ranges: v10Ranges)
    public static let v11 = VIAKeycodeMap(basicTable: v11BasicTable, ranges: v11Ranges)
    public static let v12 = VIAKeycodeMap(basicTable: v12BasicTable, ranges: v12Ranges)
}
