import Foundation

/// Resolves a connected keyboard's physical layout from its VID:PID.
///
/// Strategy:
/// 1. Disk cache hit?  Parse and return.
/// 2. Manifest hit?    Fetch the curated KLE definition from the-via/keyboards
///                     over HTTPS, cache the raw bytes, parse, return.
/// 3. Otherwise        Throw `notInManifest` so the caller can fall back to a
///                     user-supplied `qmk info` JSON.
///
/// The bundled manifest is built from a snapshot of the-via/keyboards (1998
/// boards at time of writing). To refresh: re-clone the repo into reference/
/// and re-run `Tools/build_via_manifest.py`.
public actor LayoutResolver {
    public static let defaultRawBaseURL = URL(string: "https://raw.githubusercontent.com/the-via/keyboards/master/")!

    public struct ManifestEntry: Sendable, Hashable, Codable {
        public let name: String?
        public let path: String
    }

    public enum ResolveError: Error, CustomStringConvertible, Sendable {
        case manifestMissing(String)
        case manifestMalformed(String)
        case notInManifest(vendorID: UInt16, productID: UInt16)
        case networkFailure(String)
        case httpError(statusCode: Int)
        case parseFailure(String)

        public var description: String {
            switch self {
            case .manifestMissing(let m): return "Bundled VIA manifest not loadable: \(m)"
            case .manifestMalformed(let m): return "Manifest malformed: \(m)"
            case .notInManifest(let v, let p):
                return String(format: "No layout in VIA repo for %04X:%04X", v, p)
            case .networkFailure(let m): return "Network failure: \(m)"
            case .httpError(let code): return "HTTP \(code) fetching layout"
            case .parseFailure(let m): return "Parse failure: \(m)"
            }
        }
    }

    private let manifest: [String: [ManifestEntry]]
    private let cacheDirectory: URL
    private let urlSession: URLSession
    private let rawBaseURL: URL

    public init(
        manifest: [String: [ManifestEntry]],
        cacheDirectory: URL,
        urlSession: URLSession = .shared,
        rawBaseURL: URL = LayoutResolver.defaultRawBaseURL
    ) {
        self.manifest = manifest
        self.cacheDirectory = cacheDirectory
        self.urlSession = urlSession
        self.rawBaseURL = rawBaseURL
    }

    /// Loads the bundled VIA manifest and uses ~/Library/Application Support/LayerLens/keyboards/ for the cache.
    public static func builtIn(
        urlSession: URLSession = .shared,
        rawBaseURL: URL = LayoutResolver.defaultRawBaseURL
    ) throws -> LayoutResolver {
        let manifest = try loadBundledManifest()
        let cache = defaultCacheDirectory()
        return LayoutResolver(
            manifest: manifest,
            cacheDirectory: cache,
            urlSession: urlSession,
            rawBaseURL: rawBaseURL
        )
    }

    public static func defaultCacheDirectory() -> URL {
        let appSupport = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return appSupport.appending(path: "LayerLens/keyboards", directoryHint: .isDirectory)
    }

    public static func loadBundledManifest() throws -> [String: [ManifestEntry]] {
        // Production .app builds place the manifest in standard
        // Contents/Resources/ (so code-signing seals it correctly), which is
        // exposed via Bundle.main. Fall back to Bundle.module for the dev
        // path where SPM-generated bundles are how resources flow. We *only*
        // touch Bundle.module if Bundle.main came up empty. Accessing it
        // when the SPM bundle is missing fatalErrors the app on launch.
        let url: URL
        if let main = Bundle.main.url(forResource: "via_keyboards_manifest", withExtension: "json") {
            url = main
        } else if let module = Bundle.module.url(forResource: "via_keyboards_manifest", withExtension: "json") {
            url = module
        } else {
            throw ResolveError.manifestMissing("via_keyboards_manifest.json not in bundle")
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([String: [ManifestEntry]].self, from: data)
        } catch {
            throw ResolveError.manifestMalformed("\(error)")
        }
    }

    // MARK: - Public API

    public func resolve(vendorID: UInt16, productID: UInt16) async throws -> KeyboardDefinition {
        let key = Self.manifestKey(vid: vendorID, pid: productID)

        if let cached = readCache(key: key) {
            return try parse(data: cached)
        }

        guard let entry = manifest[key]?.first else {
            throw ResolveError.notInManifest(vendorID: vendorID, productID: productID)
        }

        let raw = try await fetch(path: entry.path)
        let definition = try parse(data: raw)
        try writeCache(key: key, data: raw)
        return definition
    }

    /// Load a layout JSON from a file the user picked. The file may be
    /// a VIA keyboard definition, a Vial decompressed `.vil`, or any KLE-
    /// based JSON that conforms to the parsing surface. VID:PID overrides
    /// stomp whatever's in the file's `vendorId`/`productId` fields so
    /// the override stays bound to the connected hardware.
    public static func loadFromFile(
        _ url: URL,
        vendorID: UInt16,
        productID: UInt16
    ) throws -> KeyboardDefinition {
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data)
        return try KLEParser.parseDefinition(
            json,
            vendorIDOverride: vendorID,
            productIDOverride: productID
        )
    }

    /// Vial-aware resolution. When `client` reports protocol v9 (Vial
    /// sentinel), fetch the layout from the device itself. Vial firmware
    /// embeds its compressed JSON in the binary, and the embedded version
    /// is authoritative even when a VIA registry definition exists for the
    /// same VID:PID. Falls back to the standard VIA-manifest path for
    /// non-Vial keyboards.
    public func resolve(
        vendorID: UInt16,
        productID: UInt16,
        viaProtocolVersion: UInt16,
        client: VIAClient
    ) async throws -> KeyboardDefinition {
        if viaProtocolVersion == 9 {
            // Vial: pull definition straight off the device, cache the raw
            // decompressed JSON (not the re-encoded `KeyboardDefinition`)
            // so that `cachedJSON` returns a payload still containing
            // `menus` / `lighting` / VialRGB hints, fields that
            // `KeyboardDefinition` doesn't model but `VIAMenuParser` does.
            let loaded = try await VialDefinitionLoader.load(
                from: client,
                vendorID: vendorID,
                productID: productID
            )
            try? writeCache(
                key: Self.manifestKey(vid: vendorID, pid: productID),
                data: loaded.rawJSON
            )
            return loaded.definition
        }
        return try await resolve(vendorID: vendorID, productID: productID)
    }

    public func cachedJSON(vendorID: UInt16, productID: UInt16) -> Data? {
        readCache(key: Self.manifestKey(vid: vendorID, pid: productID))
    }

    /// Convenience: parse the cached VIA JSON's `menus` array (lighting,
    /// indicators, board-specific extras). Empty array if there's no cache
    /// or the keyboard doesn't ship a menu.
    public func menus(vendorID: UInt16, productID: UInt16) -> [VIAMenuNode] {
        guard let data = cachedJSON(vendorID: vendorID, productID: productID),
              let json = try? JSONSerialization.jsonObject(with: data, options: []) else {
            return []
        }
        return VIAMenuParser.parse(viaDefinition: json)
    }

    public func clearCache() throws {
        if FileManager.default.fileExists(atPath: cacheDirectory.path) {
            try FileManager.default.removeItem(at: cacheDirectory)
        }
    }

    // MARK: - Internals

    static func manifestKey(vid: UInt16, pid: UInt16) -> String {
        String(format: "%04X:%04X", vid, pid)
    }

    private func parse(data: Data) throws -> KeyboardDefinition {
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw ResolveError.parseFailure("\(error)")
        }
        do {
            return try KLEParser.parseDefinition(json)
        } catch {
            throw ResolveError.parseFailure("\(error)")
        }
    }

    private func fetch(path: String) async throws -> Data {
        guard let url = URL(string: path, relativeTo: rawBaseURL) else {
            throw ResolveError.networkFailure("invalid URL for path \(path)")
        }
        do {
            let (data, response) = try await urlSession.data(from: url)
            guard let http = response as? HTTPURLResponse else {
                throw ResolveError.networkFailure("non-HTTP response")
            }
            guard 200..<300 ~= http.statusCode else {
                throw ResolveError.httpError(statusCode: http.statusCode)
            }
            return data
        } catch let e as ResolveError {
            throw e
        } catch {
            throw ResolveError.networkFailure("\(error)")
        }
    }

    private func cacheURL(for key: String) -> URL {
        let safeName = key.replacingOccurrences(of: ":", with: "_") + ".json"
        return cacheDirectory.appending(path: safeName)
    }

    private func readCache(key: String) -> Data? {
        try? Data(contentsOf: cacheURL(for: key))
    }

    private func writeCache(key: String, data: Data) throws {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try data.write(to: cacheURL(for: key), options: [.atomic])
    }
}
