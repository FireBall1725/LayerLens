import Testing
@testable import LayerLensCore

@Suite("Smoke")
struct SmokeTests {
    @Test func packageBuilds() {
        #expect(LayerLensCore.version == "0.0.1")
    }
}
