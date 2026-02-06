import XCTest
import CP2ResolveOverlap
import CP2Domain
import CP2Geometry

final class ResolveOuterFaceTests: XCTestCase {
    func testResolveSelfOverlapChoosesMaxAbsAreaFace() {
        let bowtie: [Vec2] = [
            Vec2(0, 0),
            Vec2(3, 3),
            Vec2(0, 3),
            Vec2(3, 0),
            Vec2(0, 0)
        ]
        let policy = DeterminismPolicy(eps: 1.0e-6, stableSort: .lexicographicXYThenIndex)
        let (result, artifacts) = ResolveSelfOverlapUseCase.run(
            ring: bowtie,
            policy: policy,
            selectionPolicy: .lineGalleryMaxAbsAreaFace(minAreaRatio: 0.0),
            includeDebug: false
        )
        guard let faces = artifacts?.faceSet.faces, !faces.isEmpty else {
            XCTFail("expected faces from resolve")
            return
        }
        let maxAbsArea = faces.map { abs($0.area) }.max() ?? 0.0
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.selectedAbsArea, maxAbsArea, accuracy: 1.0e-6)
    }
}
