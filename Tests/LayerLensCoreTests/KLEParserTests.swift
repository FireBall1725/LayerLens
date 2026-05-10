import Testing
import Foundation
@testable import LayerLensCore

@Suite("KLEParser")
struct KLEParserTests {

    @Test("Plain row places keys at (0,0), (1,0), (2,0)")
    func plainRow() {
        let keymap: [Any] = [
            ["0,0", "0,1", "0,2"]
        ]
        let keys = KLEParser.parseKeymap(keymap)
        #expect(keys.count == 3)
        #expect(keys[0].row == 0 && keys[0].col == 0)
        #expect(keys[0].x == 0 && keys[0].y == 0)
        #expect(keys[1].x == 1 && keys[1].y == 0)
        #expect(keys[2].x == 2 && keys[2].y == 0)
    }

    @Test("Width modifier adjusts placement and resets to 1.0")
    func widthModifier() {
        let keymap: [Any] = [
            [["w": 2], "0,0", "0,1"]
        ]
        let keys = KLEParser.parseKeymap(keymap)
        #expect(keys.count == 2)
        #expect(keys[0].w == 2)
        #expect(keys[0].x == 0)
        #expect(keys[1].x == 2)  // first key's width pushed second
        #expect(keys[1].w == 1)  // reset back to 1
    }

    @Test("Y advances per row when angle is zero")
    func multipleRows() {
        let keymap: [Any] = [
            ["0,0", "0,1"],
            ["1,0", "1,1"]
        ]
        let keys = KLEParser.parseKeymap(keymap)
        #expect(keys.count == 4)
        #expect(keys[0].y == 0)
        #expect(keys[1].y == 0)
        #expect(keys[2].y == 1)
        #expect(keys[3].y == 1)
    }

    @Test("Multi-line label uses first line for matrix coords")
    func multiLineLabel() {
        let keymap: [Any] = [
            ["3,7\n\n\nesc"]
        ]
        let keys = KLEParser.parseKeymap(keymap)
        #expect(keys.count == 1)
        #expect(keys[0].row == 3 && keys[0].col == 7)
    }

    @Test("Non-matrix labels are skipped without breaking position")
    func nonMatrixLabel() {
        let keymap: [Any] = [
            ["just a label", "0,0"]
        ]
        let keys = KLEParser.parseKeymap(keymap)
        // The non-matrix label still consumes a slot's worth of x advancement.
        #expect(keys.count == 1)
        #expect(keys[0].x == 1)
    }

    @Test("Parses real Work Louder Micro Pad VIA definition")
    func realMicroPadDefinition() throws {
        let url = try #require(Bundle.module.url(forResource: "work_louder_micro_via", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data)

        let def = try KLEParser.parseDefinition(json)
        #expect(def.vendorID == 0x574C)
        #expect(def.productID == 0xE6E3)
        #expect(def.rows == 4)
        #expect(def.cols == 4)
        #expect(def.layouts.count == 1)

        let layout = try #require(def.layouts.first)
        // Micro Pad's 4x4 matrix is fully populated (12 buttons + encoder buttons + knobs).
        #expect(layout.keys.count == 16)

        // Every key references a row in [0,3] and col in [0,3].
        for k in layout.keys {
            #expect(k.row >= 0 && k.row < def.rows)
            #expect(k.col >= 0 && k.col < def.cols)
        }
    }
}
