import Testing
import Foundation
@testable import LayerLensCore

@Suite("VIAClient")
struct VIAClientTests {

    @Test("protocolVersion encodes get_protocol_version and decodes response")
    func protocolVersion() async throws {
        let mock = MockHIDTransport()
        mock.responder = { req in
            #expect(req[0] == 0x01)
            var r = Data(count: 32)
            r[0] = 0x01
            r[1] = 0x00
            r[2] = 0x0C  // version 12
            return r
        }
        let client = VIAClient(transport: mock)
        let v = try await client.protocolVersion()
        #expect(v == 12)
        #expect(mock.sent.count == 1)
        #expect(mock.sent[0].count == 32)
    }

    @Test("layerCount decodes single-byte response")
    func layerCount() async throws {
        let mock = MockHIDTransport()
        mock.responder = { req in
            #expect(req[0] == 0x11)
            var r = Data(count: 32)
            r[0] = 0x11
            r[1] = 0x04
            return r
        }
        let client = VIAClient(transport: mock)
        let count = try await client.layerCount()
        #expect(count == 4)
    }

    @Test("keymapBuffer encodes offset/length and decodes payload")
    func keymapBuffer() async throws {
        let mock = MockHIDTransport()
        mock.responder = { req in
            #expect(req[0] == 0x12)
            #expect(req[1] == 0x01) // offset_hi
            #expect(req[2] == 0x02) // offset_lo  -> offset 0x0102 = 258
            #expect(req[3] == 0x04) // length

            var r = Data(count: 32)
            r[0] = 0x12
            r[1] = 0x01
            r[2] = 0x02
            r[3] = 0x04
            r[4] = 0xDE; r[5] = 0xAD; r[6] = 0xBE; r[7] = 0xEF
            return r
        }
        let client = VIAClient(transport: mock)
        let bytes = try await client.keymapBuffer(offset: 0x0102, length: 4)
        #expect(bytes == [0xDE, 0xAD, 0xBE, 0xEF])
    }

    @Test("keymapBuffer rejects oversized chunk request")
    func keymapBufferTooLarge() async throws {
        let mock = MockHIDTransport()
        let client = VIAClient(transport: mock)
        await #expect(throws: VIAError.self) {
            try await client.keymapBuffer(offset: 0, length: 29)
        }
    }

    @Test("readKeymap chunks across multiple GET_BUFFER requests")
    func readKeymapChunking() async throws {
        let layers = 2
        let rows = 4
        let cols = 4
        let totalBytes = layers * rows * cols * 2  // 64 bytes -> needs ceil(64/28) = 3 chunks

        // Pre-compute the keycodes we'll return: kc[layer][row][col] = layer*100 + row*10 + col
        var raw = [UInt8](); raw.reserveCapacity(totalBytes)
        for l in 0..<layers {
            for r in 0..<rows {
                for c in 0..<cols {
                    let kc = UInt16(l * 100 + r * 10 + c)
                    raw.append(UInt8(kc >> 8))
                    raw.append(UInt8(kc & 0xFF))
                }
            }
        }

        let mock = MockHIDTransport()
        let frozenRaw = raw
        mock.responder = { req in
            #expect(req[0] == 0x12)
            let offset = (Int(req[1]) << 8) | Int(req[2])
            let length = Int(req[3])
            var r = Data(count: 32)
            r[0] = 0x12; r[1] = req[1]; r[2] = req[2]; r[3] = req[3]
            for i in 0..<length {
                r[4 + i] = frozenRaw[offset + i]
            }
            return r
        }

        let client = VIAClient(transport: mock)
        let keymap = try await client.readKeymap(layers: layers, rows: rows, cols: cols)

        for l in 0..<layers {
            for r in 0..<rows {
                for c in 0..<cols {
                    #expect(keymap[l][r][c] == UInt16(l * 100 + r * 10 + c))
                }
            }
        }

        // Verify we issued enough chunked requests.
        let bufferRequests = mock.sent.filter { $0[0] == 0x12 }
        #expect(bufferRequests.count == 3)
    }

    @Test("stray non-matching reports are skipped")
    func straysIgnored() async throws {
        let mock = MockHIDTransport()
        mock.responder = { req in
            // Inject one stray report with a different opcode before the real reply.
            var stray = Data(count: 32)
            stray[0] = 0xAA
            stray[1] = 0xBB
            let strayCopy = stray
            Task { @Sendable [weak mock] in
                await Task.yield()
                mock?.injectReport(strayCopy)
            }
            // Real reply
            var r = Data(count: 32)
            r[0] = req[0]
            r[1] = 0x00
            r[2] = 0x0A  // version 10
            return r
        }
        let client = VIAClient(transport: mock)
        let v = try await client.protocolVersion()
        #expect(v == 10)
    }
}
