import Foundation
import IOKit
import IOKit.hid

/// A single open Raw-HID interface. Sends/receives 32-byte reports.
///
/// VIA uses unnumbered reports (no Report ID byte on the wire). We pass reportID=0
/// to IOHIDDeviceSetReport and our 32-byte buffer carries the command byte at index 0.
public final class HIDDevice: @unchecked Sendable {

    public static let reportLength: Int = 32

    private let device: IOHIDDevice
    private let queue: DispatchQueue
    private var inputBuffer: UnsafeMutablePointer<UInt8>
    private var continuation: AsyncStream<Data>.Continuation?
    private var isOpen: Bool = false

    public let incomingReports: AsyncStream<Data>

    public init(device: IOHIDDevice) {
        self.device = device
        self.queue = DispatchQueue(label: "dev.layerlens.hid", qos: .userInitiated)
        self.inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Self.reportLength)
        self.inputBuffer.initialize(repeating: 0, count: Self.reportLength)

        var continuationRef: AsyncStream<Data>.Continuation!
        self.incomingReports = AsyncStream<Data> { c in
            continuationRef = c
        }
        self.continuation = continuationRef
    }

    deinit {
        if isOpen {
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        inputBuffer.deinitialize(count: Self.reportLength)
        inputBuffer.deallocate()
    }

    public func open() throws {
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            throw HIDError.openFailed(result)
        }

        IOHIDDeviceSetDispatchQueue(device, queue)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(
            device,
            inputBuffer,
            Self.reportLength,
            Self.inputCallback,
            context
        )

        IOHIDDeviceActivate(device)
        isOpen = true
    }

    public func close() {
        guard isOpen else { return }
        isOpen = false
        IOHIDDeviceCancel(device)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        continuation?.finish()
    }

    /// Send a 32-byte output report. Pads or truncates to `reportLength`.
    public func send(_ payload: Data) throws {
        guard isOpen else { throw HIDError.closed }

        var bytes = [UInt8](payload.prefix(Self.reportLength))
        if bytes.count < Self.reportLength {
            bytes.append(contentsOf: [UInt8](repeating: 0, count: Self.reportLength - bytes.count))
        }

        let result = bytes.withUnsafeBufferPointer { buffer -> IOReturn in
            IOHIDDeviceSetReport(
                device,
                kIOHIDReportTypeOutput,
                CFIndex(0),
                buffer.baseAddress!,
                CFIndex(Self.reportLength)
            )
        }

        guard result == kIOReturnSuccess else {
            throw HIDError.sendFailed(result)
        }
    }

    /// Send a request and await the next inbound report (with a timeout).
    /// Note: VIA replies always echo the command byte at index 0, but this minimal
    /// helper just returns the very next inbound report. Sufficient for serialized
    /// request/response flow on a quiet device. The protocol layer can add command-id
    /// matching once we move past the smoke test.
    public func request(_ payload: Data, timeout: Duration = .seconds(1)) async throws -> Data {
        try send(payload)

        return try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask { [self] in
                for await report in incomingReports {
                    return report
                }
                throw HIDError.closed
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw HIDError.timeout
            }
            guard let result = try await group.next() else { throw HIDError.timeout }
            group.cancelAll()
            return result
        }
    }

    private static let inputCallback: IOHIDReportCallback = { context, _, _, _, _, report, reportLength in
        guard let context else { return }
        let device = Unmanaged<HIDDevice>.fromOpaque(context).takeUnretainedValue()
        let data = Data(bytes: report, count: reportLength)
        device.continuation?.yield(data)
    }
}
