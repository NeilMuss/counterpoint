// Tests/CP2SkeletonTests/Sampling/GlobalTSamplerInvariantsTests.swift
import XCTest
import CP2Geometry
import CP2Skeleton

final class GlobalTSamplerInvariantsTests: XCTestCase {

    func testAdaptiveGeometryOnly_LineProducesOnlyEndpoints() throws {
        // Straight line skeleton: midpoint lies exactly on chord -> err==0 -> accept.
        let p0 = Vec2(0, 0)
        let p1 = Vec2(100, 0)

        let positionAt: GlobalTSampler.PositionAtS = { s in
            p0.lerp(to: p1, t: s)
        }

        var cfg = SamplingConfig()
        cfg.mode = .adaptive
        cfg.flatnessEps = 1e-9
        cfg.maxDepth = 12
        cfg.maxSamples = 512

        let sampler = GlobalTSampler()
        let res = sampler.sampleGlobalT(config: cfg, positionAt: positionAt)

        try SamplingInvariants.validate(ts: res.ts, maxSamples: cfg.maxSamples, tEps: cfg.tEps)
        XCTAssertEqual(res.ts.count, 2)
        XCTAssertEqual(res.ts.first!, 0.0, accuracy: 1e-12)
        XCTAssertEqual(res.ts.last!, 1.0, accuracy: 1e-12)
    }

    func testAdaptiveGeometryOnly_CurveSubdividesWhenMidpointIsNotOnChord() throws {
        // Pick a more aggressive curve. (If this still ends up flat under this metric,
        // the test will tell us and we’ll swap to a custom cubic.)
        let path = SkeletonPath(segments: [fastSCurve2FixtureCubic()])

        // Coarser table to avoid “already-linearized” behavior masking midpoint deviation.
        let arc = ArcLengthParameterization(path: path, samplesPerSegment: 32)

        let positionAt: GlobalTSampler.PositionAtS = { s in
            arc.position(atS: s, path: path)
        }

        // Sanity: this fixture must actually bend under the chosen metric.
        let p0 = positionAt(0.0)
        let pm = positionAt(0.5)
        let p1 = positionAt(1.0)
        let err = ErrorMetrics.midpointDeviation(p0: p0, pm: pm, p1: p1)

        XCTAssertGreaterThan(
            err, 1.0e-9,
            """
            Test fixture is too flat for midpoint deviation metric.
            midpointDeviation([0,0.5,1]) = \(err)

            Either choose a more curved fixture (fastSCurve2, etc.)
            or construct a known-curved cubic directly for this test.
            """
        )

        var cfg = SamplingConfig()
        cfg.mode = .adaptive
        cfg.flatnessEps = err * 0.5     // guarantee it must subdivide if err > 0
        cfg.maxDepth = 12
        cfg.maxSamples = 512

        let sampler = GlobalTSampler()
        let res = sampler.sampleGlobalT(config: cfg, positionAt: positionAt)

        try SamplingInvariants.validate(ts: res.ts, maxSamples: cfg.maxSamples, tEps: cfg.tEps)
        XCTAssertGreaterThan(res.ts.count, 2, "Expected subdivision: err=\(err), flatnessEps=\(cfg.flatnessEps)")
    }

func testRailDeviation_SubdividesEvenWhenCenterlineIsStraight() throws {
    // Straight skeleton
    let p0 = Vec2(0, 0)
    let p1 = Vec2(100, 0)

    let positionAt: GlobalTSampler.PositionAtS = { s in
        p0.lerp(to: p1, t: s)
    }

    // Rail probe with NONLINEAR WORLD-SPACE MOTION
    struct TestRailProbe: RailProbe {
        func rails(atGlobalT t: Double) -> RailSample {
            let x = t * 100

            // Quadratic bump: midpoint is NOT on chord midpoint
            let bump = 20 * t * (1 - t)

            let left  = Vec2(x + bump,  20)
            let right = Vec2(x - bump, -20)

            return RailSample(left: left, right: right)
        }
    }


    var cfg = SamplingConfig()
    cfg.mode = .adaptive
    cfg.flatnessEps = 1e-9        // geometry says “flat”
    cfg.railEps = 1.0             // rail deviation must trigger
    cfg.maxDepth = 12
    cfg.maxSamples = 512

    let sampler = GlobalTSampler()
    let res = sampler.sampleGlobalT(
        config: cfg,
        positionAt: positionAt,
        railProbe: TestRailProbe()
    )

    try SamplingInvariants.validate(ts: res.ts, maxSamples: cfg.maxSamples, tEps: cfg.tEps)

    XCTAssertGreaterThan(
        res.ts.count, 2,
        "Expected rail deviation to force subdivision even on a straight centerline."
    )

    XCTAssertTrue(
        res.trace.contains {
            $0.reasons.contains {
                if case .subdivideRailDeviation = $0 { return true }
                return false
            }
        },
        "Expected at least one rail-deviation subdivision in trace."
    )
}



}
