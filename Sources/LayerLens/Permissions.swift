import AppKit
import IOKit.hid

/// macOS Input Monitoring permission helpers. Gates the typing-visualisation
/// feature: highlighting each key as it's pressed in the floating overlay
/// requires reading keyboard events from other apps, which macOS treats as
/// privileged starting in 10.15.
enum InputMonitoringPermission {
    enum Status {
        case granted
        case denied
        case notDetermined
    }

    /// Read the current permission state without prompting. Use for UI
    /// indicators (green check vs grey "not granted" pill).
    static var status: Status {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted:    return .granted
        case kIOHIDAccessTypeDenied:     return .denied
        default:                         return .notDetermined
        }
    }

    /// Request Input Monitoring access. Triggers the standard macOS prompt
    /// the first time it's called for this binary; on subsequent calls
    /// returns the cached decision without re-prompting.
    @discardableResult
    static func request() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    /// Jump the user to System Settings → Privacy & Security → Input
    /// Monitoring. Used when permission was previously *denied* (the
    /// system won't re-prompt; only the user can flip it back).
    static func openSystemSettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
