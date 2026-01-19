import Foundation
import XCTest
import CP2Geometry
import CP2Skeleton

final class ScallopMetricsTests: XCTestCase {
    func testScallopMetricsDistinguishSmoothFromWavy() {
        let smooth = (0...24).map { i -> Vec2 in
            let t = Double(i) / 24.0
            let angle = t * Double.pi * 0.5
            return Vec2(cos(angle), sin(angle))
        }
        let wavy = (0...80).map { i -> Vec2 in
            let t = Double(i) / 80.0
            let x = t * 2.0
            let y = 0.15 * sin(t * Double.pi * 8.0)
            return Vec2(x, y)
        }

        let smoothMetrics = analyzeScallops(
            points: smooth,
            width: 1.0,
            halfWindow: 12,
            epsilon: 1.0e-6,
            cornerThreshold: 2.5,
            capTrim: 2
        )
        let wavyMetrics = analyzeScallops(
            points: wavy,
            width: 1.0,
            halfWindow: 20,
            epsilon: 1.0e-6,
            cornerThreshold: 2.5,
            capTrim: 2
        )

        XCTAssertGreaterThan(wavyMetrics.raw.maxChordDeviation, smoothMetrics.raw.maxChordDeviation)
        XCTAssertGreaterThan(wavyMetrics.raw.normalizedMaxChordDeviation, smoothMetrics.raw.normalizedMaxChordDeviation)
    }

    func testScallopMetricsShowFastSCurveHigherThanSCurve() {
        let width = 20.0
        let height = 10.0
        let samples = 64
        let scurveSoup = boundarySoup(
            path: SkeletonPath(segments: [sCurveFixtureCubic()]),
            width: width,
            height: height,
            effectiveAngle: 0,
            sampleCount: samples
        )
        let fastSoup = boundarySoup(
            path: SkeletonPath(segments: [fastSCurveFixtureCubic()]),
            width: width,
            height: height,
            effectiveAngle: 0,
            sampleCount: samples
        )
        let scurveRing = stripDuplicateClosure(traceLoops(segments: scurveSoup, eps: 1.0e-6).first ?? [])
        let fastRing = stripDuplicateClosure(traceLoops(segments: fastSoup, eps: 1.0e-6).first ?? [])

        let scurveMetrics = analyzeScallops(
            points: scurveRing,
            width: width,
            halfWindow: 20,
            epsilon: 1.0e-6,
            cornerThreshold: 2.5,
            capTrim: 4
        )
        let fastMetrics = analyzeScallops(
            points: fastRing,
            width: width,
            halfWindow: 20,
            epsilon: 1.0e-6,
            cornerThreshold: 2.5,
            capTrim: 4
        )

        XCTAssertGreaterThan(fastMetrics.filtered.normalizedMaxChordDeviation, scurveMetrics.filtered.normalizedMaxChordDeviation * 1.2)
    }

    func testScallopMetricsOrderingAcrossStressLadder() {
        let width = 20.0
        let height = 10.0
        let samples = 64
        let scurveRing = stripDuplicateClosure(traceLoops(
            segments: boundarySoup(
                path: SkeletonPath(segments: [sCurveFixtureCubic()]),
                width: width,
                height: height,
                effectiveAngle: 0,
                sampleCount: samples
            ),
            eps: 1.0e-6
        ).first ?? [])
        let fastRing = stripDuplicateClosure(traceLoops(
            segments: boundarySoup(
                path: SkeletonPath(segments: [fastSCurveFixtureCubic()]),
                width: width,
                height: height,
                effectiveAngle: 0,
                sampleCount: samples
            ),
            eps: 1.0e-6
        ).first ?? [])
        let fast2Ring = stripDuplicateClosure(traceLoops(
            segments: boundarySoup(
                path: SkeletonPath(segments: [fastSCurve2FixtureCubic()]),
                width: width,
                height: height,
                effectiveAngle: 0,
                sampleCount: samples
            ),
            eps: 1.0e-6
        ).first ?? [])

        let scurveMetrics = analyzeScallops(
            points: scurveRing,
            width: width,
            halfWindow: 20,
            epsilon: 1.0e-6,
            cornerThreshold: 2.5,
            capTrim: 4
        )
        let fastMetrics = analyzeScallops(
            points: fastRing,
            width: width,
            halfWindow: 20,
            epsilon: 1.0e-6,
            cornerThreshold: 2.5,
            capTrim: 4
        )
        let fast2Metrics = analyzeScallops(
            points: fast2Ring,
            width: width,
            halfWindow: 20,
            epsilon: 1.0e-6,
            cornerThreshold: 2.5,
            capTrim: 4
        )

        XCTAssertGreaterThanOrEqual(
            fastMetrics.filtered.normalizedMaxChordDeviation,
            scurveMetrics.filtered.normalizedMaxChordDeviation * 1.3
        )
        XCTAssertGreaterThanOrEqual(
            fast2Metrics.filtered.normalizedMaxChordDeviation,
            fastMetrics.filtered.normalizedMaxChordDeviation * 1.2
        )
    }
}

private func stripDuplicateClosure(_ ring: [Vec2]) -> [Vec2] {
    guard ring.count > 1, Epsilon.approxEqual(ring.first ?? Vec2(0, 0), ring.last ?? Vec2(0, 0), eps: 1.0e-9) else {
        return ring
    }
    return Array(ring.dropLast())
}
