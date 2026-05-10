import SwiftUI
import AppKit
import LayerLensCore

/// Identifiers for each Settings tab. The selection lives in `@State` and is
/// reset to `.general` every time the Settings window appears, so users
/// don't get dropped back into whichever tab they had open last week.
private enum SettingsTab: String, Hashable {
    case general, overlay, display, theme, privacy, logs
}

struct SettingsView: View {
    @Environment(Preferences.self) private var preferences
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow

    /// Injected by `LayerLensApp` so we can drive the live demo overlay
    /// panel from whichever Settings tab is showing.
    let overlay: OverlayController

    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        TabView(selection: $selectedTab) {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }
                .tag(SettingsTab.general)
            overlayTab
                .tabItem { Label("Overlay", systemImage: "square.on.square") }
                .tag(SettingsTab.overlay)
            displayTab
                .tabItem { Label("Display", systemImage: "rectangle.and.text.magnifyingglass") }
                .tag(SettingsTab.display)
            themeTab
                .tabItem { Label("Theme", systemImage: "paintpalette") }
                .tag(SettingsTab.theme)
            privacyTab
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
                .tag(SettingsTab.privacy)
            LogsTabView()
                .tabItem { Label("Logs", systemImage: "doc.text.magnifyingglass") }
                .tag(SettingsTab.logs)
        }
        // .min/.ideal pair so the window opens at a comfortable size but
        // grows with Dynamic Type / user resize. The Settings scene's
        // .windowResizability(.contentMinSize) modifier (in LayerLensApp)
        // honors these floors; without it, SwiftUI snaps to ideal and
        // refuses to grow.
        .frame(
            minWidth: 580, idealWidth: 580,
            minHeight: 540, idealHeight: 540
        )
        // SwiftUI keeps the previously-selected tab across openings of a
        // Settings scene; force a reset to the first tab on appear.
        .onAppear { selectedTab = .general; updatePreview() }
        .onDisappear { overlay.hidePreview() }
        .onChange(of: selectedTab) { _, _ in updatePreview() }
    }

    /// Show the live demo overlay only on tabs that affect overlay rendering.
    private func updatePreview() {
        switch selectedTab {
        case .overlay, .display, .theme:
            overlay.showPreview()
        case .general, .logs, .privacy:
            overlay.hidePreview()
        }
    }

    private var generalTab: some View {
        @Bindable var preferences = preferences
        return Form {
            Section(detectedKeyboardsHeader) {
                if state.detectedKeyboards.isEmpty {
                    Text("No keyboards plugged in.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    // Cap the visible list at ~4 rows; scroll when the user
                    // has more boards plugged in. Without the cap a hub +
                    // a few split keyboards would push the rest of the
                    // General tab off-screen.
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(state.detectedKeyboards, id: \.info.registryPath) { kb in
                                keyboardRow(kb)
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                }
            }

            Section("At login") {
                Toggle("Start LayerLens at login", isOn: startAtLoginBinding)
            }

            Section("Legacy fallback") {
                Toggle(
                    "Connect to first detected keyboard on launch (if no auto-connect set)",
                    isOn: $preferences.autoConnectOnLaunch
                )
                .controlSize(.small)
            }

            Section {
                HStack {
                    Spacer()
                    Button("Show Onboarding Again") {
                        preferences.onboardingComplete = false
                        openWindow(id: "onboarding")
                        NSApp.activate()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Renders the "Show" / "Showing" button for a keyboard row. Click
    /// pops the floating overlay up showing this keyboard's layers, or
    /// hides it if it's already up for this keyboard. Splits into two
    /// branches so the active row uses `.borderedProminent` (filled
    /// accent-coloured pill) and the others use plain `.bordered`.
    @ViewBuilder
    private func showOverlayButton(
        for kb: DiscoveredKeyboard,
        isConnected: Bool,
        isShowing: Bool
    ) -> some View {
        if isShowing {
            Button("Showing", systemImage: "eye.fill") {
                overlay.hide()
            }
            .buttonStyle(.borderedProminent)
            .help("The floating overlay is currently up for this keyboard. Click to hide.")
        } else {
            Button("Show", systemImage: "eye") {
                state.focus(on: kb.info.registryPath)
                overlay.show()
            }
            .buttonStyle(.bordered)
            .disabled(!isConnected)
            .help("Pop the floating overlay up showing this keyboard's layers.")
        }
    }

    /// Section header for the detected-keyboards list. Surfaces a count
    /// suffix so the user knows there's more behind a scrollbar (e.g.
    /// "Detected keyboards (8)") without having to scroll to find out.
    private var detectedKeyboardsHeader: String {
        let count = state.detectedKeyboards.count
        if count == 0 { return "Detected keyboards" }
        return "Detected keyboards (\(count))"
    }

    /// Two-way bridge between SMAppService's live state and the toggle.
    /// Reads the system value (so we stay correct if the user toggles
    /// LayerLens via System Settings → General → Login Items) and writes
    /// through to register/unregister.
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

    @ViewBuilder
    private func keyboardRow(_ kb: DiscoveredKeyboard) -> some View {
        let isAuto = Binding(
            get: { preferences.shouldAutoConnect(kb) },
            set: { state.setAutoConnect($0, for: kb) }
        )
        let isConnected = state.connections[kb.info.registryPath] != nil
        // The overlay is "showing" this keyboard when it's focused AND
        // pinned visible. Both have to hold; focus alone (without pin)
        // means the overlay only flashes on layer change but isn't
        // currently on screen.
        let isFocused = state.focusedKeyboardPath == kb.info.registryPath
        let isShowing = isFocused && preferences.overlayVisible

        HStack(spacing: 12) {
            Circle()
                .fill(isConnected ? .green : .secondary.opacity(0.5))
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(kb.info.product ?? kb.info.displayVIDPID)
                    .font(.body)
                Text("\(kb.kind.label) · \(kb.info.displayVIDPID)" + (isConnected ? " · connected" : ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            showOverlayButton(for: kb, isConnected: isConnected, isShowing: isShowing)
            Button("Configure…") {
                state.configuringKeyboardPath = kb.info.registryPath
                openWindow(id: "config")
                NSApp.activate()
            }
            .buttonStyle(.bordered)
            Toggle("Auto-connect", isOn: isAuto)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .help("Auto-connect to this keyboard whenever it shows up on USB")
        }
    }

    private var overlayTab: some View {
        @Bindable var preferences = preferences
        return Form {
            Section("Size") {
                HStack {
                    Slider(value: $preferences.overlayScale, in: 32 ... 120, step: 4)
                    Text("\(Int(preferences.overlayScale)) pt")
                        .monospacedDigit()
                        .frame(width: 56, alignment: .trailing)
                }
            }

            Section("Opacity") {
                HStack {
                    Slider(value: $preferences.overlayOpacity, in: 0.30 ... 1.0)
                    Text("\(Int(preferences.overlayOpacity * 100))%")
                        .monospacedDigit()
                        .frame(width: 56, alignment: .trailing)
                }
            }

            Section("Hold duration") {
                HStack {
                    Slider(value: $preferences.overlayHoldDuration, in: 0.5 ... 10.0, step: 0.5)
                    Text(String(format: "%.1f s", preferences.overlayHoldDuration))
                        .monospacedDigit()
                        .frame(width: 56, alignment: .trailing)
                }
                Text("How long the overlay stays visible after the last layer change before fading out. Doesn't apply while the overlay is pinned via \"Show Overlay.\"")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Placement") {
                Picker("Position", selection: $preferences.overlayPlacement) {
                    ForEach(OverlayPlacement.allCases) { placement in
                        Text(placement.displayName).tag(placement)
                    }
                }
                .pickerStyle(.menu)

                Text("Drag the overlay to move it anywhere; placement automatically switches to “Custom.”")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var displayTab: some View {
        @Bindable var preferences = preferences
        return Form {
            Section("On every key") {
                Toggle("Show matrix coordinates (e.g. \"0,3\")", isOn: $preferences.showMatrixCoords)
                Toggle("Show hex code when no human-readable label exists", isOn: $preferences.showHexFallback)
            }

            Section("Font") {
                FontFamilyPicker(selection: $preferences.labelFontName)

                HStack {
                    Text("Size").frame(width: 48, alignment: .leading)
                    Slider(value: $preferences.labelFontSize, in: 8 ... 24, step: 1)
                    Text("\(Int(preferences.labelFontSize)) pt")
                        .monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                }
            }

            Section("Custom labels") {
                if preferences.keycodeOverrides.isEmpty {
                    Text("Right-click any key in the main window → \"Rename label…\" to add a custom label.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(preferences.keycodeOverrides.keys.sorted(), id: \.self) { key in
                        overrideRow(key: key)
                    }
                    HStack {
                        Spacer()
                        Button("Clear all") { preferences.keycodeOverrides = [:] }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func overrideRow(key: String) -> some View {
        let value = preferences.keycodeOverrides[key] ?? ""
        HStack {
            Text(key)
                .font(.system(.body, design: .monospaced))
                .frame(width: 130, alignment: .leading)
            Text("→")
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
            Spacer()
            Button(role: .destructive) {
                preferences.keycodeOverrides.removeValue(forKey: key)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove override for \(key)")
        }
    }

    private var themeTab: some View {
        @Bindable var preferences = preferences
        return Form {
            Section("Presets") {
                ThemePresetGrid()
            }

            Section("Key colours") {
                ColorPicker("Regular keys", selection: $preferences.colourRegular, supportsOpacity: false)
                ColorPicker("Modifiers (Shift, Ctrl, MT, OSM)", selection: $preferences.colourModifier, supportsOpacity: false)
                ColorPicker("Layer keys (MO, TO, LT, LM)", selection: $preferences.colourLayer, supportsOpacity: false)
                ColorPicker("Special keys", selection: $preferences.colourSpecial, supportsOpacity: false)
            }

            Section("Text") {
                ColorPicker("Label color", selection: $preferences.colourText, supportsOpacity: false)
            }

            HStack {
                Spacer()
                Button("Reset to defaults") { preferences.resetTheme() }
            }
        }
        .formStyle(.grouped)
    }

    /// Settings → Privacy. Toggle for anonymous telemetry plus the same
    /// "what's sent / what's not" breakdown the onboarding step uses, so
    /// users who skipped past it (or want a refresher) have the full
    /// picture before deciding.
    private var privacyTab: some View {
        @Bindable var preferences = preferences
        return Form {
            Section("Anonymous usage telemetry") {
                Toggle("Help improve LayerLens by sharing anonymous usage", isOn: Binding(
                    get: { preferences.telemetryEnabled },
                    set: { newValue in
                        preferences.telemetryEnabled = newValue
                        preferences.telemetryDecided = true
                        if newValue {
                            Telemetry.configureIfEnabled(preferences: preferences)
                        }
                    }
                ))
                Text("Off by default. When on, LayerLens sends a small set of anonymous signals via TelemetryDeck. No personally identifying data ever leaves your machine.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("What's sent") {
                privacySettingsRow(
                    icon: "checkmark.circle.fill",
                    color: .green,
                    body: "macOS version, CPU type, app version, locale. Keyboard VID:PID and kind (QMK or Vial). Whether the firmware module is installed and which mode it's in."
                )
            }

            Section("Never sent") {
                privacySettingsRow(
                    icon: "xmark.circle.fill",
                    color: .secondary,
                    body: "Keystrokes, layer contents, custom labels. Your name, hostname, IP address. Anything that could identify you or what you're typing."
                )
            }

            Section {
                HStack {
                    Spacer()
                    Link("Read PRIVACY.md",
                         destination: URL(string: "https://github.com/FireBall1725/LayerLens/blob/main/PRIVACY.md")!)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Compact paragraph row for the Privacy tab. Mirrors the onboarding
    /// step's icon + body layout so users see consistent visuals.
    private func privacySettingsRow(icon: String, color: Color, body: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 20)
            Text(body)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Custom font picker that renders each family in its own face inside a
/// searchable popover. Replaces the default SwiftUI Picker, which is
/// alphabetical-text-only and unusable for "find me a nice key label font."
///
/// Keyboard model: search field auto-focuses on open. Down-arrow from the
/// search field moves focus into the List, where macOS List handles
/// up/down traversal natively. Return commits the highlighted row.
/// Escape dismisses the popover at any time.
struct FontFamilyPicker: View {
    @Binding var selection: String
    @State private var isOpen: Bool = false
    @State private var search: String = ""
    /// Mirrors the user's arrow-key traversal of the list. Initialised to
    /// the live `selection` on open so they start on whichever font is
    /// currently selected, not the top of the list.
    @State private var highlighted: String? = nil
    @FocusState private var searchFocused: Bool
    @FocusState private var listFocused: Bool

    private static let families: [String] = NSFontManager.shared.availableFontFamilies
        .filter { !$0.hasPrefix(".") }
        .sorted()

    var body: some View {
        HStack {
            Text("Family").frame(width: 48, alignment: .leading)
            triggerButton
                .popover(isPresented: $isOpen, arrowEdge: .bottom) {
                    fontList
                        .frame(width: 320, height: 380)
                        .onAppear {
                            highlighted = selection
                            searchFocused = true
                        }
                }
        }
    }

    private var triggerButton: some View {
        Button {
            isOpen.toggle()
        } label: {
            HStack(spacing: 8) {
                Text(displayName)
                    .font(previewFont)
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down")
                    .foregroundStyle(.secondary)
                    .imageScale(.small)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(.background.secondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.separator, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Font family")
        .accessibilityValue(displayName)
    }

    @ViewBuilder
    private var fontList: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search fonts", text: $search)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit { commitHighlighted() }
                    .onKeyPress(.downArrow) {
                        // Hop focus into the list so its native arrow-key
                        // traversal takes over.
                        searchFocused = false
                        listFocused = true
                        if highlighted == nil { highlighted = listItems.first }
                        return .handled
                    }
            }
            .padding(8)

            Divider()

            List(listItems, id: \.self, selection: $highlighted) { name in
                fontRow(name: name)
                    .tag(name)
                    .listRowSeparator(.hidden)
                    .contentShape(Rectangle())
                    .onTapGesture { commit(name) }
            }
            .listStyle(.plain)
            .focused($listFocused)
            .frame(maxHeight: .infinity)
        }
        .onKeyPress(.escape) {
            isOpen = false
            return .handled
        }
        .onKeyPress(.return) {
            commitHighlighted()
            return .handled
        }
    }

    /// All items in display order: a synthetic `"system"` row first,
    /// followed by every installed family that matches the search query.
    private var listItems: [String] {
        var items: [String] = ["system"]
        items.append(contentsOf: filtered)
        return items
    }

    private func fontRow(name: String) -> some View {
        HStack {
            Text(name == "system" ? "System" : name)
                .font(name == "system" ? .body : .custom(name, size: 14))
                .lineLimit(1)
            Spacer()
            if selection == name {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Apply the chosen font and dismiss the popover.
    private func commit(_ name: String) {
        selection = name
        isOpen = false
    }

    /// Apply whatever the list currently has highlighted (set either by
    /// the user pre-selecting or by arrow-key traversal). No-op if
    /// nothing's highlighted yet.
    private func commitHighlighted() {
        if let name = highlighted {
            commit(name)
        }
    }

    private var displayName: String {
        selection == "system" || selection.isEmpty ? "System" : selection
    }

    /// Live preview of the selected font on the trigger button. Uses the
    /// system body size so it scales with Dynamic Type.
    private var previewFont: Font {
        if selection == "system" || selection.isEmpty {
            return .body
        }
        return .custom(selection, size: NSFont.systemFontSize)
    }

    private var filtered: [String] {
        let q = search.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return Self.families }
        return Self.families.filter { $0.localizedCaseInsensitiveContains(q) }
    }
}
