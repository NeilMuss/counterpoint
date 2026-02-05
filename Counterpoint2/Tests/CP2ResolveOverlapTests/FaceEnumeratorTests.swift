import XCTest
import CP2ResolveOverlap
import CP2Domain
import CP2Geometry

final class FaceEnumeratorTests: XCTestCase {
    func test_FaceEnumerator_FindsFaces_ForBowTie() {
        let ring: [Vec2] = [
            Vec2(0, 0),
            Vec2(2, 2),
            Vec2(0, 2),
            Vec2(2, 0),
            Vec2(0, 0)
        ]
        let policy = DeterminismPolicy(eps: 1.0e-6, stableSort: .lexicographicXYThenIndex)
        let planar = SegmentPlanarizer.planarize(ring: ring, policy: policy, sourceRingId: ArtifactID("bow"), includeDebug: false)
        let (graphArtifact, graphIndex) = HalfEdgeGraphBuilder.build(planar: planar.artifact, includeDebug: false)
        let result = FaceEnumerator.enumerate(graph: graphIndex, policy: policy, graphId: graphArtifact.id, includeDebug: false)
        XCTAssertGreaterThanOrEqual(result.faceSet.faces.count, 2)
    }

    func test_FaceLoop_AreaAndWinding_Computed() {
        let ring: [Vec2] = [
            Vec2(0, 0),
            Vec2(2, 0),
            Vec2(2, 1),
            Vec2(0, 1),
            Vec2(0, 0)
        ]
        let policy = DeterminismPolicy(eps: 1.0e-6, stableSort: .lexicographicXYThenIndex)
        let planar = SegmentPlanarizer.planarize(ring: ring, policy: policy, sourceRingId: ArtifactID("rect"), includeDebug: false)
        let (graphArtifact, graphIndex) = HalfEdgeGraphBuilder.build(planar: planar.artifact, includeDebug: false)
        let result = FaceEnumerator.enumerate(graph: graphIndex, policy: policy, graphId: graphArtifact.id, includeDebug: false)
        let maxAbs = result.faceSet.faces.map { abs($0.area) }.max() ?? 0.0
        XCTAssertGreaterThan(maxAbs, 1.5)
    }
}
