import Foundation
import SWCompression

/// Fetches a Vial keyboard's embedded compressed layout JSON over Raw HID,
/// decompresses the XZ archive, and parses the result via the existing
/// KLEParser.
///
/// Vial firmware embeds the layout JSON at build time using a full XZ
/// container (LZMA2 streamed inside the standard `FD 37 7A 58 5A 00`
/// magic). The whole archive comes back over the wire verbatim, so we
/// just hand it to SWCompression's `XZArchive.unarchive` and take the
/// first member.
public enum VialDefinitionLoader {
    public enum LoadError: Error, CustomStringConvertible {
        case emptyDefinition
        case decompressionFailed(String)
        case malformedJSON(String)

        public var description: String {
            switch self {
            case .emptyDefinition:
                return "Vial keyboard returned an empty layout definition."
            case .decompressionFailed(let why):
                return "Vial layout decompression failed: \(why)"
            case .malformedJSON(let why):
                return "Decompressed Vial layout was not valid JSON: \(why)"
            }
        }
    }

    /// Pull the compressed payload from the device, decompress, parse.
    /// `vendorIDOverride` / `productIDOverride` are forwarded so the
    /// resulting `KeyboardDefinition` carries the right USB IDs even when
    /// the Vial JSON omits them (most Vial definitions do).
    /// Returns both the parsed `KeyboardDefinition` and the raw
    /// decompressed JSON. Callers should cache the raw bytes (not the
    /// re-encoded definition) so downstream code that walks fields
    /// outside `KeyboardDefinition`'s schema (`menus`, `lighting`,
    /// VialRGB hints) still has access to them.
    public struct LoadedDefinition: Sendable {
        public let definition: KeyboardDefinition
        public let rawJSON: Data
    }

    public static func load(
        from client: VIAClient,
        vendorID: UInt16,
        productID: UInt16
    ) async throws -> LoadedDefinition {
        let compressed = try await client.vialDefinitionData()
        guard !compressed.isEmpty else { throw LoadError.emptyDefinition }
        let decompressed = try decompressVialPayload(compressed)
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: decompressed)
        } catch {
            throw LoadError.malformedJSON(String(describing: error))
        }
        let definition = try KLEParser.parseDefinition(
            json,
            vendorIDOverride: vendorID,
            productIDOverride: productID
        )
        return LoadedDefinition(definition: definition, rawJSON: decompressed)
    }

    /// Decompress Vial's XZ-archived payload. The wire format is a full
    /// XZ stream (`FD 37 7A 58 5A 00` magic, LZMA2 inside), so we just
    /// hand it to SWCompression's archive unarchiver and pull out the
    /// single member's content.
    static func decompressVialPayload(_ payload: Data) throws -> Data {
        // Vial's reported `vial_get_size` is the size of the embedded array
        // in firmware, which is rounded up / padded with zeros past the
        // actual XZ stream. Trim back to the stream's `0x59 0x5A` ("YZ")
        // footer magic so the decoder doesn't run off the end into padding.
        let trimmed = trimToXZStreamEnd(payload)
        do {
            return try XZArchive.unarchive(archive: trimmed)
        } catch {
            throw LoadError.decompressionFailed(String(describing: error))
        }
    }

    /// Find the end of the (last) XZ stream in `data` by scanning backward
    /// for the stream-footer magic `59 5A`. XZ streams end with
    /// `<backward_size 4> <stream_flags 2> 'Y' 'Z'`. Returns the data up to
    /// and including that footer.
    private static func trimToXZStreamEnd(_ data: Data) -> Data {
        guard data.count >= 2 else { return data }
        for i in stride(from: data.count - 2, through: 0, by: -1) {
            if data[i] == 0x59 && data[i + 1] == 0x5A {
                return data.prefix(i + 2)
            }
        }
        return data
    }
}
