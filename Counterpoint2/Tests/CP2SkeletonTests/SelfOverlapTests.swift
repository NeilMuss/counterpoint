import XCTest
import CP2Geometry
import CP2Skeleton

final class SelfOverlapTests: XCTestCase {
    func testSelfOverlapStrokeKeepsNonzeroArea() {
        let seg0 = CubicBezier2(
            p0: Vec2(0, 0),
            p1: Vec2(100, 200),
            p2: Vec2(-100, 200),
            p3: Vec2(0, 0)
        )
        let seg1 = CubicBezier2(
            p0: Vec2(0, 0),
            p1: Vec2(100, -200),
            p2: Vec2(-100, -200),
            p3: Vec2(0, 0)
        )
        let path = SkeletonPath(segments: [seg0, seg1])
        let segments = boundarySoup(
            path: path,
            width: 20.0,
            height: 10.0,
            effectiveAngle: 0.0,
            sampleCount: 64,
            arcSamplesPerSegment: 256,
            adaptiveSampling: true,
            flatnessEps: 0.25,
            railEps: 0.25,
            maxDepth: 12,
            maxSamples: 512
        )
        let rings = traceLoops(segments: segments, eps: 1.0e-6, debugStep: nil)
        XCTAssertGreaterThanOrEqual(rings.count, 1)
        let areas = rings.map { signedArea($0) }.filter { abs($0) > 1.0e-6 }
        XCTAssertFalse(areas.isEmpty)
        let firstSign = areas.first! > 0.0
        for area in areas.dropFirst() {
            XCTAssertEqual(area > 0.0, firstSign)
        }
    }
}
