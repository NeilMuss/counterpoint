import XCTest
import CP2Geometry
import CP2Skeleton
@testable import cp2_cli

final class CapFilletLineFixtureTests: XCTestCase {
    func testCapFilletLineRendersAids() throws {
        let spec = try loadSpecOrThrow(path: "Fixtures/glyphs/cap_fillet_line.v0.json")
        var options = CLIOptions()
        options.capFilletFixtureOverlays = true
        let svg = try renderSVGString(options: options, spec: spec)
        XCTAssertTrue(svg.contains("cap-fillet-line-aids-butt"))
        XCTAssertTrue(svg.contains("cap-fillet-line-aids-fillet"))
        XCTAssertTrue(svg.contains("cap-fillet-line-arc-points-fillet"))
    }

    func testCapFilletLineRingRetainsArc() {
        var options = CLIOptions()
        options.capFilletArcSegments = 32
        let path = SkeletonPath(segments: [lineCubic(from: Vec2(0, -70), to: Vec2(200, -70))])
        let funcs = StrokeParamFuncs(
            alphaStartGT: 0.0,
            alphaEndValue: 1.0,
            widthAtT: { _ in 80.0 },
            widthLeftAtT: { _ in 40.0 },
            widthRightAtT: { _ in 40.0 },
            widthLeftSegmentAlphaAtT: { _ in 1.0 },
            widthRightSegmentAlphaAtT: { _ in 1.0 },
            thetaAtT: { _ in 0.0 },
            offsetAtT: { _ in 0.0 },
            alphaAtT: { _ in 1.0 },
            usesVariableWidthAngleAlpha: true,
            angleMode: .relative,
            paramKeyframeTs: [0.0, 1.0]
        )
        let plan = makeSweepPlan(
            options: options,
            funcs: funcs,
            baselineWidth: 80.0,
            sweepWidth: 80.0,
            sweepHeight: 10.0,
            sweepSampleCount: 64
        )
        let result = runSweep(
            path: path,
            plan: plan,
            options: options,
            capNamespace: "fillet",
            startCap: .butt,
            endCap: .fillet(radius: 5.0, corner: .both)
        )
        let leftRail = [Vec2(0, -30), Vec2(200, -30)]
        let rightRail = [Vec2(0, -110), Vec2(200, -110)]
        let base = baseCapPolyline(leftRail: leftRail, rightRail: rightRail, atStart: false)
        XCTAssertEqual(base.count, 4)
        let leftPrev = base[0]
        let leftEnd = base[1]
        let rightEnd = base[2]
        let rightPrev = base[3]
        let leftEdge = (leftEnd - leftPrev).normalized()
        let endFace = (rightEnd - leftEnd).normalized()
        let rightEdge = (rightPrev - rightEnd).normalized()
        XCTAssertLessThan(abs(leftEdge.dot(endFace)), 1.0e-6)
        XCTAssertLessThan(abs(endFace.dot(rightEdge)), 1.0e-6)
        let endLeft = result.capFillets.first { $0.kind == "end" && $0.side == "left" && $0.success }
        let endRight = result.capFillets.first { $0.kind == "end" && $0.side == "right" && $0.success }
        XCTAssertNotNil(endLeft)
        XCTAssertNotNil(endRight)
        XCTAssertGreaterThanOrEqual(endLeft?.insertedPoints ?? 0, 20)
        XCTAssertGreaterThanOrEqual(endRight?.insertedPoints ?? 0, 20)
        guard let left = endLeft, let right = endRight else { return }
        XCTAssertLessThan(abs((left.corner - left.p).length - left.radius), 1.0e-6)
        XCTAssertLessThan(abs((left.q - left.corner).length - left.radius), 1.0e-6)
        XCTAssertLessThan(abs((right.corner - right.p).length - right.radius), 1.0e-6)
        XCTAssertLessThan(abs((right.q - right.corner).length - right.radius), 1.0e-6)
        let ringPoints = result.rings.flatMap { $0 }
        let arcSamples = sampleArcPoints(left: left, right: right, segments: options.capFilletArcSegments)
        let arcHits = ringPoints.filter { ringPoint in
            arcSamples.contains { (ringPoint - $0).length <= 1.0e-6 }
        }
        XCTAssertGreaterThanOrEqual(arcHits.count, 40)
        let chordA = right.p
        let chordB = left.q
        let chordMatches = result.segmentsUsed.filter { seg in
            (Epsilon.approxEqual(seg.a, chordA) && Epsilon.approxEqual(seg.b, chordB)) ||
            (Epsilon.approxEqual(seg.a, chordB) && Epsilon.approxEqual(seg.b, chordA))
        }
        XCTAssertFalse(chordMatches.isEmpty)
        let bypassA = left.corner
        let bypassB = right.corner
        let bypassMatches = result.segmentsUsed.filter { seg in
            (Epsilon.approxEqual(seg.a, bypassA) && Epsilon.approxEqual(seg.b, bypassB)) ||
            (Epsilon.approxEqual(seg.a, bypassB) && Epsilon.approxEqual(seg.b, bypassA))
        }
        XCTAssertTrue(bypassMatches.isEmpty)
        var maxDist = 0.0
        for point in arcHits {
            maxDist = max(maxDist, distancePointToSegment(point, chordA, chordB))
        }
        XCTAssertGreaterThan(maxDist, 1.0)
    }
}

private func distancePointToSegment(_ p: Vec2, _ a: Vec2, _ b: Vec2) -> Double {
    let ab = b - a
    let denom = max(Epsilon.defaultValue, ab.dot(ab))
    let t = max(0.0, min(1.0, (p - a).dot(ab) / denom))
    let proj = a + ab * t
    return (p - proj).length
}

private func sampleArcPoints(left: CapFilletDebug, right: CapFilletDebug, segments: Int) -> [Vec2] {
    let steps = max(2, segments + 1)
    var points: [Vec2] = []
    if let bridge = left.bridge {
        var local: [Vec2] = []
        for i in 0..<steps {
            let t = Double(i) / Double(steps - 1)
            local.append(bridge.evaluate(t))
        }
        if local.count >= 2 {
            local[0] = left.p
            local[local.count - 1] = left.q
        }
        points.append(contentsOf: local)
    }
    if let bridge = right.bridge {
        var local: [Vec2] = []
        for i in 0..<steps {
            let t = Double(i) / Double(steps - 1)
            local.append(bridge.evaluate(t))
        }
        if local.count >= 2 {
            local[0] = right.p
            local[local.count - 1] = right.q
        }
        points.append(contentsOf: local)
    }
    return points
}
