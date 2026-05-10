import SwiftUI
import LayerLensCore

/// Compact view shown inside the floating overlay panel: layer name header
/// (if the user named this layer) plus the keyboard for the focused
/// connection's currently-active layer.
struct OverlayView: View {
    @Environment(AppState.self) private var state
    @Environment(Preferences.self) private var preferences

    var body: some View {
        Group {
            if let conn = state.focusedConnection,
               let definition = conn.definition,
               let layout = definition.layouts.first,
               !conn.keymap.isEmpty {
                VStack(spacing: 6) {
                    Text(layerHeader(for: conn))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(preferences.colourText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(preferences.colourRegular.opacity(0.85))
                        )

                    KeyboardLayoutView(
                        layout: layout,
                        layerKeycodes: conn.keymap[conn.selectedLayer],
                        scale: preferences.overlayScale,
                        protocolVersion: conn.protocolVersion,
                        useOverlayFont: true,
                        useOverlayTheme: true,
                        pressedKeycodes: state.pressedKeycodes
                    )
                }
                .padding(12)
            } else {
                Text("Connect a keyboard from the menu bar.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.black.opacity(0.55))
                    )
                    .padding(8)
            }
        }
    }

    private func layerHeader(for conn: ActiveConnection) -> String {
        let i = conn.selectedLayer
        if let name = preferences.layerName(forKeyboard: conn.keyboard, layer: i),
           !name.isEmpty {
            return name
        }
        return "Layer \(i)"
    }
}
