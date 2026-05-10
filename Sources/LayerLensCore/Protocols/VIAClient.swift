import Foundation

/// Async VIA Raw-HID client. Wraps a `HIDTransport` and exposes the subset of
/// VIA commands LayerLens needs (protocol version, layer count, keymap buffer).
///
/// Inbound reports are drained in a background Task and routed FIFO to the
/// per-opcode waiter that's currently in flight. Outbound requests are
/// serialized via a Task chain so two concurrent callers can't issue
/// overlapping sends to a device that handles only one at a time.
public actor VIAClient {
    public static let reportLength: Int = 32
    public static let keycodeBytes: Int = 2
    /// VIA caps GET_BUFFER payload at 28 bytes (32 - 4 header bytes).
    public static let maxBufferChunk: Int = 28

    private let transport: HIDTransport
    private var waiters: [Waiter] = []
    private var nextWaiterID: UInt64 = 0
    private var sendChain: Task<Void, Never>
    private var drainTask: Task<Void, Never>?
    private let layerEventsContinuation: AsyncStream<LayerLensNotifyEvent>.Continuation

    /// Wall-clock instant of the most recent Raw HID input report that
    /// didn't match any of our waiters and wasn't a v1 layerlens_notify
    /// push. Such reports arrive when another Raw HID consumer (Vial, VIA,
    /// QMK Toolbox, etc.) has the same device open and is doing its own
    /// request/response over the shared input pipe. macOS broadcasts every
    /// input report to every registered listener, so we see their replies.
    /// LayerLens uses this to back off polling while a foreign tool is
    /// active so our 0xF1 replies don't collide with theirs.
    private var lastForeignReportAt: ContinuousClock.Instant?

    /// Stream of layerlens_notify (0xF1) events pushed unsolicited by the
    /// firmware. Empty until/unless the device runs `layerlens_notify`.
    public nonisolated let layerNotifyEvents: AsyncStream<LayerLensNotifyEvent>

    private struct Waiter: Sendable {
        let id: UInt64
        let opcode: UInt8
        let subOpcode: UInt8?
        /// When true, this waiter takes the next non-`layerlens_notify`
        /// report regardless of opcode/sub-opcode. Used for Vial sub-
        /// commands whose replies overwrite bytes 0/1 with payload data
        /// instead of echoing the opcode header back. Send-chain
        /// serialisation guarantees only one match-any waiter is live at
        /// a time, so this stays unambiguous.
        let matchAny: Bool
        let continuation: CheckedContinuation<[UInt8], Error>
    }

    public init(transport: HIDTransport) {
        self.transport = transport
        self.sendChain = Task {} // already-finished sentinel

        var c: AsyncStream<LayerLensNotifyEvent>.Continuation!
        self.layerNotifyEvents = AsyncStream<LayerLensNotifyEvent> { c = $0 }
        self.layerEventsContinuation = c

        Task { await self.startDrain() }
    }

    private func startDrain() {
        drainTask = Task { [weak self, transport] in
            for await report in transport.incomingReports {
                await self?.handleReport([UInt8](report))
            }
            await self?.terminate()
        }
    }

    private func handleReport(_ bytes: [UInt8]) {
        guard let opcode = bytes.first else { return }
        if let idx = waiters.firstIndex(where: { (w: Waiter) in
            // Match-any waiters claim the next non-notify report
            // unconditionally. Vial sub-commands replace the opcode
            // echo bytes with payload data, so we can't filter by them.
            if w.matchAny { return true }
            guard w.opcode == opcode else { return false }
            if let sub = w.subOpcode {
                return bytes.count >= 2 && bytes[1] == sub
            }
            return true
        }) {
            let waiter = waiters.remove(at: idx)
            waiter.continuation.resume(returning: bytes)
            return
        }
        // No waiter for this opcode. Route layerlens_notify pushes onto their
        // dedicated stream and treat anything else as foreign HID traffic.
        if opcode == LayerLensNotify.reportID,
           let event = LayerLensNotifyEvent(report: Data(bytes)) {
            layerEventsContinuation.yield(event)
            return
        }
        lastForeignReportAt = ContinuousClock.now
    }

    /// Time elapsed since the last foreign HID report we saw. Used by
    /// `runPollLoop` to skip polls while Vial / VIA is actively talking to
    /// the same keyboard. Returns a large sentinel when no foreign traffic
    /// has ever been observed.
    public func timeSinceForeignTraffic() -> Duration {
        guard let last = lastForeignReportAt else { return .seconds(3600) }
        return ContinuousClock.now - last
    }

    private func terminate() {
        for w in waiters {
            w.continuation.resume(throwing: VIAError.transportClosed)
        }
        waiters.removeAll()
        layerEventsContinuation.finish()
    }

    // MARK: - High-level commands

    public func protocolVersion() async throws -> UInt16 {
        let r = try await send(command: .getProtocolVersion)
        guard r.count >= 3 else { throw VIAError.shortResponse(command: 0x01, expectedAtLeast: 3, got: r.count) }
        return (UInt16(r[1]) << 8) | UInt16(r[2])
    }

    public func layerCount() async throws -> UInt8 {
        let r = try await send(command: .dynamicKeymapGetLayerCount)
        guard r.count >= 2 else { throw VIAError.shortResponse(command: 0x11, expectedAtLeast: 2, got: r.count) }
        return r[1]
    }

    // MARK: - Vial extensions
    //
    // Vial keyboards report VIA protocol v9 as a sentinel and expose their
    // own protocol over the same Raw HID channel using opcode 0xFE. The
    // critical bit for LayerLens is the embedded keyboard definition: every
    // Vial firmware ships with its layout JSON compressed (raw LZMA1) into
    // the binary, retrievable via `getSize` + chunked `getDefinition` reads.

    /// Read the size in bytes of the Vial-embedded compressed layout. The
    /// firmware writes four LE bytes at offsets 0..4 of the response,
    /// overwriting the opcode echo, so we use `matchAny` and read the
    /// size from the very first byte of the reply.
    public func vialDefinitionSize() async throws -> UInt32 {
        let r = try await send(
            command: .vial,
            payload: [VialSubCommand.getSize.rawValue],
            matchAny: true
        )
        guard r.count >= 4 else {
            throw VIAError.shortResponse(command: 0xFE, expectedAtLeast: 4, got: r.count)
        }
        return UInt32(r[0]) | (UInt32(r[1]) << 8) | (UInt32(r[2]) << 16) | (UInt32(r[3]) << 24)
    }

    /// Vial firmware uses a 32-byte chunk window for the definition fetch.
    /// Page indices count chunks, not bytes. See `vial_get_def` in
    /// vial-qmk's `quantum/vial.c`.
    public static let vialChunkSize: Int = 32

    /// Read one 32-byte page of the compressed layout. `page` is a chunk
    /// index, NOT a byte offset. Vial firmware multiplies it by 32 to get
    /// the array offset (`start = page * VIAL_RAW_EPSIZE`).
    public func vialDefinitionChunk(page: UInt16) async throws -> [UInt8] {
        let r = try await send(
            command: .vial,
            payload: [
                VialSubCommand.getDefinition.rawValue,
                UInt8(page & 0xFF),
                UInt8((page >> 8) & 0xFF)
            ],
            matchAny: true
        )
        return r
    }

    /// Convenience: read the entire Vial-embedded compressed layout. Loops
    /// `vialDefinitionChunk(page:)` calls until `vialDefinitionSize` bytes
    /// have been collected, trimming the final chunk down to the exact
    /// reported size.
    public func vialDefinitionData() async throws -> Data {
        let total = Int(try await vialDefinitionSize())
        guard total > 0 else { return Data() }
        var out = Data(capacity: total)
        var page: UInt16 = 0
        while out.count < total {
            let chunk = try await vialDefinitionChunk(page: page)
            let remaining = total - out.count
            let take = min(remaining, chunk.count)
            out.append(contentsOf: chunk.prefix(take))
            page &+= 1
        }
        return out
    }

    // MARK: - Custom values (id_custom_set_value / get_value / save)
    //
    // VIA's lighting menu (Backlight, RGBLIGHT, RGB Matrix, Indicators, ...)
    // routes every read/write through these three commands. The (channel,
    // value_id) tuple identifies which subsystem and which knob; the firmware
    // dispatches via `via_custom_value_command` and per-channel handlers.

    /// Read a value from the firmware's custom-value subsystem.
    /// `lengthHint` controls how many trailing bytes the caller wants: 1
    /// for a brightness/effect/speed scalar, 3 for HSV-style colour (h/s/v),
    /// 4 for a 32-bit value, etc.
    public func customGetValue(
        channel: UInt8,
        valueID: UInt8,
        lengthHint: Int = 4
    ) async throws -> [UInt8] {
        let r = try await send(
            command: .customGetValue,
            payload: [channel, valueID]
        )
        let preview = r.prefix(8).map { String(format: "%02X", $0) }.joined(separator: " ")
        Log.debug("[VIA get  ch=\(channel) val=\(valueID) hint=\(lengthHint)] rx \(preview)…")
        // Layout: [opcode, channel, value_id, byte0, byte1, ...]
        let prefix = 3
        guard r.count >= prefix + lengthHint else {
            throw VIAError.shortResponse(
                command: VIACommand.customGetValue.rawValue,
                expectedAtLeast: prefix + lengthHint,
                got: r.count
            )
        }
        return Array(r[prefix ..< prefix + lengthHint])
    }

    /// Write a value to the firmware's custom-value subsystem. `bytes` is
    /// whatever payload the (channel, value_id) expects (1-28 bytes typical).
    @discardableResult
    public func customSetValue(
        channel: UInt8,
        valueID: UInt8,
        bytes: [UInt8]
    ) async throws -> [UInt8] {
        var payload: [UInt8] = [channel, valueID]
        payload.append(contentsOf: bytes)
        let preview = payload.prefix(8).map { String(format: "%02X", $0) }.joined(separator: " ")
        Log.debug("[VIA set  ch=\(channel) val=\(valueID)] tx \(preview)…")
        let r = try await send(command: .customSetValue, payload: payload)
        let rxPreview = r.prefix(8).map { String(format: "%02X", $0) }.joined(separator: " ")
        Log.debug("[VIA set  ch=\(channel) val=\(valueID)] rx \(rxPreview)…")
        return r
    }

    /// Persist the channel's current values to EEPROM.
    @discardableResult
    public func customSave(channel: UInt8) async throws -> [UInt8] {
        Log.debug("[VIA save ch=\(channel)]")
        let r = try await send(command: .customSave, payload: [channel])
        let preview = r.prefix(4).map { String(format: "%02X", $0) }.joined(separator: " ")
        Log.debug("[VIA save ch=\(channel)] rx \(preview)…")
        return r
    }

    // MARK: - Legacy lighting (id_lighting_set_value, no channel byte)
    //
    // Pre-channel-routing firmware (older Keychron, etc.) uses the same 0x07
    // / 0x08 / 0x09 command bytes but expects payload `[cmd, value_id, ...]`
    // with no channel byte. VIA's app dispatches based on the keyboard JSON's
    // `lighting.extends` field; we mirror the same heuristic.

    public func legacyLightingGetValue(valueID: UInt8, lengthHint: Int) async throws -> [UInt8] {
        let r = try await send(command: .customGetValue, payload: [valueID])
        let preview = r.prefix(8).map { String(format: "%02X", $0) }.joined(separator: " ")
        Log.debug("[VIA leg-get  val=\(String(format: "%02X", valueID))] rx \(preview)…")
        // Layout: [opcode, value_id, byte0, byte1, ...]
        let prefix = 2
        guard r.count >= prefix + lengthHint else {
            throw VIAError.shortResponse(
                command: VIACommand.customGetValue.rawValue,
                expectedAtLeast: prefix + lengthHint,
                got: r.count
            )
        }
        return Array(r[prefix ..< prefix + lengthHint])
    }

    @discardableResult
    public func legacyLightingSetValue(valueID: UInt8, bytes: [UInt8]) async throws -> [UInt8] {
        var payload: [UInt8] = [valueID]
        payload.append(contentsOf: bytes)
        let preview = payload.prefix(8).map { String(format: "%02X", $0) }.joined(separator: " ")
        Log.debug("[VIA leg-set  val=\(String(format: "%02X", valueID))] tx \(preview)…")
        let r = try await send(command: .customSetValue, payload: payload)
        let rxPreview = r.prefix(8).map { String(format: "%02X", $0) }.joined(separator: " ")
        Log.debug("[VIA leg-set  val=\(String(format: "%02X", valueID))] rx \(rxPreview)…")
        return r
    }

    @discardableResult
    public func legacyLightingSave() async throws -> [UInt8] {
        Log.debug("[VIA leg-save]")
        let r = try await send(command: .customSave, payload: [])
        let preview = r.prefix(4).map { String(format: "%02X", $0) }.joined(separator: " ")
        Log.debug("[VIA leg-save] rx \(preview)…")
        return r
    }

    /// Read up to 28 bytes of keymap buffer at `offset`. Caller is responsible for
    /// chunking; see `readKeymap(layers:rows:cols:)` for the full-matrix helper.
    public func keymapBuffer(offset: UInt16, length: UInt8) async throws -> [UInt8] {
        guard length <= UInt8(Self.maxBufferChunk) else {
            throw VIAError.invalidArgument("length \(length) exceeds max chunk \(Self.maxBufferChunk)")
        }
        let payload: [UInt8] = [
            UInt8((offset >> 8) & 0xFF),
            UInt8(offset & 0xFF),
            length
        ]
        let r = try await send(command: .dynamicKeymapGetBuffer, payload: payload)
        let header = 4 // [opcode, off_hi, off_lo, length]
        guard r.count >= header + Int(length) else {
            throw VIAError.shortResponse(command: 0x12, expectedAtLeast: header + Int(length), got: r.count)
        }
        return Array(r[header ..< header + Int(length)])
    }

    /// Read every layer's keymap at once.
    /// Returns `[layer][row][col]` of raw QMK keycodes (UInt16, big-endian on the wire).
    public func readKeymap(layers: Int, rows: Int, cols: Int) async throws -> [[[UInt16]]] {
        precondition(layers > 0 && rows > 0 && cols > 0)
        let totalKeycodes = layers * rows * cols
        let totalBytes = totalKeycodes * Self.keycodeBytes
        var raw = [UInt8](); raw.reserveCapacity(totalBytes)

        var offset = 0
        while offset < totalBytes {
            let remaining = totalBytes - offset
            let chunk = min(Self.maxBufferChunk, remaining)
            let bytes = try await keymapBuffer(offset: UInt16(offset), length: UInt8(chunk))
            raw.append(contentsOf: bytes)
            offset += chunk
        }

        var result = Array(repeating: Array(repeating: Array(repeating: UInt16(0), count: cols), count: rows), count: layers)
        for layer in 0 ..< layers {
            for row in 0 ..< rows {
                for col in 0 ..< cols {
                    let i = ((layer * rows + row) * cols + col) * 2
                    result[layer][row][col] = (UInt16(raw[i]) << 8) | UInt16(raw[i + 1])
                }
            }
        }
        return result
    }

    // MARK: - Low-level send/receive

    /// Send a 32-byte report and await the next response with matching opcode.
    /// Sends are serialized via the internal Task chain.
    func send(
        command: VIACommand,
        payload: [UInt8] = [],
        subOpcode: UInt8? = nil,
        matchAny: Bool = false
    ) async throws -> [UInt8] {
        let previous = sendChain
        let work = Task<[UInt8], Error> { [weak self] in
            await previous.value
            guard let self else { throw VIAError.transportClosed }
            return try await self.performSend(
                opcode: command.rawValue,
                payload: payload,
                subOpcode: subOpcode,
                matchAny: matchAny
            )
        }
        sendChain = Task { _ = try? await work.value }
        return try await work.value
    }

    private func performSend(
        opcode: UInt8,
        payload: [UInt8],
        subOpcode: UInt8?,
        matchAny: Bool
    ) async throws -> [UInt8] {
        var request = [UInt8](repeating: 0, count: Self.reportLength)
        request[0] = opcode
        for (i, b) in payload.enumerated() {
            guard i + 1 < Self.reportLength else { break }
            request[i + 1] = b
        }

        let id = nextWaiterID
        nextWaiterID &+= 1

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<[UInt8], Error>) in
                waiters.append(Waiter(
                    id: id, opcode: opcode, subOpcode: subOpcode,
                    matchAny: matchAny, continuation: c
                ))
                do {
                    try transport.send(Data(request))
                } catch {
                    waiters.removeAll { $0.id == id }
                    c.resume(throwing: error)
                }
            }
        } onCancel: { [weak self] in
            // Drop the waiter so the continuation isn't leaked when the
            // caller times out / cancels (e.g. layer-state polling probe
            // against a keyboard without the layerlens_notify module).
            Task { await self?.cancelWaiter(id: id) }
        }
    }

    private func cancelWaiter(id: UInt64) {
        if let idx = waiters.firstIndex(where: { $0.id == id }) {
            let w = waiters.remove(at: idx)
            w.continuation.resume(throwing: VIAError.cancelled)
        }
    }

    // MARK: - LayerLens Notify (poll-mode layer state)
    //
    // Protocol v2 of the layerlens_notify firmware module (see
    // `firmware/layerlens_notify/PROTOCOL.md`). The host sends `[0xF1, 0x00]`,
    // the firmware replies with the current layer_state bitmask. There are
    // no unsolicited frames; the v1 push model collided with VIA/Vial's
    // single-consumer Raw HID assumption.

    /// Default poll cadence for `LayerStatePoller` and friends. 50 ms /
    /// 20 Hz is fast enough that a tap-and-hold on a layer key feels live in
    /// the overlay, and slow enough to barely register on USB bandwidth.
    public static let layerStatePollInterval: Duration = .milliseconds(50)

    /// Default first-poll timeout. If the keyboard doesn't respond within
    /// this window we conclude the module isn't installed and stop polling.
    public static let layerStateProbeTimeout: Duration = .milliseconds(250)

    /// How long to stay silent after observing foreign Raw HID traffic
    /// (Vial / VIA / QMK Toolbox replies on the shared input pipe). Our
    /// 0xF1 replies broadcast to every consumer, so the other tool sees
    /// them as garbage and can drop its connection or, in Vial's case,
    /// throw a JS error. Pausing for 1.5 s after each foreign report we
    /// observe gives them room to complete their own request/response
    /// transactions cleanly.
    public static let coexistenceQuietPeriod: Duration = .milliseconds(1500)

    /// Send a `GET_LAYER_STATE` request and parse the reply. Returns nil if
    /// the keyboard responded but the payload was malformed (different
    /// firmware reusing 0xF1, or a future incompatible version). Throws
    /// `VIAError.timeout` if the keyboard didn't reply at all within
    /// `timeout`. That's the signal "no module installed".
    public func queryLayerState(
        timeout: Duration = layerStateProbeTimeout
    ) async throws -> LayerLensNotifyEvent? {
        let bytes = try await sendWithTimeout(
            command: .layerLens,
            payload: [LayerLensSubCommand.getLayerState.rawValue],
            subOpcode: LayerLensSubCommand.getLayerState.rawValue,
            timeout: timeout
        )
        return LayerLensNotifyEvent(pollResponse: Data(bytes))
    }

    /// Race a `send()` against a sleep. If the timer fires first, we cancel
    /// the send task. Its `withTaskCancellationHandler` then drops the
    /// waiter so it can't leak.
    private func sendWithTimeout(
        command: VIACommand,
        payload: [UInt8],
        subOpcode: UInt8?,
        timeout: Duration
    ) async throws -> [UInt8] {
        try await withThrowingTaskGroup(of: [UInt8]?.self) { group in
            group.addTask {
                try await self.send(
                    command: command,
                    payload: payload,
                    subOpcode: subOpcode
                )
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                return nil
            }
            defer { group.cancelAll() }
            let first = try await group.next() ?? nil
            if let bytes = first {
                return bytes
            }
            throw VIAError.timeout(command: command.rawValue)
        }
    }
}
