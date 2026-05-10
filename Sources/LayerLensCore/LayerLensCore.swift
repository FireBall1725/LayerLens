/// LayerLensCore is the protocol + parsing core for LayerLens.
/// UI lives in the separate macOS app target; this library is platform-agnostic
/// where possible (parsing, models) and macOS-specific only where required (HID via IOKit).
public enum LayerLensCore {
    public static let version = "0.0.1"
}
