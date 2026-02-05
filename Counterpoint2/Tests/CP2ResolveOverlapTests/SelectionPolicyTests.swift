import XCTest
import CP2ResolveOverlap
import CP2Domain
import CP2Geometry

final class SelectionPolicyTests: XCTestCase {
    func test_SelectionPolicy_LineGallery_PicksLargestAreaFace() {
        let faceLarge = FaceLoop(
            faceId: 0,
            boundary: [Vec2(0,0), Vec2(2,0), Vec2(2,2), Vec2(0,2), Vec2(0,0)],
            area: 4.0,
            winding: .ccw,
            halfEdgeCycle: [0, 1, 2]
        )
        let faceSmall = FaceLoop(
            faceId: 1,
            boundary: [Vec2(0,0), Vec2(1,0), Vec2(0,1), Vec2(0,0)],
            area: 0.5,
            winding: .ccw,
            halfEdgeCycle: [3, 4, 5]
        )
        let policy = DeterminismPolicy(eps: 1.0e-6, stableSort: .lexicographicXYThenIndex)
        let (result, _) = SelectionPolicy.select(
            policy: .lineGalleryMaxAbsAreaFace(minAreaRatio: 0.01),
            originalRing: faceLarge.boundary,
            faces: [faceSmall, faceLarge],
            determinism: policy,
            includeDebug: false
        )
        XCTAssertEqual(result.selectedFaceId, 0)
        XCTAssertNil(result.failureReason)
    }

    func test_SelectionPolicy_RejectedSpecks_AreaGuard() {
        let faceTiny = FaceLoop(
            faceId: 0,
            boundary: [Vec2(0,0), Vec2(0.1,0), Vec2(0,0.1), Vec2(0,0)],
            area: 0.005,
            winding: .ccw,
            halfEdgeCycle: [0, 1, 2]
        )
        let policy = DeterminismPolicy(eps: 1.0e-6, stableSort: .lexicographicXYThenIndex)
        let (result, _) = SelectionPolicy.select(
            policy: .lineGalleryMaxAbsAreaFace(minAreaRatio: 0.5),
            originalRing: [Vec2(0,0), Vec2(2,0), Vec2(2,2), Vec2(0,2), Vec2(0,0)],
            faces: [faceTiny],
            determinism: policy,
            includeDebug: false
        )
        XCTAssertEqual(result.failureReason, "areaTooSmall")
    }
}
