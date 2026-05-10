import Foundation
import IOKit
import IOKit.hid
import LayerLensCore

/// Global keystroke listener. Subscribes to every Generic-Desktop
/// keyboard via `IOHIDManager` and reports the set of HID usage codes
/// currently held down.
///
/// This is the host-side counterpart to the firmware module: the module
/// tells us which *layer* is active; this tells us which *keys* on that
/// layer the user is pressing. Together they let the floating overlay
/// highlight live keystrokes.
///
/// Requires the Input Monitoring TCC permission. `start` is a no-op when
/// the user hasn't granted it (`IOHIDManagerOpen` returns
/// `kIOReturnNotPermitted`); the caller should ensure the permission
/// surface lives elsewhere; see `Permissions.swift`.
@MainActor
final class KeystrokeListener {
    /// Set of HID Keyboard-page (`0x07`) usage codes currently pressed.
    /// QMK's basic-keycode table aliases these for usages 0x00..0xE7, so
    /// this set is directly comparable to `keymap[layer][row][col]` for
    /// the basic-key range.
    private(set) var pressed: Set<UInt16> = []

    private var manager: IOHIDManager?
    /// Closure fired on every press / release with the new `pressed` set.
    private var onChange: ((Set<UInt16>) -> Void)?

    /// Open the IOHIDManager and start listening. Idempotent: calling
    /// twice without an intervening `stop()` is a no-op.
    func start(onChange: @escaping @MainActor (Set<UInt16>) -> Void) {
        guard manager == nil else { return }
        self.onChange = onChange

        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        // Match every keyboard. The IOHIDManager will multiplex events
        // across them; we don't care which physical board produced a
        // given keypress, only that *some* key was pressed.
        let matching: [String: Any] = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard
        ]
        IOHIDManagerSetDeviceMatching(mgr, matching as CFDictionary)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(mgr, Self.callback, context)

        IOHIDManagerScheduleWithRunLoop(
            mgr,
            CFRunLoopGetMain(),
            CFRunLoopMode.defaultMode.rawValue
        )

        let status = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        guard status == kIOReturnSuccess else {
            // kIOReturnNotPermitted (-536870174) when Input Monitoring
            // hasn't been granted. Other failures are very rare.
            Log.warn(String(format:
                "KeystrokeListener: IOHIDManagerOpen failed (0x%X). Typing highlight disabled",
                status
            ))
            IOHIDManagerUnscheduleFromRunLoop(
                mgr,
                CFRunLoopGetMain(),
                CFRunLoopMode.defaultMode.rawValue
            )
            return
        }

        manager = mgr
        Log.info("KeystrokeListener: started, typing highlight active")
    }

    /// Close the IOHIDManager. Safe to call when not started.
    func stop() {
        guard let mgr = manager else { return }
        IOHIDManagerUnscheduleFromRunLoop(
            mgr,
            CFRunLoopGetMain(),
            CFRunLoopMode.defaultMode.rawValue
        )
        IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = nil
        if !pressed.isEmpty {
            pressed.removeAll()
            onChange?(pressed)
        }
    }

    /// IOHIDManager fires this on every press and release.
    private static let callback: IOHIDValueCallback = { context, _, _, value in
        guard let context else { return }
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let intValue = IOHIDValueGetIntegerValue(value)
        // Only Keyboard / Keypad usage page (0x07). Other elements (LEDs,
        // consumer page) get routed here on multi-function keyboards too;
        // those aren't keys we render. Also bound the usage to UInt16:
        // some boards expose vendor-defined usages above 0xFFFF on the
        // keyboard page that QMK keycodes can't address anyway.
        guard usagePage == UInt32(kHIDPage_KeyboardOrKeypad),
              usage <= UInt32(UInt16.max) else { return }
        let usage16 = UInt16(usage)
        let isDown = intValue != 0

        // Resolve the listener on the C callback thread (synchronous), so
        // we never send the raw `context` pointer across an actor
        // boundary; Swift 6 strict concurrency rejects that. The class
        // itself is @MainActor and therefore Sendable, so capturing the
        // resulting reference into the Task is fine.
        let listener = Unmanaged<KeystrokeListener>
            .fromOpaque(context)
            .takeUnretainedValue()

        Task { @MainActor in
            if isDown {
                listener.pressed.insert(usage16)
            } else {
                listener.pressed.remove(usage16)
            }
            listener.onChange?(listener.pressed)
        }
    }
}
