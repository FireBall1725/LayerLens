import Foundation

/// VIA Raw-HID command IDs (byte 0 of the 32-byte report).
/// Spec: https://www.caniusevia.com/docs/specification
public enum VIACommand: UInt8, Sendable {
    case getProtocolVersion = 0x01
    case getKeyboardValue = 0x02
    case setKeyboardValue = 0x03
    case dynamicKeymapGetKeycode = 0x04
    case dynamicKeymapSetKeycode = 0x05
    case dynamicKeymapReset = 0x06
    case customSetValue = 0x07
    case customGetValue = 0x08
    case customSave = 0x09
    case eepromReset = 0x0A
    case bootloaderJump = 0x0B
    case dynamicKeymapMacroGetCount = 0x0C
    case dynamicKeymapMacroGetBufferSize = 0x0D
    case dynamicKeymapMacroGetBuffer = 0x0E
    case dynamicKeymapMacroSetBuffer = 0x0F
    case dynamicKeymapMacroReset = 0x10
    case dynamicKeymapGetLayerCount = 0x11
    case dynamicKeymapGetBuffer = 0x12
    case dynamicKeymapSetBuffer = 0x13
    case dynamicKeymapGetEncoder = 0x14
    case dynamicKeymapSetEncoder = 0x15
    /// Vial extension: byte 0 = 0xFE, byte 1 = sub-command.
    case vial = 0xFE
    /// LayerLens Notify extension: byte 0 = 0xF1, byte 1 = sub-command.
    /// Third-party opcode handled by the `layerlens_notify` QMK module via
    /// vial-qmk's `raw_hid_receive_kb` default-branch hook. See
    /// `firmware/layerlens_notify/PROTOCOL.md`.
    case layerLens = 0xF1
}

/// Sub-commands for the LayerLens Notify extension (`0xF1` opcode).
public enum LayerLensSubCommand: UInt8, Sendable {
    /// Returns the firmware's current `layer_state_t` bitmask. Reply shape:
    /// `[0xF1, 0x00, version, b3, b2, b1, b0, ...]`.
    case getLayerState = 0x00
}

/// Sub-commands for the Vial extension (`0xFE` opcode). Vial encodes its
/// own protocol over the same Raw HID interface VIA uses: byte 0 = 0xFE,
/// byte 1 = one of these. Spec lives at
/// https://github.com/vial-kb/vial-qmk/blob/vial/quantum/vial.h
public enum VialSubCommand: UInt8, Sendable {
    case getKeyboardId       = 0x00
    case getSize             = 0x01
    case getDefinition       = 0x02
    case getEncoder          = 0x03
    case setEncoder          = 0x04
    case getUnlockStatus     = 0x05
    case unlockStart         = 0x06
    case unlockPoll          = 0x07
    case lock                = 0x08
    case qmkSettingsQuery    = 0x09
    case qmkSettingsGet      = 0x0A
    case qmkSettingsSet      = 0x0B
    case qmkSettingsReset    = 0x0C
    case dynamicEntryOp      = 0x0D
}

/// Sub-command for `id_get_keyboard_value` (0x02) / `id_set_keyboard_value` (0x03).
public enum VIAKeyboardValue: UInt8, Sendable {
    case uptime = 0x01
    case layoutOptions = 0x02
    case switchMatrixState = 0x03
    case firmwareVersion = 0x04
    case deviceIndication = 0x05
}
