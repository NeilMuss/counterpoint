import XCTest
import CP2Geometry
import CP2Skeleton
@testable import cp2_cli

final class ButtCapNoOverhangTests: XCTestCase {
    func testWavy07ButtCapHasNoOverhang() throws {
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
        options.debugCapBoundary = true
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

        let endLeft = result.capPlaneDebugs.first { $0.endpoint == "end" && $0.side == "left" }
        let endRight = result.capPlaneDebugs.first { $0.endpoint == "end" && $0.side == "right" }
        XCTAssertNotNil(endLeft)
        XCTAssertNotNil(endRight)
        if let left = endLeft {
            XCTAssertLessThanOrEqual(left.maxOverhangAfter, 1.0e-6)
        }
        if let right = endRight {
            XCTAssertLessThanOrEqual(right.maxOverhangAfter, 1.0e-6)
        }
    }
}
