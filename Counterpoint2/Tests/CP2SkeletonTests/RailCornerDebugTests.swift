import XCTest
import CP2Geometry
import CP2Skeleton

final class RailCornerDebugTests: XCTestCase {
    func testCornerDebugUsesLocalAxesWithoutRotation() {
        let center = Vec2(0, 0)
        let tangent = Vec2(1, 0)
        let normal = Vec2(0, 1)

        let debug = computeRailCornerDebug(
            index: 0,
            center: center,
            tangent: tangent,
            normal: normal,
            widthLeft: 1.0,
            widthRight: 1.0,
            height: 2.0,
            effectiveAngle: 0.0,
            computeCorners: { c, u, v, widthTotal, height, _ in
                let halfW = 0.5 * widthTotal
                let halfH = 0.5 * height
                return [
                    c + u * halfW + v * halfH,
                    c + u * halfW - v * halfH,
                    c - u * halfW - v * halfH,
                    c - u * halfW + v * halfH
                ]
            },
            left: center + normal,
            right: center - normal
        )

        XCTAssertTrue(Epsilon.approxEqual(debug.uRot, debug.u, eps: 1.0e-9))
        XCTAssertTrue(Epsilon.approxEqual(debug.vRot, debug.v, eps: 1.0e-9))
        XCTAssertEqual(debug.corners.count, 4)
    }

    func testDecomposeDeltaMatchesExpected() {
        let left = Vec2(0, 1)
        let right = Vec2(0, -1)
        let tangent = Vec2(1, 0)
        let normal = Vec2(0, 1)

        let decomp = decomposeDelta(
            left: left,
            right: right,
            tangent: tangent,
            normal: normal,
            expectedWidth: 2.0
        )

        XCTAssertEqual(decomp.len, 2.0, accuracy: 1.0e-6)
        XCTAssertEqual(decomp.dotT, 0.0, accuracy: 1.0e-6)
        XCTAssertEqual(decomp.widthErr, 0.0, accuracy: 1.0e-6)
    }
}
