import Foundation

/// Abstract Raw HID transport. Lets the protocol layer be tested
/// against a fake transport without opening real hardware.
public protocol HIDTransport: Sendable {
    /// 32-byte inbound reports as they arrive from the device.
    var incomingReports: AsyncStream<Data> { get }

    /// Send a 32-byte output report. Implementations pad/truncate.
    func send(_ payload: Data) throws
}

extension HIDDevice: HIDTransport {}
