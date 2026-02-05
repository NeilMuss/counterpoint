import XCTest
import CP2Geometry

final class FaceEnumeratorTests: XCTestCase {
    func testFaceEnumeratorFindsFaces() {
        let ring: [Vec2] = [
            Vec2(0, 0),
            Vec2(2, 2),
            Vec2(0, 2),
            Vec2(2, 0),
            Vec2(0, 0)
        ]
        let planar = SegmentPlanarizer.planarize(ring: ring, eps: 1.0e-6)
        let graph = HalfEdgeGraph(vertices: planar.vertices, edges: planar.edges)
        let faces = FaceEnumerator.enumerate(graph: graph)
        XCTAssertGreaterThan(faces.faces.count, 0)
        XCTAssertGreaterThanOrEqual(faces.smallFaceCount, 0)
    }
}
