import Testing
import Foundation
@testable import LayerLensCore

@Suite("LayoutGeometry")
struct LayoutGeometryTests {

    @Test("Zero-angle rotation is a no-op")
    func zeroAngle() {
        let (x, y) = LayoutGeometry.flattenedTopLeftAfterCenterRotation(
            x: 3, y: 5, w: 1, h: 1,
            angleDegrees: 0,
            pivotX: 0, pivotY: 0
        )
        #expect(x == 3)
        #expect(y == 5)
    }

    @Test("90° around origin maps (1,0) center to (0,1)")
    func ninetyDegreesAroundOrigin() {
        // 1×1 key at top-left (0.5, -0.5) has center at (1.0, 0.0).
        // Rotating 90° CCW around origin should put center at (0, 1.0),
        // so top-left = (-0.5, 0.5).
        let (x, y) = LayoutGeometry.flattenedTopLeftAfterCenterRotation(
            x: 0.5, y: -0.5, w: 1, h: 1,
            angleDegrees: 90,
            pivotX: 0, pivotY: 0
        )
        #expect(abs(x - (-0.5)) < 1e-9)
        #expect(abs(y - 0.5) < 1e-9)
    }

    @Test("Pivot equal to center is fixed point")
    func pivotAtCenter() {
        let (x, y) = LayoutGeometry.flattenedTopLeftAfterCenterRotation(
            x: 2, y: 4, w: 2, h: 2,
            angleDegrees: 45,
            pivotX: 3, pivotY: 5  // == center
        )
        #expect(abs(x - 2) < 1e-9)
        #expect(abs(y - 4) < 1e-9)
    }
}
