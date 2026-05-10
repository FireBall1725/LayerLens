import Foundation
import IOKit
import IOKit.hid

/// VIA / QMK Raw HID convention: usage page 0xFF60, usage 0x61.
public enum RawHIDConstants {
    public static let viaUsagePage: UInt16 = 0xFF60
    public static let viaUsage: UInt16 = 0x61
}

/// Snapshot enumeration of Raw-HID interfaces. Synchronous; does not retain manager state.
public enum HIDEnumerator {

    /// Enumerate all currently-attached HID interfaces matching the VIA Raw HID convention.
    public static func discoverKeyboards() -> [DiscoveredKeyboard] {
        let pairs = matchingDevices()
        var seen = Set<UInt32>()
        var result: [DiscoveredKeyboard] = []
        for (info, _) in pairs {
            let key = (UInt32(info.vendorID) << 16) | UInt32(info.productID)
            if seen.insert(key).inserted {
                result.append(DiscoveredKeyboard(info: info, kind: classify(info)))
            }
        }
        return result.sorted { $0.displayName < $1.displayName }
    }

    /// Resolve a previously-discovered keyboard back to a live IOHIDDevice.
    /// Re-enumerates and matches by (vendorID, productID, registryPath).
    public static func resolveDevice(for keyboard: DiscoveredKeyboard) -> IOHIDDevice? {
        for (info, device) in matchingDevices() {
            if info.vendorID == keyboard.info.vendorID,
               info.productID == keyboard.info.productID,
               info.registryPath == keyboard.info.registryPath {
                return device
            }
        }
        return nil
    }

    /// Returns every Raw-HID-matched (info, device) pair currently attached. Multiple
    /// entries may share VID:PID; callers that just want a logical device list should dedupe.
    static func matchingDevices() -> [(HIDDeviceInfo, IOHIDDevice)] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        let matching: [String: Any] = [
            kIOHIDDeviceUsagePageKey: Int(RawHIDConstants.viaUsagePage),
            kIOHIDDeviceUsageKey: Int(RawHIDConstants.viaUsage)
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            return []
        }

        return deviceSet.compactMap { device in
            guard let info = makeInfo(from: device) else { return nil }
            return (info, device)
        }
    }

    static func classify(_ info: HIDDeviceInfo) -> HIDDeviceKind {
        if let serial = info.serialNumber, serial.lowercased().hasPrefix("vial:") {
            return .vial
        }
        return .qmk
    }

    static func makeInfo(from device: IOHIDDevice) -> HIDDeviceInfo? {
        guard
            let vid = property(device, kIOHIDVendorIDKey) as? Int,
            let pid = property(device, kIOHIDProductIDKey) as? Int
        else { return nil }

        let usagePage = (property(device, kIOHIDPrimaryUsagePageKey) as? Int) ?? 0
        let usage = (property(device, kIOHIDPrimaryUsageKey) as? Int) ?? 0
        let manufacturer = property(device, kIOHIDManufacturerKey) as? String
        let product = property(device, kIOHIDProductKey) as? String
        let serial = property(device, kIOHIDSerialNumberKey) as? String

        let entry = IOHIDDeviceGetService(device)
        var path = ""
        if entry != IO_OBJECT_NULL {
            var cPath = [CChar](repeating: 0, count: 1024)
            if IORegistryEntryGetPath(entry, kIOServicePlane, &cPath) == KERN_SUCCESS {
                let bytes = cPath.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
                path = String(decoding: bytes, as: UTF8.self)
            }
        }

        return HIDDeviceInfo(
            vendorID: UInt16(truncatingIfNeeded: vid),
            productID: UInt16(truncatingIfNeeded: pid),
            usagePage: UInt16(truncatingIfNeeded: usagePage),
            usage: UInt16(truncatingIfNeeded: usage),
            manufacturer: manufacturer,
            product: product,
            serialNumber: serial,
            registryPath: path
        )
    }

    private static func property(_ device: IOHIDDevice, _ key: String) -> Any? {
        IOHIDDeviceGetProperty(device, key as CFString)
    }
}
