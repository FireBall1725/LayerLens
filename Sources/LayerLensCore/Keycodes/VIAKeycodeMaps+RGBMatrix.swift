import Foundation

/// Labels for QMK's RGB Matrix keycodes (0x7840...0x784E).
///
/// VIA's own key-to-byte tables stop at the legacy RGBLIGHT block (0x782x),
/// so the generated tables in `VIAKeycodeMaps.generated.swift` decode RGB
/// Matrix keycodes as raw hex. The values live in QMK's quantum keycode
/// space (`quantum/keycodes.h`) and are stable across VIA protocol versions,
/// so one supplement table applies to every map.
extension VIAKeycodeMap {
  static let rgbMatrixTable: [UInt16: QMKKeycodeLabel] = [
    0x7840: QMKKeycodeLabel(tap: "RGB On"),  // QK_RGB_MATRIX_ON
    0x7841: QMKKeycodeLabel(tap: "RGB Off"),  // QK_RGB_MATRIX_OFF
    0x7842: QMKKeycodeLabel(tap: "RGB"),  // QK_RGB_MATRIX_TOGGLE
    0x7843: QMKKeycodeLabel(tap: "RGB+"),  // QK_RGB_MATRIX_MODE_NEXT
    0x7844: QMKKeycodeLabel(tap: "RGB-"),  // QK_RGB_MATRIX_MODE_PREVIOUS
    0x7845: QMKKeycodeLabel(tap: "Hue+"),  // QK_RGB_MATRIX_HUE_UP
    0x7846: QMKKeycodeLabel(tap: "Hue-"),  // QK_RGB_MATRIX_HUE_DOWN
    0x7847: QMKKeycodeLabel(tap: "Sat+"),  // QK_RGB_MATRIX_SATURATION_UP
    0x7848: QMKKeycodeLabel(tap: "Sat-"),  // QK_RGB_MATRIX_SATURATION_DOWN
    0x7849: QMKKeycodeLabel(tap: "Val+"),  // QK_RGB_MATRIX_VALUE_UP
    0x784A: QMKKeycodeLabel(tap: "Val-"),  // QK_RGB_MATRIX_VALUE_DOWN
    0x784B: QMKKeycodeLabel(tap: "Speed+"),  // QK_RGB_MATRIX_SPEED_UP
    0x784C: QMKKeycodeLabel(tap: "Speed-"),  // QK_RGB_MATRIX_SPEED_DOWN
    0x784D: QMKKeycodeLabel(tap: "Flag+"),  // QK_RGB_MATRIX_FLAG_NEXT
    0x784E: QMKKeycodeLabel(tap: "Flag-"),  // QK_RGB_MATRIX_FLAG_PREVIOUS
  ]
}
