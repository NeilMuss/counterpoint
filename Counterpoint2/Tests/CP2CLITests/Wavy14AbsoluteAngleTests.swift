import XCTest
import CP2Geometry
import CP2Skeleton
@testable import cp2_cli

final class Wavy14AbsoluteAngleTests: XCTestCase {
    private func computeMinSeparation(
        path: SkeletonPath,
        plan: SweepPlan,
        options: CLIOptions
    ) -> (minSep: Double, minIndex: Int, minGT: Double, left: Vec2, right: Vec2, tangentDeg: Double, thetaDeg: Double) {
        let result = runSweep(
            path: path,
            plan: plan,
            options: options,
            capNamespace: "test",
            startCap: .butt,
            endCap: .butt
        )
        let ts = result.sampling?.ts ?? [0.0, 0.5, 1.0]
        let pathParam = SkeletonPathParameterization(path: path, samplesPerSegment: options.arcSamples)
        func styleAtGT(_ gt: Double) -> SweepStyle {
            SweepStyle(
                width: plan.scaledWidthAtT(gt),
                widthLeft: plan.scaledWidthLeftAtT(gt),
                widthRight: plan.scaledWidthRightAtT(gt),
                height: plan.sweepHeight,
                angle: plan.thetaAtT(gt),
                offset: plan.offsetAtT(gt),
                angleIsRelative: plan.angleMode == .relative
            )
        }
        var minSep = Double.greatestFiniteMagnitude
        var minIndex = 0
        var minGT = ts.first ?? 0.0
        var minLeft = Vec2(0, 0)
        var minRight = Vec2(0, 0)
        var minTangentDeg = 0.0
        var minThetaDeg = 0.0
        for (index, gt) in ts.enumerated() {
            let frame = railSampleFrameAtGlobalT(
                param: pathParam,
                warpGT: plan.warpT,
                styleAtGT: styleAtGT,
                gt: gt,
                index: index
            )
            let style = styleAtGT(gt)
            let halfWidth = style.width * 0.5
            let wL = style.widthLeft > 0.0 ? style.widthLeft : halfWidth
            let wR = style.widthRight > 0.0 ? style.widthRight : halfWidth
            let corners = penCorners(
                center: frame.center,
                crossAxis: frame.crossAxis,
                widthLeft: wL,
                widthRight: wR,
                height: style.height
            )
            let sep = min((corners.c0 - corners.c1).length, (corners.c3 - corners.c2).length)
            if sep < minSep {
                minSep = sep
                minIndex = index
                minGT = gt
                minLeft = frame.left
                minRight = frame.right
                minTangentDeg = atan2(frame.tangent.y, frame.tangent.x) * 180.0 / Double.pi
                minThetaDeg = plan.thetaAtT(gt) * 180.0 / Double.pi
            }
        }
        return (minSep, minIndex, minGT, minLeft, minRight, minTangentDeg, minThetaDeg)
    }

    private func computeMaxRingArea(
        path: SkeletonPath,
        plan: SweepPlan,
        options: CLIOptions
    ) -> Double {
        let result = runSweep(
            path: path,
            plan: plan,
            options: options,
            capNamespace: "test",
            startCap: .butt,
            endCap: .butt
        )
        let rings = result.rings
        return rings.map { abs(signedArea($0)) }.max() ?? 0.0
    }

    private func computeMaxRingAreaAndBBox(
        path: SkeletonPath,
        plan: SweepPlan,
        options: CLIOptions
    ) -> (area: Double, min: Vec2, max: Vec2) {
        let result = runSweep(
            path: path,
            plan: plan,
            options: options,
            capNamespace: "test",
            startCap: .butt,
            endCap: .butt
        )
        let ring = result.rings.max { abs(signedArea($0)) < abs(signedArea($1)) } ?? []
        guard let first = ring.first else {
            return (0.0, Vec2(0, 0), Vec2(0, 0))
        }
        var minP = first
        var maxP = first
        for p in ring {
            minP = Vec2(min(minP.x, p.x), min(minP.y, p.y))
            maxP = Vec2(max(maxP.x, p.x), max(maxP.y, p.y))
        }
        let area = abs(signedArea(ring))
        return (area, minP, maxP)
    }

    func testWavy14AbsoluteAngleModeHasNonZeroRailSeparationAtTangentMatch() throws {
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
        XCTAssertGreaterThan(plan.sweepSampleCount, 10)
        XCTAssertEqual(plan.angleMode, .absolute)

        let minStats = computeMinSeparation(path: path, plan: plan, options: options)
        if minStats.minSep <= 1.0 {
            XCTFail(String(format: "minSep=%.6f i=%d gt=%.6f left=(%.4f,%.4f) right=(%.4f,%.4f) tangentDeg=%.3f thetaDeg=%.3f", minStats.minSep, minStats.minIndex, minStats.minGT, minStats.left.x, minStats.left.y, minStats.right.x, minStats.right.y, minStats.tangentDeg, minStats.thetaDeg))
        }
    }

    func testWavy14AbsoluteAngleModeHeightWiringIncreasesSeparation() throws {
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
        let provider = SpecParamProvider(params: params)
        let funcs = provider.makeParamFuncs(options: options, exampleName: spec.example, sweepWidth: 20.0)

        let plan6 = makeSweepPlan(
            options: options,
            funcs: funcs,
            baselineWidth: 20.0,
            sweepWidth: 20.0,
            sweepHeight: 6.0,
            sweepSampleCount: 64
        )
        let plan12 = makeSweepPlan(
            options: options,
            funcs: funcs,
            baselineWidth: 20.0,
            sweepWidth: 20.0,
            sweepHeight: 12.0,
            sweepSampleCount: 64
        )

        let min6 = computeMinSeparation(path: path, plan: plan6, options: options)
        let min12 = computeMinSeparation(path: path, plan: plan12, options: options)

        XCTAssertGreaterThan(min12.minSep, min6.minSep + 5.0)
    }

    func testWavy14AbsoluteAngleModeHeightAffectsRingArea() throws {
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

        let plan6 = makeSweepPlan(
            options: options,
            funcs: funcs,
            baselineWidth: 20.0,
            sweepWidth: 20.0,
            sweepHeight: 6.0,
            sweepSampleCount: 64
        )
        let plan12 = makeSweepPlan(
            options: options,
            funcs: funcs,
            baselineWidth: 20.0,
            sweepWidth: 20.0,
            sweepHeight: 12.0,
            sweepSampleCount: 64
        )

        let stats6 = computeMaxRingAreaAndBBox(path: path, plan: plan6, options: options)
        let stats12 = computeMaxRingAreaAndBBox(path: path, plan: plan12, options: options)
        XCTAssertGreaterThan(stats6.area, 1000.0)
        XCTAssertGreaterThan(stats12.area, 1000.0)
    }

    func testWavy14RectCornersProducesFatBBox() throws {
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

        let stats = computeMaxRingAreaAndBBox(path: path, plan: plan, options: options)
        let size = stats.max - stats.min
        let thickness = min(size.x, size.y)
        XCTAssertGreaterThan(stats.area, 1000.0)
        XCTAssertGreaterThan(thickness, 8.0)
    }

    func testWavy14SamplingIncludesGeometrySamples() throws {
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
        let result = runSweep(
            path: path,
            plan: plan,
            options: options,
            capNamespace: "test",
            startCap: .butt,
            endCap: .butt
        )
        let sampleCount = result.sampling?.ts.count ?? 0
        XCTAssertGreaterThanOrEqual(sampleCount, 16)
        let area = computeMaxRingArea(path: path, plan: plan, options: options)
        XCTAssertGreaterThan(area, 1000.0)
    }
}
