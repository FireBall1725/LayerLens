import SwiftUI
import LayerLensCore

/// Menu bar dropdown content. Deliberately minimal: every keyboard-
/// specific action (configure, connect, disconnect, pin overlay) lives
/// in Settings or the Configure window. The menu is just an entry
/// point: open the app, see the about, check for updates, quit.
struct MenuBarMenuView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    let updater: UpdateController

    var body: some View {
        Button("Settings…") {
            openSettings()
            NSApp.activate()
        }
        .keyboardShortcut(",", modifiers: [.command])

        Button("About LayerLens") {
            openWindow(id: "about")
            NSApp.activate()
        }

        Button("Check for Updates…") {
            updater.checkForUpdates()
            NSApp.activate()
        }

        Divider()

        Button("Quit LayerLens") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: [.command])
    }
}
