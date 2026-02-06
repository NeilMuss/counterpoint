import XCTest
import CP2Geometry
import CP2Skeleton
import CP2Domain
import CP2ResolveOverlap
@testable import cp2_cli

final class RectCornersSelectionTests: XCTestCase {
    func testRectCornersSelectionChoosesLargeSilhouetteForWavy14() throws {
        let spec = try loadSpecOrThrow(path: "Fixtures/glyphs/gallery_lines/line_14_translation_wavy.v0.json")
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
        options.example = spec.example
        options.penShape = .rectCorners
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

        if case .resolvedFace = sweep.finalContour.provenance {
            XCTAssertEqual(sweep.finalContour.selfX, 0)
            let bounds = ringBounds(sweep.finalContour.points)
            XCTAssertGreaterThan(bounds.max.x, 400.0)
            XCTAssertLessThan(bounds.min.y, -100.0)
        } else {
            XCTFail("expected final contour to be selected from planarized faces")
        }
    }

    func testFinalRingChooserPrefersSimpleRingWhenAvailable() throws {
        let spec = try loadSpecOrThrow(path: "Fixtures/glyphs/gallery_lines/line_14_translation_wavy.v0.json")
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
        options.example = spec.example
        options.penShape = .rectCorners
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

        XCTAssertGreaterThan(sweep.envelopeSelfX, 0)
        XCTAssertEqual(ringSelfIntersectionCount(sweep.finalContour.points), 0)
        let bounds = ringBounds(sweep.finalContour.points)
        XCTAssertGreaterThan(bounds.max.x, 400.0)
        XCTAssertLessThan(bounds.min.y, -100.0)
    }
}
