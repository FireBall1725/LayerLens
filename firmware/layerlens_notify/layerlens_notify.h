// SPDX-License-Identifier: GPL-3.0-only
//
// LayerLens Notify: QMK module that exposes the active layer state to the
// LayerLens host app over Raw HID.
//
// The module is intentionally inert: it claims no QMK hooks and keeps no
// global state beyond a single recorded layer-state slot. The keymap
// author wires the two functions below into their own `layer_state_set_*`
// and `raw_hid_receive` hooks.
//
// Default mode is poll: the host requests, we reply. This coexists
// cleanly with VIA / Vial running side-by-side. To opt into push mode
// (firmware also emits an unsolicited frame on every layer change,
// useful when polling doesn't round-trip to the firmware in your
// build, e.g. some custom Bluetooth setups), add:
//
//     #define LAYERLENS_NOTIFY_PUSH
//
// to your keymap's `config.h`, or `OPT_DEFS += -DLAYERLENS_NOTIFY_PUSH` in
// `rules.mk`. No code change needed in your keymap.
//
// See PROTOCOL.md for the wire format and keymap wiring snippets.
#pragma once

#include "quantum.h"
#include <stdbool.h>
#include <stdint.h>

#define LAYERLENS_NOTIFY_REPORT_ID        0xF1
#define LAYERLENS_NOTIFY_PROTOCOL_VERSION 0x02

// Sub-command in byte 1 of an incoming poll request.
#define LAYERLENS_NOTIFY_CMD_GET_LAYER_STATE 0x00

// Layer-state recorder. Chain from your `layer_state_set_user` / `_kb`.
// See PROTOCOL.md.
layer_state_t layer_state_set_layerlens_notify(layer_state_t state);

// Raw-HID receive handler. Wire this into your `raw_hid_receive` (raw
// QMK) or `raw_hid_receive_kb` (VIA / Vial):
//
//     if (layerlens_notify_handle_command(data, length)) return;
//
// Returns `true` when the frame was a LayerLens command and `data` has
// been filled with the reply. When `VIAL_ENABLE` isn't defined the
// function calls `raw_hid_send` itself; otherwise it just fills `data`
// and returns, deferring the send to Vial's framework so we don't
// double-send.
//
// Returns `false` when the frame wasn't ours; fall through to whatever
// other handlers your keymap has (or set `data[0] = id_unhandled` on
// VIA / Vial).
//
// To keep the polled layer state in sync, chain `layer_state_set_user`
// through `layer_state_set_layerlens_notify`. See PROTOCOL.md / README.
bool layerlens_notify_handle_command(uint8_t *data, uint8_t length);
