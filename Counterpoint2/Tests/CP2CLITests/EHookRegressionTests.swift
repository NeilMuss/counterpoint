import XCTest
import CP2Geometry
import CP2Skeleton
@testable import cp2_cli

final class EHookRegressionTests: XCTestCase {
    func testEHookStartCapArcIsInRing() throws {
        let spec = try loadSpecOrThrow(path: "Fixtures/glyphs/e.v0.json")
        guard let ink = spec.ink else {
            XCTFail("expected ink in spec")
            return
        }
        guard let stroke = spec.strokes?.first(where: { $0.id == "e-bowl" }) else {
            XCTFail("expected e-bowl stroke")
            return
        }
        guard let params = stroke.params else {
            XCTFail("expected stroke params")
            return
        }
        let segments = try resolveInkSegments(
            name: stroke.ink,
            ink: ink,
            strict: true,
            warn: { _ in }
        )
        guard !segments.isEmpty else {
            XCTFail("expected at least one ink segment")
            return
        }
        let path = SkeletonPath(segments: segments.map(cubicForSegment))
        var options = CLIOptions()
        options.capFilletArcSegments = 8
        let provider = SpecParamProvider(params: params)
        let funcs = provider.makeParamFuncs(options: options, exampleName: spec.example, sweepWidth: 20.0)
        let plan = makeSweepPlan(
            options: options,
            funcs: funcs,
            baselineWidth: 20.0,
            sweepWidth: 20.0,
            sweepHeight: 10.0,
            sweepSampleCount: 64
        )
        let result = runSweep(
            path: path,
            plan: plan,
            options: options,
            capNamespace: stroke.id,
            startCap: params.startCap ?? .butt,
            endCap: params.endCap ?? .butt
        )
        guard let startLeft = result.capFillets.first(where: { $0.kind == "start" && $0.side == "left" && $0.success }) else {
            XCTFail("expected successful start-left fillet for e-bowl")
            return
        }
        let arcSamples = sampleArcPoints(fillet: startLeft, segments: options.capFilletArcSegments)
        let ringPoints = result.rings.flatMap { $0 }
        let arcHits = ringPoints.filter { ringPoint in
            arcSamples.contains { (ringPoint - $0).length <= 1.0e-6 }
        }
        XCTAssertGreaterThanOrEqual(arcHits.count, 6)

        let ring = result.ring
        guard !ring.isEmpty else {
            XCTFail("expected non-empty ring for e-bowl")
            return
        }
        let centroid = polygonCentroid(ring)
        let avgPoint = ring.reduce(Vec2(0, 0)) { $0 + $1 } * (1.0 / Double(max(1, ring.count)))
        let anchorCandidates = [centroid, avgPoint, ring.first ?? Vec2(0, 0), ring[ring.count / 2]]
        let anchor = anchorCandidates.first { pointInPolygon($0, polygon: ring) } ?? centroid
        let hookDir = (anchor - startLeft.arcMidpoint).normalized()
        let probe1 = startLeft.arcMidpoint + hookDir * 5.0
        let probe2 = startLeft.p + hookDir * 5.0
        let probe3 = startLeft.q + hookDir * 5.0
        let probes = [probe1, probe2, probe3]
        let insideCount = probes.filter { pointInPolygon($0, polygon: ring) }.count
        XCTAssertGreaterThanOrEqual(insideCount, 2)
        let outsideProbe = startLeft.arcMidpoint - hookDir * 8.0
        XCTAssertFalse(pointInPolygon(outsideProbe, polygon: ring))
    }
}

private func sampleArcPoints(fillet: CapFilletDebug, segments: Int) -> [Vec2] {
    guard let bridge = fillet.bridge else { return [] }
    let steps = max(2, segments + 1)
    var points: [Vec2] = []
    points.reserveCapacity(steps)
    for i in 0..<steps {
        let t = Double(i) / Double(steps - 1)
        points.append(bridge.evaluate(t))
    }
    if points.count >= 2 {
        points[0] = fillet.p
        points[points.count - 1] = fillet.q
    }
    return points
}

private func pointInPolygon(_ point: Vec2, polygon: [Vec2]) -> Bool {
    guard polygon.count >= 3 else { return false }
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

private func polygonCentroid(_ polygon: [Vec2]) -> Vec2 {
    guard polygon.count >= 3 else { return Vec2(0, 0) }
    var area = 0.0
    var cx = 0.0
    var cy = 0.0
    for i in 0..<polygon.count {
        let a = polygon[i]
        let b = polygon[(i + 1) % polygon.count]
        let cross = a.x * b.y - b.x * a.y
        area += cross
        cx += (a.x + b.x) * cross
        cy += (a.y + b.y) * cross
    }
    area *= 0.5
    if abs(area) <= 1.0e-12 {
        let sum = polygon.reduce(Vec2(0, 0)) { $0 + $1 }
        return sum * (1.0 / Double(polygon.count))
    }
    let factor = 1.0 / (6.0 * area)
    return Vec2(cx * factor, cy * factor)
}
