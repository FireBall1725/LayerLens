import LayerLensCore
import SwiftUI

/// Top-level groupings in the Configure window's keycode picker.
/// `.compose` is the mod-tap / layer-tap builder; the others are flat
/// palettes from `KeycodePalette`.
enum KeycodeCategory: String, CaseIterable, Identifiable, Hashable {
  case basic = "Basic"
  case mods = "Mods"
  case layers = "Layers"
  case media = "Media"
  case compose = "Compose"
  case custom = "Custom"

  var id: String { rawValue }

  var sfSymbol: String {
    switch self {
    case .basic: return "keyboard"
    case .mods: return "command"
    case .layers: return "square.stack.3d.up"
    case .media: return "play.circle"
    case .compose: return "slider.horizontal.3"
    case .custom: return "number"
    }
  }
}

/// Tap-target keycodes offered inside the Compose tab. A trimmed subset of
/// the full Basic palette — the keys people actually map to mod-taps and
/// layer-taps. Keeps the composer grid one screenful instead of scrolling.
let composeTapKeycodes: [UInt16] =
  (Array(UInt16(0x0004) ... 0x001D)  // A..Z
    + Array(UInt16(0x001E) ... 0x0027)  // 1..0
    + [0x0028, 0x0029, 0x002A, 0x002B, 0x002C]  // Enter Esc BSpc Tab Space
    + Array(UInt16(0x002D) ... 0x0038)  // - = [ ] \ ; ' ` , . /
    + [0x004F, 0x0050, 0x0051, 0x0052]  // → ← ↓ ↑
  )

/// Bitmask flags for QMK mod-tap "which modifiers are held."
enum ComposeMod: String, CaseIterable, Identifiable, Hashable {
  case ctrl = "Ctrl"
  case shift = "Shift"
  case alt = "Alt"
  case cmd = "Cmd"

  var id: String { rawValue }

  /// Left-side bit. Right-side mod-taps OR in 0x10.
  var leftBit: UInt16 {
    switch self {
    case .ctrl: return 0x01
    case .shift: return 0x02
    case .alt: return 0x04
    case .cmd: return 0x08
    }
  }
}

enum ComposeSide: String, CaseIterable, Identifiable, Hashable {
  case left = "Left"
  case right = "Right"
  var id: String { rawValue }
}

enum ComposeMode: String, CaseIterable, Identifiable, Hashable {
  case modTap = "Mod-Tap"
  case layerTap = "Layer-Tap"
  var id: String { rawValue }
}

/// Hand-curated keycode lists per category. Order is display-friendly
/// (visually grouped) rather than strictly by hex value, so the grid
/// reads naturally. Sourced from QMK's HID usage table — the labels
/// themselves come from VIAKeycodeMap at render time.
enum KeycodePalette {
  typealias Group = (label: String, keycodes: [UInt16])

  static let basicGroups: [Group] = [
    ("Letters", Array(UInt16(0x0004) ... 0x001D)),
    ("Numbers", Array(UInt16(0x001E) ... 0x0027)),
    ("Common", [0x0028, 0x0029, 0x002A, 0x002B, 0x002C]),  // Enter Esc BSpc Tab Space
    ("Punctuation", Array(UInt16(0x002D) ... 0x0038)),
    ("Locks", [0x0039, 0x0053, 0x0047]),  // Caps NumLk ScrLk
    ("F-keys", Array(UInt16(0x003A) ... 0x0045)),
    ("Navigation", [0x0049, 0x004A, 0x004B, 0x004C, 0x004D, 0x004E]),  // Ins Home PgUp Del End PgDn
    ("Arrows", [0x0052, 0x0050, 0x0051, 0x004F]),  // Up Left Down Right
    ("Numpad", Array(UInt16(0x0054) ... 0x0063)),
    ("Special", [0x0046, 0x0048, 0x0000, 0x0001]),  // PrtSc Pause KC_NO KC_TRNS
  ]

  static let modGroups: [Group] = [
    ("Left", [0x00E0, 0x00E1, 0x00E2, 0x00E3]),
    ("Right", [0x00E4, 0x00E5, 0x00E6, 0x00E7]),
  ]

  static let mediaGroups: [Group] = [
    ("Audio", [0x00A8, 0x00A9, 0x00AA]),  // Mute Vol+ Vol-
    ("Transport", [0x00AC, 0x00AB, 0x00AE, 0x00AD, 0x00AF]),  // Prev Next Play Stop Media
    ("Display", [0x00BD, 0x00BE]),  // Bright+ Bright-
  ]

  /// Layer keycodes are dynamic — one entry per available layer per
  /// access mode. The Configure window passes the live layer count.
  static func layerGroups(layerCount: Int, ranges: VIAKeycodeRanges) -> [Group] {
    guard layerCount > 0 else { return [] }
    let n = UInt16(min(layerCount, 16))  // 16 is plenty; keeps the grid sane

    func sequence(from start: UInt16) -> [UInt16] {
      (0 ..< n).map { start + $0 }
    }

    return [
      ("MO — momentary", sequence(from: ranges.momentary.lowerBound)),
      ("TG — toggle", sequence(from: ranges.toggleLayer.lowerBound)),
      ("TO — go to", sequence(from: ranges.toLayer.lowerBound)),
      ("DF — default", sequence(from: ranges.defaultLayer.lowerBound)),
      ("OSL — one-shot", sequence(from: ranges.oneShotLayer.lowerBound)),
      ("TT — tap-toggle", sequence(from: ranges.layerTapToggle.lowerBound)),
    ]
  }
}

/// The right-side picker panel inside the Configure window's Keymap tab.
/// Reads `connection.selectedKey` to know what's being edited; calls
/// `onPick` with a chosen UInt16 keycode (the parent decides what to do
/// with it — typically a `setKeycode` write via the connection).
struct KeycodePickerView: View {
  let connection: ActiveConnection
  let onPick: (UInt16) -> Void

  @State private var category: KeycodeCategory = .basic
  @State private var searchQuery: String = ""
  // Composer state. Lives at the picker level so it survives category
  // round-trips (user can poke around Basic, come back to Compose, and
  // their in-progress mod-tap is still there).
  @State private var composeMode: ComposeMode = .modTap
  @State private var composeSelectedMods: Set<ComposeMod> = [.ctrl]
  @State private var composeSide: ComposeSide = .left
  @State private var composeLayer: Int = 1
  @State private var composeTap: UInt16 = 0x0004  // KC_A
  @State private var customInput: String = ""

  private var protocolVersion: UInt16 { connection.protocolVersion }

  private var ranges: VIAKeycodeRanges? {
    VIAKeycodeMap.map(forProtocolVersion: protocolVersion)?.ranges
  }

  /// Keycode currently assigned at the selected matrix position. Used to
  /// highlight the matching button in the palette.
  private var currentKeycode: UInt16? {
    guard let sel = connection.selectedKey else { return nil }
    let layer = connection.selectedLayer
    guard connection.keymap.indices.contains(layer),
      connection.keymap[layer].indices.contains(sel.row),
      connection.keymap[layer][sel.row].indices.contains(sel.col)
    else { return nil }
    return connection.keymap[layer][sel.row][sel.col]
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Picker("Category", selection: $category) {
        ForEach(KeycodeCategory.allCases) { c in
          Text(c.rawValue).tag(c)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()

      if category == .compose {
        composerView
      } else if category == .custom {
        customInputView
      } else {
        HStack(spacing: 6) {
          Image(systemName: "magnifyingglass")
            .foregroundStyle(.tertiary)
            .font(.caption)
          TextField("Search", text: $searchQuery)
            .textFieldStyle(.plain)
            .font(.caption)
          if !searchQuery.isEmpty {
            Button {
              searchQuery = ""
            } label: {
              Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
          RoundedRectangle(cornerRadius: 6)
            .fill(Color(nsColor: .controlBackgroundColor))
        )

        ScrollView {
          VStack(alignment: .leading, spacing: 14) {
            if searchQuery.isEmpty,
              !connection.recentKeycodes.isEmpty
            {
              keycodeGroupView(
                (
                  label: "Recent",
                  keycodes: connection.recentKeycodes
                )
              )
            }

            ForEach(filteredGroups, id: \.label) { group in
              keycodeGroupView(group)
            }

            if filteredGroups.isEmpty, !searchQuery.isEmpty {
              Text("No keycodes match “\(searchQuery)”")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 16)
            }
          }
          .padding(.vertical, 4)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
  }

  /// Apply the search filter (when non-empty) to the current category's
  /// groups. Matches keycode labels case-insensitively.
  private var filteredGroups: [KeycodePalette.Group] {
    let raw = groups(for: category)
    let query = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
    guard !query.isEmpty else { return raw }
    return raw.compactMap { group in
      let matched = group.keycodes.filter {
        label(for: $0).lowercased().contains(query)
      }
      return matched.isEmpty ? nil : (label: group.label, keycodes: matched)
    }
  }

  // MARK: - Custom (raw hex / decimal input)

  @ViewBuilder
  private var customInputView: some View {
    let parsed = parseCustomInput(customInput)
    VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: 6) {
        Text("Raw keycode")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        TextField("KC_A  ·  0x6104  ·  24836", text: $customInput)
          .textFieldStyle(.roundedBorder)
          .font(.system(size: 13, design: .monospaced))
          .autocorrectionDisabled()
          .onSubmit {
            if let kc = parsed { onPick(kc) }
          }
        Text("QMK name (KC_NO, KC_LCTL, RGB_TOG…), hex (0x…), or decimal. Up to 0xFFFF.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Divider()

      VStack(alignment: .leading, spacing: 6) {
        Text("Preview")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        if let kc = parsed {
          HStack(alignment: .firstTextBaseline) {
            Text(label(for: kc))
              .font(.system(size: 13, weight: .semibold))
            Text(String(format: "0x%04X", kc))
              .font(.caption.monospaced())
              .foregroundStyle(.secondary)
            Spacer()
          }
        } else if customInput.isEmpty {
          Text("Enter a value above.")
            .font(.caption)
            .foregroundStyle(.tertiary)
        } else {
          Text("Not a valid 16-bit keycode.")
            .font(.caption)
            .foregroundStyle(.red)
        }
      }

      Button {
        if let kc = parsed { onPick(kc) }
      } label: {
        Text("Assign to selected key")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.regular)
      .disabled(parsed == nil)

      Spacer(minLength: 0)
    }
    .padding(.vertical, 4)
  }

  /// Parse the Custom-tab input. Tries, in order:
  ///   1. QMK symbolic name (`KC_A`, `KC_LCTL`, `RGB_TOG`, or short `A`)
  ///   2. Hex with `0x` prefix
  ///   3. Decimal (digits only) or hex (when input contains a-f)
  /// Returns nil for empty / unrecognised / out-of-range input.
  private func parseCustomInput(_ raw: String) -> UInt16? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    // QMK names take precedence — they contain underscores or
    // non-hex letters (KC_NO, RGB_TOG, …) which the numeric paths
    // would reject anyway, but checking first means a bare "A" also
    // resolves to KC_A (0x0004) instead of being read as hex 0xA.
    if let kc = VIAKeycodeMap.keycode(forName: trimmed) {
      return kc
    }

    let lower = trimmed.lowercased()
    let stripped: String
    let radix: Int
    if lower.hasPrefix("0x") {
      stripped = String(lower.dropFirst(2))
      radix = 16
    } else if lower.contains(where: { "abcdef".contains($0) }) {
      stripped = lower
      radix = 16
    } else {
      stripped = lower
      radix = 10
    }

    guard let value = UInt32(stripped, radix: radix),
      value <= UInt32(UInt16.max)
    else { return nil }
    return UInt16(value)
  }

  // MARK: - Composer (mod-tap / layer-tap builder)

  @ViewBuilder
  private var composerView: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        Picker("Mode", selection: $composeMode) {
          ForEach(ComposeMode.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()

        holdSection
        Divider()
        tapSection
        Divider()
        previewAndApply
      }
      .padding(.vertical, 4)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  @ViewBuilder
  private var holdSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Hold")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)

      switch composeMode {
      case .modTap:
        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 56, maximum: 80), spacing: 4)],
          alignment: .leading,
          spacing: 4
        ) {
          ForEach(ComposeMod.allCases) { mod in
            Toggle(
              isOn: Binding(
                get: { composeSelectedMods.contains(mod) },
                set: { keep in
                  if keep { composeSelectedMods.insert(mod) } else { composeSelectedMods.remove(mod) }
                }
              )
            ) {
              Text(mod.rawValue).font(.system(size: 11, weight: .semibold))
            }
            .toggleStyle(.button)
            .controlSize(.small)
          }
        }
        Picker("Side", selection: $composeSide) {
          ForEach(ComposeSide.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()

      case .layerTap:
        Picker("Layer", selection: $composeLayer) {
          let max = min(max(connection.keymap.count, 1), 16)
          ForEach(0 ..< max, id: \.self) { i in
            Text("Layer \(i)").tag(i)
          }
        }
        .pickerStyle(.menu)
        .labelsHidden()
      }
    }
  }

  @ViewBuilder
  private var tapSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Tap")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)

      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 38, maximum: 60), spacing: 3)],
        alignment: .leading,
        spacing: 3
      ) {
        ForEach(composeTapKeycodes, id: \.self) { kc in
          KeycodeButton(
            keycode: kc,
            label: label(for: kc),
            isCurrent: kc == composeTap,
            onTap: { composeTap = kc }
          )
        }
      }
    }
  }

  @ViewBuilder
  private var previewAndApply: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Preview")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)

      HStack(alignment: .firstTextBaseline) {
        if let composed = encodedCompose {
          Text(label(for: composed))
            .font(.system(size: 13, weight: .semibold))
          Text(String(format: "0x%04X", composed))
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
          Spacer()
        } else {
          Text("Composite keycode out of range for this protocol.")
            .font(.caption)
            .foregroundStyle(.red)
          Spacer()
        }
      }

      Button {
        if let composed = encodedCompose {
          onPick(composed)
        }
      } label: {
        Text("Assign to selected key")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.regular)
      .disabled(encodedCompose == nil)
    }
  }

  /// Encode the current composer settings as a UInt16. Returns nil when
  /// the result would fall outside the connected board's mod-tap or
  /// layer-tap range — typically only when the user picks a tap keycode
  /// > 0xFF, which the composeTapKeycodes list already avoids.
  private var encodedCompose: UInt16? {
    guard let ranges else { return nil }
    guard composeTap <= 0xFF else { return nil }
    let base = composeTap
    switch composeMode {
    case .modTap:
      var mask: UInt16 = 0
      for mod in composeSelectedMods { mask |= mod.leftBit }
      if composeSide == .right { mask |= 0x10 }
      let composite = ranges.modTap.lowerBound + (mask << 8) + base
      return ranges.modTap.contains(composite) ? composite : nil
    case .layerTap:
      let layer = UInt16(composeLayer)
      let composite = ranges.layerTap.lowerBound + (layer << 8) + base
      return ranges.layerTap.contains(composite) ? composite : nil
    }
  }

  private func groups(for category: KeycodeCategory) -> [KeycodePalette.Group] {
    switch category {
    case .basic: return KeycodePalette.basicGroups
    case .mods: return KeycodePalette.modGroups
    case .media: return KeycodePalette.mediaGroups
    case .layers:
      guard let ranges else { return [] }
      return KeycodePalette.layerGroups(layerCount: connection.keymap.count, ranges: ranges)
    case .compose, .custom:
      // Both have dedicated views (not group-based).
      return []
    }
  }

  private func keycodeGroupView(_ group: KeycodePalette.Group) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(group.label)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 52, maximum: 80), spacing: 4)],
        alignment: .leading,
        spacing: 4
      ) {
        ForEach(group.keycodes, id: \.self) { kc in
          KeycodeButton(
            keycode: kc,
            label: label(for: kc),
            isCurrent: kc == currentKeycode,
            onTap: { onPick(kc) }
          )
        }
      }
    }
  }

  private func label(for kc: UInt16) -> String {
    if kc == 0x0000 { return "—" }
    if kc == 0x0001 { return "▽" }
    if let macGlyph = MacKeySymbols.symbol(for: kc) {
      return macGlyph
    }
    if let l = QMKKeycodeFormatter.label(for: kc, protocolVersion: protocolVersion),
      !l.tap.isEmpty
    {
      return l.tap
    }
    return String(format: "0x%04X", kc)
  }
}

private struct KeycodeButton: View {
  let keycode: UInt16
  let label: String
  let isCurrent: Bool
  let onTap: () -> Void

  var body: some View {
    Button(action: onTap) {
      Text(label)
        .font(.system(size: 11, weight: .semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.55)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .background(
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(
              isCurrent
                ? AnyShapeStyle(Color.accentColor.opacity(0.22))
                : AnyShapeStyle(Color(nsColor: .controlBackgroundColor)))
        )
        .overlay(
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .stroke(
              isCurrent ? Color.accentColor : Color.primary.opacity(0.12),
              lineWidth: isCurrent ? 1.5 : 1
            )
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help("\(label)  \(String(format: "0x%04X", keycode))")
  }
}
