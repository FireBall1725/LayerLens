import Foundation

/// Snapshot description of a Raw-HID-capable device discovered via IOHIDManager.
public struct HIDDeviceInfo: Sendable, Hashable {
    public let vendorID: UInt16
    public let productID: UInt16
    public let usagePage: UInt16
    public let usage: UInt16
    public let manufacturer: String?
    public let product: String?
    public let serialNumber: String?
    /// Stable IORegistry path; survives across enumeration cycles for the same physical interface.
    public let registryPath: String

    public init(
        vendorID: UInt16,
        productID: UInt16,
        usagePage: UInt16,
        usage: UInt16,
        manufacturer: String?,
        product: String?,
        serialNumber: String?,
        registryPath: String
    ) {
        self.vendorID = vendorID
        self.productID = productID
        self.usagePage = usagePage
        self.usage = usage
        self.manufacturer = manufacturer
        self.product = product
        self.serialNumber = serialNumber
        self.registryPath = registryPath
    }

    public var displayVIDPID: String {
        String(format: "%04X:%04X", vendorID, productID)
    }
}

/// Coarse classification of a discovered Raw-HID device.
public enum HIDDeviceKind: Sendable, Hashable {
    case qmk
    case vial

    public var label: String {
        switch self {
        case .qmk: return "QMK"
        case .vial: return "Vial"
        }
    }
}

public struct DiscoveredKeyboard: Sendable, Hashable, Identifiable {
    public let info: HIDDeviceInfo
    public let kind: HIDDeviceKind

    /// Stable id for SwiftUI lists/sheets; matches the IORegistry path so
    /// the same physical interface keeps its identity across snapshots.
    public var id: String { info.registryPath }

    public var displayName: String {
        let base = info.product ?? info.displayVIDPID
        return "\(base) (\(kind.label), \(info.displayVIDPID))"
    }
}
