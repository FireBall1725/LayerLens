import Foundation

/// Parses QMK `info.json` / `keyboard.json` (the format produced by
/// `qmk info -kb <kb> -m -f json`). Each key in `layouts.<name>.layout[]`
/// carries its own matrix coords and absolute position, much simpler than
/// KLE's stateful row walk.
public enum QMKInfoParser {

    public static func parseDefinition(fileAt path: String) throws -> KeyboardDefinition {
        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            throw LayoutError.fileNotReadable(path: path, underlying: "\(error)")
        }
        return try parseDefinition(data: data)
    }

    public static func parseDefinition(data: Data) throws -> KeyboardDefinition {
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw LayoutError.malformedJSON("\(error)")
        }
        return try parseDefinition(json)
    }

    public static func parseDefinition(_ json: Any) throws -> KeyboardDefinition {
        guard let root = json as? [String: Any] else {
            throw LayoutError.typeMismatch("root", expected: "object")
        }

        guard let rawLayouts = root["layouts"] as? [String: Any] else {
            throw LayoutError.missingField("layouts")
        }

        var layouts: [KeyboardLayout] = []
        for (name, raw) in rawLayouts {
            guard let layoutObj = raw as? [String: Any] else { continue }
            let keys = try collectLayoutKeys(layoutObj)
            layouts.append(KeyboardLayout(name: name, keys: keys))
        }
        layouts.sort { $0.name < $1.name } // stable order

        let isSplit = (root["split"] as? [String: Any])?["enabled"] as? Bool ?? false
        let rowMultiplier = isSplit ? 2 : 1

        guard let matrixPins = root["matrix_pins"] as? [String: Any] else {
            throw LayoutError.missingField("matrix_pins")
        }
        guard let rowsArray = matrixPins["rows"] as? [Any] else {
            throw LayoutError.missingField("matrix_pins.rows")
        }
        guard let colsArray = matrixPins["cols"] as? [Any] else {
            throw LayoutError.missingField("matrix_pins.cols")
        }

        let rows = rowsArray.count * rowMultiplier
        let cols = colsArray.count

        guard let usb = root["usb"] as? [String: Any] else {
            throw LayoutError.missingField("usb")
        }
        let vid = try parseHex16(usb["vid"], field: "usb.vid")
        let pid = try parseHex16(usb["pid"], field: "usb.pid")

        return KeyboardDefinition(
            vendorID: vid,
            productID: pid,
            rows: rows,
            cols: cols,
            layouts: layouts
        )
    }

    private static func collectLayoutKeys(_ layout: [String: Any]) throws -> [LayoutKey] {
        guard let layoutArray = layout["layout"] as? [[String: Any]] else {
            throw LayoutError.missingField("layout")
        }

        var keys: [LayoutKey] = []
        for key in layoutArray {
            guard let matrix = key["matrix"] as? [Any], matrix.count >= 2,
                  let row = (matrix[0] as? NSNumber)?.intValue,
                  let col = (matrix[1] as? NSNumber)?.intValue else {
                throw LayoutError.missingField("matrix")
            }

            let x = (key["x"] as? NSNumber)?.doubleValue ?? 0
            let y = (key["y"] as? NSNumber)?.doubleValue ?? 0
            let w = (key["w"] as? NSNumber)?.doubleValue ?? 1
            let h = (key["h"] as? NSNumber)?.doubleValue ?? 1

            let angle = (key["r"] as? NSNumber)?.doubleValue ?? 0
            let pivotX = (key["rx"] as? NSNumber)?.doubleValue ?? x
            let pivotY = (key["ry"] as? NSNumber)?.doubleValue ?? y

            let (fx, fy) = LayoutGeometry.flattenedTopLeftAfterCenterRotation(
                x: x, y: y, w: w, h: h,
                angleDegrees: angle,
                pivotX: pivotX,
                pivotY: pivotY
            )

            keys.append(LayoutKey(row: row, col: col, x: fx, y: fy, w: w, h: h))
        }
        return keys
    }

    private static func parseHex16(_ raw: Any?, field: String) throws -> UInt16 {
        if let s = raw as? String {
            let cleaned = s.hasPrefix("0x") || s.hasPrefix("0X") ? String(s.dropFirst(2)) : s
            guard let v = UInt16(cleaned, radix: 16) else {
                throw LayoutError.invalidHexNumber(s)
            }
            return v
        }
        throw LayoutError.missingField(field)
    }
}
