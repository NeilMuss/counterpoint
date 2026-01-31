import XCTest
import CP2Geometry
import CP2Skeleton

final class CapJoinInvariantTests: XCTestCase {
    func testCapJoinEdgesStayNearLocalWidth() {
        let width: Double = 20.0
        let height: Double = 10.0
        let strokeA = SkeletonPath(segments: [lineCubic(Vec2(0, 0), Vec2(100, 0))])
        let strokeB = SkeletonPath(segments: [lineCubic(Vec2(1000, 0), Vec2(1100, 0))])

        let segmentsA = boundarySoup(
            path: strokeA,
            width: width,
            height: height,
            effectiveAngle: 0.0,
            sampleCount: 8,
            arcSamplesPerSegment: 8,
            adaptiveSampling: false,
            flatnessEps: 0.25,
            railEps: 0.25,
            maxDepth: 4,
            maxSamples: 64,
            capNamespace: "strokeA",
            capLocalIndex: 0
        )
        let segmentsB = boundarySoup(
            path: strokeB,
            width: width,
            height: height,
            effectiveAngle: 0.0,
            sampleCount: 8,
            arcSamplesPerSegment: 8,
            adaptiveSampling: false,
            flatnessEps: 0.25,
            railEps: 0.25,
            maxDepth: 4,
            maxSamples: 64,
            capNamespace: "strokeB",
            capLocalIndex: 0
        )

        let segments = segmentsA + segmentsB
        let capEdges = segments.filter { seg in
            switch seg.source {
            case .capStartEdge(let role, _), .capEndEdge(let role, _):
                return role == .joinLR
            default:
                return false
            }
        }
        for seg in capEdges {
            let len = (seg.a - seg.b).length
            XCTAssertLessThanOrEqual(len, width * 5.0)
        }
    }
}

private func lineCubic(_ start: Vec2, _ end: Vec2) -> CubicBezier2 {
    let delta = end - start
    let p1 = start + delta * (1.0 / 3.0)
    let p2 = start + delta * (2.0 / 3.0)
    return CubicBezier2(p0: start, p1: p1, p2: p2, p3: end)
}
