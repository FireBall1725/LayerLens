import Testing
import Foundation
@testable import LayerLensCore

@Suite("QMKInfoParser")
struct QMKInfoParserTests {

    @Test("Parses real Work Louder Micro Pad keyboard.json")
    func realMicroPadInfo() throws {
        let url = try #require(Bundle.module.url(forResource: "work_louder_micro_qmk", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let def = try QMKInfoParser.parseDefinition(data: data)

        #expect(def.vendorID == 0x574C)
        #expect(def.productID == 0xE6E3)
        #expect(def.rows == 4)
        #expect(def.cols == 4)
        #expect(def.layouts.count >= 1)

        let layout = try #require(def.layouts.first { $0.name == "LAYOUT" } ?? def.layouts.first)
        #expect(layout.keys.count == 16)

        for k in layout.keys {
            #expect(k.row >= 0 && k.row < def.rows)
            #expect(k.col >= 0 && k.col < def.cols)
            #expect(k.w >= 1.0)
            #expect(k.h >= 1.0)
        }
    }

    @Test("Split-keyboard flag doubles row count")
    func splitDoublesRows() throws {
        let json: [String: Any] = [
            "usb": ["vid": "0x1234", "pid": "0x5678"],
            "matrix_pins": ["rows": [0, 0, 0], "cols": [0, 0, 0, 0, 0, 0]],
            "split": ["enabled": true],
            "layouts": [
                "LAYOUT": [
                    "layout": [
                        ["matrix": [0, 0], "x": 0, "y": 0]
                    ]
                ]
            ]
        ]
        let def = try QMKInfoParser.parseDefinition(json)
        #expect(def.rows == 6)  // 3 * 2
        #expect(def.cols == 6)
    }

    @Test("Missing usb section throws missingField")
    func missingUSB() async throws {
        let json: [String: Any] = [
            "matrix_pins": ["rows": [0], "cols": [0]],
            "layouts": ["L": ["layout": []]]
        ]
        #expect(throws: LayoutError.self) {
            _ = try QMKInfoParser.parseDefinition(json)
        }
    }
}
