import XCTest
import CP2Geometry
@testable import CP2Skeleton

final class PenCornerTests: XCTestCase {
    private func lineCubic(_ a: Vec2, _ b: Vec2) -> CubicBezier2 {
        let d = b - a
        return CubicBezier2(
            p0: a,
            p1: a + d * (1.0 / 3.0),
            p2: a + d * (2.0 / 3.0),
            p3: b
        )
    }

    func testPenCornersBasicDistances() {
        let center = Vec2(0, 0)
        let axis = Vec2(sqrt(0.5), sqrt(0.5))
        let corners = penCorners(
            center: center,
            crossAxis: axis,
            widthLeft: 10,
            widthRight: 10,
            height: 6
        )
        XCTAssertFalse(Epsilon.approxEqual(corners.c0, corners.c1))
        XCTAssertFalse(Epsilon.approxEqual(corners.c1, corners.c2))
        XCTAssertFalse(Epsilon.approxEqual(corners.c2, corners.c3))

        let heightSpan = (corners.c0 - corners.c1).length
        let widthSpan = (corners.c0 - corners.c3).length
        XCTAssertEqual(heightSpan, 12.0, accuracy: 1.0e-6)
        XCTAssertEqual(widthSpan, 20.0, accuracy: 1.0e-6)
    }

    func testRectCornerSoupProducesNonZeroAreaForAbsoluteAngle() {
        let path = SkeletonPath(segments: [
            lineCubic(Vec2(0, 0), Vec2(50, 50)),
            lineCubic(Vec2(50, 50), Vec2(100, 100))
        ])
        let segments = boundarySoupVariableWidthAngleAlpha(
            path: path,
            height: 6.0,
            sampleCount: 32,
            arcSamplesPerSegment: 16,
            adaptiveSampling: false,
            flatnessEps: 0.25,
            railEps: 0.25,
            attrEpsOffset: 0.25,
            attrEpsWidth: 0.25,
            attrEpsAngle: 0.00436,
            attrEpsAlpha: 0.25,
            maxDepth: 8,
            maxSamples: 128,
            widthAtT: { _ in 20.0 },
            widthLeftAtT: nil,
            widthRightAtT: nil,
            angleAtT: { _ in Double.pi * 0.25 },
            offsetAtT: { _ in 0.0 },
            alphaAtT: { _ in 0.0 },
            alphaStart: 0.0,
            angleIsRelative: false,
            keyframeTs: [],
            penShape: .auto
        )
        let rings = traceLoops(segments: segments, eps: 1.0e-6)
        let maxArea = rings.map { abs(signedArea($0)) }.max() ?? 0.0
        XCTAssertGreaterThan(maxArea, 200.0)
    }

    func testRelativeModeUsesRailsOnlyWhenAuto() {
        let path = SkeletonPath(segments: [
            lineCubic(Vec2(0, 0), Vec2(100, 0))
        ])
        let segmentsAuto = boundarySoupVariableWidthAngleAlpha(
            path: path,
            height: 6.0,
            sampleCount: 16,
            arcSamplesPerSegment: 8,
            adaptiveSampling: false,
            flatnessEps: 0.25,
            railEps: 0.25,
            attrEpsOffset: 0.25,
            attrEpsWidth: 0.25,
            attrEpsAngle: 0.00436,
            attrEpsAlpha: 0.25,
            maxDepth: 6,
            maxSamples: 64,
            widthAtT: { _ in 20.0 },
            widthLeftAtT: nil,
            widthRightAtT: nil,
            angleAtT: { _ in 0.0 },
            offsetAtT: { _ in 0.0 },
            alphaAtT: { _ in 0.0 },
            alphaStart: 0.0,
            angleIsRelative: true,
            keyframeTs: [],
            penShape: .auto
        )
        let segmentsRailsOnly = boundarySoupVariableWidthAngleAlpha(
            path: path,
            height: 6.0,
            sampleCount: 16,
            arcSamplesPerSegment: 8,
            adaptiveSampling: false,
            flatnessEps: 0.25,
            railEps: 0.25,
            attrEpsOffset: 0.25,
            attrEpsWidth: 0.25,
            attrEpsAngle: 0.00436,
            attrEpsAlpha: 0.25,
            maxDepth: 6,
            maxSamples: 64,
            widthAtT: { _ in 20.0 },
            widthLeftAtT: nil,
            widthRightAtT: nil,
            angleAtT: { _ in 0.0 },
            offsetAtT: { _ in 0.0 },
            alphaAtT: { _ in 0.0 },
            alphaStart: 0.0,
            angleIsRelative: true,
            keyframeTs: [],
            penShape: .railsOnly
        )
        XCTAssertEqual(segmentsAuto, segmentsRailsOnly)
    }

    func testEdgeStripLoopsCountAndClosure() {
        let samples = 3
        var c0: [Vec2] = []
        var c1: [Vec2] = []
        var c2: [Vec2] = []
        var c3: [Vec2] = []
        for i in 0..<samples {
            let t = Double(i) / Double(max(1, samples - 1))
            let center = Vec2(t * 10.0, 0.0)
            let axis = Vec2(1, 0)
            let corners = penCorners(center: center, crossAxis: axis, widthLeft: 2, widthRight: 2, height: 1)
            c0.append(corners.c0)
            c1.append(corners.c1)
            c2.append(corners.c2)
            c3.append(corners.c3)
        }
        let loops = buildPenEdgeStripLoops(corner0: c0, corner1: c1, corner2: c2, corner3: c3, eps: 1.0e-6)
        XCTAssertEqual(loops.count, 4)
        for loop in loops {
            XCTAssertEqual(loop.count, 2 * samples + 1)
            XCTAssertTrue(Epsilon.approxEqual(loop.first!, loop.last!, eps: 1.0e-6))
        }
    }
}
