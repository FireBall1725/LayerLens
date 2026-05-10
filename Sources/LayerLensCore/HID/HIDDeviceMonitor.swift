import Foundation
import IOKit
import IOKit.hid

/// Long-lived `IOHIDManager` that watches USB Raw-HID devices (usage page
/// `0xFF60` / usage `0x61`) and pushes a fresh device list whenever something
/// is plugged in or removed.
///
/// Snapshots from `HIDEnumerator.discoverKeyboards()` are still useful for a
/// one-shot listing; this class is for the "react to plug/unplug" path.
public final class HIDDeviceMonitor: @unchecked Sendable {
    public typealias DeviceListCallback = @Sendable ([DiscoveredKeyboard]) -> Void

    private let manager: IOHIDManager
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var attachedDevices: [IOHIDDevice: HIDDeviceInfo] = [:]
    private let callback: DeviceListCallback

    public init(callback: @escaping DeviceListCallback) {
        self.manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.queue = DispatchQueue(label: "dev.layerlens.hid-monitor", qos: .userInitiated)
        self.callback = callback

        let matching: [String: Any] = [
            kIOHIDDeviceUsagePageKey: Int(RawHIDConstants.viaUsagePage),
            kIOHIDDeviceUsageKey: Int(RawHIDConstants.viaUsage)
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        IOHIDManagerSetDispatchQueue(manager, queue)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, Self.matchingCallback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, Self.removalCallback, context)
        IOHIDManagerActivate(manager)
    }

    deinit {
        IOHIDManagerCancel(manager)
    }

    // MARK: - Callbacks (run on `queue`)

    private static let matchingCallback: IOHIDDeviceCallback = { context, _, _, device in
        guard let context else { return }
        let monitor = Unmanaged<HIDDeviceMonitor>.fromOpaque(context).takeUnretainedValue()
        monitor.handleAttach(device)
    }

    private static let removalCallback: IOHIDDeviceCallback = { context, _, _, device in
        guard let context else { return }
        let monitor = Unmanaged<HIDDeviceMonitor>.fromOpaque(context).takeUnretainedValue()
        monitor.handleDetach(device)
    }

    private func handleAttach(_ device: IOHIDDevice) {
        guard let info = HIDEnumerator.makeInfo(from: device) else { return }
        lock.lock()
        attachedDevices[device] = info
        let snapshot = currentSnapshotLocked()
        lock.unlock()
        callback(snapshot)
    }

    private func handleDetach(_ device: IOHIDDevice) {
        lock.lock()
        attachedDevices.removeValue(forKey: device)
        let snapshot = currentSnapshotLocked()
        lock.unlock()
        callback(snapshot)
    }

    private func currentSnapshotLocked() -> [DiscoveredKeyboard] {
        var seen = Set<UInt32>()
        var result: [DiscoveredKeyboard] = []
        for (_, info) in attachedDevices {
            let key = (UInt32(info.vendorID) << 16) | UInt32(info.productID)
            if seen.insert(key).inserted {
                result.append(DiscoveredKeyboard(info: info, kind: HIDEnumerator.classify(info)))
            }
        }
        return result.sorted { $0.displayName < $1.displayName }
    }
}
