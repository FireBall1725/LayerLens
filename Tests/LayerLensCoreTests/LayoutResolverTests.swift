import Testing
import Foundation
@testable import LayerLensCore

@Suite("LayoutResolver", .serialized)
struct LayoutResolverTests {

    /// URLProtocol that lets each test inject a (request) -> (response, data) handler.
    final class MockURLProtocol: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (HTTPURLResponse, Data))?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let h = MockURLProtocol.handler else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            let (resp, data) = h(request)
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    private static func mockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private static func tempDir() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "LayerLensTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Manifest lookup -> network fetch -> parse for Micro Pad")
    func resolveMicroPad() async throws {
        // Use the real fixture as the "remote" payload.
        let fixtureURL = try #require(Bundle.module.url(forResource: "work_louder_micro_via", withExtension: "json"))
        let payload = try Data(contentsOf: fixtureURL)

        MockURLProtocol.handler = { request in
            #expect(request.url?.absoluteString.hasSuffix("v3/work_louder/micro.json") == true)
            let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, payload)
        }

        let manifest: [String: [LayoutResolver.ManifestEntry]] = [
            "574C:E6E3": [.init(name: "Creator Micro", path: "v3/work_louder/micro.json")]
        ]
        let cache = Self.tempDir()
        defer { try? FileManager.default.removeItem(at: cache) }

        let resolver = LayoutResolver(
            manifest: manifest,
            cacheDirectory: cache,
            urlSession: Self.mockSession(),
            rawBaseURL: URL(string: "https://example.test/")!
        )

        let def = try await resolver.resolve(vendorID: 0x574C, productID: 0xE6E3)
        #expect(def.vendorID == 0x574C)
        #expect(def.productID == 0xE6E3)
        #expect(def.rows == 4 && def.cols == 4)
        #expect(def.layouts.first?.keys.count == 16)

        // Cache file written.
        let cached = try #require(await resolver.cachedJSON(vendorID: 0x574C, productID: 0xE6E3))
        #expect(cached == payload)
    }

    @Test("Cached payload skips network on second call")
    func cacheHit() async throws {
        let fixtureURL = try #require(Bundle.module.url(forResource: "work_louder_micro_via", withExtension: "json"))
        let payload = try Data(contentsOf: fixtureURL)

        final class Counter: @unchecked Sendable {
            private let lock = NSLock()
            private var n = 0
            func bump() { lock.lock(); n += 1; lock.unlock() }
            func value() -> Int { lock.lock(); defer { lock.unlock() }; return n }
        }
        let calls = Counter()

        MockURLProtocol.handler = { request in
            calls.bump()
            let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, payload)
        }

        let manifest: [String: [LayoutResolver.ManifestEntry]] = [
            "574C:E6E3": [.init(name: "Creator Micro", path: "v3/work_louder/micro.json")]
        ]
        let cache = Self.tempDir()
        defer { try? FileManager.default.removeItem(at: cache) }

        let resolver = LayoutResolver(
            manifest: manifest,
            cacheDirectory: cache,
            urlSession: Self.mockSession(),
            rawBaseURL: URL(string: "https://example.test/")!
        )

        _ = try await resolver.resolve(vendorID: 0x574C, productID: 0xE6E3)
        _ = try await resolver.resolve(vendorID: 0x574C, productID: 0xE6E3)
        #expect(calls.value() == 1)
    }

    @Test("notInManifest when VID:PID is unknown")
    func notInManifest() async throws {
        let cache = Self.tempDir()
        defer { try? FileManager.default.removeItem(at: cache) }
        let resolver = LayoutResolver(
            manifest: [:],
            cacheDirectory: cache,
            urlSession: Self.mockSession(),
            rawBaseURL: URL(string: "https://example.test/")!
        )
        await #expect(throws: LayoutResolver.ResolveError.self) {
            _ = try await resolver.resolve(vendorID: 0xDEAD, productID: 0xBEEF)
        }
    }

    @Test("HTTP error from upstream propagates as httpError")
    func httpError() async throws {
        MockURLProtocol.handler = { request in
            let resp = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data())
        }
        let manifest: [String: [LayoutResolver.ManifestEntry]] = [
            "1111:2222": [.init(name: nil, path: "v3/missing.json")]
        ]
        let cache = Self.tempDir()
        defer { try? FileManager.default.removeItem(at: cache) }
        let resolver = LayoutResolver(
            manifest: manifest,
            cacheDirectory: cache,
            urlSession: Self.mockSession(),
            rawBaseURL: URL(string: "https://example.test/")!
        )
        await #expect(throws: LayoutResolver.ResolveError.self) {
            _ = try await resolver.resolve(vendorID: 0x1111, productID: 0x2222)
        }
    }

    @Test("Bundled manifest contains the user's Micro Pad")
    func bundledManifestContainsMicroPad() throws {
        let manifest = try LayoutResolver.loadBundledManifest()
        let entries = try #require(manifest["574C:E6E3"])
        #expect(entries.contains(where: { $0.path == "v3/work_louder/micro.json" }))
        #expect(manifest.count > 1900) // sanity: full snapshot, not a truncated stub
    }
}
