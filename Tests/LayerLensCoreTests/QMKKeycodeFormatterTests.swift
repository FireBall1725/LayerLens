import Testing
import Foundation
@testable import LayerLensCore

@Suite("QMKKeycodeFormatter")
struct QMKKeycodeFormatterTests {

    // MARK: - Letters / common keycodes (same value across v10 and v12)

    @Test("Letters resolve in v10 and v12 the same way")
    func basicLetters() {
        for v in [10, 12] {
            #expect(QMKKeycodeFormatter.label(for: 0x0004, protocolVersion: UInt16(v))?.tap == "A")
            #expect(QMKKeycodeFormatter.label(for: 0x001D, protocolVersion: UInt16(v))?.tap == "Z")
        }
    }

    @Test("KC_NO and KC_TRNS")
    func nullKeys() {
        #expect(QMKKeycodeFormatter.label(for: 0x0000, protocolVersion: 10)?.tap == "")
        #expect(QMKKeycodeFormatter.label(for: 0x0001, protocolVersion: 10) == nil)
    }

    // MARK: - User's actual Micro Pad (VIA protocol v10)

    @Test("Micro Pad media keys (v10)")
    func microPadMediaV10() {
        #expect(QMKKeycodeFormatter.label(for: 0x00AB, protocolVersion: 10)?.tap == "Next")
        #expect(QMKKeycodeFormatter.label(for: 0x00AC, protocolVersion: 10)?.tap == "Prev")
        #expect(QMKKeycodeFormatter.label(for: 0x00AE, protocolVersion: 10)?.tap == "Play")
    }

    @Test("Micro Pad row 3: 0x5CC2 decodes as RGB on v10")
    func microPadRow3RGB() {
        #expect(QMKKeycodeFormatter.label(for: 0x5CC2, protocolVersion: 10)?.tap == "RGB")
    }

    @Test("Micro Pad macros (v10) decode as M0 / M1")
    func microPadMacros() {
        #expect(QMKKeycodeFormatter.label(for: 0x5F12, protocolVersion: 10)?.tap == "M0")
        #expect(QMKKeycodeFormatter.label(for: 0x5F13, protocolVersion: 10)?.tap == "M1")
    }

    @Test("Micro Pad 0x5011 decodes as TO(17) under v10")
    func microPadTO() {
        let l = QMKKeycodeFormatter.label(for: 0x5011, protocolVersion: 10)
        #expect(l?.tap == "TO(17)")
        #expect(l?.layerRef == 17)
    }

    // MARK: - Quantum ranges differ between v10 and v12

    @Test("0x5011 decodes differently on v10 vs v12")
    func sameByteDifferentMeaningAcrossProtocols() {
        // v10: QK_TO   = 0x5000..<0x5020       -> 0x5011 = TO(17)
        // v12: QK_LMOD = 0x5000..<0x5200       -> 0x5011 = LM(0, mod-mask 0x11)
        //      QK_TO   = 0x5200..<0x5220 (moved to make room for layer-mod)
        // Same byte, two completely different intents. This test guards
        // against a regression where the v12 range table accidentally adopts
        // the v10 layout (or vice versa).
        #expect(QMKKeycodeFormatter.label(for: 0x5011, protocolVersion: 10)?.tap == "TO(17)")
        let v12 = QMKKeycodeFormatter.label(for: 0x5011, protocolVersion: 12)?.tap
        #expect(v12?.hasPrefix("LM(0,") == true, "got \(v12 ?? "nil")")

        // Sanity-check that v12's actual TO range is where we think it is.
        #expect(QMKKeycodeFormatter.label(for: 0x5201, protocolVersion: 12)?.tap == "TO(1)")
    }

    @Test("Modifier alias LCTL(A) renders the same on both protocols")
    func lctlAlias() {
        // QK_MODS starts at 0x0100 on both protocols.
        let v10 = QMKKeycodeFormatter.label(for: 0x0104, protocolVersion: 10)
        let v12 = QMKKeycodeFormatter.label(for: 0x0104, protocolVersion: 12)
        #expect(v10?.tap == "LCTL(A)")
        #expect(v12?.tap == "LCTL(A)")
    }

    // MARK: - Unsupported protocol (< 10)

    @Test("Protocol v9 (Vial sentinel) decodes via the v12 keycode table")
    func vialSentinelUsesV12Map() {
        // Vial firmware reports protocol 9 as a sentinel meaning "I'm a
        // Vial keyboard." Recent vial-qmk uses VIA v12-shaped quantum
        // keycodes, so we route v9 lookups through the v12 table.
        // KC_A is 0x0004 across all protocol versions; this just guards
        // the basic-table dispatch path.
        let l = QMKKeycodeFormatter.label(for: 0x0004, protocolVersion: 9)
        #expect(l?.tap == "A")

        // QK_MOMENTARY in v12 starts at 0x5220, so `MO(1) = 0x5221`. v10's
        // momentary range was 0x5100, so this would have fallen back to
        // hex if v9 still routed to v10.
        let mo1 = QMKKeycodeFormatter.label(for: 0x5221, protocolVersion: 9)
        #expect(mo1?.tap == "MO(1)")
    }

    @Test("Below v9 (true unsupported VIA) falls back to hex without crashing")
    func preVIAFallsBackToHex() {
        let l = QMKKeycodeFormatter.label(for: 0x0004, protocolVersion: 7)
        #expect(l?.tap == "0x0004")
    }

    // MARK: - Forward-compat: v13/v14 use the v12 default map

    @Test("Future protocol version still decodes (forward-compat to default map)")
    func futureVersion() {
        #expect(QMKKeycodeFormatter.label(for: 0x0004, protocolVersion: 99)?.tap == "A")
    }

    // MARK: - Shifted glyphs (VIA UX)

    @Test("LSFT(1)..LSFT(8) render as shifted US-layout glyphs")
    func shiftDigitsRenderAsGlyphs() {
        // QK_LSFT = 0x0200; QK_LSFT | KC_1 (0x1E) = 0x021E
        #expect(QMKKeycodeFormatter.label(for: 0x021E, protocolVersion: 10)?.tap == "!")
        #expect(QMKKeycodeFormatter.label(for: 0x021F, protocolVersion: 10)?.tap == "@")
        #expect(QMKKeycodeFormatter.label(for: 0x0220, protocolVersion: 10)?.tap == "#")
        #expect(QMKKeycodeFormatter.label(for: 0x0221, protocolVersion: 10)?.tap == "$")
        #expect(QMKKeycodeFormatter.label(for: 0x0222, protocolVersion: 10)?.tap == "%")
        #expect(QMKKeycodeFormatter.label(for: 0x0223, protocolVersion: 10)?.tap == "^")
        #expect(QMKKeycodeFormatter.label(for: 0x0224, protocolVersion: 10)?.tap == "&")
        #expect(QMKKeycodeFormatter.label(for: 0x0225, protocolVersion: 10)?.tap == "*")
    }

    @Test("RSFT-only path also renders shifted glyphs")
    func rshiftRenderGlyphs() {
        // QK_RSFT = 0x1200; RSFT(KC_1) = 0x121E -> "!"
        #expect(QMKKeycodeFormatter.label(for: 0x121E, protocolVersion: 12)?.tap == "!")
    }

    @Test("LSFT(letter) still uses LCTL-style alias (not glyph)")
    func shiftLetterStillAlias() {
        // LSFT(KC_A) = 0x0204 -- letter has no separate shifted glyph entry.
        // Falls through to alias rendering: "LSFT(A)".
        #expect(QMKKeycodeFormatter.label(for: 0x0204, protocolVersion: 10)?.tap == "LSFT(A)")
    }

    @Test("Multi-modifier (Ctrl+Shift+1) does not collapse to glyph")
    func multiModifierStillSpelled() {
        // QK_LCTL | QK_LSFT | KC_1 = 0x0100 | 0x0200 | 0x001E = 0x031E
        // Should be a multi-mod alias, not "!".
        let l = QMKKeycodeFormatter.label(for: 0x031E, protocolVersion: 10)
        #expect(l?.tap != "!")
    }
}
