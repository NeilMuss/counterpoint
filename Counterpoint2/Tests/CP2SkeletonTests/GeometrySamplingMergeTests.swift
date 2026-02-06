import XCTest
import CP2Geometry
@testable import CP2Skeleton

final class GeometrySamplingMergeTests: XCTestCase {
    private func wavyPath() -> SkeletonPath {
        let segments: [CubicBezier2] = [
            CubicBezier2(
                p0: Vec2(0, 0),
                p1: Vec2(30.666666666666668, 0),
                p2: Vec2(61.333333333333336, 120),
                p3: Vec2(92, 120)
            ),
            CubicBezier2(
                p0: Vec2(92, 120),
                p1: Vec2(122.66666666666667, 120),
                p2: Vec2(153.33333333333334, -120),
                p3: Vec2(184, -120)
            ),
            CubicBezier2(
                p0: Vec2(184, -120),
                p1: Vec2(214.66666666666666, -120),
                p2: Vec2(245.33333333333334, 120),
                p3: Vec2(276, 120)
            ),
            CubicBezier2(
                p0: Vec2(276, 120),
                p1: Vec2(306.6666666666667, 120),
                p2: Vec2(337.3333333333333, -120),
                p3: Vec2(368, -120)
            ),
            CubicBezier2(
                p0: Vec2(368, -120),
                p1: Vec2(398.6666666666667, -120),
                p2: Vec2(429.3333333333333, 0),
                p3: Vec2(460, 0)
            )
        ]
        return SkeletonPath(segments: segments)
    }

    func testGeometryAdaptiveSamplingOnWavyPathProducesManySamples() {
        let path = wavyPath()
        let param = SkeletonPathParameterization(path: path, samplesPerSegment: 256)
        var cfg = SamplingConfig()
        cfg.mode = .adaptive
        cfg.flatnessEps = 0.25
        cfg.maxDepth = 12
        cfg.maxSamples = 512
        let sampler = GlobalTSampler()
        let result = sampler.sampleGlobalT(
            config: cfg,
            positionAt: { t in param.position(globalT: t) }
        )
        XCTAssertEqual(result.ts.first, 0.0)
        XCTAssertEqual(result.ts.last, 1.0)
        XCTAssertGreaterThanOrEqual(result.ts.count, 16)
    }

    func testMergeWithKeyframesPreservesGeometrySamples() {
        let geometry = [0.0, 0.5, 1.0]
        let mergedSame = injectKeyframeSamples(geometry, keyframes: [0.0, 1.0], eps: 1.0e-9)
        XCTAssertEqual(mergedSame, geometry)

        let mergedExtra = injectKeyframeSamples(geometry, keyframes: [0.3], eps: 1.0e-9)
        XCTAssertEqual(mergedExtra.count, 4)
        XCTAssertTrue(mergedExtra.contains(where: { abs($0 - 0.3) <= 1.0e-9 }))
        XCTAssertEqual(mergedExtra, mergedExtra.sorted())
    }
}
