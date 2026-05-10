import Foundation
@testable import LayerLensCore

/// In-memory `HIDTransport` for protocol-layer tests.
///
/// Tests pre-stage responses (or a response builder) keyed by the first byte
/// of the outbound report. When `send(_:)` is called, the matching response is
/// yielded onto the inbound stream after a configurable delay (defaults to "next runloop tick").
final class MockHIDTransport: HIDTransport, @unchecked Sendable {
    typealias ResponseFactory = @Sendable (_ request: Data) -> Data?

    private let lock = NSLock()
    private var continuation: AsyncStream<Data>.Continuation
    let incomingReports: AsyncStream<Data>

    /// Outbound reports captured in order, one per `send` call.
    private(set) var sent: [Data] = []

    /// If set, called for every send to produce a response (or nil to ignore).
    var responder: ResponseFactory?

    init() {
        var c: AsyncStream<Data>.Continuation!
        self.incomingReports = AsyncStream<Data> { c = $0 }
        self.continuation = c
    }

    func send(_ payload: Data) throws {
        lock.lock()
        sent.append(payload)
        let r = responder
        lock.unlock()

        guard let response = r?(payload) else { return }
        Task {
            // Yield on a later tick so the caller has time to enqueue its waiter.
            await Task.yield()
            self.continuation.yield(response)
        }
    }

    /// Manually push an inbound report (e.g. to simulate an async event with no
    /// preceding request, like a layerlens_notify push).
    func injectReport(_ report: Data) {
        continuation.yield(report)
    }

    func finish() {
        continuation.finish()
    }
}
