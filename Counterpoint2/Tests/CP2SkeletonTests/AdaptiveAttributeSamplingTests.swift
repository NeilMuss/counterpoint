import XCTest
import CP2Geometry
import CP2Skeleton

final class AdaptiveAttributeSamplingTests: XCTestCase {
    func testAdaptiveSamplingSubdividesOnAttributeDeviation() {
        let sampler = GlobalTSampler()
        var cfg = SamplingConfig()
        cfg.mode = .adaptive
        cfg.flatnessEps = 1.0e9
        cfg.railEps = 1.0e9
        cfg.attrEpsOffset = 1.0
        cfg.attrEpsWidth = 1.0
        cfg.attrEpsAngle = 1.0
        cfg.attrEpsAlpha = 1.0

        let positionAt: GlobalTSampler.PositionAtS = { t in
            Vec2(100.0 * t, 0.0)
        }
        let paramsAt: (@Sendable (Double) -> GlobalTSampler.StrokeParamsSample?) = { t in
            let offset = t <= 0.5 ? (40.0 * t) : (40.0 * (1.0 - t))
            return GlobalTSampler.StrokeParamsSample(
                widthLeft: 50.0,
                widthRight: 50.0,
                theta: 0.0,
                offset: offset,
                alpha: 0.0
            )
        }

        let result = sampler.sampleGlobalT(
            config: cfg,
            positionAt: positionAt,
            railProbe: nil,
            paramsAt: paramsAt
        )

        XCTAssertGreaterThan(result.ts.count, 2)
        XCTAssertGreaterThan(result.stats.subdividedByParam, 0)
    }
}
