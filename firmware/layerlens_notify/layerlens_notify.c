// SPDX-License-Identifier: GPL-3.0-only
#include "layerlens_notify.h"
#include "raw_hid.h"
#include <string.h>

#ifndef RAW_ENABLE
#    error "layerlens_notify requires RAW_ENABLE = yes in your keymap rules.mk"
#endif

// VIA Raw HID is fixed at 32-byte reports. Hardcoded so we don't depend
// on RAW_EPSIZE from usb_descriptor.h, which isn't part of every
// keyboard's public include path.
#define LAYERLENS_NOTIFY_REPORT_LEN 32

// Tracked layer state. Updated by `layer_state_set_layerlens_notify`,
// read by `handle_command` when the host polls.
//
// Always uint32_t regardless of platform: `layer_state_t` is uint8_t on
// AVR and uint32_t on ARM, but the wire format is fixed at four bytes
// either way, and storing widened means the read in handle_command
// doesn't need a conditional.
static uint32_t tracked_layer_state = 0;

layer_state_t layer_state_set_layerlens_notify(layer_state_t state) {
    tracked_layer_state = (uint32_t)state;

#ifdef LAYERLENS_NOTIFY_PUSH
    // Push frames use the v1 wire shape:
    //   [0xF1, version, b3, b2, b1, b0, ...]
    // The poll-response shape is different ([0xF1, 0x00, version, …])
    // so the host can tell unsolicited pushes from in-flight poll
    // replies just by looking at byte 1.
    uint8_t data[LAYERLENS_NOTIFY_REPORT_LEN];
    memset(data, 0, sizeof(data));
    data[0] = LAYERLENS_NOTIFY_REPORT_ID;
    data[1] = LAYERLENS_NOTIFY_PROTOCOL_VERSION;
    data[2] = (uint8_t)((tracked_layer_state >> 24) & 0xFF);
    data[3] = (uint8_t)((tracked_layer_state >> 16) & 0xFF);
    data[4] = (uint8_t)((tracked_layer_state >>  8) & 0xFF);
    data[5] = (uint8_t)( tracked_layer_state        & 0xFF);
    raw_hid_send(data, LAYERLENS_NOTIFY_REPORT_LEN);
#endif

    return state;
}

bool layerlens_notify_handle_command(uint8_t *data, uint8_t length) {
    (void)length;
    if (data[0] != LAYERLENS_NOTIFY_REPORT_ID) return false;

    switch (data[1]) {
        case LAYERLENS_NOTIFY_CMD_GET_LAYER_STATE:
            data[2] = LAYERLENS_NOTIFY_PROTOCOL_VERSION;
            data[3] = (uint8_t)((tracked_layer_state >> 24) & 0xFF);
            data[4] = (uint8_t)((tracked_layer_state >> 16) & 0xFF);
            data[5] = (uint8_t)((tracked_layer_state >>  8) & 0xFF);
            data[6] = (uint8_t)( tracked_layer_state        & 0xFF);
            break;
        default:
            return false;
    }

    // On Vial the framework sends the reply itself after our `_kb`
    // returns, so we skip our send to avoid duplicates. On plain VIA
    // and raw QMK we send the reply here.
#ifndef VIAL_ENABLE
    raw_hid_send(data, LAYERLENS_NOTIFY_REPORT_LEN);
#endif
    return true;
}
