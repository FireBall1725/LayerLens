import Foundation

enum LayoutGeometry {

    /// Translate a key with rotation into an axis-aligned position. KeyPeek and
    /// LayerLens render keys as rectangles without rotation; for any keymap that
    /// uses rotation (`r`/`rx`/`ry`), we flatten by rotating the key's *center*
    /// around the pivot, then converting back to a top-left origin. Visually
    /// imperfect for steep angles but matches KeyPeek's rendering exactly.
    static func flattenedTopLeftAfterCenterRotation(
        x: Double,
        y: Double,
        w: Double,
        h: Double,
        angleDegrees: Double,
        pivotX: Double,
        pivotY: Double
    ) -> (x: Double, y: Double) {
        if abs(angleDegrees) <= .ulpOfOne {
            return (x, y)
        }

        let centerX = x + (w * 0.5)
        let centerY = y + (h * 0.5)

        let localX = centerX - pivotX
        let localY = centerY - pivotY

        let radians = angleDegrees * .pi / 180.0
        let cosA = cos(radians)
        let sinA = sin(radians)

        let rotatedCenterX = (localX * cosA) - (localY * sinA) + pivotX
        let rotatedCenterY = (localX * sinA) + (localY * cosA) + pivotY

        return (rotatedCenterX - (w * 0.5), rotatedCenterY - (h * 0.5))
    }
}
