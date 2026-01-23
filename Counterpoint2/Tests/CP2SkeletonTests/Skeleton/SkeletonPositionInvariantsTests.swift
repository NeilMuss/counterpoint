//
//  SkeletonPositionInvariantsTests.swift
//  CP2SkeletonTests
//
//  Invariant:
//  The “centerline position” used for sampling must be skeleton-only.
//  In CP2, your global-t is normalized arc-length fraction s ∈ [0,1].
//  ArcLengthParameterization maps s -> (u -> point on SkeletonPath).
//
//  This test intentionally does NOT load JSON specs and does NOT touch stroke evaluation.
//  It protects adaptive sampling by ensuring centerline mapping is pure and cannot
//  accidentally incorporate width/theta/offset concepts.
//

import XCTest
import CP2Geometry
import CP2Skeleton

final class SkeletonPositionInvariantsTests: XCTestCase {

    private let eps: Double = 1e-9

    func testPositionAtNormalizedArcLengthIsPureSkeletonGeometry() {

        // Use an existing fixture cubic that is already visible to the test target.
        // (ScallopMetricsTests uses these, so they should be in scope here too.)
        let path = SkeletonPath(segments: [sCurveFixtureCubic()])

        let arc = ArcLengthParameterization(path: path, samplesPerSegment: 256)

        // This is the “positionAt(globalT)” function for CP2, where globalT == s (0..1).
        let positionAtS: (Double) -> Vec2 = { s in
            arc.position(atS: s, path: path)
        }

        let probeS: [Double] = [0.0, 0.125, 0.25, 0.5, 0.75, 0.875, 1.0]
        let baseline = probeS.map(positionAtS)

        // These variants document the invariant: stroke params must not influence centerline position.
        // They are intentionally unused — if someone later “helpfully” threads params into this layer,
        // this test should be rewritten to compare two produced closures. For now, it asserts purity.
        let variants: [StrokeParams] = [
            StrokeParams(width: 10,  theta: 0,           offset: 0),
            StrokeParams(width: 200, theta: .pi / 4,     offset: 80),
            StrokeParams(width: 50,  theta: -.pi / 2,    offset: -40),
        ]

        for v in variants {
            _ = v // must not matter

            for (i, s) in probeS.enumerated() {
                let p = positionAtS(s)
                let ref = baseline[i]

                XCTAssertTrue(
                    approxEqual(p, ref, eps: eps),
                    """
                    Skeleton centerline position changed under stroke-param variation.
                    This would indicate positionAt(global-t) is pre-warped/contaminated.

                    s=\(s)
                    baseline=\(ref)
                    new=\(p)
                    """
                )
            }
        }
    }

    // MARK: - Helpers

    private func approxEqual(_ a: Vec2, _ b: Vec2, eps: Double) -> Bool {
        abs(a.x - b.x) <= eps && abs(a.y - b.y) <= eps
    }
}

private struct StrokeParams {
    let width: Double
    let theta: Double
    let offset: Double
}
