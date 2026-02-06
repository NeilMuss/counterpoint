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

        let determinism = DeterminismPolicy(eps: 1.0e-6, stableSort: .lexicographicXYThenIndex)
        let (resolved, artifacts) = ResolveSelfOverlapUseCase.run(
            ring: sweep.ring,
            policy: determinism,
            selectionPolicy: .rectCornersBBox(minAreaRatio: 0.01, minBBoxRatio: 0.01),
            includeDebug: false
        )

        let ring = resolved.success ? resolved.ring : sweep.ring
        let bounds = ringBounds(ring)
        let width = bounds.max.x - bounds.min.x
        let height = bounds.max.y - bounds.min.y

        XCTAssertGreaterThan(width, 300.0)
        XCTAssertGreaterThan(height, 150.0)

        if let faces = artifacts?.faceSet.faces, !faces.isEmpty {
            let maxAbsArea = faces.map { abs($0.area) }.max() ?? 0.0
            XCTAssertGreaterThan(resolved.selectedAbsArea, 0.5 * maxAbsArea)
        } else {
            XCTFail("expected faces for rectCorners selection")
        }
    }

    func testFinalRingChooserPicksMaxAbsArea() throws {
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

        let maxAbsArea = sweep.rings.map { abs(signedArea($0)) }.max() ?? 0.0
        let selectedAbsArea = abs(signedArea(sweep.ring))
        XCTAssertEqual(selectedAbsArea, maxAbsArea, accuracy: 1.0e-6)

        let bounds = ringBounds(sweep.ring)
        let width = bounds.max.x - bounds.min.x
        let height = bounds.max.y - bounds.min.y
        XCTAssertGreaterThan(width, 300.0)
        XCTAssertGreaterThan(height, 150.0)
    }
}
