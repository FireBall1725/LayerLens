import Foundation

/// QMK left-side modifier bit mask in the high byte of QK_MODS-range keycodes.
enum QMKModBit {
    static let lctl: UInt16 = 0x0100
    static let lsft: UInt16 = 0x0200
    static let lalt: UInt16 = 0x0400
    static let lgui: UInt16 = 0x0800
    static let rmodsMin: UInt16 = 0x1000
    static let rctl: UInt16 = 0x1100
    static let rsft: UInt16 = 0x1200
    static let ralt: UInt16 = 0x1400
    static let rgui: UInt16 = 0x1800
}

/// Mod-tap mod-mask bit positions (in the high nibble of mod-tap remainder).
enum QMKModFlag {
    static let lctl: UInt16 = 0x01
    static let lsft: UInt16 = 0x02
    static let lalt: UInt16 = 0x04
    static let lgui: UInt16 = 0x08
    static let rctl: UInt16 = 0x10
    static let rsft: UInt16 = 0x20
    static let ralt: UInt16 = 0x40
    static let rgui: UInt16 = 0x80
}

/// (Display name, modifier mask) tuples used to render mod combinations
/// against `QK_MODS` keycodes. Order matters: exact-match search first, so
/// nicer aliases come before bit-decomposed fallbacks.
let qmkModifierAliases: [(name: String, mask: UInt16)] = [
    ("LCTL", QMKModBit.lctl),
    ("LSFT", QMKModBit.lsft),
    ("LALT", QMKModBit.lalt),
    ("LGUI", QMKModBit.lgui),
    ("RCTL", QMKModBit.rctl),
    ("RSFT", QMKModBit.rsft),
    ("RALT", QMKModBit.ralt),
    ("RGUI", QMKModBit.rgui),
    ("SGUI", QMKModBit.lsft | QMKModBit.lgui),
    ("LSG",  QMKModBit.lsft | QMKModBit.lgui),
    ("LAG",  QMKModBit.lalt | QMKModBit.lgui),
    ("RSG",  QMKModBit.rsft | QMKModBit.rgui),
    ("RAG",  QMKModBit.ralt | QMKModBit.rgui),
    ("LCA",  QMKModBit.lctl | QMKModBit.lalt),
    ("LSA",  QMKModBit.lsft | QMKModBit.lalt),
    ("RSA",  QMKModBit.rsft | QMKModBit.ralt),
    ("RCS",  QMKModBit.rctl | QMKModBit.rsft),
    ("LCAG", QMKModBit.lctl | QMKModBit.lalt | QMKModBit.lgui),
    ("MEH",  QMKModBit.lctl | QMKModBit.lalt | QMKModBit.lsft),
    ("HYPR", QMKModBit.lctl | QMKModBit.lalt | QMKModBit.lsft | QMKModBit.lgui),
]
