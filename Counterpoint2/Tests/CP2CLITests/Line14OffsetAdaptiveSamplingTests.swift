import XCTest
import CP2Geometry
import CP2Skeleton
@testable import cp2_cli

final class Line14OffsetAdaptiveSamplingTests: XCTestCase {
    func testLine14OffsetShowsSilhouetteShift() throws {
        let spec = try loadSpecOrThrow(path: "Fixtures/glyphs/gallery_lines/line_14_offset.v0.json")
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
        options.adaptiveSampling = true
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

        let ring = result.ring
        XCTAssertFalse(ring.isEmpty)
        let startMaxY = maxY(in: ring, xMin: 20, xMax: 60)
        let midMaxY = maxY(in: ring, xMin: 210, xMax: 250)
        let lateMaxY = maxY(in: ring, xMin: 330, xMax: 370)
        XCTAssertGreaterThan(abs(midMaxY - startMaxY), 5.0)
        XCTAssertGreaterThan(abs(lateMaxY - startMaxY), 5.0)
    }
}

private func maxY(in ring: [Vec2], xMin: Double, xMax: Double) -> Double {
    let candidates = ring.filter { $0.x >= xMin && $0.x <= xMax }
    return candidates.map { $0.y }.max() ?? 0.0
}
