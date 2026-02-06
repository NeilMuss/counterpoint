import XCTest
import CP2Geometry
import CP2Skeleton

final class AngleModeAbsoluteTests: XCTestCase {
    private func makeLinePath() -> SkeletonPath {
        let p0 = Vec2(0, 0)
        let p1 = Vec2(0, 0)
        let p2 = Vec2(10, 10)
        let p3 = Vec2(10, 10)
        return SkeletonPath(CubicBezier2(p0: p0, p1: p1, p2: p2, p3: p3))
    }

    private func rectangleCorners(center: Vec2, tangent: Vec2, normal: Vec2, width: Double, height: Double, effectiveAngle: Double) -> [Vec2] {
        let halfW = width * 0.5
        let halfH = height * 0.5
        let local: [Vec2] = [
            Vec2(-halfW, -halfH),
            Vec2(halfW, -halfH),
            Vec2(halfW, halfH),
            Vec2(-halfW, halfH)
        ]
        let cosA = cos(effectiveAngle)
        let sinA = sin(effectiveAngle)
        return local.map { corner in
            let rotated = Vec2(
                corner.x * cosA - corner.y * sinA,
                corner.x * sinA + corner.y * cosA
            )
            let world = tangent * rotated.y + normal * rotated.x
            return center + world
        }
    }

    func testAbsoluteAngleModeHeightDoesNotCollapseWhenThetaEqualsTangent() {
        let path = makeLinePath()
        let param = SkeletonPathParameterization(path: path, samplesPerSegment: 16)
        let theta = Double.pi / 4.0
        let styleAtGT: (Double) -> SweepStyle = { _ in
            SweepStyle(
                width: 20.0,
                widthLeft: 10.0,
                widthRight: 10.0,
                height: 6.0,
                angle: theta,
                offset: 0.0,
                angleIsRelative: false
            )
        }
        let frame = railSampleFrameAtGlobalT(param: param, warpGT: { $0 }, styleAtGT: styleAtGT, gt: 0.5, index: 0)
        let uRot = frame.tangent * cos(frame.effectiveAngle) - frame.normal * sin(frame.effectiveAngle)
        let corners = rectangleCorners(center: frame.center, tangent: frame.tangent, normal: frame.normal, width: 20.0, height: 6.0, effectiveAngle: frame.effectiveAngle)
        let projections = corners.map { ($0 - frame.center).dot(uRot) }
        let height = (projections.max() ?? 0.0) - (projections.min() ?? 0.0)
        XCTAssertEqual(height, 6.0, accuracy: 1.0e-3)
        XCTAssertGreaterThan((frame.right - frame.left).length, 0.0)
    }

    func testRelativeAngleModeStillUsesNormalWhenThetaZero() {
        let path = makeLinePath()
        let param = SkeletonPathParameterization(path: path, samplesPerSegment: 16)
        let styleAtGT: (Double) -> SweepStyle = { _ in
            SweepStyle(
                width: 20.0,
                widthLeft: 10.0,
                widthRight: 10.0,
                height: 6.0,
                angle: 0.0,
                offset: 0.0,
                angleIsRelative: true
            )
        }
        let frame = railSampleFrameAtGlobalT(param: param, warpGT: { $0 }, styleAtGT: styleAtGT, gt: 0.5, index: 0)
        let alignment = frame.crossAxis.normalized().dot(frame.normal.normalized())
        XCTAssertGreaterThan(alignment, 0.999)
    }

    func testAbsoluteAngleModeProducesNonZeroAreaRing() {
        let path = makeLinePath()
        let segments = boundarySoupVariableWidthAngleAlpha(
            path: path,
            height: 6.0,
            sampleCount: 12,
            arcSamplesPerSegment: 32,
            adaptiveSampling: false,
            flatnessEps: 0.25,
            railEps: 0.25,
            attrEpsOffset: 0.25,
            attrEpsWidth: 0.25,
            attrEpsAngle: 0.00436,
            attrEpsAlpha: 0.25,
            maxDepth: 8,
            maxSamples: 256,
            widthAtT: { _ in 20.0 },
            widthLeftAtT: { _ in 10.0 },
            widthRightAtT: { _ in 10.0 },
            angleAtT: { _ in Double.pi / 4.0 },
            offsetAtT: { _ in 0.0 },
            alphaAtT: { _ in 0.0 },
            alphaStart: 0.0,
            angleIsRelative: false,
            keyframeTs: []
        )
        let rings = traceLoops(segments: segments, eps: 1.0e-6)
        let bestArea = rings.map { abs(signedArea($0)) }.max() ?? 0.0
        XCTAssertGreaterThan(bestArea, 100.0)
    }
}
