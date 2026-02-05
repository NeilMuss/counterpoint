import XCTest
import CP2ResolveOverlap
import CP2Domain
import CP2Geometry

final class HalfEdgeGraphTests: XCTestCase {
    private func rectangleRing() -> [Vec2] {
        [
            Vec2(0, 0),
            Vec2(2, 0),
            Vec2(2, 1),
            Vec2(0, 1),
            Vec2(0, 0)
        ]
    }

    func test_HalfEdgeGraph_TwinsAreMutual() {
        let policy = DeterminismPolicy(eps: 1.0e-6, stableSort: .lexicographicXYThenIndex)
        let planar = SegmentPlanarizer.planarize(ring: rectangleRing(), policy: policy, sourceRingId: ArtifactID("rect"), includeDebug: false)
        let (graph, _) = HalfEdgeGraphBuilder.build(planar: planar.artifact, includeDebug: false)
        for (idx, edge) in graph.halfEdges.enumerated() {
            XCTAssertEqual(graph.halfEdges[edge.twin].twin, idx)
        }
    }

    func test_HalfEdgeGraph_NextPrevConsistency_SimpleSquare() {
        let policy = DeterminismPolicy(eps: 1.0e-6, stableSort: .lexicographicXYThenIndex)
        let planar = SegmentPlanarizer.planarize(ring: rectangleRing(), policy: policy, sourceRingId: ArtifactID("rect"), includeDebug: false)
        let (graph, _) = HalfEdgeGraphBuilder.build(planar: planar.artifact, includeDebug: false)
        for (idx, edge) in graph.halfEdges.enumerated() {
            XCTAssertTrue(edge.next >= 0)
            XCTAssertTrue(edge.prev >= 0)
            XCTAssertEqual(graph.halfEdges[edge.next].prev, idx)
            XCTAssertEqual(graph.halfEdges[edge.prev].next, idx)
        }
    }

    func test_HalfEdgeGraph_DeterministicHalfEdgeOrdering() {
        let policy = DeterminismPolicy(eps: 1.0e-6, stableSort: .lexicographicXYThenIndex)
        let planar = SegmentPlanarizer.planarize(ring: rectangleRing(), policy: policy, sourceRingId: ArtifactID("rect"), includeDebug: false)
        let (graphA, _) = HalfEdgeGraphBuilder.build(planar: planar.artifact, includeDebug: false)
        let (graphB, _) = HalfEdgeGraphBuilder.build(planar: planar.artifact, includeDebug: false)
        XCTAssertEqual(graphA.halfEdges, graphB.halfEdges)
    }
}
