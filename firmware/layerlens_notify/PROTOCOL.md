# layerlens_notify wire protocol

32-byte Raw HID frames over the VIA Raw HID interface (usage page `0xFF60`,
usage `0x61`), so no extra USB endpoint is needed. The only firmware flag
required is `RAW_ENABLE = yes`.

The module supports two delivery modes; the keymap author selects via a
single compile-time `#define`:

- **Poll mode (default, no flag)**: host requests, firmware replies.
  Coexists cleanly with VIA / Vial running side-by-side. Recommended for
  most USB users.
- **Push mode (`#define LAYERLENS_NOTIFY_PUSH`)**: firmware additionally
  emits an unsolicited report on every layer change. Use this when
  polling doesn't reach the firmware for whatever reason in your build
  (some custom Bluetooth setups). Conflicts with concurrent VIA / Vial
  use because the unsolicited frames look like garbage to other Raw HID
  consumers. With the flag set, both polls and pushes are emitted; the
  host de-dupes.

The host listens for both formats simultaneously, so a firmware that
emits either or both Just Works.

## Protocol version

Byte 0 of every frame is `LAYERLENS_NOTIFY_REPORT_ID` (`0xF1`). The
current protocol version is `0x02`, reported back in poll responses and
push frames so the host can negotiate forward-compat behaviour.

| Version | Wire |
|--------:|---|
| `0x01`  | Push-only. Withdrawn; interfered with VIA/Vial. |
| `0x02`  | Poll request/response, plus optional push frames in the v1 shape. Current. |

## Poll: `GET_LAYER_STATE` (sub-command `0x00`)

**Host → firmware (32 bytes):**

| Byte  | Value           | Notes |
|------:|---|---|
| 0     | `0xF1`          | report id |
| 1     | `0x00`          | sub-command |
| 2..31 | `0x00` (recommended) | reserved; ignored by firmware |

**Firmware → host (32 bytes):**

| Byte  | Field                    | Notes |
|------:|---|---|
| 0     | `0xF1`                   | report id (echoed) |
| 1     | `0x00`                   | sub-command (echoed) |
| 2     | protocol version         | currently `0x02` |
| 3     | layer state byte 3 (MSB) | `(layer_state >> 24) & 0xFF` |
| 4     | layer state byte 2       | `(layer_state >> 16) & 0xFF` |
| 5     | layer state byte 1       | `(layer_state >>  8) & 0xFF` |
| 6     | layer state byte 0 (LSB) | ` layer_state        & 0xFF` |
| 7..31 | reserved                 | zero-padded; future fields go here |

The reply is built from the module's tracked-state slot, last updated
by `layer_state_set_layerlens_notify`, so the keymap must chain
through that from `layer_state_set_user` for poll replies to reflect
the live state.

## Push frame (optional)

When the keymap is compiled with `#define LAYERLENS_NOTIFY_PUSH`, the
firmware emits this 32-byte frame on every layer transition (in
addition to handling polls):

| Byte  | Field                    | Notes |
|------:|---|---|
| 0     | `0xF1`                   | report id |
| 1     | protocol version         | currently `0x02`; **never `0x00`** so the host can tell push frames from poll responses by byte 1 |
| 2     | layer state byte 3 (MSB) | `(layer_state >> 24) & 0xFF` |
| 3     | layer state byte 2       | `(layer_state >> 16) & 0xFF` |
| 4     | layer state byte 1       | `(layer_state >>  8) & 0xFF` |
| 5     | layer state byte 0 (LSB) | ` layer_state        & 0xFF` |
| 6..31 | reserved                 | zero-padded |

This shape is identical to the withdrawn v1 push format, so a host
written against v1 still works against a v2 push-mode firmware.

## `layer_state` semantics

QMK's `layer_state_t` is `uint32_t` on ARM and `uint8_t` (widened to 32)
on AVR. Bit *N* set means layer *N* is currently active. Bit 0 may or
may not be reflected explicitly depending on how the firmware tracks the
base layer; consumers should treat bit 0 as implicit when no other bits
are set.

## Detection and forward compatibility

A host that doesn't know whether the connected keyboard has the module
installed can probe by sending `[0xF1, 0x00]` once and waiting ~250 ms
for a reply. If one arrives, polling is safe and the firmware is poll-
capable. If the probe times out, the firmware is either uninstalled or
push-only; the host should fall back to passively watching for `0xF1`
push frames.

LayerLens polls at 50 ms (20 Hz). Faster polling burns USB bandwidth and
battery without improving overlay UX, since `layer_state_set_*` only
fires on transitions.

## Wiring into your keymap

Two snippets total. The module exposes pure functions and claims no QMK
hooks; you wire them into your own.

### Layer-state recorder

```c
#include "layerlens_notify.h"

layer_state_t layer_state_set_user(layer_state_t state) {
    return layer_state_set_layerlens_notify(state);
}
```

If you already have a `layer_state_set_user`, just chain through us:

```c
layer_state_t layer_state_set_user(layer_state_t state) {
    state = layer_state_set_layerlens_notify(state);
    // ... your existing logic ...
    return state;
}
```

### Raw-HID receiver

Pick the snippet for your firmware. `handle_command` calls
`raw_hid_send` itself on raw QMK and VIA; on Vial it leaves the send
to the framework so we don't double-send. (`VIAL_ENABLE` is the gate.)

**VIA** (modern upstream QMK with `VIA_ENABLE = yes`):

```c
bool via_command_kb(uint8_t *data, uint8_t length) {
    return layerlens_notify_handle_command(data, length);
}
```

If you need this hook for your own commands too, chain through us:

```c
bool via_command_kb(uint8_t *data, uint8_t length) {
    if (layerlens_notify_handle_command(data, length)) return true;
    // ... your other commands ...
    return false;
}
```

**Vial** (vial-qmk fork):

```c
void raw_hid_receive_kb(uint8_t *data, uint8_t length) {
    if (layerlens_notify_handle_command(data, length)) return;
    // ... your other commands ...
}
```

**Plain QMK, no VIA**:

```c
void raw_hid_receive(uint8_t *data, uint8_t length) {
    if (layerlens_notify_handle_command(data, length)) return;
    // ... your existing logic ...
}
```

### Push mode

To opt into push delivery (lower latency, or for builds where polling
doesn't round-trip to the firmware), add this to your keymap's
`config.h`:

```c
#define LAYERLENS_NOTIFY_PUSH
```

No code change in your keymap; `layer_state_set_layerlens_notify`
already pushes when the flag is defined.

## Why `0xF1`

VIA's standard commands occupy `0x00` through `0x15`. Vial reserves
`0xFD` and `0xFE`. The `0xC0`-`0xFC` zone is unassigned. `0xF1` sits far
enough away to be unambiguous and reads as a single-byte mnemonic for
"layerlens". Both firmware and host filter incoming frames by this byte
before doing anything else.
