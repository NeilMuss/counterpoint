import XCTest
import CP2Geometry
import CP2Skeleton

final class RoundCapQualityTests: XCTestCase {
    func testRoundCapUsesHighResolutionArcAndConstantRadius() {
        let leftRail = [Vec2(0, 40), Vec2(200, 40)]
        let rightRail = [Vec2(0, -40), Vec2(200, -40)]
        let requestedSegments = 64

        let caps = buildCaps(
            leftRail: leftRail,
            rightRail: rightRail,
            capNamespace: "test",
            capLocalIndex: 0,
            widthStart: 80,
            widthEnd: 80,
            startCap: .butt,
            endCap: .round,
            capFilletArcSegments: 8,
            capRoundArcSegments: requestedSegments,
            debugFillet: nil,
            debugCapBoundary: nil
        )

        let capSegments = caps.segments.filter { seg in
            if case .capEndEdge = seg.source { return true }
            return false
        }
        XCTAssertFalse(capSegments.isEmpty)

        let points = chainPoints(from: capSegments)
        let center = Vec2(200, 0)
        let radius = 0.5 * (rightRail.last! - leftRail.last!).length
        let eps = 1.0e-3

        let arcPoints = points.filter { abs(($0 - center).length - radius) <= eps }
        XCTAssertGreaterThanOrEqual(arcPoints.count, requestedSegments + 1)

        let maxDeviation = arcPoints.map { abs(($0 - center).length - radius) }.max() ?? 0.0
        XCTAssertLessThanOrEqual(maxDeviation, eps)
    }
}

private func chainPoints(from segments: [Segment2]) -> [Vec2] {
    var points: [Vec2] = []
    for seg in segments {
        if points.isEmpty {
            points.append(seg.a)
            points.append(seg.b)
            continue
        }
        if Epsilon.approxEqual(points[points.count - 1], seg.a) {
            points.append(seg.b)
        } else if Epsilon.approxEqual(points[points.count - 1], seg.b) {
            points.append(seg.a)
        } else {
            points.append(seg.a)
            points.append(seg.b)
        }
    }
    return points
}
