import XCTest
import CP2ResolveOverlap
import CP2Domain
import CP2Geometry

final class ResolveSelfOverlapTests: XCTestCase {
    func test_ResolveSelfOverlap_Smoke_BowTie_WithDebugPayloads() throws {
        let ring: [Vec2] = [
            Vec2(0, 0),
            Vec2(2, 2),
            Vec2(0, 2),
            Vec2(2, 0),
            Vec2(0, 0)
        ]
        let policy = DeterminismPolicy(eps: 1.0e-6, stableSort: .lexicographicXYThenIndex)
        let (result, artifacts) = ResolveSelfOverlapUseCase.run(ring: ring, policy: policy, includeDebug: true)
        XCTAssertTrue(result.success)
        XCTAssertNotNil(artifacts)
        guard let artifacts else { return }

        XCTAssertGreaterThan(artifacts.faceSet.faces.count, 0)
        XCTAssertGreaterThan(result.ring.count, 3)

        let decoder = JSONDecoder()
        if let data = artifacts.planar.debug?.entries[PlanarizerDebugPayload.kind] {
            let payload = try decoder.decode(PlanarizerDebugPayload.self, from: data)
            XCTAssertEqual(payload.segments, 4)
            XCTAssertGreaterThan(payload.intersections, 0)
        } else {
            XCTFail("missing planarizer debug payload")
        }
        if let data = artifacts.graph.debug?.entries[GraphDebugPayload.kind] {
            _ = try decoder.decode(GraphDebugPayload.self, from: data)
        } else {
            XCTFail("missing graph debug payload")
        }
        if let data = artifacts.faceSet.debug?.entries[FaceEnumDebugPayload.kind] {
            let payload = try decoder.decode(FaceEnumDebugPayload.self, from: data)
            XCTAssertGreaterThan(payload.faces, 0)
        } else {
            XCTFail("missing face enum debug payload")
        }
        if let data = artifacts.selection.debug?.entries[SelectionDebugPayload.kind] {
            let payload = try decoder.decode(SelectionDebugPayload.self, from: data)
            XCTAssertGreaterThanOrEqual(payload.candidates, 1)
        } else {
            XCTFail("missing selection debug payload")
        }
    }
}
