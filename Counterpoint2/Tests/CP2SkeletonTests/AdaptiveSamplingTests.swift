import Foundation
import XCTest
import CP2Geometry
import CP2Skeleton

final class AdaptiveSamplingTests: XCTestCase {
    func testAdaptiveSamplerDeterministicAndIncludesEndpoints() {
        let cubic = CubicBezier2(
            p0: Vec2(0, 0),
            p1: Vec2(0, 33),
            p2: Vec2(0, 66),
            p3: Vec2(0, 100)
        )
        let samplesA = AdaptiveSampler.sampleCubic(
            cubic: cubic,
            maxDepth: 12,
            flatnessEps: 0.25,
            maxSamples: 512
        )
        let samplesB = AdaptiveSampler.sampleCubic(
            cubic: cubic,
            maxDepth: 12,
            flatnessEps: 0.25,
            maxSamples: 512
        )
        XCTAssertEqual(samplesA, samplesB)
        XCTAssertEqual(samplesA.first, 0.0)
        XCTAssertEqual(samplesA.last, 1.0)
        XCTAssertTrue(samplesA.count >= 2)
        XCTAssertEqual(samplesA, samplesA.sorted())
    }

    func testAdaptiveSamplerRefinesFastCurvesMoreThanSCurve() {
        let scurve = sCurveFixtureCubic()
        let fast = fastSCurve2FixtureCubic()
        let samplesS = AdaptiveSampler.sampleCubic(
            cubic: scurve,
            maxDepth: 12,
            flatnessEps: 0.25,
            maxSamples: 512
        )
        let samplesF = AdaptiveSampler.sampleCubic(
            cubic: fast,
            maxDepth: 12,
            flatnessEps: 0.25,
            maxSamples: 512
        )
        XCTAssertGreaterThan(samplesF.count, samplesS.count)
        XCTAssertLessThanOrEqual(samplesS.count, 512)
        XCTAssertLessThanOrEqual(samplesF.count, 512)
    }
}
