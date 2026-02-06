import XCTest
import CP2Geometry
import CP2Skeleton
@testable import cp2_cli

final class Wavy07NoHolesTests: XCTestCase {
    func testWavy07RingHasNoSelfIntersections() throws {
        let spec = try loadSpecOrThrow(path: "Fixtures/glyphs/gallery_lines/line_07_piecewise_alpha_middle_wavy.v0.json")
        guard let ink = spec.ink else {
            XCTFail("expected ink in spec")
            return
        }
        guard let stroke = spec.strokes?.first else {
            XCTFail("expected stroke")
            return
        }
        guard let params = stroke.params else {
            XCTFail("expected params")
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
        options.debugRingTopology = true
        options.resolveSelfOverlap = true
        options.example = "line_07_piecewise_alpha_middle_wavy"
        let provider = SpecParamProvider(params: params)
        let funcs = provider.makeParamFuncs(options: options, exampleName: spec.example, sweepWidth: 20.0)
        let plan = makeSweepPlan(
            options: options,
            funcs: funcs,
            baselineWidth: 20.0,
            sweepWidth: 20.0,
            sweepHeight: 10.0,
            sweepSampleCount: 96
        )
        let result = runSweep(
            path: path,
            plan: plan,
            options: options,
            capNamespace: stroke.id,
            startCap: params.startCap ?? .butt,
            endCap: params.endCap ?? .butt
        )

        XCTAssertFalse(result.finalContour.points.isEmpty)
        let intersections = ringSelfIntersections(points: result.finalContour.points, eps: 1.0e-6)
        XCTAssertEqual(intersections.count, 0)
        XCTAssertEqual(result.ringTopology?.rings.count, 1)
        let area = abs(signedArea(result.finalContour.points))
        XCTAssertGreaterThan(area, 1000.0)
    }
}

private func ringSelfIntersections(points: [Vec2], eps: Double) -> [Vec2] {
    let n = points.count
    guard n >= 4 else { return [] }
    let lastIsFirst = Epsilon.approxEqual(points.first!, points.last!)
    let edgeCount = lastIsFirst ? n - 1 : n
    func cross(_ a: Vec2, _ b: Vec2) -> Double { a.x * b.y - a.y * b.x }
    func segmentIntersection(_ a: Vec2, _ b: Vec2, _ c: Vec2, _ d: Vec2) -> Vec2? {
        let r = b - a
        let s = d - c
        let denom = cross(r, s)
        if abs(denom) <= eps { return nil }
        let t = cross(c - a, s) / denom
        let u = cross(c - a, r) / denom
        if t >= -eps && t <= 1.0 + eps && u >= -eps && u <= 1.0 + eps {
            return Vec2(a.x + r.x * t, a.y + r.y * t)
        }
        return nil
    }
    var hits: [Vec2] = []
    for i in 0..<edgeCount {
        let a0 = points[i]
        let a1 = points[(i + 1) % edgeCount]
        if (a1 - a0).length <= eps { continue }
        if i + 2 >= edgeCount { continue }
        for j in (i + 2)..<edgeCount {
            if i == 0 && j == edgeCount - 1 { continue }
            let b0 = points[j]
            let b1 = points[(j + 1) % edgeCount]
            if (b1 - b0).length <= eps { continue }
            if let hit = segmentIntersection(a0, a1, b0, b1) {
                if Epsilon.approxEqual(hit, a0, eps: eps)
                    || Epsilon.approxEqual(hit, a1, eps: eps)
                    || Epsilon.approxEqual(hit, b0, eps: eps)
                    || Epsilon.approxEqual(hit, b1, eps: eps) {
                    continue
                }
                hits.append(hit)
            }
        }
    }
    return hits
}

private func signedArea(_ ring: [Vec2]) -> Double {
    guard ring.count >= 3 else { return 0.0 }
    var area = 0.0
    for i in 0..<(ring.count - 1) {
        let a = ring[i]
        let b = ring[i + 1]
        area += (a.x * b.y - b.x * a.y)
    }
    return area * 0.5
}
