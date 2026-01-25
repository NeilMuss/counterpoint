import XCTest
import CP2Geometry
import CP2Skeleton

final class RailParamSweepTests: XCTestCase {
    func testWidthRampChangesRailDistance() {
        let path = SkeletonPath(segments: [
            CubicBezier2(
                p0: Vec2(0, 0),
                p1: Vec2(0, 33),
                p2: Vec2(0, 66),
                p3: Vec2(0, 100)
            )
        ])
        let param = SkeletonPathParameterization(path: path, samplesPerSegment: 256)
        let warpGT: (Double) -> Double = { $0 }
        let styleAtGT: (Double) -> SweepStyle = { t in
            let width = 20.0 + 180.0 * t
            return SweepStyle(width: width, height: 10.0, angle: 0.0, offset: 0.0, angleIsRelative: true)
        }

        let start = railSampleFrameAtGlobalT(param: param, warpGT: warpGT, styleAtGT: styleAtGT, gt: 0.0, index: 0)
        let end = railSampleFrameAtGlobalT(param: param, warpGT: warpGT, styleAtGT: styleAtGT, gt: 1.0, index: 1)

        let startDist = (start.right - start.left).length
        let endDist = (end.right - end.left).length
        XCTAssertEqual(startDist, 20.0, accuracy: 1.0e-6)
        XCTAssertEqual(endDist, 200.0, accuracy: 1.0e-6)
    }

    func testOffsetRampShiftsCenterAlongCrossAxis() {
        let path = SkeletonPath(segments: [
            CubicBezier2(
                p0: Vec2(0, 0),
                p1: Vec2(0, 33),
                p2: Vec2(0, 66),
                p3: Vec2(0, 100)
            )
        ])
        let param = SkeletonPathParameterization(path: path, samplesPerSegment: 256)
        let warpGT: (Double) -> Double = { $0 }
        let styleAtGT: (Double) -> SweepStyle = { t in
            let offset = 100.0 * t
            return SweepStyle(width: 20.0, height: 10.0, angle: 0.0, offset: offset, angleIsRelative: true)
        }

        let frame = railSampleFrameAtGlobalT(param: param, warpGT: warpGT, styleAtGT: styleAtGT, gt: 1.0, index: 0)
        let point = param.position(globalT: 1.0)
        let shift = (frame.center - point).length
        XCTAssertEqual(shift, 100.0, accuracy: 1.0e-6)
    }
}
