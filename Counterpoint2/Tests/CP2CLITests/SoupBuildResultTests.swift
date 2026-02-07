import XCTest
import CP2Geometry
import CP2Skeleton
@testable import cp2_cli

final class SoupBuildResultTests: XCTestCase {
    func testSoupBuildCountsAreConsistent() {
        var options = CLIOptions()
        options.penShape = .rectCorners
        let path = SkeletonPath(segments: [lineCubic(from: Vec2(0, 0), to: Vec2(200, 0))])
        let funcs = StrokeParamFuncs(
            alphaStartGT: 0.0,
            alphaEndValue: 1.0,
            widthAtT: { _ in 80.0 },
            widthLeftAtT: { _ in 40.0 },
            widthRightAtT: { _ in 40.0 },
            widthLeftSegmentAlphaAtT: { _ in 1.0 },
            widthRightSegmentAlphaAtT: { _ in 1.0 },
            thetaAtT: { _ in 0.0 },
            offsetAtT: { _ in 0.0 },
            alphaAtT: { _ in 1.0 },
            usesVariableWidthAngleAlpha: false,
            angleMode: .absolute,
            paramKeyframeTs: [0.0, 1.0]
        )
        let plan = makeSweepPlan(
            options: options,
            funcs: funcs,
            baselineWidth: 80.0,
            sweepWidth: 80.0,
            sweepHeight: 10.0,
            sweepSampleCount: 32
        )
        let soup = buildSoup(
            path: path,
            plan: plan,
            options: options,
            capNamespace: "test",
            startCap: .butt,
            endCap: .butt,
            traceSink: nil
        )
        XCTAssertEqual(soup.soupTotalSegments, soup.segments.count)
        XCTAssertLessThanOrEqual(soup.soupLaneSegments + soup.soupPerimeterSegments, soup.soupTotalSegments)
        XCTAssertGreaterThan(soup.soupTotalSegments, 0)
    }
}
