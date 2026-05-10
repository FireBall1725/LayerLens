import Foundation
import LayerLensCore
import IOKit
import IOKit.hid

@MainActor
@Observable
final class AppState {
    /// Live list of Raw HID candidates from `HIDDeviceMonitor`. Updates on plug/unplug.
    var detectedKeyboards: [DiscoveredKeyboard] = []

    /// Live, fully-bootstrapped connections keyed by IOKit registry path.
    var connections: [String: ActiveConnection] = [:]

    /// Which connection feeds the main window + overlay UI right now. The
    /// most recent layer-notify event wins. Falls back to the first active
    /// connection when nothing has flashed yet.
    var focusedKeyboardPath: String?

    /// Most recent error or activity message (single line). Kept simple; per-
    /// connection failures live on the connection itself.
    var lastMessage: String = ""

    /// Set of HID keyboard-page (`0x07`) usage codes currently pressed.
    /// Pumped from `KeystrokeListener` on every press / release. The
    /// `KeyboardLayoutView` reads from this to highlight matching keys
    /// in the visible layer's keymap.
    ///
    /// This is keymap-keycode comparable: a key whose layer keycode
    /// equals an entry in this set is being pressed right now (within
    /// the basic 0x00..0xE7 range that HID and QMK share).
    var pressedKeycodes: Set<UInt16> = []

    /// Set by `LayerLensApp` so live layer-notify events can flash the overlay.
    weak var overlay: OverlayController?

    /// Drives the per-keyboard Configure window. Set by the menu bar / settings
    /// before calling openWindow(id: "config"); the Window scene reads this to
    /// pick which keyboard to render.
    var configuringKeyboardPath: String?

    /// Convenience: the keyboard the Configure window is currently aimed at.
    var configuringKeyboard: DiscoveredKeyboard? {
        guard let path = configuringKeyboardPath else { return nil }
        return detectedKeyboards.first(where: { $0.info.registryPath == path })
            ?? connections[path]?.keyboard
    }

    private var monitor: HIDDeviceMonitor?
    private weak var preferences: Preferences?

    /// Global keystroke listener for the typing-highlight feature.
    /// Started lazily once Input Monitoring is granted; opening it
    /// before that would trip the macOS TCC prompt out of context.
    private let keystrokes = KeystrokeListener()

    /// Start the keystroke listener if the user has already granted
    /// Input Monitoring. No-op otherwise (won't trigger the system
    /// permission prompt). Safe to call repeatedly. Called at launch
    /// and again after the onboarding flow detects a fresh grant.
    func enableKeystrokeListeningIfGranted() {
        guard InputMonitoringPermission.status == .granted else { return }
        keystrokes.start { [weak self] pressed in
            self?.pressedKeycodes = pressed
        }
    }

    // MARK: - Convenience accessors used by the UI

    var focusedConnection: ActiveConnection? {
        if let path = focusedKeyboardPath, let conn = connections[path] { return conn }
        return connections.values.sorted(by: { $0.id < $1.id }).first
    }

    var hasAnyLiveLayerEvents: Bool {
        connections.values.contains { $0.hasLiveLayerEvents }
    }

    var anyConnected: Bool { !connections.isEmpty }

    // MARK: - Lifecycle

    func attach(preferences: Preferences) {
        self.preferences = preferences

        monitor = HIDDeviceMonitor { [weak self] devices in
            // Callback lands on the monitor's dispatch queue. Hop to MainActor.
            Task { @MainActor [weak self] in
                self?.handleDeviceListChanged(devices)
            }
        }

        observeAutoConnectChanges()
    }

    /// Watch for changes to the user's auto-connect set and (re-)connect any
    /// currently-attached keyboard that's now opted in. Runs at every change
    /// to the set, including ticking the checkbox while a keyboard is already
    /// plugged in (the bug this fixes).
    private func observeAutoConnectChanges() {
        guard let preferences else { return }
        withObservationTracking {
            _ = preferences.autoConnectVIDPIDs
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self, let prefs = self.preferences else { return }
                for kb in self.detectedKeyboards
                where prefs.shouldAutoConnect(kb)
                   && self.connections[kb.info.registryPath] == nil {
                    await self.connect(to: kb)
                }
                self.observeAutoConnectChanges()  // re-register
            }
        }
    }

    // MARK: - Discovery

    private func handleDeviceListChanged(_ list: [DiscoveredKeyboard]) {
        detectedKeyboards = list

        // Drop connections whose device is no longer present. Order matters:
        //   1. Hide overlay (so AppKit can't re-layout an empty panel)
        //   2. Shift focusedKeyboardPath to a still-live connection BEFORE
        //      removing the dict entry. Otherwise SwiftUI evaluates
        //      `focusedConnection == nil` mid-update and AppKit crashes
        //      during a constraint pass (EXC_BREAKPOINT in NSViewUpdateConstraints).
        //   3. Remove the connection from the dict.
        //   4. Close the connection (HIDDevice etc.)
        let attachedPaths = Set(list.map(\.info.registryPath))
        let goneEntries = connections.filter { !attachedPaths.contains($0.key) }

        for (path, conn) in goneEntries {
            if focusedKeyboardPath == path {
                overlay?.dismissImmediately()
                let nextPath = connections.keys
                    .filter { $0 != path && attachedPaths.contains($0) }
                    .sorted()
                    .first
                focusedKeyboardPath = nextPath  // may be nil if no other live connection
            }
            connections.removeValue(forKey: path)
            conn.close()
            lastMessage = "\(conn.keyboard.info.product ?? conn.keyboard.info.displayVIDPID) disconnected"
        }

        // Auto-connect any candidate the user opted into.
        guard let prefs = preferences else { return }
        for kb in list where prefs.shouldAutoConnect(kb) {
            if connections[kb.info.registryPath] == nil {
                Task { await self.connect(to: kb) }
            }
        }
    }

    // MARK: - Connect / disconnect

    func connect(to keyboard: DiscoveredKeyboard) async {
        guard connections[keyboard.info.registryPath] == nil else { return }

        guard let raw = HIDEnumerator.resolveDevice(for: keyboard) else {
            lastMessage = "Could not open \(keyboard.displayName)"
            return
        }
        let device = HIDDevice(device: raw)
        do { try device.open() } catch {
            lastMessage = "Open failed: \(error)"
            return
        }
        let client = VIAClient(transport: device)
        let conn = ActiveConnection(keyboard: keyboard, device: device, client: client)
        connections[keyboard.info.registryPath] = conn

        do {
            let resolver = try LayoutResolver.builtIn()
            let override = preferences?.customLayoutPath(forKeyboard: keyboard)
            try await conn.bootstrap(
                layoutResolver: resolver,
                customLayoutOverride: override
            )
        } catch let LayoutResolver.ResolveError.notInManifest(vid, pid) {
            conn.error = "\(String(format: "%04X:%04X", vid, pid)) not in VIA keyboards repo"
            lastMessage = conn.error ?? "Layout not found"
            conn.close()
            connections.removeValue(forKey: keyboard.info.registryPath)
            return
        } catch {
            conn.error = "\(error)"
            lastMessage = "\(keyboard.displayName): \(error)"
            conn.close()
            connections.removeValue(forKey: keyboard.info.registryPath)
            return
        }

        focusedKeyboardPath = keyboard.info.registryPath
        lastMessage = "\(keyboard.displayName) connected"

        // Telemetry: report the keyboard's VID:PID, kind, and protocol
        // version so we can build keyboard-popularity histograms.
        // Product names and serial numbers are deliberately not sent.
        if let preferences {
            Telemetry.send(
                "Keyboard.Connected",
                parameters: [
                    "vidPid": keyboard.info.displayVIDPID,
                    "kind": keyboard.kind.label,
                    "protocolVersion": String(conn.protocolVersion)
                ],
                preferences: preferences
            )
        }

        let path = keyboard.info.registryPath
        conn.startNotifyStream(
            onEvent: { [weak self] _ in
                // The notify handler already updated the connection's state.
                // Surface this keyboard as the focus and flash the overlay.
                // Pass the resolved active layer so the overlay stays pinned
                // while a non-base layer is held and re-arms its fade-out only
                // on release.
                guard let self else { return }
                self.focusedKeyboardPath = path
                let activeLayer = self.connections[path]?.selectedLayer ?? 0
                self.overlay?.flash(activeLayer: activeLayer)
            },
            onModuleDetected: { [weak self] in
                // Fires once per connection if the firmware module
                // answered the poll probe. Tells us module-adoption
                // rate without naming or counting individual users
                // beyond the anonymous TelemetryDeck hash.
                guard let self, let preferences = self.preferences else { return }
                Telemetry.send(
                    "Module.Detected",
                    parameters: ["mode": "poll"],
                    preferences: preferences
                )
            }
        )

        // One-time courtesy flash on successful connect so the user gets a
        // visual confirmation without having to press a layer key first.
        overlay?.flash()
    }

    func focus(on path: String) {
        focusedKeyboardPath = path
    }

    /// Single entry point for the Settings auto-connect checkbox. Updates
    /// the persisted auto-connect set AND immediately connects (or
    /// disconnects) the keyboard. Manual menu-bar Connect/Disconnect
    /// doesn't touch the auto-connect set.
    func setAutoConnect(_ on: Bool, for keyboard: DiscoveredKeyboard) {
        preferences?.setAutoConnect(on, for: keyboard)
        let path = keyboard.info.registryPath
        if on {
            if connections[path] == nil {
                Task { await connect(to: keyboard) }
            }
        } else {
            if connections[path] != nil {
                disconnect(path)
            }
        }
    }

    func disconnect(_ path: String) {
        guard let conn = connections[path] else { return }
        if focusedKeyboardPath == path {
            overlay?.dismissImmediately()
            focusedKeyboardPath = connections.keys.filter { $0 != path }.sorted().first
        }
        connections.removeValue(forKey: path)
        conn.close()
        lastMessage = "\(conn.keyboard.displayName) disconnected"
    }

    func disconnectAll() {
        for (_, conn) in connections {
            conn.close()
        }
        connections.removeAll()
        focusedKeyboardPath = nil
    }

    /// Connect to the first detected keyboard if the user has any
    /// `autoConnectOnLaunch`-equivalent set, called once at startup.
    func connectFirstIfPreferred() async {
        guard let prefs = preferences else { return }

        // Path A: an explicit per-device auto-connect entry already matches.
        for kb in detectedKeyboards where prefs.shouldAutoConnect(kb) {
            await connect(to: kb)
        }

        // Path B: legacy "auto-connect on launch" flag. Connect to the first
        // detected keyboard if nothing else is set up.
        if prefs.autoConnectOnLaunch && connections.isEmpty,
           let first = detectedKeyboards.first {
            await connect(to: first)
        }
    }
}
