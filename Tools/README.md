# Tools

Build-time helpers that produce checked-in artifacts. Not used at runtime.

## `build_via_manifest.py` and `refresh_via_manifest.sh`

Walks a local clone of [the-via/keyboards](https://github.com/the-via/keyboards)
and emits a VID/PID -> {name, path} index used by `LayoutResolver` to look
up which file to download for a given keyboard.

```sh
./Tools/refresh_via_manifest.sh        # clone + rebuild
```

## `build_via_keycode_tables.py`

Parses the-via/app's `src/utils/key-to-byte/{v10,default}.ts` and emits
`Sources/LayerLensCore/Keycodes/VIAKeycodeMaps.generated.swift`: two
parallel keycode tables (v10 and v12+) with both the value-to-label
dictionary and the per-version range constants (`QK_TO`, `QK_MOD_TAP`, etc).

VIA renumbered the quantum keycode space between protocols, so the same
byte (e.g. `0x5011`) has different meaning on a v10 device (TO(17)) vs
a v12 device (TO(1)). The runtime `QMKKeycodeFormatter` dispatches
against the right map using the device's `id_get_protocol_version` reply.

To refresh:

```sh
gh api repos/the-via/app/contents/src/utils/key-to-byte/v10.ts --jq '.content' \
    | base64 -d > reference/via-app-keymaps/v10.ts
gh api repos/the-via/app/contents/src/utils/key-to-byte/default.ts --jq '.content' \
    | base64 -d > reference/via-app-keymaps/default.ts
python3 Tools/build_via_keycode_tables.py
```
