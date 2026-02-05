import XCTest
import CP2ResolveOverlap
import CP2Domain
import CP2Geometry

final class OverlapArtifactsTests: XCTestCase {
    func test_Artifacts_ValidateHappyPath() throws {
        let policy = DeterminismPolicy(eps: 1.0e-6, stableSort: .lexicographicXYThenIndex)
        let planar = PlanarizedSegmentsArtifact(
            id: ArtifactID("planar"),
            policy: policy,
            sourceRingId: ArtifactID("ring"),
            vertices: [Vec2(0,0), Vec2(1,0), Vec2(1,1)],
            segments: [SegmentRef(a: 0, b: 1), SegmentRef(a: 1, b: 2)]
        )
        try planar.validate()

        let he = HalfEdge(origin: 0, twin: 1, next: 1, prev: 1, face: -1)
        let graph = HalfEdgeGraphArtifact(
            id: ArtifactID("graph"),
            policy: policy,
            planarId: planar.id,
            vertices: planar.vertices,
            halfEdges: [he, HalfEdge(origin: 1, twin: 0, next: 0, prev: 0, face: -1)],
            faces: [FaceRecord(anyHalfEdge: 0)]
        )
        try graph.validate()

        let face = FaceLoop(
            faceId: 0,
            boundary: [Vec2(0,0), Vec2(1,0), Vec2(0,1), Vec2(0,0)],
            area: 0.5,
            winding: .ccw,
            halfEdgeCycle: [0, 1, 2]
        )
        let faceSet = FaceSetArtifact(id: ArtifactID("faces"), policy: policy, graphId: graph.id, faces: [face])
        try faceSet.validate()

        let ring = Ring(points: face.boundary, winding: .ccw, area: 0.5)
        let selection = SelectionResultArtifact(
            id: ArtifactID("selection"),
            policy: policy,
            faceSetId: faceSet.id,
            selectedFaceId: 0,
            selectedRing: ring,
            rejectedFaceIds: []
        )
        try selection.validate()
    }

    func test_Artifacts_ValidateFails_OnBadIndices() {
        let policy = DeterminismPolicy(eps: 1.0e-6, stableSort: .lexicographicXYThenIndex)
        let planar = PlanarizedSegmentsArtifact(
            id: ArtifactID("planar"),
            policy: policy,
            sourceRingId: ArtifactID("ring"),
            vertices: [Vec2(0,0), Vec2(1,0)],
            segments: [SegmentRef(a: 0, b: 2)]
        )
        XCTAssertThrowsError(try planar.validate())
    }
}
