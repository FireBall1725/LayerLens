import SwiftUI
import LayerLensCore

/// Renders the keyboard's VIA `menus` definition as a SwiftUI form section,
/// wired to live VIA `customGetValue` / `customSetValue` / `customSave`
/// round-trips. Intended for embedding inside `KeyboardConfigView`'s
/// "Lighting & RGB" area.
///
/// **Slider write strategy.** Slider drags fire `customSetValue` live so
/// the keyboard's lighting reacts in real time, but `customSave` (which
/// writes to EEPROM) only fires when the user *releases* the slider. The
/// previous "save on every tick" pattern was burning flash on every drag
/// and saturating the Raw HID pipe. Discrete controls (dropdown, color
/// picker) save inline, since each interaction is a single value change
/// rather than a continuous stream.
@MainActor
struct VIAMenuRendererView: View {
    let nodes: [VIAMenuNode]
    let connection: ActiveConnection

    /// Live in-memory state of every control's current value. Keyed by VIA
    /// identifier (`id_qmk_rgblight_brightness`, etc.). Numeric values for
    /// ranges/dropdowns, packed Color for colour pickers.
    @State private var values: [String: ControlValue] = [:]

    var body: some View {
        Group {
            ForEach(nodes) { node in
                renderNode(node)
            }
        }
        .task(id: connection.id) {
            // Re-read on every connection-id change. No `didLoad` guard so a
            // disconnect/reconnect re-syncs to whatever the firmware actually
            // has now (user may have changed it from another tool while we
            // were disconnected).
            await loadAllValues()
        }
    }

    /// Recursive function that needs a type-erased return because SwiftUI's
    /// opaque-return inference can't handle a function that calls itself.
    private func renderNode(_ node: VIAMenuNode) -> AnyView {
        switch node {
        case .section(let s):
            return AnyView(
                Section(s.label) {
                    ForEach(s.children) { child in
                        renderNode(child)
                    }
                }
            )
        case .control(let c):
            return AnyView(
                Group {
                    if shouldShow(c) { renderControl(c) }
                }
            )
        }
    }

    @ViewBuilder
    private func renderControl(_ c: VIAMenuControl) -> some View {
        switch c.kind {
        case .range:    rangeControl(c)
        case .dropdown: dropdownControl(c)
        case .colour:   colourControl(c)
        case .unknown:
            LabeledContent(c.label) {
                Text("(unsupported \(c.kind.rawValue))")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Range slider

    private func rangeControl(_ c: VIAMenuControl) -> some View {
        let lo = Double(c.options.first ?? 0)
        let hi = Double(c.options.dropFirst().first ?? 255)
        let current = (values[c.identifier]?.scalar).map(Double.init) ?? lo

        return LabeledContent(c.label) {
            HStack {
                Slider(
                    value: Binding(
                        get: { current },
                        set: { newVal in
                            let int = Int(newVal.rounded())
                            values[c.identifier] = .scalar(int)
                            // Live preview only; no save until the user
                            // releases. Skips burning EEPROM on every tick.
                            writeValue(c, bytes: [UInt8(truncatingIfNeeded: int)])
                        }
                    ),
                    in: lo ... hi,
                    onEditingChanged: { editing in
                        if !editing { saveControl(c) }
                    }
                )
                Text("\(Int(current))")
                    .monospacedDigit()
                    .frame(minWidth: 44, alignment: .trailing)
            }
            .accessibilityLabel(c.label)
            .accessibilityValue("\(Int(current))")
        }
    }

    // MARK: - Dropdown

    private func dropdownControl(_ c: VIAMenuControl) -> some View {
        let current = values[c.identifier]?.scalar ?? 0
        return LabeledContent(c.label) {
            // Pass the visible label as the Picker's accessibility label,
            // then hide it visually so the LabeledContent layout owns the
            // text. Without this, VoiceOver announces "" for the picker.
            Picker(c.label, selection: Binding(
                get: { current },
                set: { newVal in
                    values[c.identifier] = .scalar(newVal)
                    writeAndSave(c, bytes: [UInt8(truncatingIfNeeded: newVal)])
                }
            )) {
                if c.dropdownOptions.isEmpty {
                    let count = c.options.first ?? 0
                    ForEach(0 ..< max(count, 1), id: \.self) { i in
                        Text("Mode \(i)").tag(i)
                    }
                } else {
                    ForEach(Array(c.dropdownOptions.enumerated()), id: \.offset) { i, name in
                        Text(name).tag(i)
                    }
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    // MARK: - Color (HSV: hue, sat)

    private func colourControl(_ c: VIAMenuControl) -> some View {
        // VIA colour values are a 2-byte (hue, sat) tuple. Value never reaches
        // the lighting subsystem, the brightness slider controls it. We keep
        // the SwiftUI ColorPicker bound to a Color in HSB space, with V locked
        // at 1.0 so the picked hue is preserved when the user drags it.
        let hs = values[c.identifier]?.hueSat ?? (h: 0, s: 0)
        return LabeledContent(c.label) {
            ColorPicker(
                c.label,
                selection: Binding(
                    get: { Color(hue: Double(hs.h) / 255.0, saturation: Double(hs.s) / 255.0, brightness: 1.0) },
                    set: { newColor in
                        let (h, s) = packToHueSat(newColor)
                        values[c.identifier] = .hueSat(h: h, s: s)
                        writeAndSave(c, bytes: [h, s])
                    }
                ),
                supportsOpacity: false
            )
            .labelsHidden()
        }
    }

    private func packToHueSat(_ c: Color) -> (UInt8, UInt8) {
        let ns = NSColor(c).usingColorSpace(.sRGB) ?? NSColor.black
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return (UInt8((h * 255).rounded()), UInt8((s * 255).rounded()))
    }

    // MARK: - showIf evaluation

    /// Tiny evaluator for VIA's `showIf` strings. Handles the common shapes:
    ///   `{id} != 0`,  `{id} == N`,  `{a} != 0 && {b} != 1`
    /// Returns `true` when the expression's missing or evaluates true; we err
    /// toward showing controls when in doubt.
    private func shouldShow(_ c: VIAMenuControl) -> Bool {
        guard let raw = c.showIf, !raw.isEmpty else { return true }
        // Split on `&&`; every clause must hold.
        let clauses = raw.components(separatedBy: "&&").map { $0.trimmingCharacters(in: .whitespaces) }
        for clause in clauses {
            if !evaluate(clause) { return false }
        }
        return true
    }

    private func evaluate(_ clause: String) -> Bool {
        // Match `{ident} OP num`
        let pattern = #"^\{([a-zA-Z0-9_]+)\}\s*(==|!=|<=|>=|<|>)\s*(\d+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: clause, range: NSRange(clause.startIndex..., in: clause)),
              m.numberOfRanges == 4 else {
            return true
        }
        let s = clause as NSString
        let identifier = s.substring(with: m.range(at: 1))
        let op = s.substring(with: m.range(at: 2))
        let target = Int(s.substring(with: m.range(at: 3))) ?? 0
        let actual = values[identifier]?.scalar ?? 0
        switch op {
        case "==": return actual == target
        case "!=": return actual != target
        case "<":  return actual <  target
        case "<=": return actual <= target
        case ">":  return actual >  target
        case ">=": return actual >= target
        default:   return true
        }
    }

    // MARK: - Reads / writes

    private func loadAllValues() async {
        let controls = collectControls(nodes)
        for c in controls {
            do {
                let bytes: [UInt8]
                switch c.kind {
                case .colour:
                    bytes = try await readControl(c, lengthHint: 2)
                    values[c.identifier] = .hueSat(h: bytes.first ?? 0, s: bytes.dropFirst().first ?? 0)
                case .range, .dropdown:
                    bytes = try await readControl(c, lengthHint: 1)
                    values[c.identifier] = .scalar(Int(bytes.first ?? 0))
                case .unknown:
                    continue
                }
            } catch {
                // Per-control read failure shouldn't kill the whole UI;
                // leave the value at its default.
                continue
            }
        }
    }

    private func readControl(_ c: VIAMenuControl, lengthHint: Int) async throws -> [UInt8] {
        if c.useLegacyLighting {
            return try await connection.via.legacyLightingGetValue(valueID: c.valueID, lengthHint: lengthHint)
        }
        return try await connection.via.customGetValue(channel: c.channel, valueID: c.valueID, lengthHint: lengthHint)
    }

    private func collectControls(_ nodes: [VIAMenuNode]) -> [VIAMenuControl] {
        var out: [VIAMenuControl] = []
        for n in nodes {
            switch n {
            case .control(let c): out.append(c)
            case .section(let s): out.append(contentsOf: collectControls(s.children))
            }
        }
        return out
    }

    /// Send a `customSetValue` (or legacy equivalent) without saving to
    /// EEPROM. Used by sliders during a drag; the keyboard's runtime
    /// state changes immediately so the lighting reacts, but flash isn't
    /// touched until the user releases.
    private func writeValue(_ c: VIAMenuControl, bytes: [UInt8]) {
        let channel = c.channel
        let valueID = c.valueID
        let legacy  = c.useLegacyLighting
        Task { [via = connection.via] in
            if legacy {
                try? await via.legacyLightingSetValue(valueID: valueID, bytes: bytes)
            } else {
                try? await via.customSetValue(channel: channel, valueID: valueID, bytes: bytes)
            }
        }
    }

    /// Send a `customSave` (or legacy equivalent) to commit whatever the
    /// runtime state currently is into EEPROM. Used as the slider's
    /// release callback.
    private func saveControl(_ c: VIAMenuControl) {
        let channel = c.channel
        let legacy = c.useLegacyLighting
        Task { [via = connection.via] in
            if legacy {
                try? await via.legacyLightingSave()
            } else {
                try? await via.customSave(channel: channel)
            }
        }
    }

    /// Set + save in one shot, for discrete controls (dropdown, colour
    /// picker) whose interactions are single value changes rather than
    /// continuous streams.
    private func writeAndSave(_ c: VIAMenuControl, bytes: [UInt8]) {
        let channel = c.channel
        let valueID = c.valueID
        let legacy  = c.useLegacyLighting
        Task { [via = connection.via] in
            if legacy {
                try? await via.legacyLightingSetValue(valueID: valueID, bytes: bytes)
                try? await via.legacyLightingSave()
            } else {
                try? await via.customSetValue(channel: channel, valueID: valueID, bytes: bytes)
                try? await via.customSave(channel: channel)
            }
        }
    }

    // MARK: - Storage

    private enum ControlValue {
        case scalar(Int)
        case hueSat(h: UInt8, s: UInt8)

        var scalar: Int? {
            if case .scalar(let v) = self { return v }
            return nil
        }
        var hueSat: (h: UInt8, s: UInt8)? {
            if case .hueSat(let h, let s) = self { return (h, s) }
            return nil
        }
    }
}
