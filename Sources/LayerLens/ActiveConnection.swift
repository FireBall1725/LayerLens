import Foundation
import SwiftUI
import AppKit
import LayerLensCore

/// One live connection to a Raw HID keyboard. Owns the HIDDevice + VIAClient
/// and the read keymap/layer state. AppState holds a dictionary of these,
/// keyed by IOKit registry path.
@MainActor
@Observable
final class ActiveConnection: Identifiable {
    let id: String
    let keyboard: DiscoveredKeyboard

    var protocolVersion: UInt16 = 0
    var definition: KeyboardDefinition?
    /// Where `definition` came from. Set by `bootstrap` based on the
    /// resolver path that won. Surfaced in the Configure window's stats
    /// row so the user can tell the registry from the device fetch.
    var layoutSource: LayoutSource?
    var keymap: [[[UInt16]]] = []
    var selectedLayer: Int = 0
    var activeLayerMask: UInt32 = 0
    var hasLiveLayerEvents: Bool = false
    var error: String?

    /// Parsed VIA `menus` (lighting / indicators / extras). Populated at
    /// bootstrap from the cached VIA JSON; empty if the board doesn't ship one.
    var menus: [VIAMenuNode] = []

    /// Direct VIA client handle for the config UI to issue customGetValue /
    /// customSetValue / customSave commands. Read-only; connection lifecycle
    /// stays in this class.
    var via: VIAClient { client }

    private let device: HIDDevice
    private let client: VIAClient
    private var notifyTask: Task<Void, Never>?

    init(keyboard: DiscoveredKeyboard, device: HIDDevice, client: VIAClient) {
        self.id = keyboard.info.registryPath
        self.keyboard = keyboard
        self.device = device
        self.client = client
    }

    /// Read protocol version, layout, keymap. The layout source order is:
    /// (1) user override (Configure → Connection → Layout source → Custom),
    /// (2) Vial firmware fetch when protocol v9 is reported, (3) bundled
    /// VIA manifest for everyone else.
    func bootstrap(
        layoutResolver: LayoutResolver,
        customLayoutOverride: URL? = nil
    ) async throws {
        let version = try await client.protocolVersion()
        protocolVersion = version
        guard version >= VIAKeycodeMap.minSupportedProtocolVersion else {
            throw BootstrapError.unsupportedProtocolVersion(version)
        }
        if version == 9 {
            Log.info("[bootstrap] \(keyboard.displayName): Vial detected (proto v9), fetching layout from device")
        }

        let definition: KeyboardDefinition
        let source: LayoutSource
        if let override = customLayoutOverride {
            definition = try LayoutResolver.loadFromFile(
                override,
                vendorID: keyboard.info.vendorID,
                productID: keyboard.info.productID
            )
            source = .userProvided
        } else {
            definition = try await layoutResolver.resolve(
                vendorID: keyboard.info.vendorID,
                productID: keyboard.info.productID,
                viaProtocolVersion: version,
                client: client
            )
            source = (version == 9) ? .vialDevice : .viaRegistry
        }
        self.definition = definition
        self.layoutSource = source

        let layers = try await client.layerCount()
        let keymap = try await client.readKeymap(
            layers: Int(layers),
            rows: definition.rows,
            cols: definition.cols
        )
        self.keymap = keymap
        self.selectedLayer = 0

        // Parse the keyboard's VIA menu definition from the same cached JSON
        // we just used for layout. Free of charge: no extra round-trip.
        self.menus = await layoutResolver.menus(
            vendorID: keyboard.info.vendorID,
            productID: keyboard.info.productID
        )
    }

    /// Start mirroring the device's active layers. The firmware module
    /// can deliver state in two ways and the keymap chooses which:
    ///
    /// - Poll: host sends `[0xF1, 0x00]`, firmware replies with the
    ///   tracked layer state. Vial / VIA-safe.
    /// - Push: firmware emits unsolicited `0xF1` reports on every layer
    ///   transition. Required for QMK Bluetooth setups where Raw HID
    ///   OUT can't reach the MCU.
    ///
    /// We listen for both at once. The push listener runs unconditionally
    /// (it's just consuming a stream that's empty unless the firmware
    /// pushes); the poll loop only starts if the initial probe answers.
    /// A single firmware can do both and the host won't double-fire,
    /// because `handleEvent` ignores no-op transitions where the layer
    /// state already matches what the overlay is showing.
    func startNotifyStream(
        onEvent: @escaping @Sendable @MainActor (LayerLensNotifyEvent) -> Void,
        onModuleDetected: (@Sendable @MainActor () -> Void)? = nil
    ) {
        notifyTask?.cancel()
        notifyTask = Task { [weak self, client, keyboard] in
            let probe: LayerLensNotifyEvent?
            do {
                probe = try await client.queryLayerState()
            } catch {
                probe = nil
            }
            if let event = probe {
                Log.info("[layerlens_notify] \(keyboard.displayName): poll mode (proto v\(event.protocolVersion))")
                await self?.handleEvent(event, sink: onEvent)
                await onModuleDetected?()
            } else {
                Log.info("[layerlens_notify] \(keyboard.displayName): no poll response. Push-only mode (or module not installed)")
            }

            await withTaskGroup(of: Void.self) { group in
                group.addTask { [weak self, client, onEvent] in
                    for await event in client.layerNotifyEvents {
                        if Task.isCancelled { return }
                        await self?.handleEvent(event, sink: onEvent)
                    }
                }
                if let event = probe {
                    group.addTask { [weak self, client, onEvent] in
                        await Self.runPollLoop(
                            client: client,
                            weakSelf: self,
                            initialState: event.layerState,
                            onEvent: onEvent
                        )
                    }
                }
                await group.waitForAll()
            }
        }
    }

    /// Static so the polling loop has no implicit `self` retention; only
    /// touches the instance through the weak reference passed in.
    private static func runPollLoop(
        client: VIAClient,
        weakSelf: ActiveConnection?,
        initialState: UInt32,
        onEvent: @escaping @Sendable @MainActor (LayerLensNotifyEvent) -> Void
    ) async {
        var lastState: UInt32 = initialState
        var pollCount: UInt64 = 0
        var skipCount: UInt64 = 0
        var errorCount: UInt64 = 0
        var heartbeatAt: ContinuousClock.Instant = .now
        while !Task.isCancelled {
            try? await Task.sleep(for: VIAClient.layerStatePollInterval)
            guard !Task.isCancelled else { return }

            // Back off while another Raw HID consumer (Vial / VIA / QMK
            // Toolbox) is actively talking to the keyboard. We can tell by
            // watching for input reports we didn't ask for; see
            // `VIAClient.timeSinceForeignTraffic`. Skipping polls during
            // those windows keeps our 0xF1 replies from corrupting the
            // other tool's request/response.
            let elapsedSinceForeign = await client.timeSinceForeignTraffic()
            if elapsedSinceForeign < VIAClient.coexistenceQuietPeriod {
                skipCount &+= 1
                continue
            }

            pollCount &+= 1
            let event: LayerLensNotifyEvent?
            do {
                event = try await client.queryLayerState(
                    timeout: .milliseconds(150)
                )
            } catch {
                errorCount &+= 1
                // Transient: likely a Vial / VIA round-trip in flight on
                // another tool stealing our reply window. Keep polling;
                // a permanently-dead transport surfaces via cancellation.
                continue
            }
            guard let e = event else { continue }
            // Emit a heartbeat every ~5 s so we can tell from the log whether
            // polling is actually running, even when nothing's changing.
            let now = ContinuousClock.now
            if now - heartbeatAt >= .seconds(5) {
                Log.debug(String(format: "[poll heartbeat] polls=%llu skipped=%llu errors=%llu lastState=0x%08X currentState=0x%08X",
                                 pollCount, skipCount, errorCount, lastState, e.layerState))
                heartbeatAt = now
            }
            if e.layerState != lastState {
                lastState = e.layerState
                await weakSelf?.handleEvent(e, sink: onEvent)
            }
        }
    }

    private func handleEvent(
        _ event: LayerLensNotifyEvent,
        sink: @escaping @Sendable @MainActor (LayerLensNotifyEvent) -> Void
    ) {
        // Dedupe: a firmware that does both push and poll will land the
        // same state via two paths in quick succession. We let the first
        // event for a given state through (so the very first observation,
        // which sets `hasLiveLayerEvents` from false → true, always
        // counts) and drop subsequent no-op repeats so the overlay
        // doesn't double-flash.
        let isFirstEvent = !hasLiveLayerEvents
        let isStateChange = event.layerState != activeLayerMask
        guard isFirstEvent || isStateChange else { return }

        Log.info(String(format: "[layer] %@: state=0x%08X highest=%d",
                        keyboard.displayName,
                        event.layerState,
                        event.highestActiveLayer))
        hasLiveLayerEvents = true
        activeLayerMask = event.layerState
        let highest = event.highestActiveLayer
        if keymap.indices.contains(highest) {
            selectedLayer = highest
        }
        announceLayerChange(event)
        sink(event)
    }

    /// Post a VoiceOver announcement when the active layer changes so users
    /// running with the screen reader on get a verbal cue alongside the
    /// visual overlay flash. No-ops when VoiceOver isn't running (the
    /// notification is silently dropped).
    private func announceLayerChange(_ event: LayerLensNotifyEvent) {
        // Skip when only the base layer is active. That's the "released
        // back to base" event and announcing it on every transition would
        // be noisy ("Base layer. Base layer. Base layer.").
        guard event.layerState != 0 else { return }
        let label = "Layer \(event.highestActiveLayer)"
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: label,
                .priority: NSAccessibilityPriorityLevel.medium.rawValue
            ]
        )
    }

    func close() {
        notifyTask?.cancel()
        notifyTask = nil
        device.close()
    }

    enum BootstrapError: Error, CustomStringConvertible {
        case unsupportedProtocolVersion(UInt16)
        var description: String {
            switch self {
            case .unsupportedProtocolVersion(let v):
                return "VIA protocol v\(v) is older than v\(VIAKeycodeMap.minSupportedProtocolVersion). Update your firmware to a recent QMK build."
            }
        }
    }
}
