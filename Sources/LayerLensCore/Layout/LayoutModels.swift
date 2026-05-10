import Foundation

/// Where a `KeyboardDefinition` originated. Surfaced in the Configure
/// window so users can tell whether the rendering reflects the firmware-
/// embedded definition (Vial) or an external registry (VIA), and in the
/// future can override either with a user-supplied file.
public enum LayoutSource: Sendable, Hashable, Codable {
    /// Pulled from the bundled VIA keyboards manifest by VID:PID.
    case viaRegistry
    /// Fetched + decompressed straight from a Vial keyboard's firmware.
    case vialDevice
    /// User-supplied JSON file overriding the auto-resolved definition.
    case userProvided

    public var displayName: String {
        switch self {
        case .viaRegistry:  return "Registry"
        case .vialDevice:   return "Device"
        case .userProvided: return "Custom"
        }
    }
}

/// A single key on a physical keyboard layout.
public struct LayoutKey: Sendable, Hashable, Codable {
    public let row: Int
    public let col: Int
    /// Top-left of the un-rotated bounding rectangle. When `rotation` is
    /// non-zero, the rectangle is drawn rotated about its centre. KLE
    /// already accounts for the rotation pivot when computing this point,
    /// so renderers just need to draw the rect at (x, y) and apply
    /// `.rotationEffect(.degrees(rotation), anchor: .center)`.
    public let x: Double
    public let y: Double
    public let w: Double
    public let h: Double
    /// Visual rotation in degrees (clockwise positive). Almost always 0
    /// outside split keyboards' thumb clusters.
    public let rotation: Double

    public init(
        row: Int, col: Int,
        x: Double, y: Double,
        w: Double, h: Double,
        rotation: Double = 0
    ) {
        self.row = row
        self.col = col
        self.x = x
        self.y = y
        self.w = w
        self.h = h
        self.rotation = rotation
    }
}

/// A named arrangement of keys (e.g. "LAYOUT_split_3x6_3").
public struct KeyboardLayout: Sendable, Hashable, Codable {
    public let name: String
    public let keys: [LayoutKey]

    public init(name: String, keys: [LayoutKey]) {
        self.name = name
        self.keys = keys
    }

    /// Bounding box (max corner). Origin is implicitly (0,0).
    public var dimensions: (width: Double, height: Double) {
        let maxX = keys.map { $0.x + $0.w }.max() ?? 0
        let maxY = keys.map { $0.y + $0.h }.max() ?? 0
        return (maxX, maxY)
    }
}

/// Full physical description of a keyboard: the matrix shape, USB IDs, and
/// one or more named layouts (a board may expose several alternate physical
/// arrangements over the same matrix).
public struct KeyboardDefinition: Sendable, Hashable, Codable {
    public let vendorID: UInt16
    public let productID: UInt16
    public let rows: Int
    public let cols: Int
    public let layouts: [KeyboardLayout]

    public init(vendorID: UInt16, productID: UInt16, rows: Int, cols: Int, layouts: [KeyboardLayout]) {
        self.vendorID = vendorID
        self.productID = productID
        self.rows = rows
        self.cols = cols
        self.layouts = layouts
    }

    public var layoutNames: [String] {
        layouts.map(\.name)
    }

    public func layout(named name: String) -> KeyboardLayout? {
        layouts.first { $0.name == name }
    }
}
