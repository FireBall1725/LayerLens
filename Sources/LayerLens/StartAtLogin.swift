import Foundation
import ServiceManagement

/// Thin wrapper around `SMAppService.mainApp` that exposes the
/// register/unregister flow as a SwiftUI-friendly value type. Use the
/// shared instance via `Preferences.startAtLogin` (Bool binding); that
/// owns the source-of-truth UserDefault and stays in sync with the
/// system state.
///
/// SMAppService requires the .app to be in `/Applications` (or otherwise
/// reachable to launchd). When called from a debug `swift run` build it
/// returns `.notRegistered` and `register()` will throw `notFound`; we
/// surface the error rather than silently no-op'ing so the Settings UI
/// can show a meaningful message.
enum StartAtLogin {
    /// Whether the app is currently set to launch at login.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Register the app as a login item. macOS may prompt the user the
    /// first time. Throws when the .app isn't in a launchd-discoverable
    /// location (e.g. running from `.build/release` during dev).
    static func enable() throws {
        try SMAppService.mainApp.register()
    }

    /// Stop launching at login. Idempotent: calling on an already-
    /// disabled service is a no-op (SMAppService throws notFound which
    /// we swallow).
    static func disable() throws {
        do {
            try SMAppService.mainApp.unregister()
        } catch SMAppServiceError.notRegistered {
            // already disabled, fine
        }
    }
}

private enum SMAppServiceError: Error {
    case notRegistered
}
