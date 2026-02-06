import XCTest
import CP2Geometry
import CP2Domain
@testable import CP2ResolveOverlap

final class SoupPlanarizerTests: XCTestCase {
    func testPlanarizeSoupSplitsCrossingSegments() {
        let segments: [(Vec2, Vec2)] = [
            (Vec2(0, 0), Vec2(10, 10)),
            (Vec2(0, 10), Vec2(10, 0))
        ]
        let policy = DeterminismPolicy(eps: 1.0e-6, stableSort: .lexicographicXYThenIndex)
        let output = SegmentPlanarizer.planarize(segments: segments, policy: policy, sourceRingId: ArtifactID("soup"), includeDebug: false)
        XCTAssertEqual(output.stats.intersections, 1)
        XCTAssertEqual(output.stats.splitEdges, 4)
        XCTAssertEqual(output.stats.splitVerts, 5)
    }
}
