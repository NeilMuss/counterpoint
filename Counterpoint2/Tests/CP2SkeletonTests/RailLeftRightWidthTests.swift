import XCTest
import CP2Geometry
import CP2Skeleton

final class RailLeftRightWidthTests: XCTestCase {
    func testIndependentLeftRightWidthsAffectDistanceAndDirection() {
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
            let wL = 10.0 + 40.0 * t
            let wR = 30.0
            let total = wL + wR
            return SweepStyle(width: total, widthLeft: wL, widthRight: wR, height: 10.0, angle: 0.0, offset: 0.0, angleIsRelative: true)
        }

        let start = railSampleFrameAtGlobalT(param: param, warpGT: warpGT, styleAtGT: styleAtGT, gt: 0.0, index: 0)
        let end = railSampleFrameAtGlobalT(param: param, warpGT: warpGT, styleAtGT: styleAtGT, gt: 1.0, index: 1)

        XCTAssertEqual((start.right - start.left).length, 40.0, accuracy: 1.0e-6)
        XCTAssertEqual((end.right - end.left).length, 80.0, accuracy: 1.0e-6)
        XCTAssertLessThan(start.left.x, start.right.x)
        XCTAssertLessThan(end.left.x, end.right.x)
    }

    func testLegacyWidthUsesSymmetricHalves() {
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
            let half = width * 0.5
            return SweepStyle(width: width, widthLeft: half, widthRight: half, height: 10.0, angle: 0.0, offset: 0.0, angleIsRelative: true)
        }

        let start = railSampleFrameAtGlobalT(param: param, warpGT: warpGT, styleAtGT: styleAtGT, gt: 0.0, index: 0)
        let end = railSampleFrameAtGlobalT(param: param, warpGT: warpGT, styleAtGT: styleAtGT, gt: 1.0, index: 1)

        XCTAssertEqual((start.right - start.left).length, 20.0, accuracy: 1.0e-6)
        XCTAssertEqual((end.right - end.left).length, 200.0, accuracy: 1.0e-6)
    }
}
