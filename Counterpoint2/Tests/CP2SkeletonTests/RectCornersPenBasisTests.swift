import XCTest
import CP2Geometry
import CP2Skeleton

final class RectCornersPenBasisTests: XCTestCase {
    func testAbsoluteAngle_CrossAlignedWithTangent_DoesNotCollapseHeight() {
        let center = Vec2(0, 0)
        let crossAxis = Vec2(2.0, 0.0) // non-unit but aligned with tangent
        let widthLeft = 10.0
        let widthRight = 10.0
        let height = 6.0

        let corners = penCorners(
            center: center,
            crossAxis: crossAxis,
            widthLeft: widthLeft,
            widthRight: widthRight,
            height: height
        )

        let edgeH = (corners.c0 - corners.c1).length
        let edgeW = (corners.c0 - corners.c3).length
        XCTAssertGreaterThan(edgeH, 1.0e-6)
        XCTAssertGreaterThan(edgeW, 1.0e-6)

        let e1 = corners.c1 - corners.c0
        let e2 = corners.c3 - corners.c0
        let area = abs(e1.x * e2.y - e1.y * e2.x)
        let expected = (widthLeft + widthRight) * (2.0 * height)
        XCTAssertEqual(area, expected, accuracy: 1.0e-6)
    }
}
