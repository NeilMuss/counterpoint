import XCTest
import CP2Geometry

final class HalfEdgeGraphTests: XCTestCase {
    func testHalfEdgeGraphTwinsAndNext() {
        let ring: [Vec2] = [
            Vec2(0, 0),
            Vec2(2, 0),
            Vec2(2, 2),
            Vec2(0, 2),
            Vec2(0, 0)
        ]
        let planar = SegmentPlanarizer.planarize(ring: ring, eps: 1.0e-6)
        let graph = HalfEdgeGraph(vertices: planar.vertices, edges: planar.edges)
        XCTAssertEqual(graph.twinsPaired, graph.halfEdges.count)
        for edge in graph.halfEdges {
            let next = graph.nextHalfEdgeKeepingLeftFace(from: edge.id)
            XCTAssertNotNil(next)
            XCTAssertNotEqual(next, edge.twinId)
        }
    }
}
