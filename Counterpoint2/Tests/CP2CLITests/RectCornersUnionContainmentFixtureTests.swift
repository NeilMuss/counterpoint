import XCTest
import CP2Geometry
import CP2Skeleton
@testable import cp2_cli

final class RectCornersUnionContainmentFixtureTests: XCTestCase {
    func testLine14WavyStampCornersAreInsideOutputContour() throws {
        let spec = try loadSpecOrThrow(path: "Fixtures/glyphs/gallery_lines/line_14_translation_wavy.v0.json")
        guard let ink = spec.ink, let stroke = spec.strokes?.first, let params = stroke.params else {
            XCTFail("expected ink and stroke params")
            return
        }
        let segments = try resolveInkSegments(
            name: stroke.ink,
            ink: ink,
            strict: true,
            warn: { _ in }
        )
        let path = SkeletonPath(segments: segments.map(cubicForSegment))

        var options = CLIOptions()
        options.example = spec.example
        options.penShape = .rectCorners
        options.debugPenStamps = true

        let provider = SpecParamProvider(params: params)
        let funcs = provider.makeParamFuncs(options: options, exampleName: spec.example, sweepWidth: 20.0)
        let plan = makeSweepPlan(
            options: options,
            funcs: funcs,
            baselineWidth: 20.0,
            sweepWidth: 20.0,
            sweepHeight: 6.0,
            sweepSampleCount: 64
        )

        let sweep = runSweep(
            path: path,
            plan: plan,
            options: options,
            capNamespace: "test",
            startCap: .butt,
            endCap: .butt
        )

        guard let stamps = sweep.penStamps?.samples, !stamps.isEmpty else {
            XCTFail("expected pen stamps")
            return
        }
        let ring = ensureClosed(sweep.finalContour.points)
        let step = 7
        let eps = 1.0e-3
        for index in stride(from: 0, to: stamps.count, by: step) {
            let corners = stamps[index].corners
            for corner in corners {
                XCTAssertTrue(pointInPolygonOrOnEdge(corner, polygon: ring, eps: eps))
            }
        }
    }
}

private func ensureClosed(_ ring: [Vec2]) -> [Vec2] {
    guard let first = ring.first else { return ring }
    if let last = ring.last, Epsilon.approxEqual(first, last, eps: 1.0e-9) {
        return ring
    }
    return ring + [first]
}

private func pointInPolygonOrOnEdge(_ point: Vec2, polygon: [Vec2], eps: Double) -> Bool {
    guard polygon.count >= 4 else { return false }
    for i in 0..<(polygon.count - 1) {
        if distanceToSegment(point, polygon[i], polygon[i + 1]) <= eps {
            return true
        }
    }
    var inside = false
    var j = polygon.count - 1
    for i in 0..<polygon.count {
        let pi = polygon[i]
        let pj = polygon[j]
        let intersects = ((pi.y > point.y) != (pj.y > point.y)) &&
            (point.x < (pj.x - pi.x) * (point.y - pi.y) / ((pj.y - pi.y) + 1.0e-12) + pi.x)
        if intersects { inside.toggle() }
        j = i
    }
    return inside
}

private func distanceToSegment(_ p: Vec2, _ a: Vec2, _ b: Vec2) -> Double {
    let ab = b - a
    let denom = ab.dot(ab)
    if denom <= 1.0e-12 { return (p - a).length }
    let t = max(0.0, min(1.0, (p - a).dot(ab) / denom))
    let proj = a + ab * t
    return (p - proj).length
}
