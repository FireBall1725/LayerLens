import Foundation

public enum VIAError: Error, CustomStringConvertible, Sendable {
    case transportClosed
    case unexpectedResponse(expected: UInt8, got: UInt8)
    case shortResponse(command: UInt8, expectedAtLeast: Int, got: Int)
    case invalidArgument(String)
    case timeout(command: UInt8)
    case cancelled

    public var description: String {
        switch self {
        case .transportClosed:
            return "VIA transport closed before response arrived"
        case .unexpectedResponse(let expected, let got):
            return String(format: "Expected response opcode 0x%02X, got 0x%02X", expected, got)
        case .shortResponse(let cmd, let min, let got):
            return String(format: "Response for opcode 0x%02X too short: expected ≥%d bytes, got %d", cmd, min, got)
        case .invalidArgument(let msg):
            return "Invalid argument: \(msg)"
        case .timeout(let cmd):
            return String(format: "VIA opcode 0x%02X timed out waiting for response", cmd)
        case .cancelled:
            return "VIA send cancelled before response arrived"
        }
    }
}
