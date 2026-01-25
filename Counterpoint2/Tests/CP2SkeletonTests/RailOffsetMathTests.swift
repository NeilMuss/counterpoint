import XCTest
import CP2Geometry
@testable import CP2Skeleton

final class RailOffsetMathTests: XCTestCase {
    func testRailPointsFromCrossAxisSymmetricWidths() {
        let center = Vec2(12.0, -8.0)
        let crossAxis = Vec2(-0.207912, -0.978148)
        let points = railPointsFromCrossAxis(
            center: center,
            crossAxis: crossAxis,
            widthLeft: 8.0,
            widthRight: 8.0
        )
        let dist = (points.right - points.left).length
        XCTAssertEqual(dist, 16.0, accuracy: 1.0e-6)
    }

    func testRailPointsFromCrossAxisAsymmetricWidths() {
        let center = Vec2(12.0, -8.0)
        let crossAxis = Vec2(-0.207912, -0.978148)
        let points = railPointsFromCrossAxis(
            center: center,
            crossAxis: crossAxis,
            widthLeft: 6.0,
            widthRight: 10.0
        )
        let dist = (points.right - points.left).length
        XCTAssertEqual(dist, 16.0, accuracy: 1.0e-6)
        XCTAssertEqual((points.left - center).length, 6.0, accuracy: 1.0e-6)
        XCTAssertEqual((points.right - center).length, 10.0, accuracy: 1.0e-6)
    }

    func testRailFrameDiagnosticsAlignmentUsesCrossAxis() {
        let center = Vec2(0.0, 0.0)
        let tangent = Vec2(1.0, 0.0)
        let normal = Vec2(0.0, 1.0)
        let crossAxis = Vec2(0.0, 1.0)
        let points = railPointsFromCrossAxis(
            center: center,
            crossAxis: crossAxis,
            widthLeft: 1.0,
            widthRight: 1.0
        )
        let frame = RailSampleFrame(
            index: 0,
            center: center,
            tangent: tangent,
            normal: normal,
            crossAxis: crossAxis,
            effectiveAngle: 0.0,
            widthLeft: 1.0,
            widthRight: 1.0,
            widthTotal: 2.0,
            left: points.left,
            right: points.right
        )
        let diag = computeRailFrameDiagnostics(frames: [frame], widthEps: 1.0e-6, perpEps: 1.0e-6, unitEps: 1.0e-6)
        XCTAssertEqual(diag.checks.count, 1)
        let check = diag.checks[0]
        XCTAssertEqual(check.widthErr, 0.0, accuracy: 1.0e-6)
        XCTAssertEqual(check.alignment, 0.0, accuracy: 1.0e-6)
    }
}
