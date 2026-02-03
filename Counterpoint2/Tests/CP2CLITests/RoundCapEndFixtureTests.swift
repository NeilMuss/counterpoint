import XCTest
import CP2Geometry
import CP2Skeleton
@testable import cp2_cli

final class RoundCapEndFixtureTests: XCTestCase {
    func testRoundEndCapProducesArc() throws {
        let spec = try loadSpecOrThrow(path: "Fixtures/glyphs/gallery_lines/line_02_roundcap_end.v0.json")
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
        options.debugCapBoundary = true
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
        let roundResult = runSweep(
            path: path,
            plan: plan,
            options: options,
            capNamespace: stroke.id,
            startCap: params.startCap ?? .butt,
            endCap: params.endCap ?? .butt
        )

        let roundMaxX = roundResult.ring.map { $0.x }.max() ?? 0.0
        XCTAssertGreaterThan(roundMaxX, 461.0)

        let boundary = roundResult.capBoundaryDebugs.first { $0.endpoint == "end" }
        XCTAssertNotNil(boundary)
        XCTAssertGreaterThan(boundary?.arcPoints.count ?? 0, 0)

        let arcPoints = roundResult.ring.filter { $0.x > 460.0 }
        XCTAssertGreaterThan(arcPoints.count, 4)
        let arcSigns = curvatureSigns(points: arcPoints)
        XCTAssertGreaterThan(arcSigns.count, 2)
        XCTAssertTrue(arcSigns.allSatisfy { $0 == arcSigns.first })

        let buttResult = runSweep(
            path: path,
            plan: plan,
            options: options,
            capNamespace: stroke.id,
            startCap: params.startCap ?? .butt,
            endCap: .butt
        )
        let buttMaxX = buttResult.ring.map { $0.x }.max() ?? 0.0
        XCTAssertGreaterThan(roundMaxX - buttMaxX, 5.0)
    }
}

private func curvatureSigns(points: [Vec2]) -> [Int] {
    guard points.count >= 3 else { return [] }
    var signs: [Int] = []
    for i in 1..<(points.count - 1) {
        let a = points[i - 1]
        let b = points[i]
        let c = points[i + 1]
        let u = b - a
        let v = c - b
        let cross = u.x * v.y - u.y * v.x
        if abs(cross) > 1.0e-6 {
            signs.append(cross > 0 ? 1 : -1)
        }
    }
    return signs
}
