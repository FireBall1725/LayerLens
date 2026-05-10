# layerlens_notify (QMK module)

A small QMK module that exposes the active-layer bitmask to the
[LayerLens](../../README.md) macOS app over Raw HID, so the floating
overlay can mirror your active layers in real time.

GPL-3.0-only.

## Why a custom module

VIA's protocol exposes the keymap matrix but **does not** expose live
layer-change events. KeyPeek's upstream relies on
[`srwi/keypeek_layer_notify`](https://github.com/srwi/qmk-modules);
LayerLens has its own wire format (see [`PROTOCOL.md`](./PROTOCOL.md))
so it doesn't depend on that fork remaining maintained, and one module
serves either tool.

## What this module does (and doesn't)

It exposes two pure functions and **claims no QMK hooks**. Your keymap
chooses where to call them. That keeps it composable with everything
else your keymap is doing: no weak-symbol races, no hidden auto-wiring.

- `layer_state_set_layerlens_notify(state)`: chain-point for layer
  tracking. Call from your `layer_state_set_user`. Returns `state` so
  you can compose with other transforms. With
  `#define LAYERLENS_NOTIFY_PUSH` it also emits an unsolicited Raw HID
  frame on every layer change; without the flag it just records.
- `layerlens_notify_handle_command(data, length)`: handle a poll
  request from the host. Returns `true` if the frame was for us and
  fills the response into `data`. Calls `raw_hid_send` itself on raw
  QMK and plain VIA; defers to Vial's framework when `VIAL_ENABLE` is
  defined.

## Requirements

- QMK firmware with the modules feature (any release from 2024 onwards).
- `RAW_ENABLE = yes` in your keymap's `rules.mk`. (Plus `VIA_ENABLE = yes`
  if you're on VIA / Vial.)

## Install

Drop this directory into your QMK userspace under
`modules/fireball1725/layerlens_notify/` (or use a git submodule). Then
add it to your keymap's `keymap.json`:

```json
{
    "modules": [
        "fireball1725/layerlens_notify"
    ]
}
```

(`fireball1725` is just a directory namespace under your `modules/`
folder. Pick any name you like, as long as the folder path and the
`keymap.json` entry match.)

Add the wiring snippets below to your `keymap.c`. Build and flash:

```sh
qmk compile -kb <your_keyboard> -km <your_keymap>
```

## Wiring

Two snippets go in your `keymap.c`. The receiver is optional only if
you've opted into push mode and don't expect polls; the recorder is
always required.

### Recorder

```c
#include "layerlens_notify.h"

layer_state_t layer_state_set_user(layer_state_t state) {
    return layer_state_set_layerlens_notify(state);
}
```

If you already have a `layer_state_set_user`, just chain through us
instead:

```c
layer_state_t layer_state_set_user(layer_state_t state) {
    state = layer_state_set_layerlens_notify(state);
    // ... your existing logic ...
    return state;
}
```

### Receiver

Pick the snippet for your firmware. `handle_command` sends the reply
itself on raw QMK and VIA; on Vial the framework sends and the module
stays silent. (`VIAL_ENABLE` is the gate.)

**VIA** (modern upstream QMK with `VIA_ENABLE = yes`):

```c
bool via_command_kb(uint8_t *data, uint8_t length) {
    return layerlens_notify_handle_command(data, length);
}
```

`via_command_kb` returns `bool`; we just forward our handler's result.
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

**Plain QMK, no VIA:**

```c
void raw_hid_receive(uint8_t *data, uint8_t length) {
    if (layerlens_notify_handle_command(data, length)) return;
    // ... your existing logic ...
}
```

## Push mode

By default the module is poll-only: silent until the host asks. If
polling doesn't round-trip to the firmware in your build (e.g. some
custom Bluetooth setups), opt into push mode and the firmware will also
emit an unsolicited report on every layer change.

Add this to your keymap's `config.h`:

```c
#define LAYERLENS_NOTIFY_PUSH
```

Or pass it via `rules.mk`:

```make
OPT_DEFS += -DLAYERLENS_NOTIFY_PUSH
```

No `keymap.c` change needed; `layer_state_set_layerlens_notify`
already pushes when the flag is defined.

Push mode conflicts with concurrent VIA / Vial use on the same Raw HID
channel: the unsolicited frames look like garbage replies to in-flight
configurator requests. Keep VIA / Vial closed while running LayerLens
in push mode.

## Verifying it works

After flashing, plug the board in and start LayerLens. The Configure
window's "Live" stat should flip to "Yes" and the floating overlay
should flash whenever you change layers.

You can also smoke-test independently with any Raw HID inspector that
listens on usage page `0xFF60` / usage `0x61`. Send `[0xF1, 0x00]` and
you should get back a 32-byte response starting with `0xF1 0x00 0x02`
followed by the four layer-state bytes.
