import XCTest
import CP2Geometry
import CP2Skeleton
@testable import cp2_cli

final class KeyframedScalarAlphaTests: XCTestCase {
    func testSegmentAlphaUsesLeftKeyframe() {
        let scalar = KeyframedScalar(
            keyframes: [
                Keyframe(t: 0.0, value: 95.0),
                Keyframe(t: 0.013, value: 95.0, interpToNext: InterpToNext(alpha: -2.0)),
                Keyframe(t: 0.2, value: 35.0)
            ]
        )

        let early = scalar.eval(t: 0.0065)
        XCTAssertEqual(early, 95.0, accuracy: 1.0e-6)

        let t = 0.1065
        let t0 = 0.013
        let t1 = 0.2
        let u = (t - t0) / (t1 - t0)
        let exponent = exp(-2.0)
        let uWarp = pow(u, exponent)
        let expected = 95.0 + (35.0 - 95.0) * uWarp
        let mid = scalar.eval(t: t)
        XCTAssertEqual(mid, expected, accuracy: 1.0e-6)
    }

    func testPerSegmentAlphaWarpAffectsMidpoint() {
        let scalar = KeyframedScalar(
            keyframes: [
                Keyframe(t: 0.0, value: 0.0, interpToNext: InterpToNext(alpha: 0.6)),
                Keyframe(t: 1.0, value: 100.0)
            ]
        )
        let mid = scalar.eval(t: 0.5)
        XCTAssertLessThan(mid, 50.0)
        XCTAssertEqual(scalar.eval(t: 0.0), 0.0, accuracy: 1.0e-9)
        XCTAssertEqual(scalar.eval(t: 1.0), 100.0, accuracy: 1.0e-9)
    }

    func testSegmentAlphaAppliesPerSegment() {
        let scalar = KeyframedScalar(
            keyframes: [
                Keyframe(t: 0.0, value: 0.0, interpToNext: InterpToNext(alpha: -0.5)),
                Keyframe(t: 0.5, value: 50.0, interpToNext: InterpToNext(alpha: 0.5)),
                Keyframe(t: 1.0, value: 100.0)
            ]
        )
        let v0 = scalar.eval(t: 0.25)
        let v1 = scalar.eval(t: 0.75)
        XCTAssertGreaterThan(v0, 25.0)
        XCTAssertLessThan(v1, 75.0)
    }

    func testWidthUsesSegmentAlphaInSweep() {
        let params = StrokeParams(
            angleMode: .relative,
            theta: nil,
            width: nil,
            widthLeft: KeyframedScalar(
                keyframes: [
                    Keyframe(t: 0.0, value: 10.0, interpToNext: InterpToNext(alpha: 0.7)),
                    Keyframe(t: 1.0, value: 50.0)
                ]
            ),
            widthRight: KeyframedScalar(keyframes: [Keyframe(t: 0.0, value: 30.0), Keyframe(t: 1.0, value: 30.0)]),
            offset: nil,
            alpha: nil
        )
        let provider = SpecParamProvider(params: params)
        let funcs = provider.makeParamFuncs(options: CLIOptions(), exampleName: nil, sweepWidth: 20.0)
        let path = SkeletonPath(segments: [
            CubicBezier2(
                p0: Vec2(0, 0),
                p1: Vec2(0, 33),
                p2: Vec2(0, 66),
                p3: Vec2(0, 100)
            )
        ])
        let param = SkeletonPathParameterization(path: path, samplesPerSegment: 256)
        let styleAtGT: (Double) -> SweepStyle = { t in
            let wL = funcs.widthLeftAtT(t)
            let wR = funcs.widthRightAtT(t)
            let width = wL + wR
            return SweepStyle(width: width, widthLeft: wL, widthRight: wR, height: 10.0, angle: 0.0, offset: 0.0, angleIsRelative: true)
        }

        let frame = railSampleFrameAtGlobalT(param: param, warpGT: { $0 }, styleAtGT: styleAtGT, gt: 0.5, index: 0)
        let dist = (frame.right - frame.left).length
        let exponent = exp(0.7)
        let uWarp = pow(0.5, exponent)
        let expectedLeft = 10.0 + (50.0 - 10.0) * uWarp
        let expectedRight = 30.0
        let expectedDist = expectedLeft + expectedRight
        XCTAssertEqual(dist, expectedDist, accuracy: 1.0e-6)
    }
}
