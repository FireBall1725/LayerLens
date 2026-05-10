import SwiftUI
import LayerLensCore

/// Step progression for the first-run onboarding flow. Order matters:
/// `next`/`previous` walk this enum.
enum OnboardingStep: Int, CaseIterable, Hashable {
    case welcome
    case connect
    case permissions
    case startAtLogin
    case privacy
    case finish
}

/// First-run welcome window. Shown automatically on launch when
/// `Preferences.onboardingComplete` is false; re-openable any time from
/// Settings → General. Each step is independently skippable so the user
/// can race past anything they don't care about.
struct OnboardingView: View {
    @Environment(AppState.self) private var state
    @Environment(Preferences.self) private var preferences
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow

    @State private var step: OnboardingStep = .welcome
    @State private var permissionStatus: InputMonitoringPermission.Status = .notDetermined

    var body: some View {
        VStack(spacing: 0) {
            // Body content scrolls inside the fixed window. Step copy
            // never overflows at default text size, but Dynamic Type
            // accessibility scales can — scrolling is the right answer
            // there rather than letting the window grow.
            ScrollView {
                content
                    .padding(.horizontal, 36)
                    .padding(.vertical, 28)
            }

            Divider()

            footer
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
        }
        // Fixed window size; pairs with `.windowResizability(.contentSize)`
        // on the Window declaration in LayerLensApp to lock the wizard's
        // dimensions across launches.
        .frame(width: 720, height: 560)
        .onAppear {
            // Reset to the first step every time the wizard appears.
            // SwiftUI preserves the view tree across window close/reopen,
            // so without this, "Show Onboarding Again" from Settings
            // would resurface the window on whatever step the user
            // last viewed (typically .finish).
            step = .welcome
        }
    }

    // MARK: - Content per step

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:      welcomeStep
        case .connect:      connectStep
        case .permissions:  permissionsStep
        case .startAtLogin: startAtLoginStep
        case .privacy:      privacyStep
        case .finish:       finishStep
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 18) {
            Image(systemName: "keyboard")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .foregroundStyle(.tint)
                .padding(.top, 16)

            Text("Welcome to LayerLens")
                .font(.largeTitle.weight(.semibold))

            Text("A floating overlay that mirrors your QMK or Vial keyboard's active layer in real time. Live layer events, custom labels, lighting controls, and a neutral keymap viewer for any board on the VIA registry.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)

            Spacer(minLength: 0)
        }
    }

    private var connectStep: some View {
        VStack(spacing: 14) {
            Image(systemName: "cable.connector")
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .foregroundStyle(.tint)
                .padding(.top, 8)

            Text("Plug in a keyboard")
                .font(.title.weight(.semibold))

            Text("LayerLens auto-detects QMK and Vial keyboards over USB. If yours isn't listed, double-check that VIA support is enabled in its firmware.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)

            keyboardListPreview
                .frame(maxWidth: 460)
                .padding(.top, 6)

            // Live overlay flashing requires our QMK module
            // (`layerlens_notify`) flashed onto the keyboard. Surface
            // the explainer up-front rather than letting the user
            // discover later that the overlay isn't auto-flashing.
            // Onboarding sends users to the GitHub readme directly
            // (avoids stacking another window on top of the wizard);
            // the Configure window's "Live no" banner still opens the
            // FirmwareHelpView in-app.
            Link(destination: URL(string: "https://github.com/FireBall1725/LayerLens/tree/main/firmware/layerlens_notify")!) {
                Label("How to enable live layer events", systemImage: "bolt.badge.clock")
                    .font(.caption)
            }
            .foregroundStyle(.tint)

            Spacer(minLength: 0)
        }
    }

    private var permissionsStep: some View {
        VStack(spacing: 14) {
            Image(systemName: "hand.raised.circle")
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .foregroundStyle(.tint)
                .padding(.top, 8)

            Text("See your typing in the overlay")
                .font(.title.weight(.semibold))

            Text("LayerLens can highlight each key as you press it on the floating overlay. macOS asks for permission to read keyboard events the first time, so other apps' keystrokes can light up the right key.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)

            permissionStatusRow
                .padding(.top, 4)

            Text("This is optional. Layer overlay still works without it; only the typing highlight needs Input Monitoring.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
                .padding(.top, 2)

            Spacer(minLength: 0)
        }
        .task {
            permissionStatus = InputMonitoringPermission.status
        }
        // Re-check whenever LayerLens regains focus. Catches the
        // "user opened System Settings, flipped the toggle, came
        // back" path; the in-app TCC prompt path is covered by the
        // short polling loop on the Grant button itself.
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )) { _ in
            permissionStatus = InputMonitoringPermission.status
            state.enableKeystrokeListeningIfGranted()
        }
    }

    @ViewBuilder
    private var permissionStatusRow: some View {
        switch permissionStatus {
        case .granted:
            Label("Input Monitoring granted", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.callout)
        case .denied:
            VStack(spacing: 8) {
                Label("Input Monitoring denied", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
                Button("Open System Settings…") {
                    InputMonitoringPermission.openSystemSettings()
                }
            }
        case .notDetermined:
            Button("Grant Input Monitoring…") {
                InputMonitoringPermission.request()
                // The TCC prompt is async; re-poll status briefly so the
                // row flips to the granted/denied state without the user
                // having to navigate away and back.
                Task {
                    for _ in 0 ..< 10 {
                        try? await Task.sleep(for: .milliseconds(300))
                        let s = InputMonitoringPermission.status
                        if s != .notDetermined {
                            permissionStatus = s
                            // Now that the user has decided, kick the
                            // keystroke listener over the line. AppState
                            // checks status itself so this is a no-op on
                            // .denied.
                            state.enableKeystrokeListeningIfGranted()
                            break
                        }
                    }
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var startAtLoginStep: some View {
        @Bindable var preferences = preferences
        return VStack(spacing: 14) {
            Image(systemName: "power.circle")
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .foregroundStyle(.tint)
                .padding(.top, 8)

            Text("Launch at login?")
                .font(.title.weight(.semibold))

            Text("LayerLens lives in your menu bar. Most users want it running whenever they're at their Mac. Turn this on and it'll start automatically each time you log in.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)

            Toggle("Start LayerLens at login", isOn: startAtLoginBinding)
                .toggleStyle(.switch)
                .padding(.top, 8)

            Text("You can change this later in Settings → General.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
    }

    private var privacyStep: some View {
        VStack(spacing: 14) {
            Image(systemName: "chart.bar.xaxis")
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .foregroundStyle(.tint)
                .padding(.top, 8)

            Text("Help improve LayerLens?")
                .font(.title.weight(.semibold))

            Text("LayerLens can send a small set of anonymous usage signals so we know which keyboards and macOS versions to prioritise. It's off by default and you can flip it any time in Settings → Privacy.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)

            VStack(alignment: .leading, spacing: 8) {
                privacyRow(
                    icon: "checkmark.circle.fill",
                    color: .green,
                    title: "Sent",
                    body: "macOS version, CPU type, app version, locale, keyboard VID:PID, whether the firmware module is installed."
                )
                privacyRow(
                    icon: "xmark.circle.fill",
                    color: .secondary,
                    title: "Never sent",
                    body: "Keystrokes, layer contents, custom labels, your name, hostname, IP address, or anything that could identify you."
                )
            }
            .frame(maxWidth: 460, alignment: .leading)
            .padding(.top, 4)

            Link("Read the full PRIVACY.md",
                 destination: URL(string: "https://github.com/FireBall1725/LayerLens/blob/main/PRIVACY.md")!)
                .font(.caption)

            Spacer(minLength: 0)
        }
    }

    /// Compact "Sent / Never sent" row used inside the privacy step. The
    /// icon + colour give the user a quick visual differentiator before
    /// they read the body copy.
    private func privacyRow(icon: String, color: Color, title: String, body: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                Text(body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var finishStep: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .foregroundStyle(.green)
                .padding(.top, 12)

            Text("You're all set")
                .font(.title.weight(.semibold))

            VStack(alignment: .leading, spacing: 10) {
                bulletRow("keyboard", "Click the keyboard icon in your menu bar to see detected boards.")
                bulletRow("eye", "Pick \"Show Overlay\" to pin the floating layer view, or just press a layer key. It'll flash automatically.")
                bulletRow("gearshape", "Open Settings (⌘,) for theme presets, font, overlay placement, and more.")
            }
            .frame(maxWidth: 460, alignment: .leading)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Footer (step indicator + nav buttons)

    private var footer: some View {
        HStack(spacing: 16) {
            stepIndicator

            Spacer()

            if step != .finish && step != .privacy {
                Button("Skip", action: complete)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }

            if step != .welcome {
                Button("Back", action: previousStep)
            }

            switch step {
            case .privacy:
                // Privacy gets two explicit choices instead of a generic
                // "Next". Both record `telemetryDecided` so the step
                // doesn't re-ask; only "Help improve" flips telemetry on.
                Button("No thanks") {
                    @Bindable var prefs = preferences
                    prefs.telemetryEnabled = false
                    prefs.telemetryDecided = true
                    nextStep()
                }
                Button("Help improve LayerLens") {
                    @Bindable var prefs = preferences
                    prefs.telemetryEnabled = true
                    prefs.telemetryDecided = true
                    Telemetry.configureIfEnabled(preferences: preferences)
                    nextStep()
                }
                .keyboardShortcut(.defaultAction)
            case .finish:
                Button("Done", action: complete)
                    .keyboardShortcut(.defaultAction)
            default:
                Button("Next", action: nextStep)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases, id: \.self) { s in
                Circle()
                    .fill(s == step ? Color.accentColor : Color.secondary.opacity(0.30))
                    .frame(width: 7, height: 7)
            }
        }
    }

    // MARK: - Connect step helper

    /// Compact list of currently-detected keyboards, refreshing live as
    /// the user plugs/unplugs. Empty state nudges them to plug something
    /// in before continuing, but we don't *block* on a connection;
    /// "Skip" / "Next" still work.
    @ViewBuilder
    private var keyboardListPreview: some View {
        let list = state.detectedKeyboards
        VStack(alignment: .leading, spacing: 6) {
            if list.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for a keyboard…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 16)
            } else {
                ForEach(list, id: \.info.registryPath) { kb in
                    HStack {
                        Image(systemName: "keyboard")
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(kb.info.product ?? kb.info.displayVIDPID)
                                .font(.callout)
                            Text("\(kb.kind.label) · \(kb.info.displayVIDPID)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Spacer()
                        if state.connections[kb.info.registryPath] != nil {
                            Label("Connected", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                                .labelStyle(.iconOnly)
                        }
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.background.secondary)
                    )
                }
            }
        }
    }

    // MARK: - Start-at-login binding

    /// Two-way bridge between the SMAppService state and the toggle UI.
    /// Reads from the live system value (so a user who registered via
    /// some other means still sees the right toggle) and writes through
    /// to register/unregister, surfacing failures in `lastMessage` for
    /// now (a dedicated error UI lands later).
    private var startAtLoginBinding: Binding<Bool> {
        Binding(
            get: { StartAtLogin.isEnabled },
            set: { newValue in
                do {
                    if newValue {
                        try StartAtLogin.enable()
                    } else {
                        try StartAtLogin.disable()
                    }
                } catch {
                    state.lastMessage = "Couldn't update Start at Login: \(error.localizedDescription)"
                }
            }
        )
    }

    // MARK: - Step navigation

    private func nextStep() {
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        withAnimation(.easeInOut(duration: 0.18)) { step = next }
    }

    private func previousStep() {
        guard let prev = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        withAnimation(.easeInOut(duration: 0.18)) { step = prev }
    }

    private func complete() {
        preferences.onboardingComplete = true
        dismissWindow(id: "onboarding")
    }

    // MARK: - Misc

    private func bulletRow(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 20)
                .foregroundStyle(.tint)
            Text(text)
                .font(.callout)
        }
    }
}
