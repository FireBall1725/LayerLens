#!/usr/bin/env python3
"""Generate Swift VIA keycode tables (v10 + v12+) from the-via/app sources.

VIA's app maintains per-protocol-version keycode mappings at
src/utils/key-to-byte/{v10.ts,default.ts}. The maps disagree on quantum
ranges (QK_TO, QK_MOD_TAP, etc.) AND list far more concrete keycodes than
QMK's modern Keycode enum (RGB_*, BL_*, MAGIC_*, MU_*, ...).

This tool is the source of truth for our Swift label tables.

Inputs:
  reference/via-app-keymaps/v10.ts
  reference/via-app-keymaps/default.ts

Output:
  Sources/LayerLensCore/Keycodes/VIAKeycodeMaps.generated.swift
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "reference/via-app-keymaps"
OUT = ROOT / "Sources/LayerLensCore/Keycodes/VIAKeycodeMaps.generated.swift"

# ---------- parse ----------

ENTRY_RE = re.compile(r"^\s+(_?[A-Z][A-Z0-9_]*):\s*0x([0-9a-fA-F]+),?\s*$")

def parse_ts(path: Path) -> dict[str, int]:
    out: dict[str, int] = {}
    for line in path.read_text().splitlines():
        m = ENTRY_RE.match(line)
        if m:
            out[m.group(1)] = int(m.group(2), 16)
    return out

# ---------- labels ----------

# Curated short labels for common keycodes. Kept in sync with KeyPeek's basic.rs
# style (single letter for KC_A..Z, "Enter" for KC_ENT, etc.) and extended with
# RGB / backlight / MAGIC / Music names. Anything missing falls through to the
# heuristic in `derive_label()`.
LABEL_OVERRIDES: dict[str, str] = {
    "KC_NO": "",
    "KC_TRNS": "",
    "KC_TRANSPARENT": "",
    "KC_ENT": "Enter",
    "KC_ENTER": "Enter",
    "KC_ESC": "Esc",
    "KC_ESCAPE": "Esc",
    "KC_BSPC": "Bksp",
    "KC_BACKSPACE": "Bksp",
    "KC_TAB": "Tab",
    "KC_SPC": "Space",
    "KC_SPACE": "Space",
    "KC_MINS": "-",
    "KC_MINUS": "-",
    "KC_EQL": "=",
    "KC_EQUAL": "=",
    "KC_LBRC": "[",
    "KC_LEFT_BRACKET": "[",
    "KC_RBRC": "]",
    "KC_RIGHT_BRACKET": "]",
    "KC_BSLS": "\\",
    "KC_BACKSLASH": "\\",
    "KC_NUHS": "#",
    "KC_NONUS_HASH": "#",
    "KC_SCLN": ";",
    "KC_SEMICOLON": ";",
    "KC_QUOT": "'",
    "KC_QUOTE": "'",
    "KC_GRV": "`",
    "KC_GRAVE": "`",
    "KC_COMM": ",",
    "KC_COMMA": ",",
    "KC_DOT": ".",
    "KC_SLSH": "/",
    "KC_SLASH": "/",
    "KC_CAPS": "Caps",
    "KC_CAPS_LOCK": "Caps",
    "KC_PSCR": "PrtSc",
    "KC_PRINT_SCREEN": "PrtSc",
    "KC_SCRL": "ScrLk",
    "KC_SCROLL_LOCK": "ScrLk",
    "KC_PAUS": "Pause",
    "KC_PAUSE": "Pause",
    "KC_INS": "Ins",
    "KC_INSERT": "Ins",
    "KC_HOME": "Home",
    "KC_PGUP": "PgUp",
    "KC_PAGE_UP": "PgUp",
    "KC_DEL": "Del",
    "KC_DELETE": "Del",
    "KC_END": "End",
    "KC_PGDN": "PgDn",
    "KC_PAGE_DOWN": "PgDn",
    "KC_RGHT": "→",
    "KC_RIGHT": "→",
    "KC_LEFT": "←",
    "KC_DOWN": "↓",
    "KC_UP": "↑",
    "KC_NUM": "Num",
    "KC_NUM_LOCK": "Num",
    "KC_PSLS": "KP /",
    "KC_KP_SLASH": "KP /",
    "KC_PAST": "KP *",
    "KC_KP_ASTERISK": "KP *",
    "KC_PMNS": "KP -",
    "KC_KP_MINUS": "KP -",
    "KC_PPLS": "KP +",
    "KC_KP_PLUS": "KP +",
    "KC_PENT": "KP Ent",
    "KC_KP_ENTER": "KP Ent",
    "KC_P1": "KP 1", "KC_KP_1": "KP 1",
    "KC_P2": "KP 2", "KC_KP_2": "KP 2",
    "KC_P3": "KP 3", "KC_KP_3": "KP 3",
    "KC_P4": "KP 4", "KC_KP_4": "KP 4",
    "KC_P5": "KP 5", "KC_KP_5": "KP 5",
    "KC_P6": "KP 6", "KC_KP_6": "KP 6",
    "KC_P7": "KP 7", "KC_KP_7": "KP 7",
    "KC_P8": "KP 8", "KC_KP_8": "KP 8",
    "KC_P9": "KP 9", "KC_KP_9": "KP 9",
    "KC_P0": "KP 0", "KC_KP_0": "KP 0",
    "KC_PDOT": "KP .",
    "KC_KP_DOT": "KP .",
    "KC_NUBS": "Non-US \\",
    "KC_NONUS_BACKSLASH": "Non-US \\",
    "KC_APP": "Menu",
    "KC_APPLICATION": "Menu",
    "KC_KB_POWER": "Power",
    "KC_KB_MUTE": "Mute",
    "KC_KB_VOLUME_UP": "Vol+",
    "KC_KB_VOLUME_DOWN": "Vol-",
    "KC_AUDIO_MUTE": "Mute",
    "KC_MUTE": "Mute",
    "KC_AUDIO_VOL_UP": "Vol+",
    "KC_VOLU": "Vol+",
    "KC_AUDIO_VOL_DOWN": "Vol-",
    "KC_VOLD": "Vol-",
    "KC_MEDIA_NEXT_TRACK": "Next",
    "KC_MNXT": "Next",
    "KC_MEDIA_PREV_TRACK": "Prev",
    "KC_MPRV": "Prev",
    "KC_MEDIA_STOP": "Stop",
    "KC_MSTP": "Stop",
    "KC_MEDIA_PLAY_PAUSE": "Play",
    "KC_MPLY": "Play",
    "KC_MEDIA_SELECT": "Media",
    "KC_MSEL": "Media",
    "KC_MEDIA_EJECT": "Eject",
    "KC_EJCT": "Eject",
    "KC_MAIL": "Mail",
    "KC_CALCULATOR": "Calc",
    "KC_CALC": "Calc",
    "KC_MY_COMPUTER": "PC",
    "KC_MYCM": "PC",
    "KC_WWW_SEARCH": "Search",
    "KC_WSCH": "Search",
    "KC_WWW_HOME": "Home",
    "KC_WHOM": "Home",
    "KC_WWW_BACK": "Back",
    "KC_WBAK": "Back",
    "KC_WWW_FORWARD": "Fwd",
    "KC_WFWD": "Fwd",
    "KC_WWW_STOP": "Stop",
    "KC_WSTP": "Stop",
    "KC_WWW_REFRESH": "Refresh",
    "KC_WREF": "Refresh",
    "KC_WWW_FAVORITES": "Favs",
    "KC_WFAV": "Favs",
    "KC_MEDIA_FAST_FORWARD": "FF",
    "KC_MFFD": "FF",
    "KC_MEDIA_REWIND": "Rew",
    "KC_MRWD": "Rew",
    "KC_BRIGHTNESS_UP": "Bright+",
    "KC_BRIU": "Bright+",
    "KC_BRIGHTNESS_DOWN": "Bright-",
    "KC_BRID": "Bright-",
    "KC_LCTL": "LCtrl", "KC_LCTRL": "LCtrl", "KC_LEFT_CTRL": "LCtrl",
    "KC_LSFT": "LShift", "KC_LSHIFT": "LShift", "KC_LEFT_SHIFT": "LShift",
    "KC_LALT": "LAlt", "KC_LEFT_ALT": "LAlt",
    "KC_LGUI": "LCmd", "KC_LCMD": "LCmd", "KC_LWIN": "LWin", "KC_LEFT_GUI": "LCmd",
    "KC_RCTL": "RCtrl", "KC_RCTRL": "RCtrl", "KC_RIGHT_CTRL": "RCtrl",
    "KC_RSFT": "RShift", "KC_RSHIFT": "RShift", "KC_RIGHT_SHIFT": "RShift",
    "KC_RALT": "RAlt", "KC_RIGHT_ALT": "RAlt", "KC_ALGR": "AltGr",
    "KC_RGUI": "RCmd", "KC_RCMD": "RCmd", "KC_RWIN": "RWin", "KC_RIGHT_GUI": "RCmd",
    "KC_GESC": "GEsc",
    # Lighting
    "BL_ON": "BL On", "BL_OFF": "BL Off",
    "BL_DEC": "BL-", "BL_INC": "BL+",
    "BL_TOGG": "BL", "BL_STEP": "BL Step", "BL_BRTG": "BL Breathe",
    "RGB_TOG": "RGB",
    "RGB_MOD": "RGB+", "RGB_RMOD": "RGB-",
    "RGB_HUI": "Hue+", "RGB_HUD": "Hue-",
    "RGB_SAI": "Sat+", "RGB_SAD": "Sat-",
    "RGB_VAI": "Val+", "RGB_VAD": "Val-",
    "RGB_SPI": "Speed+", "RGB_SPD": "Speed-",
    "RGB_M_P": "RGB Plain", "RGB_M_B": "RGB Breathe",
    "RGB_M_R": "RGB Rainbow", "RGB_M_SW": "RGB Swirl",
    "RGB_M_SN": "RGB Snake", "RGB_M_K": "RGB Knight",
    "RGB_M_X": "RGB Xmas", "RGB_M_G": "RGB Gradient",
    # Magic
    "MAGIC_TOGGLE_NKRO": "NKRO",
    "MAGIC_TOGGLE_GUI": "GUI Toggle",
    # Music
    "MU_ON": "Music On", "MU_OFF": "Music Off",
    "MU_TOG": "Music", "MU_MOD": "Music Mode",
    # Misc
    "DEBUG": "Debug",
    "RESET": "Reset",
    "EE_CLR": "EE Clear",
    "QK_BOOT": "Boot",
}

def derive_label(name: str) -> str:
    if name in LABEL_OVERRIDES:
        return LABEL_OVERRIDES[name]
    # Single-letter KC_X
    if re.fullmatch(r"KC_[A-Z]", name):
        return name[3]
    # KC_<digit>
    if re.fullmatch(r"KC_[0-9]", name):
        return name[3]
    # KC_F<n>
    m = re.fullmatch(r"KC_F([0-9]+)", name)
    if m:
        return "F" + m.group(1)
    # KC_INTERNATIONAL_<n> / KC_LANG_<n>
    m = re.fullmatch(r"KC_INTERNATIONAL_([0-9])", name)
    if m: return f"Intl {m.group(1)}"
    m = re.fullmatch(r"KC_LANG_([0-9])", name) or re.fullmatch(r"KC_LANGUAGE_([0-9])", name)
    if m: return f"Lang {m.group(1)}"
    # Strip a known prefix and titlecase
    for prefix in ("KC_", "RGB_", "BL_", "MAGIC_", "MU_", "QK_"):
        if name.startswith(prefix):
            return name[len(prefix):].replace("_", " ").title()
    return name.replace("_", " ").title()

# ---------- emit ----------

# Range constants we need to extract (must be present in both TS files).
RANGE_PAIRS = [
    ("mods",            "_QK_MODS",           "_QK_MODS_MAX"),
    ("modTap",          "_QK_MOD_TAP",        "_QK_MOD_TAP_MAX"),
    ("layerTap",        "_QK_LAYER_TAP",      "_QK_LAYER_TAP_MAX"),
    ("layerMod",        "_QK_LAYER_MOD",      "_QK_LAYER_MOD_MAX"),
    ("toLayer",         "_QK_TO",             "_QK_TO_MAX"),
    ("momentary",       "_QK_MOMENTARY",      "_QK_MOMENTARY_MAX"),
    ("defaultLayer",    "_QK_DEF_LAYER",      "_QK_DEF_LAYER_MAX"),
    ("toggleLayer",     "_QK_TOGGLE_LAYER",   "_QK_TOGGLE_LAYER_MAX"),
    ("oneShotLayer",    "_QK_ONE_SHOT_LAYER", "_QK_ONE_SHOT_LAYER_MAX"),
    ("oneShotMod",      "_QK_ONE_SHOT_MOD",   "_QK_ONE_SHOT_MOD_MAX"),
    ("layerTapToggle",  "_QK_LAYER_TAP_TOGGLE", "_QK_LAYER_TAP_TOGGLE_MAX"),
    ("macro",           "_QK_MACRO",          "_QK_MACRO_MAX"),
    ("kbCustom",        "_QK_KB",             "_QK_KB_MAX"),
]

def swift_str(s: str) -> str:
    s = s.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{s}"'

def render(maps: dict[str, dict[str, int]]) -> str:
    lines: list[str] = []
    lines.append("// Auto-generated by Tools/build_via_keycode_tables.py. Do not edit.")
    lines.append("// Source: the-via/app src/utils/key-to-byte/{v10,default}.ts")
    lines.append("import Foundation")
    lines.append("")

    # Emit basic tables
    for label, entries in maps.items():
        lines.append(f"extension VIAKeycodeMap {{")
        lines.append(f"    /// Generated keycode label table for {label}.")
        lines.append(f"    static let {label}BasicTable: [UInt16: QMKKeycodeLabel] = [")
        seen: set[int] = set()
        for name, val in sorted(entries.items(), key=lambda kv: kv[1]):
            if name.startswith("_"):
                continue
            if val in seen:
                continue
            seen.add(val)
            tap = derive_label(name)
            lines.append(
                f'        0x{val:04X}: QMKKeycodeLabel(tap: {swift_str(tap)}),  // {name}'
            )
        lines.append("    ]")
        lines.append("}")
        lines.append("")

    # Emit ranges
    for label, entries in maps.items():
        lines.append(f"extension VIAKeycodeMap {{")
        lines.append(f"    static let {label}Ranges: VIAKeycodeRanges = VIAKeycodeRanges(")
        for i, (name, start_key, max_key) in enumerate(RANGE_PAIRS):
            start = entries.get(start_key)
            end_inclusive = entries.get(max_key)
            if start is None or end_inclusive is None:
                continue
            comma = "," if i < len(RANGE_PAIRS) - 1 else ""
            lines.append(f"        {name}: 0x{start:04X} ..< 0x{end_inclusive + 1:04X}{comma}")
        lines.append("    )")
        lines.append("}")
        lines.append("")
    return "\n".join(lines)

def main():
    v10 = parse_ts(SRC / "v10.ts")
    v11 = parse_ts(SRC / "v11.ts")
    v12 = parse_ts(SRC / "v12.ts")
    out = render({"v10": v10, "v11": v11, "v12": v12})
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(out)
    for name, table in [("v10", v10), ("v11", v11), ("v12", v12)]:
        print(f"{name} entries: {len([n for n in table if not n.startswith('_')])}")
    print(f"wrote {OUT} ({OUT.stat().st_size} bytes)")

if __name__ == "__main__":
    main()
