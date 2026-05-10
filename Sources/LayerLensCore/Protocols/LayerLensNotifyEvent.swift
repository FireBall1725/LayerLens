import Foundation

/// Wire format constants for the LayerLens Notify firmware module.
/// Mirrors `firmware/layerlens_notify/PROTOCOL.md`.
public enum LayerLensNotify {
    public static let reportID: UInt8 = 0xF1
    /// Sub-command byte (frame[1]) for "what's the current layer state?".
    /// Sent by the host as a request and echoed by the firmware in the reply.
    public static let getLayerStateSubCommand: UInt8 = 0x00
    /// Maximum protocol version this client understands. Reports with a
    /// higher byte 2 should be treated cautiously: fields beyond the
    /// documented response shape are reserved and may carry version-specific
    /// data, but the version + state bytes are stable.
    public static let supportedProtocolVersion: UInt8 = 0x02
}

/// Decoded layer-state snapshot. The shape is the same regardless of how it
/// arrived (poll response in protocol v2, push report in legacy v1).
public struct LayerLensNotifyEvent: Sendable, Hashable {
    /// Protocol version reported by the firmware.
    public let protocolVersion: UInt8
    /// QMK `layer_state_t` bitmask: bit N set => layer N is active.
    public let layerState: UInt32

    public init(protocolVersion: UInt8, layerState: UInt32) {
        self.protocolVersion = protocolVersion
        self.layerState = layerState
    }

    /// Index of the highest active layer in the bitmask, or 0 if no bits set.
    /// Matches QMK's `get_highest_layer(layer_state)` semantics.
    public var highestActiveLayer: Int {
        guard layerState != 0 else { return 0 }
        for i in (0 ..< 32).reversed() where (layerState >> i) & 1 == 1 {
            return i
        }
        return 0
    }

    /// Iterates active layer indices in ascending order.
    public var activeLayers: [Int] {
        (0 ..< 32).filter { (layerState >> $0) & 1 == 1 }
    }

    /// Decode a v2 poll response: `[0xF1, 0x00, version, b3, b2, b1, b0, ...]`.
    /// Returns nil if the report isn't shaped right.
    public init?(pollResponse report: Data) {
        guard report.count >= 7,
              report[0] == LayerLensNotify.reportID,
              report[1] == LayerLensNotify.getLayerStateSubCommand else {
            return nil
        }
        self.protocolVersion = report[2]
        self.layerState = (UInt32(report[3]) << 24)
                        | (UInt32(report[4]) << 16)
                        | (UInt32(report[5]) <<  8)
                        |  UInt32(report[6])
    }

    /// Decode a v1 unsolicited push report: `[0xF1, version, b3, b2, b1, b0, ...]`.
    /// Kept so a new host can still mirror layers from a keyboard running the
    /// withdrawn v1 firmware until the user reflashes. Returns nil if the
    /// report isn't shaped right.
    public init?(report: Data) {
        guard report.count >= 6, report[0] == LayerLensNotify.reportID else {
            return nil
        }
        // v1 frames have version at byte 1; reject anything that looks like a
        // v2 poll response (byte 1 == 0x00 sub-command echo) so we don't
        // misread its longer layout.
        let candidateVersion = report[1]
        guard candidateVersion != LayerLensNotify.getLayerStateSubCommand else {
            return nil
        }
        self.protocolVersion = candidateVersion
        self.layerState = (UInt32(report[2]) << 24)
                        | (UInt32(report[3]) << 16)
                        | (UInt32(report[4]) <<  8)
                        |  UInt32(report[5])
    }
}
