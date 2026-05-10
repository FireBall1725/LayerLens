import Foundation
import LayerLensCore

@main
struct Probe {
    static func main() async {
        let keyboards = HIDEnumerator.discoverKeyboards()

        if keyboards.isEmpty {
            print("No Raw-HID keyboards found (usage page 0x\(hex16(RawHIDConstants.viaUsagePage)), usage 0x\(hex8(RawHIDConstants.viaUsage))).")
            print("Make sure VIA/Vial Raw HID is enabled in firmware and the device is connected.")
            return
        }

        print("Found \(keyboards.count) keyboard(s):\n")
        for kb in keyboards {
            print("  \(kb.displayName)")
            print("    vendor:       \(kb.info.manufacturer ?? "-")")
            print("    product:      \(kb.info.product ?? "-")")
            print("    serial:       \(kb.info.serialNumber ?? "-")")
            print("    usagePage/usage: 0x\(hex16(kb.info.usagePage))/0x\(hex8(kb.info.usage))")
            print("")
        }

        guard let first = keyboards.first,
              let raw = HIDEnumerator.resolveDevice(for: first) else {
            print("Could not resolve IOHIDDevice for the first keyboard.")
            return
        }

        let device = HIDDevice(device: raw)
        do { try device.open() } catch {
            print("Open failed: \(error)"); return
        }
        defer { device.close() }

        let client = VIAClient(transport: device)

        do {
            let version = try await client.protocolVersion()
            print("VIA protocol version: \(version)")

            let layers = try await client.layerCount()
            print("Layer count: \(layers)")

            // Resolve the physical layout from VIA's keyboards repo by VID:PID.
            print("\nResolving layout from the-via/keyboards…")
            let resolver = try LayoutResolver.builtIn()
            let definition: KeyboardDefinition
            do {
                definition = try await resolver.resolve(
                    vendorID: first.info.vendorID,
                    productID: first.info.productID
                )
                print("✓ Resolved: \(definition.rows) rows × \(definition.cols) cols, \(definition.layouts.first?.keys.count ?? 0) physical keys")
            } catch let LayoutResolver.ResolveError.notInManifest(vid, pid) {
                print("⚠ \(String(format: "%04X:%04X", vid, pid)) is not in the VIA keyboards repo. Falling back to matrix-only output.")
                let rows = Int(layers) > 0 ? 4 : 4 // unknown; bail with sane default
                let keymap = try await client.readKeymap(layers: Int(layers), rows: rows, cols: 4)
                printMatrix(keymap)
                return
            }

            print("\nReading full keymap (\(layers) layers × \(definition.rows) × \(definition.cols))…")
            let keymap = try await client.readKeymap(
                layers: Int(layers),
                rows: definition.rows,
                cols: definition.cols
            )

            for (l, layer) in keymap.enumerated() {
                print("\n── Layer \(l) ── (matrix view)")
                for (r, row) in layer.enumerated() {
                    let cells = row.map { String(format: "0x%04X", $0) }.joined(separator: "  ")
                    print("  R\(r): \(cells)")
                }
            }
        } catch {
            print("VIA error: \(error)")
        }
    }

    static func printMatrix(_ keymap: [[[UInt16]]]) {
        for (l, layer) in keymap.enumerated() {
            print("\n── Layer \(l) ──")
            for (r, row) in layer.enumerated() {
                let cells = row.map { String(format: "0x%04X", $0) }.joined(separator: "  ")
                print("  R\(r): \(cells)")
            }
        }
    }

    static func hex8(_ v: UInt16) -> String { String(format: "%02X", v) }
    static func hex16(_ v: UInt16) -> String { String(format: "%04X", v) }
}
