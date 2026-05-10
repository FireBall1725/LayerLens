import Foundation

/// Parses KLE-style layout JSON used by VIA (`v3/<...>.json` from the
/// the-via/keyboards repo) and Vial keymap definitions.
///
/// KLE format (https://github.com/ijprest/kle-serial): the top-level layout
/// is an array of rows, each row an array of items that are either
/// property-modifier objects (`{x, y, w, h, r, rx, ry, ...}`) or string labels
/// containing the matrix coordinate as the first line ("row,col").
public enum KLEParser {

    /// Parse a VIA / Vial keyboard JSON definition (top-level object with
    /// `matrix`, `layouts.keymap`, and optionally `vendorId`/`productId`).
    /// Pass `vid`/`pid` overrides for Vial blobs which omit them.
    public static func parseDefinition(
        _ json: Any,
        vendorIDOverride: UInt16? = nil,
        productIDOverride: UInt16? = nil
    ) throws -> KeyboardDefinition {
        guard let root = json as? [String: Any] else {
            throw LayoutError.typeMismatch("root", expected: "object")
        }

        guard let matrix = root["matrix"] as? [String: Any] else {
            throw LayoutError.missingField("matrix")
        }
        guard let rows = (matrix["rows"] as? NSNumber)?.intValue else {
            throw LayoutError.missingField("matrix.rows")
        }
        guard let cols = (matrix["cols"] as? NSNumber)?.intValue else {
            throw LayoutError.missingField("matrix.cols")
        }

        guard let layouts = root["layouts"] as? [String: Any] else {
            throw LayoutError.missingField("layouts")
        }
        guard let keymap = layouts["keymap"] as? [Any] else {
            throw LayoutError.missingField("layouts.keymap")
        }

        // `layouts.labels` declares alt-layout groups. Each entry is either a
        // string (binary toggle) or an array (multi-option). Bare labels in
        // the keymap that look like "GROUP,OPTION" are selector pseudo-keys
        // (VIA renders them as toggle UI above the keyboard), NOT real
        // matrix positions. We pass the labels through so parseKeymap can
        // skip them; otherwise they collide with real matrix coords and
        // float around the keyboard rendering.
        let labels = layouts["labels"] as? [Any] ?? []
        let keys = parseKeymap(keymap, altLayoutLabels: labels)
        let layout = KeyboardLayout(name: "default", keys: keys)

        let vid = try vendorIDOverride ?? extractHexID(root["vendorId"], field: "vendorId")
        let pid = try productIDOverride ?? extractHexID(root["productId"], field: "productId")

        return KeyboardDefinition(
            vendorID: vid,
            productID: pid,
            rows: rows,
            cols: cols,
            layouts: [layout]
        )
    }

    /// Parse just the `keymap` array (an array-of-arrays) into LayoutKeys.
    /// Exposed so callers that already have the array (e.g. tests, Vial)
    /// can skip the wrapper. `altLayoutLabels` is the contents of the
    /// sibling `layouts.labels` field (or empty); used to recognise and
    /// skip selector pseudo-keys whose group index matches a labels entry.
    public static func parseKeymap(
        _ keymap: [Any],
        altLayoutLabels: [Any] = []
    ) -> [LayoutKey] {
        // Build per-group option counts so we know exactly which "G,O" pairs
        // are selectors. Each entry in labels is either:
        //   - String          (binary toggle, 2 options: 0=off, 1=on)
        //   - [String]        (first element is group name, rest are option
        //                      labels; option count = array.count - 1)
        let altOptionCounts: [Int] = altLayoutLabels.map { entry in
            if entry is String { return 2 }
            if let arr = entry as? [Any] { return max(0, arr.count - 1) }
            return 0
        }
        var keys: [LayoutKey] = []
        var currentY: Double = 0
        var rotationAngle: Double = 0
        var rotationX: Double = 0
        var rotationY: Double = 0

        for row in keymap {
            guard let rowArray = row as? [Any] else { continue }

            var currentX: Double = 0
            var currentW: Double = 1
            var currentH: Double = 1

            for item in rowArray {
                if let obj = item as? [String: Any] {
                    if let rx = (obj["rx"] as? NSNumber)?.doubleValue {
                        rotationX = rx
                        currentX = 0  // reset relative to new rotation origin
                        currentY = 0
                    }
                    if let ry = (obj["ry"] as? NSNumber)?.doubleValue {
                        rotationY = ry
                        currentY = 0
                    }
                    if let r = (obj["r"] as? NSNumber)?.doubleValue {
                        rotationAngle = r
                    }
                    if let w = (obj["w"] as? NSNumber)?.doubleValue {
                        currentW = w
                    }
                    if let h = (obj["h"] as? NSNumber)?.doubleValue {
                        currentH = h
                    }
                    if let x = (obj["x"] as? NSNumber)?.doubleValue {
                        currentX += x
                    }
                    if let y = (obj["y"] as? NSNumber)?.doubleValue {
                        currentY += y
                    }
                } else if let label = item as? String {
                    // Bare single-line "GROUP,OPTION" labels whose group
                    // indexes into layouts.labels are *selector pseudo-keys*
                    // (VIA renders them as toggle UI above the keyboard).
                    // Skip them: they're not real matrix positions and
                    // would otherwise collide with row/col coords like (0,0).
                    if isAltLayoutSelector(label, optionCounts: altOptionCounts) {
                        currentX += currentW
                        currentW = 1
                        currentH = 1
                        continue
                    }

                    let altOption = altLayoutOption(label)
                    // Render only ungrouped keys + option 0 of each alt-layout
                    // group. KLE marks alt-layout candidates in the front-bottom-
                    // left label slot ("GROUP,OPTION" on line 4 of the multi-line
                    // label); VIA's web app reads `layout_options` from firmware
                    // to pick which option per group to render. Until that wires
                    // through (task #9 / a follow-up), defaulting to option 0
                    // matches VIA's first-paint behaviour and keeps split-board
                    // thumb clusters from drawing 2× over each other.
                    let isDefault = altOption == nil || altOption!.option == 0
                    if isDefault, let (row, col) = parseMatrixLabel(label) {
                        let absoluteX = rotationX + currentX
                        let absoluteY = rotationY + currentY
                        let (finalX, finalY) = LayoutGeometry.flattenedTopLeftAfterCenterRotation(
                            x: absoluteX,
                            y: absoluteY,
                            w: currentW,
                            h: currentH,
                            angleDegrees: rotationAngle,
                            pivotX: rotationX,
                            pivotY: rotationY
                        )
                        keys.append(LayoutKey(
                            row: row, col: col,
                            x: finalX, y: finalY,
                            w: currentW, h: currentH,
                            rotation: rotationAngle
                        ))
                    }
                    currentX += currentW
                    currentW = 1
                    currentH = 1
                }
            }

            // Always advance y by 1 at the end of a row. This matches
            // kle-serial's reference behaviour. Explicit `y:` offsets in
            // the next row stack on top of this advance, so rotated thumb
            // clusters with `y: -2` end up exactly where KLE expects them.
            // The previous "skip when rotated" gate was the reason Kyria's
            // thumb keys floated in the middle of the layout.
            currentY += 1
        }

        return keys
    }

    /// True for bare "GROUP,OPTION" labels that are alt-layout selector
    /// pseudo-keys, not real matrix positions. The discriminator is *both*
    /// numbers: the group index must point into `optionCounts`, AND the
    /// option index must be within that group's range. Real matrix coords
    /// like `(0,7)` on an 8x8 board with 4 binary-toggle groups would have
    /// G=0 (a valid group) but O=7 (way past the 2-option range), so they
    /// pass through correctly.
    ///
    /// On most non-split keyboards `optionCounts.isEmpty` and this always
    /// returns false, leaving real keymap labels untouched.
    private static func isAltLayoutSelector(
        _ label: String,
        optionCounts: [Int]
    ) -> Bool {
        guard !optionCounts.isEmpty else { return false }
        if label.contains("\n") { return false }
        let parts = label.split(separator: ",", maxSplits: 1).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard parts.count == 2,
              let group = Int(parts[0]),
              let option = Int(parts[1]),
              group >= 0, group < optionCounts.count else {
            return false
        }
        return option >= 0 && option < optionCounts[group]
    }

    /// Pull the alt-layout group/option pair out of a KLE label, if any.
    /// KLE labels can have up to 9 lines (one per legend slot); the
    /// 4th line (front bottom-left) is the convention VIA uses for
    /// "GROUP,OPTION" alt-layout markers, e.g. `"3,1\n\n\n0,1"` means
    /// matrix row=3 col=1, alt-layout group 0 option 1. Returns nil
    /// for labels with no alt-layout slot (the common case).
    private static func altLayoutOption(_ label: String) -> (group: Int, option: Int)? {
        let lines = label.split(
            separator: "\n",
            omittingEmptySubsequences: false
        )
        guard lines.count >= 4 else { return nil }
        let alt = lines[3].trimmingCharacters(in: .whitespaces)
        guard !alt.isEmpty else { return nil }
        let parts = alt.split(separator: ",", maxSplits: 1).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard parts.count == 2,
              let group = Int(parts[0]),
              let option = Int(parts[1]) else {
            return nil
        }
        return (group, option)
    }

    private static func parseMatrixLabel(_ label: String) -> (row: Int, col: Int)? {
        let firstLine = label.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first ?? Substring(label)
        let parts = firstLine.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 2,
              let row = Int(parts[0]),
              let col = Int(parts[1]) else {
            return nil
        }
        return (row, col)
    }

    private static func extractHexID(_ raw: Any?, field: String) throws -> UInt16 {
        if let s = raw as? String {
            let cleaned = s.hasPrefix("0x") || s.hasPrefix("0X") ? String(s.dropFirst(2)) : s
            guard let v = UInt16(cleaned, radix: 16) else {
                throw LayoutError.invalidHexNumber(s)
            }
            return v
        }
        if let n = raw as? NSNumber {
            return UInt16(truncatingIfNeeded: n.intValue)
        }
        throw LayoutError.missingField(field)
    }
}
