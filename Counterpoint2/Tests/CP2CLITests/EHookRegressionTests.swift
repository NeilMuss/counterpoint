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
