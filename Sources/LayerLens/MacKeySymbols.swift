import Foundation

/// macOS-native symbol overrides for a small set of keycodes. The keymap
/// viewer and the keycode picker prefer these over QMK's text labels
/// (KC_LCTL → "⌃", KC_TAB → "⇥", …) so the app reads as a Mac app
/// instead of a port from VIA.
///
/// The overlay deliberately *doesn't* consult this map: the overlay
/// honours the user's custom font, which often lacks these glyphs.
enum MacKeySymbols {
  /// Returns the macOS glyph for a given QMK keycode, or nil if there
  /// isn't a well-known one.
  static func symbol(for keycode: UInt16) -> String? {
    switch keycode {
    // Modifiers — L/R suffix disambiguates the two distinct
    // keycodes that share the same Apple glyph (KC_LGUI vs KC_RGUI
    // are two different keys, just both rendered as ⌘ by Apple).
    case 0x00E0: return "⌃ L"  // KC_LCTL
    case 0x00E1: return "⇧ L"  // KC_LSFT
    case 0x00E2: return "⌥ L"  // KC_LALT
    case 0x00E3: return "⌘ L"  // KC_LGUI
    case 0x00E4: return "⌃ R"  // KC_RCTL
    case 0x00E5: return "⇧ R"  // KC_RSFT
    case 0x00E6: return "⌥ R"  // KC_RALT
    case 0x00E7: return "⌘ R"  // KC_RGUI

    // Common edit keys
    case 0x0028: return "↩"  // KC_ENT
    case 0x0029: return "⎋"  // KC_ESC
    case 0x002A: return "⌫"  // KC_BSPC
    case 0x002B: return "⇥"  // KC_TAB
    case 0x0039: return "⇪"  // KC_CAPS
    case 0x004C: return "⌦"  // KC_DEL

    // Navigation
    case 0x004A: return "⇱"  // KC_HOME
    case 0x004B: return "⇞"  // KC_PGUP
    case 0x004D: return "⇲"  // KC_END
    case 0x004E: return "⇟"  // KC_PGDN

    default: return nil
    }
  }
}
