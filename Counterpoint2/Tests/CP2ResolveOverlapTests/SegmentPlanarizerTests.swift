import XCTest
import CP2ResolveOverlap
import CP2Domain
import CP2Geometry

final class SegmentPlanarizerTests: XCTestCase {
    func test_Planarizer_SplitsAtSingleIntersection_Cross() {
        let ring: [Vec2] = [
            Vec2(0, 0),
            Vec2(2, 2),
            Vec2(0, 2),
            Vec2(2, 0),
            Vec2(0, 0)
        ]
        let policy = DeterminismPolicy(eps: 1.0e-6, stableSort: .lexicographicXYThenIndex)
        let output = SegmentPlanarizer.planarize(ring: ring, policy: policy, sourceRingId: ArtifactID("ring"), includeDebug: false)
        XCTAssertGreaterThan(output.stats.intersections, 0)
        XCTAssertGreaterThan(output.artifact.segments.count, 4)
    }

    func test_Planarizer_NoChange_WhenNoIntersections_Rectangle() {
        let ring: [Vec2] = [
            Vec2(0, 0),
            Vec2(2, 0),
            Vec2(2, 1),
            Vec2(0, 1),
            Vec2(0, 0)
        ]
        let policy = DeterminismPolicy(eps: 1.0e-6, stableSort: .lexicographicXYThenIndex)
        let output = SegmentPlanarizer.planarize(ring: ring, policy: policy, sourceRingId: ArtifactID("rect"), includeDebug: false)
        XCTAssertEqual(output.stats.intersections, 0)
        XCTAssertEqual(output.artifact.segments.count, 4)
    }

    func test_Planarizer_DeterministicVertexOrdering() {
        let ring: [Vec2] = [
            Vec2(0, 0),
            Vec2(2, 2),
            Vec2(0, 2),
            Vec2(2, 0),
            Vec2(0, 0)
        ]
        let policy = DeterminismPolicy(eps: 1.0e-6, stableSort: .lexicographicXYThenIndex)
        let outputA = SegmentPlanarizer.planarize(ring: ring, policy: policy, sourceRingId: ArtifactID("ring"), includeDebug: false)
        let outputB = SegmentPlanarizer.planarize(ring: ring, policy: policy, sourceRingId: ArtifactID("ring"), includeDebug: false)
        XCTAssertEqual(outputA.artifact.vertices, outputB.artifact.vertices)
        XCTAssertEqual(outputA.artifact.segments, outputB.artifact.segments)
    }
}
