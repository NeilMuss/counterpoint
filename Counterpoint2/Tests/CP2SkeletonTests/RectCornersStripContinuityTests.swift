import XCTest
import CP2Geometry
@testable import CP2Skeleton

final class RectCornersStripContinuityTests: XCTestCase {
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

    private func approxEqual(_ a: Vec2, _ b: Vec2, eps: Double = 1.0e-6) -> Bool {
        return abs(a.x - b.x) <= eps && abs(a.y - b.y) <= eps
    }

    private func segmentsIntersect(_ a0: Vec2, _ a1: Vec2, _ b0: Vec2, _ b1: Vec2, eps: Double = 1.0e-9) -> Bool {
        func orient(_ p: Vec2, _ q: Vec2, _ r: Vec2) -> Double {
            return (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x)
        }
        let o1 = orient(a0, a1, b0)
        let o2 = orient(a0, a1, b1)
        let o3 = orient(b0, b1, a0)
        let o4 = orient(b0, b1, a1)
        if (o1 > eps && o2 < -eps) || (o1 < -eps && o2 > eps) {
            if (o3 > eps && o4 < -eps) || (o3 < -eps && o4 > eps) {
                return true
            }
        }
        return false
    }

    func testRectCorners_NoLaneTwistAcrossSamples() {
        let path = wavyPath()
        let param = SkeletonPathParameterization(path: path, samplesPerSegment: 256)
        var config = SamplingConfig()
        config.mode = .fixed(count: 12)
        let sampler = GlobalTSampler()
        let sampling = sampler.sampleGlobalT(
            config: config,
            positionAt: { t in param.position(globalT: t) }
        )
        let sampleCount = sampling.ts.count
        XCTAssertGreaterThanOrEqual(sampleCount, 8)
        let widthLeft = 12.0
        let widthRight = 12.0
        let height = 6.0

        var corners0: [Vec2] = []
        var corners1: [Vec2] = []
        var corners2: [Vec2] = []
        var corners3: [Vec2] = []
        corners0.reserveCapacity(sampleCount)
        corners1.reserveCapacity(sampleCount)
        corners2.reserveCapacity(sampleCount)
        corners3.reserveCapacity(sampleCount)

        let styleAtGT: (Double) -> SweepStyle = { _ in
            SweepStyle(
                width: widthLeft + widthRight,
                widthLeft: widthLeft,
                widthRight: widthRight,
                height: height,
                angle: 0.0,
                offset: 0.0,
                angleIsRelative: false
            )
        }
        let warpGT: (Double) -> Double = { $0 }

        for (index, gt) in sampling.ts.enumerated() {
            let frame = railSampleFrameAtGlobalT(
                param: param,
                warpGT: warpGT,
                styleAtGT: styleAtGT,
                gt: gt,
                index: index
            )
            let style = styleAtGT(gt)
            let halfWidth = style.width * 0.5
            let wL = style.widthLeft > 0.0 ? style.widthLeft : halfWidth
            let wR = style.widthRight > 0.0 ? style.widthRight : halfWidth
            let set = penCorners(
                center: frame.center,
                crossAxis: frame.crossAxis,
                widthLeft: wL,
                widthRight: wR,
                height: style.height
            )
            corners0.append(set.c0)
            corners1.append(set.c1)
            corners2.append(set.c2)
            corners3.append(set.c3)
        }

        let loops = buildPenEdgeStripLoops(
            corner0: corners0,
            corner1: corners1,
            corner2: corners2,
            corner3: corners3,
            eps: 1.0e-6
        )
        XCTAssertEqual(loops.count, 4)
        for k in 0..<4 {
            XCTAssertEqual(loops[k].count, sampleCount * 2 + 1)
        }

        let cornerLists = [corners0, corners1, corners2, corners3]
        for k in 0..<4 {
            let loop = loops[k]
            for i in 0..<sampleCount {
                XCTAssertTrue(approxEqual(loop[i], cornerLists[k][i]))
                XCTAssertTrue(approxEqual(loop[sampleCount + i], cornerLists[(k + 1) % 4][sampleCount - 1 - i]))
            }
        }

        for i in 0..<(sampleCount - 1) {
            for k in 0..<4 {
                let a0 = cornerLists[k][i]
                let a1 = cornerLists[k][i + 1]
                let b0 = cornerLists[(k + 1) % 4][i]
                let b1 = cornerLists[(k + 1) % 4][i + 1]
                XCTAssertFalse(segmentsIntersect(a0, a1, b0, b1))
            }
        }
    }
}
