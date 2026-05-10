import SwiftUI
import AppKit

/// Owns the long-lived app state and runs setup at launch. `MenuBarExtra`'s
/// menu body is only evaluated when the user clicks the icon, so we can't
/// rely on `.task` on the menu for auto-connect / overlay wiring.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let preferences = Preferences()
    let appState    = AppState()
    let overlay     = OverlayController()
    let updater     = UpdateController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar app: no dock icon, doesn't steal activation when shown.
        NSApp.setActivationPolicy(.accessory)
        // Redirect stdout + stderr to ~/Library/Logs/LayerLens/LayerLens.log
        // before the rest of bootstrap runs so every print() is captured.
        // The Settings → Logs tab and the menu bar's "Reveal log" item read
        // from the same file.
        LogService.redirectStdioToLogFile()

        // Diagnostic: stop AppKit from immediately calling _crashOnException
        // (the default behaviour that turns NSExceptions into a SIGTRAP and
        // takes down the process). With this off, the exception propagates
        // and our handler can log its full reason + stack for debugging.
        UserDefaults.standard.register(defaults: ["NSApplicationCrashOnExceptions": false])

        NSSetUncaughtExceptionHandler { exc in
            let dump = "\n[UNCAUGHT] \(exc.name.rawValue): \(exc.reason ?? "<no reason>")\n"
                       + exc.callStackSymbols.joined(separator: "\n") + "\n"
            FileHandle.standardError.write(Data(dump.utf8))
            FileHandle.standardOutput.write(Data(dump.utf8))
            // Also persist to a fixed path that survives the crash.
            try? dump.write(toFile: "/tmp/layerlens-exception.log", atomically: true, encoding: .utf8)
        }

        // Wire AppState ↔ Overlay ↔ Preferences and start the HID monitor BEFORE
        // anything else. Doing this here (instead of in a SwiftUI `.task`) means
        // it runs whether or not the user has interacted with the menu bar yet.
        appState.attach(preferences: preferences)
        overlay.attach(appState: appState, preferences: preferences)
        appState.overlay = overlay

        Task { @MainActor [appState] in
            // Give the HIDDeviceMonitor a tick to deliver its initial device
            // list before we try auto-connecting.
            try? await Task.sleep(for: .milliseconds(150))
            await appState.connectFirstIfPreferred()
        }

        // Start the global keystroke listener only if the user has
        // already granted Input Monitoring. Calling start unconditionally
        // would trip the macOS TCC prompt before the user has reached the
        // onboarding step that explains why we're asking. OnboardingView
        // calls this again after the user grants from the Permissions
        // step, and it's idempotent.
        appState.enableKeystrokeListeningIfGranted()

        // Telemetry: configure (no-op when opted out) and send the
        // App.Launched signal so we can count active installs by anon
        // user hash. Default opt-in is false; the user is asked during
        // onboarding's privacy step. See Telemetry.swift / PRIVACY.md.
        Telemetry.configureIfEnabled(preferences: preferences)
        Telemetry.send("App.Launched", preferences: preferences)
    }
}

/// Menu-bar icon with a one-shot `.task` that triggers the first-run
/// onboarding window. Lives separately so the `\.openWindow` environment
/// is in scope; AppDelegate doesn't have it.
struct MenuBarLabel: View {
    @Environment(Preferences.self) private var preferences
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: "keyboard")
            .task {
                // 250ms is enough for the Window scene plumbing to settle
                // so `openWindow(id:)` actually finds the suppressed
                // onboarding window. Without the delay, calling openWindow
                // immediately on a fresh launch can silently no-op.
                try? await Task.sleep(for: .milliseconds(250))
                guard !preferences.onboardingComplete else { return }
                openWindow(id: "onboarding")
                NSApp.activate()
            }
    }
}

/// Wrapper that picks the keyboard to render in the Configure window from
/// AppState. Falls back to a placeholder if nothing's been selected.
struct ConfigureWindowContent: View {
    @Environment(AppState.self) private var state

    var body: some View {
        if let kb = state.configuringKeyboard {
            KeyboardConfigView(keyboard: kb)
        } else {
            Text("Pick a keyboard from the menu bar to configure.")
                .foregroundStyle(.secondary)
                .padding(40)
                .frame(minWidth: 480, minHeight: 240)
        }
    }
}

@main
struct LayerLensApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarMenuView(updater: appDelegate.updater)
        } label: {
            // The label view is the only piece of the MenuBarExtra scene
            // that renders eagerly at app launch (the menu content body
            // only evaluates when the icon is clicked). Hanging the
            // first-run onboarding trigger off here means the welcome
            // window pops on initial launch without needing AppKit-level
            // hooks.
            MenuBarLabel()
                .environment(appDelegate.preferences)
        }
        .menuBarExtraStyle(.menu)

        // Per-keyboard Configure window. The keyboard to render is picked
        // by `appState.configuringKeyboardPath`, set by whatever opened us
        // (menu bar item or Settings → Configure button) before calling
        // openWindow(id: "config").
        //
        // .contentSize so the window auto-expands to fit a full-size
        // keyboard's layout (e.g., a Keychron Q1 Pro is way wider than a
        // Micro Pad). The ScrollView inside still handles the rare case
        // where the keymap is wider than the screen.
        Window("Configure Keyboard", id: "config") {
            ConfigureWindowContent()
                .environment(appDelegate.appState)
                .environment(appDelegate.preferences)
        }
        // .automatic instead of .contentSize so SwiftUI doesn't pre-snap the
        // window to the body's idealWidth on every keyboard switch. That
        // pre-snap was killing the grow animation in `resizeWindowToFit()`.
        // The view animates via NSWindow.setFrame(animate: true) instead.
        .windowResizability(.automatic)
        .defaultSize(width: 720, height: 560)
        .defaultLaunchBehavior(.suppressed)

        Settings {
            SettingsView(overlay: appDelegate.overlay)
                .environment(appDelegate.preferences)
                .environment(appDelegate.appState)
        }
        // .contentMinSize so the Settings window can grow when the user
        // bumps Dynamic Type up. SettingsView declares minWidth/Height
        // as the floor. Without this, the default Settings resizability
        // pins the window at the idealWidth/Height and content truncates
        // at large accessibility text sizes.
        .windowResizability(.contentMinSize)

        // About panel, opened from the menu bar's "About LayerLens" item.
        // .contentSize so the AboutView's intrinsic size determines the
        // window dimensions; we don't want it resizable.
        Window("About LayerLens", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)

        // First-run onboarding. Presented on launch when
        // `preferences.onboardingComplete` is false; reachable any time
        // via Settings → General → "Show Onboarding Again".
        // .contentSize pins the window to the SwiftUI content's ideal
        // size — no manual resize. Dynamic Type still scales the window
        // because the content's ideal size grows with text scale.
        // (Was .contentMinSize, but that left the window resizable; one
        // accidental drag-to-bigger then sticks across launches via
        // macOS's window-frame restoration.)
        Window("Welcome to LayerLens", id: "onboarding") {
            OnboardingView()
                .environment(appDelegate.appState)
                .environment(appDelegate.preferences)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)

        // Firmware module explainer. Opened from a "Learn more" link in
        // onboarding (and later from a status banner in the Configure
        // window if no notify events are seen).
        // .contentMinSize (not .contentSize) so the window can be resized
        // taller; the body has long code blocks that benefit from extra
        // vertical room.
        Window("Live Layer Events", id: "firmware-help") {
            FirmwareHelpView()
        }
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.suppressed)
    }
}
