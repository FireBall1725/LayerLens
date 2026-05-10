import Foundation

/// Visual classification used for coloring keys.
public enum QMKKeycodeKind: Sendable, Hashable, Codable {
    case basic
    case modifier
    case special
}

/// Human-readable label(s) for a single QMK keycode value.
///
/// `tap` is the primary label; `hold` is set for hold-tap keys (e.g., MT, LT).
/// `symbol` is a single Unicode glyph or icon hint when one exists.
public struct QMKKeycodeLabel: Sendable, Hashable, Codable {
    public let tap: String
    public let tapShort: String?
    public let hold: String?
    public let holdShort: String?
    public let symbol: String?
    public let kind: QMKKeycodeKind
    public let layerRef: Int?

    public init(
        tap: String,
        tapShort: String? = nil,
        hold: String? = nil,
        holdShort: String? = nil,
        symbol: String? = nil,
        kind: QMKKeycodeKind = .basic,
        layerRef: Int? = nil
    ) {
        self.tap = tap
        self.tapShort = tapShort
        self.hold = hold
        self.holdShort = holdShort
        self.symbol = symbol
        self.kind = kind
        self.layerRef = layerRef
    }
}
