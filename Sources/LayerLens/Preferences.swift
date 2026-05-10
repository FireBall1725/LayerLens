import Foundation
import Observation
import CoreGraphics
import SwiftUI
import LayerLensCore

/// Where on the active screen the overlay panel sits. `.custom` means "wherever
/// the user dragged it to" and pulls coordinates from `Preferences.overlayCustomX/Y`.
public enum OverlayPlacement: String, Sendable, CaseIterable, Identifiable {
    case bottomCentre, topCentre, centre, bottomLeft, bottomRight, topLeft, topRight, custom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .bottomCentre: return "Bottom Centre"
        case .topCentre:    return "Top Centre"
        case .centre:       return "Centre"
        case .bottomLeft:   return "Bottom Left"
        case .bottomRight:  return "Bottom Right"
        case .topLeft:      return "Top Left"
        case .topRight:     return "Top Right"
        case .custom:       return "Custom"
        }
    }
}

/// User-visible preferences persisted to `UserDefaults`. Kept tiny on purpose;
/// most "settings" can derive from the connected device or live state.
@MainActor
@Observable
final class Preferences {
    private let defaults = UserDefaults.standard

    private static let autoConnectKey        = "autoConnectOnLaunch"
    private static let overlayVisibleKey     = "overlayVisible"
    private static let overlayScaleKey       = "overlayScale"
    private static let overlayOpacityKey     = "overlayOpacity"
    private static let overlayHoldDurationKey = "overlayHoldDuration"
    private static let overlayPlacementKey   = "overlayPlacement"
    private static let overlayCustomXKey     = "overlayCustomX"
    private static let overlayCustomYKey     = "overlayCustomY"
    private static let colourRegularKey       = "colourRegular"
    private static let colourModifierKey      = "colourModifier"
    private static let colourLayerKey         = "colourLayer"
    private static let colourSpecialKey       = "colourSpecial"
    private static let colourTextKey          = "colourText"
    private static let autoConnectVIDPIDsKey = "autoConnectVIDPIDs"
    private static let showMatrixCoordsKey   = "showMatrixCoords"
    private static let showHexFallbackKey    = "showHexFallback"
    private static let keycodeOverridesKey   = "keycodeOverrides"
    private static let layerNamesKey         = "layerNames"
    private static let labelFontNameKey      = "labelFontName"
    private static let labelFontSizeKey      = "labelFontSize"
    private static let onboardingCompleteKey = "onboardingComplete"
    private static let customLayoutPathsKey  = "customLayoutPaths"
    private static let logLevelKey           = "logLevel"
    private static let telemetryEnabledKey   = "telemetryEnabled"
    private static let telemetryDecidedKey   = "telemetryDecided"

    /// Connect to the first detected keyboard automatically when the app starts.
    var autoConnectOnLaunch: Bool {
        didSet { defaults.set(autoConnectOnLaunch, forKey: Self.autoConnectKey) }
    }

    /// Whether the floating overlay panel is shown.
    var overlayVisible: Bool {
        didSet { defaults.set(overlayVisible, forKey: Self.overlayVisibleKey) }
    }

    /// Points per "u" (one standard key unit) in the overlay panel.
    /// Smaller = more compact overlay; bigger = readable from across the room.
    var overlayScale: Double {
        didSet { defaults.set(overlayScale, forKey: Self.overlayScaleKey) }
    }

    /// Where on screen the overlay should sit on the next show.
    var overlayPlacement: OverlayPlacement {
        didSet { defaults.set(overlayPlacement.rawValue, forKey: Self.overlayPlacementKey) }
    }

    /// Origin point used when `overlayPlacement == .custom`. Coordinates are in
    /// AppKit's bottom-left-origin screen space (matches NSWindow.frame).
    var overlayCustomOrigin: CGPoint {
        didSet {
            defaults.set(overlayCustomOrigin.x, forKey: Self.overlayCustomXKey)
            defaults.set(overlayCustomOrigin.y, forKey: Self.overlayCustomYKey)
        }
    }

    /// Maximum panel alpha. The fade animation goes 0 → opacity → 0 instead of
    /// 0 → 1 → 0, so a value of 0.85 produces a tasteful semi-transparent HUD.
    var overlayOpacity: Double {
        didSet { defaults.set(overlayOpacity, forKey: Self.overlayOpacityKey) }
    }

    /// Seconds the overlay stays fully visible after the last layer event
    /// before starting its fade-out animation. Only applies to the
    /// auto-flash path; pinned-overlay mode ignores this.
    var overlayHoldDuration: Double {
        didSet { defaults.set(overlayHoldDuration, forKey: Self.overlayHoldDurationKey) }
    }

    /// Set of "VID:PID" strings the user wants to auto-connect to whenever
    /// they appear on the USB bus. Persisted as a sorted array for stability.
    var autoConnectVIDPIDs: Set<String> {
        didSet {
            defaults.set(Array(autoConnectVIDPIDs).sorted(), forKey: Self.autoConnectVIDPIDsKey)
        }
    }

    func vidPidKey(for keyboard: DiscoveredKeyboard) -> String {
        String(format: "%04X:%04X", keyboard.info.vendorID, keyboard.info.productID)
    }

    func shouldAutoConnect(_ keyboard: DiscoveredKeyboard) -> Bool {
        autoConnectVIDPIDs.contains(vidPidKey(for: keyboard))
    }

    func setAutoConnect(_ on: Bool, for keyboard: DiscoveredKeyboard) {
        let key = vidPidKey(for: keyboard)
        if on { autoConnectVIDPIDs.insert(key) }
        else  { autoConnectVIDPIDs.remove(key) }
    }

    /// Show the small matrix-coords subtitle (e.g. "0,3") under each key.
    var showMatrixCoords: Bool {
        didSet { defaults.set(showMatrixCoords, forKey: Self.showMatrixCoordsKey) }
    }

    /// Tracks whether the first-run onboarding window has been completed
    /// (or explicitly skipped). LayerLensApp triggers the window on
    /// launch when this is false, and Settings exposes a "Show Onboarding
    /// Again" button to reset it.
    var onboardingComplete: Bool {
        didSet { defaults.set(onboardingComplete, forKey: Self.onboardingCompleteKey) }
    }

    /// Floor for which log lines reach `~/Library/Logs/LayerLens/LayerLens.log`
    /// (and therefore the Logs tab). Default `.info`, which hides the lighting
    /// tx/rx and poll-heartbeat spam. Drop to `.debug` when troubleshooting.
    /// Writes through to `Log.minimumLevel` so changes take effect on the
    /// next emission, no relaunch needed.
    var logLevel: LogLevel {
        didSet {
            defaults.set(logLevel.rawValue, forKey: Self.logLevelKey)
            Log.minimumLevel = logLevel
        }
    }

    /// Anonymous usage telemetry via TelemetryDeck. Default `false`;
    /// the user is asked once during onboarding (and can flip in
    /// Settings → Privacy any time). When false the SDK never
    /// initialises and no data leaves the machine. See PRIVACY.md.
    var telemetryEnabled: Bool {
        didSet { defaults.set(telemetryEnabled, forKey: Self.telemetryEnabledKey) }
    }

    /// Whether the user has been asked about telemetry yet. Used to
    /// gate the onboarding's privacy step from re-asking. Both Allow
    /// and No-thanks set this to true.
    var telemetryDecided: Bool {
        didSet { defaults.set(telemetryDecided, forKey: Self.telemetryDecidedKey) }
    }

    /// User-overridden layout JSON files keyed by `"VVVV:PPPP"`. When a
    /// keyboard's VID:PID is in here, ActiveConnection.bootstrap loads
    /// the JSON at that path instead of falling through to VIA registry
    /// or Vial device fetch. Useful for handwired boards, prototypes,
    /// or correcting upstream definitions.
    var customLayoutPaths: [String: String] {
        didSet {
            if let data = try? JSONEncoder().encode(customLayoutPaths) {
                defaults.set(data, forKey: Self.customLayoutPathsKey)
            }
        }
    }

    func customLayoutPath(forKeyboard kb: DiscoveredKeyboard) -> URL? {
        guard let s = customLayoutPaths[vidPidKey(for: kb)], !s.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: s)
    }

    func setCustomLayoutPath(_ url: URL?, for kb: DiscoveredKeyboard) {
        let key = vidPidKey(for: kb)
        if let url {
            customLayoutPaths[key] = url.path
        } else {
            customLayoutPaths.removeValue(forKey: key)
        }
    }

    /// PostScript font name for key labels, or `"system"` for SF Pro. Applied
    /// to overlay, Configure window, and preview rendering.
    var labelFontName: String {
        didSet { defaults.set(labelFontName, forKey: Self.labelFontNameKey) }
    }

    /// Base point size of the primary key label. Auxiliary text (alt-glyph,
    /// matrix coords) scales proportionally off this.
    var labelFontSize: Double {
        didSet { defaults.set(labelFontSize, forKey: Self.labelFontSizeKey) }
    }

    /// Resolve the user's font preference to a SwiftUI Font of the given size.
    func font(size: Double, weight: Font.Weight = .semibold) -> Font {
        if labelFontName == "system" || labelFontName.isEmpty {
            return .system(size: size, weight: weight)
        }
        return .custom(labelFontName, size: size)
    }

    /// When the formatter has no human-readable label and falls back to a hex
    /// representation (e.g., "0xFFFE"), should we render it? Off = blank cell.
    var showHexFallback: Bool {
        didSet { defaults.set(showHexFallback, forKey: Self.showHexFallbackKey) }
    }

    /// User overrides that replace the default formatter label for a specific
    /// keycode. Keyed by "v10:0xNNNN" / "v12:0xNNNN" so the same byte can mean
    /// different things between protocol versions.
    var keycodeOverrides: [String: String] {
        didSet {
            if let data = try? JSONEncoder().encode(keycodeOverrides) {
                defaults.set(data, forKey: Self.keycodeOverridesKey)
            }
        }
    }

    func overrideKey(forKeycode kc: UInt16, protocolVersion: UInt16) -> String {
        let bucket = protocolVersion <= 10 ? "v10" : "v12"
        return String(format: "%@:0x%04X", bucket, kc)
    }

    func labelOverride(for kc: UInt16, protocolVersion: UInt16) -> String? {
        keycodeOverrides[overrideKey(forKeycode: kc, protocolVersion: protocolVersion)]
    }

    func setLabelOverride(_ label: String?, for kc: UInt16, protocolVersion: UInt16) {
        let key = overrideKey(forKeycode: kc, protocolVersion: protocolVersion)
        let trimmed = (label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            keycodeOverrides.removeValue(forKey: key)
        } else {
            keycodeOverrides[key] = trimmed
        }
    }

    /// Per-keyboard, per-layer custom names ("Base", "Numpad", "Macros", ...).
    /// Keyed by "VVVV:PPPP:N" so renaming layer 1 of one keyboard doesn't
    /// affect a different board with its own layer 1.
    var layerNames: [String: String] {
        didSet {
            if let data = try? JSONEncoder().encode(layerNames) {
                defaults.set(data, forKey: Self.layerNamesKey)
            }
        }
    }

    private func layerKey(for kb: DiscoveredKeyboard, layer: Int) -> String {
        "\(vidPidKey(for: kb)):\(layer)"
    }

    func layerName(forKeyboard kb: DiscoveredKeyboard, layer: Int) -> String? {
        layerNames[layerKey(for: kb, layer: layer)]
    }

    func setLayerName(_ name: String?, for kb: DiscoveredKeyboard, layer: Int) {
        let key = layerKey(for: kb, layer: layer)
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            layerNames.removeValue(forKey: key)
        } else {
            layerNames[key] = trimmed
        }
    }

    /// Theme colours. Stored as `#RRGGBB` strings via `Color.toHex()`.
    var colourRegular: Color  { didSet { defaults.set(colourRegular.toHex(),  forKey: Self.colourRegularKey) } }
    var colourModifier: Color { didSet { defaults.set(colourModifier.toHex(), forKey: Self.colourModifierKey) } }
    var colourLayer: Color    { didSet { defaults.set(colourLayer.toHex(),    forKey: Self.colourLayerKey) } }
    var colourSpecial: Color  { didSet { defaults.set(colourSpecial.toHex(),  forKey: Self.colourSpecialKey) } }
    var colourText: Color     { didSet { defaults.set(colourText.toHex(),     forKey: Self.colourTextKey) } }

    init() {
        self.autoConnectOnLaunch = defaults.bool(forKey: Self.autoConnectKey)
        self.overlayVisible      = defaults.bool(forKey: Self.overlayVisibleKey)

        let scale = defaults.double(forKey: Self.overlayScaleKey)
        self.overlayScale = scale > 0 ? scale : 60

        let opacity = defaults.double(forKey: Self.overlayOpacityKey)
        self.overlayOpacity = opacity > 0 ? opacity : 1.0

        let hold = defaults.double(forKey: Self.overlayHoldDurationKey)
        self.overlayHoldDuration = hold > 0 ? hold : 2.5

        let raw = defaults.string(forKey: Self.overlayPlacementKey) ?? OverlayPlacement.bottomCentre.rawValue
        self.overlayPlacement = OverlayPlacement(rawValue: raw) ?? .bottomCentre

        self.overlayCustomOrigin = CGPoint(
            x: defaults.double(forKey: Self.overlayCustomXKey),
            y: defaults.double(forKey: Self.overlayCustomYKey)
        )

        let saved = (defaults.array(forKey: Self.autoConnectVIDPIDsKey) as? [String]) ?? []
        self.autoConnectVIDPIDs = Set(saved)

        self.showMatrixCoords = (defaults.object(forKey: Self.showMatrixCoordsKey) as? Bool) ?? true
        self.showHexFallback  = (defaults.object(forKey: Self.showHexFallbackKey)  as? Bool) ?? true
        self.onboardingComplete = defaults.bool(forKey: Self.onboardingCompleteKey)

        // Log level: stored as the LogLevel.rawValue Int. Default to .info
        // when no value has been set yet so first launch doesn't drown the
        // user in lighting tx/rx spam. `Log.minimumLevel` gets synced to
        // this value at the bottom of init, after all stored properties
        // are settled (Swift's two-phase init forbids self-reads here).
        let storedLogLevel = (defaults.object(forKey: Self.logLevelKey) as? Int)
            .flatMap(LogLevel.init(rawValue:))
        self.logLevel = storedLogLevel ?? .info

        // Telemetry defaults to off until the user explicitly opts in via
        // onboarding's privacy step or Settings → Privacy. `telemetryDecided`
        // gates the onboarding question so we don't re-ask on every launch.
        self.telemetryEnabled = defaults.bool(forKey: Self.telemetryEnabledKey)
        self.telemetryDecided = defaults.bool(forKey: Self.telemetryDecidedKey)

        if let data = defaults.data(forKey: Self.customLayoutPathsKey),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            self.customLayoutPaths = dict
        } else {
            self.customLayoutPaths = [:]
        }

        self.labelFontName = defaults.string(forKey: Self.labelFontNameKey) ?? "system"
        let storedFontSize = defaults.double(forKey: Self.labelFontSizeKey)
        self.labelFontSize = storedFontSize > 0 ? storedFontSize : 11

        if let data = defaults.data(forKey: Self.keycodeOverridesKey),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            self.keycodeOverrides = dict
        } else {
            self.keycodeOverrides = [:]
        }

        if let data = defaults.data(forKey: Self.layerNamesKey),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            self.layerNames = dict
        } else {
            self.layerNames = [:]
        }

        // Default theme: dark slate keys with subtle accents and white text.
        // Tuned to read clearly on most desktop wallpapers.
        self.colourRegular  = Color(hex: defaults.string(forKey: Self.colourRegularKey)  ?? "#2D3340")
        self.colourModifier = Color(hex: defaults.string(forKey: Self.colourModifierKey) ?? "#5B5184")
        self.colourLayer    = Color(hex: defaults.string(forKey: Self.colourLayerKey)    ?? "#3D6B8C")
        self.colourSpecial  = Color(hex: defaults.string(forKey: Self.colourSpecialKey)  ?? "#704030")
        self.colourText     = Color(hex: defaults.string(forKey: Self.colourTextKey)     ?? "#FFFFFF")

        // All stored properties are now settled. Sync the global Log API
        // so emissions made between here and the next user-driven level
        // change get filtered correctly.
        Log.minimumLevel = self.logLevel
    }

    func resetTheme() {
        colourRegular  = Color(hex: "#2D3340")
        colourModifier = Color(hex: "#5B5184")
        colourLayer    = Color(hex: "#3D6B8C")
        colourSpecial  = Color(hex: "#704030")
        colourText     = Color(hex: "#FFFFFF")
        overlayOpacity = 1.0
    }
}
