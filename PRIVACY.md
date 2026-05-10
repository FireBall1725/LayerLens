# Privacy

LayerLens is built privacy-first. By default it sends nothing. If you
opt in (during onboarding or via **Settings → Privacy**) we send a
small set of anonymous usage signals to help guide development.

## What's collected (only when telemetry is enabled)

| Signal | Fields |
|---|---|
| `App.Launched` | macOS version, CPU architecture, app version, locale (auto-attached by TelemetryDeck). |
| `Keyboard.Connected` | `vidPid` (e.g. `0x8D1D:0x9D9D`), `kind` (`qmk` or `vial`), `protocolVersion` (`9` / `10` / `11` / `12`). |
| `Module.Detected` | `mode` — one of `poll`, `push`, `none`. Tells us how many users have flashed the firmware module. |

That's the entire list. New signals will be documented here before they
ship.

## What's NOT collected, ever

- Keystrokes, layer-state values, layer names, custom labels.
- Keyboard product names, serial numbers, IOKit registry paths.
- Hostnames, usernames, computer names.
- Email addresses or any other contact info.
- IP addresses (TelemetryDeck strips them server-side; we never see them).
- Any keymap content, override file paths, or layout JSON.
- Crash dumps with file paths.

## Why we collect this

- **Install count** (anonymous-user hash from TelemetryDeck): how many
  Macs run LayerLens.
- **System distribution**: which macOS versions and Apple-Silicon vs
  Intel mixes to keep prioritising.
- **Keyboard popularity** (VID:PID histogram): which boards are common
  enough to test against and write layout fixes for.
- **Module adoption** (`poll` / `push` / `none`): whether the firmware
  module is making it into users' keymaps, and which mode wins out.

We don't sell this data, share it with anyone besides TelemetryDeck (the
hosting backend), or use it for anything other than guiding LayerLens
development.

## How the anonymous user hash works

TelemetryDeck derives a stable per-install identifier by hashing some
hardware identifiers locally on your machine, salting it with the app
ID, and only ever sending the hash. We see "an anonymous user did X"
and can count distinct installs without knowing who anyone is. See
[TelemetryDeck's own privacy
policy](https://telemetrydeck.com/privacy/) for the gory detail.

## Opting out

Telemetry is **off** by default on every fresh install. To turn it off
after opting in: open **Settings → Privacy** and flip the toggle. The
SDK stops sending immediately; nothing else gets transmitted.

## Source

The full implementation lives in
[`Sources/LayerLens/Telemetry.swift`](./Sources/LayerLens/Telemetry.swift).
The list of call sites is small enough to grep for: search the source
for `Telemetry.send`.
