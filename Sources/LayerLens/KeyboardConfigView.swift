import SwiftUI
import LayerLensCore

/// Per-keyboard configuration window. Three focused tabs:
///   Keymap: layer picker, keymap viewer with right-click rename, per-layer names
///   Lighting: VIA-driven RGB / indicators / underglow controls
///   Connection: auto-connect, manual connect/disconnect, status
struct KeyboardConfigView: View {
    let keyboard: DiscoveredKeyboard

    @Environment(AppState.self) private var state
    @Environment(Preferences.self) private var preferences
    @Environment(\.openWindow) private var openWindow

    private var connection: ActiveConnection? {
        state.connections[keyboard.info.registryPath]
    }

    var body: some View {
        let size = contentMinSize
        TabView {
            keymapTab
                .tabItem { Label("Keymap", systemImage: "keyboard") }
            lightingTab
                .tabItem { Label("Lighting", systemImage: "sun.max") }
            connectionTab
                .tabItem { Label("Connection", systemImage: "cable.connector") }
        }
        // Floor only; the window's actual size is animated by
        // `resizeWindowToFit()` via AppKit. Setting an idealWidth/Height
        // here would let SwiftUI pre-snap the window on keyboard switches,
        // which kills the grow animation.
        .frame(minWidth: size.width, minHeight: size.height)
        .navigationTitle(windowTitle)
        // The Window scene with id "config" is reused across keyboards.
        // SwiftUI doesn't re-apply .contentSize when the configuring
        // keyboard changes, so a Q1 Pro window stays at 1180×720 even
        // after switching to a Micro Pad. Drive the resize from AppKit.
        .task(id: keyboard.info.registryPath) {
            // Let the new layout finish reading before measuring; otherwise
            // contentMinSize falls back to 720×560 (no `definition` yet).
            try? await Task.sleep(for: .milliseconds(50))
            resizeWindowToFit()
        }
        .onChange(of: connection?.definition != nil) { _, hasDefinition in
            // Bootstrapping the keymap is async; resize once the layout
            // arrives so the first paint gets the correct floor too.
            if hasDefinition { resizeWindowToFit() }
        }
    }

    /// Locate this view's hosting NSWindow and animate its content area to
    /// the connected keyboard's bounds. Uses AppKit's built-in window
    /// resize animation rather than `setContentSize`, which snaps.
    @MainActor
    private func resizeWindowToFit() {
        let target = contentMinSize
        guard let window = NSApp.windows.first(where: {
            $0.identifier?.rawValue == "config"
        }) else { return }
        let currentContent = window.contentLayoutRect.size
        // Only resize when the size actually needs to change; otherwise we
        // jiggle the window on every tab click.
        if abs(currentContent.width - target.width) < 1,
           abs(currentContent.height - target.height) < 1 {
            return
        }

        // Convert target content size to a full window frame, anchored at the
        // current frame's *top-left* so the title bar stays put while the
        // bottom-right corner does the moving. Far less disorienting than
        // resizing from the bottom-left (NSWindow's natural origin).
        let oldFrame = window.frame
        let topLeft = NSPoint(x: oldFrame.origin.x, y: oldFrame.maxY)
        let targetContentRect = NSRect(
            x: 0, y: 0, width: target.width, height: target.height
        )
        let targetFrameSize = window.frameRect(forContentRect: targetContentRect).size
        let newFrame = NSRect(
            x: topLeft.x,
            y: topLeft.y - targetFrameSize.height,
            width: targetFrameSize.width,
            height: targetFrameSize.height
        )
        let animate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        window.setFrame(newFrame, display: true, animate: animate)
    }

    /// Window dimensions large enough to show the connected keyboard's
    /// keymap card without clipping. Falls back to a sensible default for
    /// the unconnected/no-layout case (where the placeholder copy is small).
    private var contentMinSize: CGSize {
        let fallback = CGSize(width: 720, height: 560)
        guard let conn = connection,
              let definition = conn.definition,
              let layout = definition.layouts.first,
              !layout.keys.isEmpty else {
            return fallback
        }
        let scale: Double = 64
        var minX =  Double.infinity
        var minY =  Double.infinity
        var maxX = -Double.infinity
        var maxY = -Double.infinity
        for k in layout.keys {
            // Rotated thumb clusters can stick out below/right of their
            // un-rotated rect. Take the AABB of the rotated corners so
            // the window opens tall/wide enough for the whole layout.
            let cx = k.x + k.w / 2
            let cy = k.y + k.h / 2
            let halfW = k.w / 2
            let halfH = k.h / 2
            let radians = k.rotation * .pi / 180
            let cosA = cos(radians)
            let sinA = sin(radians)
            for (lx, ly) in [(-halfW, -halfH), (halfW, -halfH), (halfW, halfH), (-halfW, halfH)] {
                let rx = lx * cosA - ly * sinA + cx
                let ry = lx * sinA + ly * cosA + cy
                minX = min(minX, rx)
                minY = min(minY, ry)
                maxX = max(maxX, rx)
                maxY = max(maxY, ry)
            }
        }
        let extentX = maxX - minX
        let extentY = maxY - minY
        // Card = keymap pixels + card padding (40) + border (4) + outer
        // VStack padding (40). Plus a small safety margin so the window
        // chrome doesn't clip the right edge.
        let width  = extentX * scale + 40 + 4 + 40 + 24
        // Vertical: keymap + picker + name field + stats + the inter-row
        // spacings the VStack adds.
        let height = extentY * scale + 60 + 44 + 60 + 80
        return CGSize(
            width:  max(fallback.width,  width),
            height: max(fallback.height, height)
        )
    }

    private var windowTitle: String {
        let name = keyboard.info.product ?? keyboard.info.displayVIDPID
        let status = connection != nil ? " (connected)" : ""
        return "\(name)\(status)"
    }

    // MARK: - Keymap tab

    @ViewBuilder
    private var keymapTab: some View {
        if let conn = connection,
           let definition = conn.definition,
           let layout = definition.layouts.first,
           !conn.keymap.isEmpty {
            keymapPane(conn: conn, layout: layout, definition: definition)
        } else {
            tabPlaceholder("Connect this keyboard to view and rename its keymap.")
        }
    }

    @ViewBuilder
    private func keymapPane(conn: ActiveConnection, layout: KeyboardLayout, definition: KeyboardDefinition) -> some View {
        @Bindable var conn = conn

        // Bind the single rename TextField to whichever layer is selected,
        // so switching layers also switches what you're naming.
        let activeLayerName = Binding(
            get: { preferences.layerName(forKeyboard: keyboard, layer: conn.selectedLayer) ?? "" },
            set: { preferences.setLayerName($0, for: keyboard, layer: conn.selectedLayer) }
        )

        // No outer ScrollView: a vertical scroll wrapper reports a flexible
        // width up the chain, which prevents `.windowResizability(.contentSize)`
        // from sizing the window to the keymap's intrinsic width. A wide
        // keyboard would then get clipped by the default 720pt floor.
        VStack(spacing: 18) {  // default centre alignment

                // Layer picker. Only show when there's more than one layer.
                if conn.keymap.count > 1 {
                    Picker("Layer", selection: $conn.selectedLayer) {
                        ForEach(0 ..< conn.keymap.count, id: \.self) { i in
                            Text(pickerLabel(for: conn, layer: i)).tag(i)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 420)

                    // Single rename field, contextual to whatever layer's
                    // selected. Replaces the previous static list.
                    HStack(spacing: 8) {
                        Text("Name")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        TextField("Base / Numpad / Macros / …", text: activeLayerName)
                            .textFieldStyle(.roundedBorder)
                    }
                    .frame(maxWidth: 420)
                }

                // Keymap viewer: gets the lion's share of the space.
                // .fixedSize on the inner card lets the keyboard's intrinsic
                // width propagate up to the Window scene, which is on
                // .contentSize, so the window grows to fit a full-size board.
                VStack(spacing: 6) {
                    KeyboardLayoutView(
                        layout: layout,
                        layerKeycodes: currentLayerKeycodes(conn),
                        scale: 64,
                        protocolVersion: conn.protocolVersion,
                        interactive: true,
                        forceShowMatrixCoords: true,
                        pressedKeycodes: state.pressedKeycodes
                    )
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(nsColor: .underPageBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(.separator, lineWidth: 1)
                            )
                    )
                    .fixedSize(horizontal: true, vertical: true)

                    Text("Right-click any key to rename its label.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                statsRow(definition: definition, conn: conn, layout: layout)
            }
            .padding(20)
            // No `.frame(maxWidth: .infinity)`; that flag tells SwiftUI
            // "I'll fill any width," which masks the card's intrinsic 1500pt
            // and leaves `.windowResizability(.contentSize)` sizing the
            // window to the 720pt floor instead of the keyboard's real size.
    }

    private func statsRow(definition: KeyboardDefinition, conn: ActiveConnection, layout: KeyboardLayout) -> some View {
        HStack(spacing: 24) {
            stat("Matrix",  "\(definition.rows)×\(definition.cols)")
            stat("Layers",  "\(conn.keymap.count)")
            stat("Keys",    "\(layout.keys.count)")
            stat("VIA",     "v\(conn.protocolVersion)")
            stat("Source",  conn.layoutSource?.displayName ?? "-")
                .help(layoutSourceTooltip(conn.layoutSource))
            liveEventsStat(detected: conn.hasLiveLayerEvents)
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func layoutSourceTooltip(_ source: LayoutSource?) -> String {
        switch source {
        case .viaRegistry:
            return "Layout matched against the bundled VIA keyboards registry by VID:PID."
        case .vialDevice:
            return "Layout fetched live from the keyboard's firmware (Vial)."
        case .userProvided:
            return "Layout overridden by a user-supplied JSON file."
        case nil:
            return ""
        }
    }

    /// Drop-in replacement for the old plain "Live yes/no" stat. When
    /// `detected` is true we render the same monospaced text the other
    /// stats use; when false we make the whole stat clickable and tag it
    /// with a question-mark glyph, so users discover the firmware help
    /// page without us having to add a new banner above the keymap.
    @ViewBuilder
    private func liveEventsStat(detected: Bool) -> some View {
        if detected {
            stat("Live", "Yes")
        } else {
            Button {
                openWindow(id: "firmware-help")
                NSApp.activate()
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text("No")
                            .font(.system(.body, design: .monospaced).weight(.semibold))
                        Image(systemName: "questionmark.circle.fill")
                            .imageScale(.small)
                            .foregroundStyle(.tint)
                    }
                    Text("Live").foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .help("Live layer events not detected. Click to learn how to flash the firmware module.")
            .accessibilityLabel("Live layer events not detected")
            .accessibilityHint("Opens instructions for flashing the firmware module.")
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(.body, design: .monospaced).weight(.semibold))
            Text(label).foregroundStyle(.secondary)
        }
    }

    private func pickerLabel(for conn: ActiveConnection, layer: Int) -> String {
        if let name = preferences.layerName(forKeyboard: conn.keyboard, layer: layer),
           !name.isEmpty {
            return name
        }
        return "Layer \(layer)"
    }

    private func currentLayerKeycodes(_ conn: ActiveConnection) -> [[UInt16]] {
        let i = conn.selectedLayer
        guard conn.keymap.indices.contains(i) else { return [] }
        return conn.keymap[i]
    }

    // MARK: - Lighting tab

    @ViewBuilder
    private var lightingTab: some View {
        if let conn = connection, !conn.menus.isEmpty {
            Form {
                VIAMenuRendererView(nodes: conn.menus, connection: conn)
            }
            .formStyle(.grouped)
        } else if connection != nil {
            tabPlaceholder("This keyboard's VIA definition doesn't declare a lighting menu.")
        } else {
            tabPlaceholder("Connect this keyboard to read its lighting controls.")
        }
    }

    // MARK: - Connection tab

    private var connectionTab: some View {
        @Bindable var preferences = preferences
        let isAuto = Binding(
            get: { preferences.shouldAutoConnect(keyboard) },
            set: { state.setAutoConnect($0, for: keyboard) }
        )

        return Form {
            Section("Status") {
                LabeledContent("Keyboard")  { Text(keyboard.info.product ?? "-") }
                LabeledContent("VID:PID")   { Text(keyboard.info.displayVIDPID).monospaced() }
                LabeledContent("Kind")      { Text(keyboard.kind.label) }
                LabeledContent("State")     {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(connection != nil ? .green : .secondary.opacity(0.5))
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                        Text(connection != nil ? "Connected" : "Not connected")
                    }
                }
                if let conn = connection {
                    LabeledContent("Protocol")    { Text("VIA v\(conn.protocolVersion)") }
                    LabeledContent("Live events") { Text(conn.hasLiveLayerEvents ? "Streaming" : "Idle") }
                }
            }

            Section("Auto-connect") {
                Toggle("Connect automatically when this keyboard is plugged in", isOn: isAuto)
            }

            layoutSourceSection

            Section {
                HStack {
                    Spacer()
                    if connection != nil {
                        Button("Disconnect") {
                            state.disconnect(keyboard.info.registryPath)
                        }
                    } else {
                        Button("Connect") {
                            Task { await state.connect(to: keyboard) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Layout-source picker. Auto means "Vial firmware fetch if v9, VIA
    /// registry otherwise"; Custom lets the user point at their own JSON
    /// (handwired boards, prototypes, fixing upstream definitions). The
    /// override path persists keyed by VID:PID.
    @State private var customFilePickerOpen = false

    private var layoutSourceSection: some View {
        @Bindable var preferences = preferences
        let currentPath = preferences.customLayoutPath(forKeyboard: keyboard)

        return Section("Layout source") {
            Picker("Source", selection: Binding(
                get: { currentPath != nil ? "custom" : "auto" },
                set: { newValue in
                    if newValue == "auto" {
                        preferences.setCustomLayoutPath(nil, for: keyboard)
                        reconnectAfterLayoutChange()
                    } else {
                        customFilePickerOpen = true
                    }
                }
            )) {
                Text("Auto (registry / device)").tag("auto")
                Text("Custom file…").tag("custom")
            }
            .pickerStyle(.menu)

            if let path = currentPath {
                LabeledContent("File") {
                    Text(path.lastPathComponent)
                        .font(.callout)
                        .truncationMode(.middle)
                        .help(path.path)
                }
                HStack {
                    Spacer()
                    Button("Choose Different File…") {
                        customFilePickerOpen = true
                    }
                    Button("Reset to Auto") {
                        preferences.setCustomLayoutPath(nil, for: keyboard)
                        reconnectAfterLayoutChange()
                    }
                }
            } else {
                Text("Loaded from the bundled VIA registry by VID:PID, or fetched live from the keyboard's firmware on Vial boards.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .fileImporter(
            isPresented: $customFilePickerOpen,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            preferences.setCustomLayoutPath(url, for: keyboard)
            reconnectAfterLayoutChange()
        }
    }

    /// Re-connect the keyboard so the override (or its absence) takes
    /// effect. Layout is only read at bootstrap, so flipping the source
    /// requires a fresh connect.
    private func reconnectAfterLayoutChange() {
        let path = keyboard.info.registryPath
        if state.connections[path] != nil {
            state.disconnect(path)
        }
        Task { await state.connect(to: keyboard) }
    }

    // MARK: - Helpers

    private func tabPlaceholder(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
