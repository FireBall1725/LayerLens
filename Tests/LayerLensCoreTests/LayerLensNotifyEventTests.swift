import Testing
import Foundation
@testable import LayerLensCore

@Suite("LayerLensNotifyEvent")
struct LayerLensNotifyEventTests {

    @Test("Decodes a well-formed report")
    func decodeWellFormed() throws {
        var report = Data(count: 32)
        report[0] = 0xF1
        report[1] = 0x01
        // layerState = 0x12345678
        report[2] = 0x12
        report[3] = 0x34
        report[4] = 0x56
        report[5] = 0x78

        let event = try #require(LayerLensNotifyEvent(report: report))
        #expect(event.protocolVersion == 0x01)
        #expect(event.layerState == 0x12345678)
    }

    @Test("Returns nil for non-0xF1 reports")
    func wrongOpcode() {
        var report = Data(count: 32)
        report[0] = 0x12 // VIA dynamic_keymap_get_buffer
        #expect(LayerLensNotifyEvent(report: report) == nil)
    }

    @Test("Returns nil for short reports")
    func shortReport() {
        let report = Data([0xF1, 0x01, 0x00, 0x00]) // only 4 bytes
        #expect(LayerLensNotifyEvent(report: report) == nil)
    }

    @Test("Decodes a well-formed v2 poll response")
    func decodePollResponse() throws {
        var report = Data(count: 32)
        report[0] = 0xF1
        report[1] = 0x00 // GET_LAYER_STATE sub-command echo
        report[2] = 0x02 // protocol version
        // layerState = 0x12345678
        report[3] = 0x12
        report[4] = 0x34
        report[5] = 0x56
        report[6] = 0x78

        let event = try #require(LayerLensNotifyEvent(pollResponse: report))
        #expect(event.protocolVersion == 0x02)
        #expect(event.layerState == 0x12345678)
    }

    @Test("Poll-response decoder rejects wrong opcode")
    func pollResponseWrongOpcode() {
        var report = Data(count: 32)
        report[0] = 0xFF // id_unhandled, e.g. firmware without the module
        report[1] = 0x00
        #expect(LayerLensNotifyEvent(pollResponse: report) == nil)
    }

    @Test("Poll-response decoder rejects wrong sub-opcode")
    func pollResponseWrongSubOpcode() {
        var report = Data(count: 32)
        report[0] = 0xF1
        report[1] = 0x99 // unknown sub-command
        #expect(LayerLensNotifyEvent(pollResponse: report) == nil)
    }

    @Test("Poll-response decoder needs at least 7 bytes")
    func pollResponseShort() {
        let report = Data([0xF1, 0x00, 0x02, 0x00, 0x00, 0x00]) // missing b0
        #expect(LayerLensNotifyEvent(pollResponse: report) == nil)
    }

    @Test("v1 push decoder rejects v2-shaped poll responses")
    func v1PushDecoderRejectsPollResponse() {
        // A v2 poll response has byte 1 == 0x00, which would be a nonsense
        // protocol version under the v1 push encoding. The v1 init? rejects
        // it so a poll reply can't accidentally fire a duplicate event when
        // both code paths run against the same report buffer.
        var report = Data(count: 32)
        report[0] = 0xF1
        report[1] = 0x00
        report[2] = 0x02
        report[3] = 0x00
        report[4] = 0x00
        report[5] = 0x00
        report[6] = 0x04
        #expect(LayerLensNotifyEvent(report: report) == nil)
    }

    @Test("highestActiveLayer reports the most-significant set bit")
    func highestActiveLayer() {
        let cases: [(UInt32, Int)] = [
            (0x00000000, 0),
            (0x00000001, 0),
            (0x00000002, 1),
            (0x00000005, 2), // bits 0 and 2 set -> 2
            (0x80000000, 31),
        ]
        for (mask, expected) in cases {
            let e = LayerLensNotifyEvent(protocolVersion: 1, layerState: mask)
            #expect(e.highestActiveLayer == expected)
        }
    }

    @Test("activeLayers enumerates set bits")
    func activeLayers() {
        let e = LayerLensNotifyEvent(protocolVersion: 1, layerState: 0b1011)
        #expect(e.activeLayers == [0, 1, 3])
    }

    @Test("VIAClient routes 0xF1 reports onto layerNotifyEvents")
    func clientRoutesEvents() async throws {
        let mock = MockHIDTransport()
        let client = VIAClient(transport: mock)

        var report = Data(count: 32)
        report[0] = 0xF1
        report[1] = 0x01
        report[2] = 0x00
        report[3] = 0x00
        report[4] = 0x00
        report[5] = 0x04 // bit 2 = layer 2 active

        // Give the drain loop a tick to subscribe before we inject.
        await Task.yield()
        mock.injectReport(report)

        let event: LayerLensNotifyEvent? = await firstEvent(
            from: client.layerNotifyEvents,
            timeout: .seconds(1)
        )
        let unwrapped = try #require(event)
        #expect(unwrapped.layerState == 0x04)
        #expect(unwrapped.highestActiveLayer == 2)
    }

    @Test("VIAClient does not route VIA replies onto layerNotifyEvents")
    func viaReplyDoesNotLeakToEvents() async throws {
        let mock = MockHIDTransport()
        mock.responder = { req in
            #expect(req[0] == 0x01)
            var r = Data(count: 32)
            r[0] = 0x01
            r[1] = 0x00
            r[2] = 0x0A
            return r
        }
        let client = VIAClient(transport: mock)
        let v = try await client.protocolVersion()
        #expect(v == 10)

        // Should not see a notify event from a non-0xF1 reply.
        let event = await firstEvent(
            from: client.layerNotifyEvents,
            timeout: .milliseconds(100)
        )
        #expect(event == nil)
    }

    // MARK: - Test helpers

    private func firstEvent(
        from stream: AsyncStream<LayerLensNotifyEvent>,
        timeout: Duration
    ) async -> LayerLensNotifyEvent? {
        await withTaskGroup(of: LayerLensNotifyEvent?.self) { group in
            group.addTask {
                for await e in stream { return e }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let r = await group.next() ?? nil
            group.cancelAll()
            return r
        }
    }
}
