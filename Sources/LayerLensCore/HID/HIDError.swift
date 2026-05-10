import Foundation
import IOKit

public enum HIDError: Error, CustomStringConvertible, Sendable {
    case deviceNotFound
    case openFailed(IOReturn)
    case sendFailed(IOReturn)
    case timeout
    case shortReport(expected: Int, actual: Int)
    case closed

    public var description: String {
        switch self {
        case .deviceNotFound:
            return "HID device not found"
        case .openFailed(let r):
            return "IOHIDDeviceOpen failed (0x\(String(r, radix: 16, uppercase: true)))"
        case .sendFailed(let r):
            return "IOHIDDeviceSetReport failed (0x\(String(r, radix: 16, uppercase: true)))"
        case .timeout:
            return "HID request timed out"
        case .shortReport(let e, let a):
            return "Short HID report: expected \(e) bytes, got \(a)"
        case .closed:
            return "HID device closed"
        }
    }
}
