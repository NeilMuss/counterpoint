import XCTest
import CP2Geometry
import CP2Skeleton

final class RailDiagnosticsTests: XCTestCase {
    func testRailDebugSummaryParallelRails() {
        let rails = [
            RailSample(left: Vec2(0, 1), right: Vec2(0, -1)),
            RailSample(left: Vec2(10, 1), right: Vec2(10, -1))
        ]

        let summary = computeRailDebugSummary(
            rails: rails,
            keyOf: { Epsilon.snapKey($0, eps: 1.0e-6) },
            prefixCount: 2
        )

        XCTAssertEqual(summary.count, 2)
        XCTAssertEqual(summary.prefix.count, 2)
        XCTAssertEqual(summary.start.distance, 2.0, accuracy: 1.0e-6)
        XCTAssertEqual(summary.end.distance, 2.0, accuracy: 1.0e-6)
        XCTAssertEqual(summary.prefix[0].distance, 2.0, accuracy: 1.0e-6)
    }

    func testRailDebugSummaryDivergentStart() {
        let rails = [
            RailSample(left: Vec2(0, 0), right: Vec2(0, -10)),
            RailSample(left: Vec2(10, 0), right: Vec2(10, -2))
        ]

        let summary = computeRailDebugSummary(
            rails: rails,
            keyOf: { Epsilon.snapKey($0, eps: 1.0e-6) },
            prefixCount: 1
        )

        XCTAssertEqual(summary.count, 2)
        XCTAssertEqual(summary.prefix.count, 1)
        XCTAssertEqual(summary.start.distance, 10.0, accuracy: 1.0e-6)
        XCTAssertEqual(summary.end.distance, 2.0, accuracy: 1.0e-6)
    }
}
