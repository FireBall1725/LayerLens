import Foundation
import TelemetryDeck
import LayerLensCore

/// Thin wrapper around the TelemetryDeck SDK. Initialisation is lazy
/// and conditional: when the user hasn't opted in, the SDK never gets
/// configured and no signal calls reach the network. The wrapper itself
/// is the single source for our app ID, so call sites don't have to
/// know it.
///
/// Privacy posture (also documented in `PRIVACY.md`):
/// - Default off. The user opts in via onboarding's privacy step or
///   Settings → Privacy.
/// - When on, TelemetryDeck attaches default fields it scrapes locally:
///   macOS version, CPU architecture, app version, locale. It does not
///   collect IP addresses (stripped server-side), keystrokes, layer
///   contents, custom labels, hostnames, usernames, or serial numbers.
/// - The "user" is an anonymous hash TelemetryDeck derives from
///   hardware identifiers. We never see plaintext.
@MainActor
enum Telemetry {
    /// LayerLens's TelemetryDeck app ID. Public; signal payloads are
    /// keyed against this on the server.
    private static let appID = "9BCD0F7D-5634-4FF6-A9F1-3F336C330890"

    /// Tracks whether `TelemetryDeck.initialize` has run in this process.
    /// `initialize` is documented as one-shot, so we gate it ourselves.
    private static var initialized = false

    /// Spin up the SDK if telemetry is enabled and we haven't already.
    /// Cheap to call repeatedly. Call at app launch, and again any time
    /// the user flips the toggle on (the toggle handler does this).
    static func configureIfEnabled(preferences: Preferences) {
        guard preferences.telemetryEnabled, !initialized else { return }
        let config = TelemetryDeck.Config(appID: appID)
        TelemetryDeck.initialize(config: config)
        initialized = true
        Log.info("Telemetry: enabled, SDK initialised")
    }

    /// Send a signal. No-op when telemetry is disabled (no SDK call,
    /// no network). No-op also when the SDK hasn't been configured yet,
    /// which happens transiently the first time the user flips the
    /// toggle on. Configure-then-send via `configureIfEnabled` first.
    static func send(
        _ signal: String,
        parameters: [String: String] = [:],
        preferences: Preferences
    ) {
        guard preferences.telemetryEnabled else { return }
        configureIfEnabled(preferences: preferences)
        guard initialized else { return }
        TelemetryDeck.signal(signal, parameters: parameters)
    }
}
