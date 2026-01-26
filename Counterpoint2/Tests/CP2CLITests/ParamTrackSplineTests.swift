import XCTest
@testable import cp2_cli

final class ParamTrackSplineTests: XCTestCase {
    func testSegmentAlphaUsesLeftKeyframe() {
        let scalar = KeyframedScalar(
            keyframes: [
                Keyframe(t: 0.0, value: 95.0),
                Keyframe(t: 0.013, value: 95.0, interpToNext: InterpToNext(alpha: -2.0)),
                Keyframe(t: 0.2, value: 35.0)
            ]
        )
        let track = ParamTrack.fromKeyframedScalar(scalar, mode: .hermiteMonotone)
        XCTAssertEqual(track.segmentAlpha(at: 0.0065), 0.0, accuracy: 1.0e-9)
        XCTAssertEqual(track.segmentAlpha(at: 0.1065), -2.0, accuracy: 1.0e-9)
    }

    func testHermiteSmoothIsC1AcrossKeyframe() {
        let track = ParamTrack(
            keyframes: [
                ParamKeyframe(t: 0.0, value: 0.0),
                ParamKeyframe(t: 0.5, value: 10.0),
                ParamKeyframe(t: 1.0, value: 0.0)
            ],
            mode: .hermite
        )
        let eps = 1.0e-4
        let left = (track.value(at: 0.5) - track.value(at: 0.5 - eps)) / eps
        let right = (track.value(at: 0.5 + eps) - track.value(at: 0.5)) / eps
        XCTAssertLessThan(abs(left - right), 2.0e-2)
    }

    func testHermiteCuspAllowsDerivativeJump() {
        let track = ParamTrack(
            keyframes: [
                ParamKeyframe(t: 0.0, value: 0.0),
                ParamKeyframe(t: 0.5, value: 10.0, knot: .cusp),
                ParamKeyframe(t: 1.0, value: 0.0)
            ],
            mode: .hermite
        )
        let eps = 1.0e-4
        let left = (track.value(at: 0.5) - track.value(at: 0.5 - eps)) / eps
        let right = (track.value(at: 0.5 + eps) - track.value(at: 0.5)) / eps
        XCTAssertGreaterThan(abs(left - right), 1.0e-3)
    }

    func testHermiteMonotoneNoOvershootWithinSegment() {
        let track = ParamTrack(
            keyframes: [
                ParamKeyframe(t: 0.0, value: 0.0),
                ParamKeyframe(t: 1.0, value: 10.0),
                ParamKeyframe(t: 2.0, value: 20.0)
            ],
            mode: .hermiteMonotone
        )
        let samples: [Double] = [0.1, 0.3, 0.6, 0.9]
        for u in samples {
            let v = track.value(at: u)
            XCTAssertGreaterThanOrEqual(v, 0.0)
            XCTAssertLessThanOrEqual(v, 10.0)
        }
        for u in samples {
            let v = track.value(at: 1.0 + u)
            XCTAssertGreaterThanOrEqual(v, 10.0)
            XCTAssertLessThanOrEqual(v, 20.0)
        }
    }

    func testTangentScalingChangesShapeNotEndpoints() {
        let base = ParamTrack(
            keyframes: [
                ParamKeyframe(t: 0.0, value: 0.0),
                ParamKeyframe(t: 1.0, value: 100.0)
            ],
            mode: .hermite
        )
        let scaled = ParamTrack(
            keyframes: [
                ParamKeyframe(t: 0.0, value: 0.0, outTangentScale: ParamTrack.scaleFromAlpha(-1.0)),
                ParamKeyframe(t: 1.0, value: 100.0)
            ],
            mode: .hermite
        )
        XCTAssertEqual(base.value(at: 0.0), 0.0, accuracy: 1.0e-9)
        XCTAssertEqual(base.value(at: 1.0), 100.0, accuracy: 1.0e-9)
        XCTAssertEqual(scaled.value(at: 0.0), 0.0, accuracy: 1.0e-9)
        XCTAssertEqual(scaled.value(at: 1.0), 100.0, accuracy: 1.0e-9)
        XCTAssertNotEqual(base.value(at: 0.5), scaled.value(at: 0.5))
    }

    func testDeterminismSameInputsSameOutputs() {
        let track = ParamTrack(
            keyframes: [
                ParamKeyframe(t: 0.0, value: 10.0),
                ParamKeyframe(t: 0.5, value: 30.0),
                ParamKeyframe(t: 1.0, value: 20.0)
            ],
            mode: .hermiteMonotone
        )
        let ts: [Double] = [0.0, 0.25, 0.5, 0.75, 1.0]
        let a = ts.map { track.value(at: $0) }
        let b = ts.map { track.value(at: $0) }
        XCTAssertEqual(a, b)
    }
}
