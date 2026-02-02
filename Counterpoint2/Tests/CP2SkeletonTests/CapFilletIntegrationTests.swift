import XCTest
import CP2Geometry
import CP2Skeleton

final class CapFilletIntegrationTests: XCTestCase {
    func testFilletCapEmitsExtraCapSegments() {
        let path = SkeletonPath(segments: [lineCubic(Vec2(0, 0), Vec2(100, 0))])
        let segments = boundarySoup(
            path: path,
            width: 20.0,
            height: 10.0,
            effectiveAngle: 0.0,
            sampleCount: 8,
            arcSamplesPerSegment: 8,
            adaptiveSampling: false,
            flatnessEps: 0.25,
            railEps: 0.25,
            maxDepth: 4,
            maxSamples: 64,
            capNamespace: "stroke",
            capLocalIndex: 0,
            startCap: .fillet(radius: 4.0, corner: .left),
            endCap: .butt
        )
        let capStartSegments = segments.filter { seg in
            if case .capStartEdge = seg.source { return true }
            return false
        }
        XCTAssertGreaterThan(capStartSegments.count, 1)
        XCTAssertTrue(capStartSegments.contains { $0.source.description.contains("fillet") })
    }

    func testFilletCapBothCornersEmitsLeftAndRight() {
        let path = SkeletonPath(segments: [lineCubic(Vec2(0, 0), Vec2(100, 0))])
        let segments = boundarySoup(
            path: path,
            width: 20.0,
            height: 10.0,
            effectiveAngle: 0.0,
            sampleCount: 8,
            arcSamplesPerSegment: 8,
            adaptiveSampling: false,
            flatnessEps: 0.25,
            railEps: 0.25,
            maxDepth: 4,
            maxSamples: 64,
            capNamespace: "stroke",
            capLocalIndex: 0,
            startCap: .fillet(radius: 4.0, corner: .both),
            endCap: .butt
        )
        let capStart = segments.filter { seg in
            if case .capStartEdge = seg.source { return true }
            return false
        }
        let descriptions = capStart.map { $0.source.description }
        XCTAssertTrue(descriptions.contains(where: { $0.contains("fillet-left") }))
        XCTAssertTrue(descriptions.contains(where: { $0.contains("fillet-right") }))

        let leftOnly = boundarySoup(
            path: path,
            width: 20.0,
            height: 10.0,
            effectiveAngle: 0.0,
            sampleCount: 8,
            arcSamplesPerSegment: 8,
            adaptiveSampling: false,
            flatnessEps: 0.25,
            railEps: 0.25,
            maxDepth: 4,
            maxSamples: 64,
            capNamespace: "stroke",
            capLocalIndex: 0,
            startCap: .fillet(radius: 4.0, corner: .left),
            endCap: .butt
        )
        let leftOnlyStart = leftOnly.filter { seg in
            if case .capStartEdge = seg.source { return true }
            return false
        }
        XCTAssertGreaterThan(capStart.count, leftOnlyStart.count)
    }

    func testFilletCapRightOnlyDiffersFromDefault() {
        let path = SkeletonPath(segments: [lineCubic(Vec2(0, 0), Vec2(100, 0))])
        let rightSegments = boundarySoup(
            path: path,
            width: 20.0,
            height: 10.0,
            effectiveAngle: 0.0,
            sampleCount: 8,
            arcSamplesPerSegment: 8,
            adaptiveSampling: false,
            flatnessEps: 0.25,
            railEps: 0.25,
            maxDepth: 4,
            maxSamples: 64,
            capNamespace: "stroke",
            capLocalIndex: 0,
            startCap: .fillet(radius: 4.0, corner: .right),
            endCap: .butt
        )
        let rightDescriptions = rightSegments
            .filter { if case .capStartEdge = $0.source { return true }; return false }
            .map { $0.source.description }
        XCTAssertTrue(rightDescriptions.contains(where: { $0.contains("fillet-right") }))
        XCTAssertFalse(rightDescriptions.contains(where: { $0.contains("fillet-left") }))
    }
}

private func lineCubic(_ start: Vec2, _ end: Vec2) -> CubicBezier2 {
    let delta = end - start
    let p1 = start + delta * (1.0 / 3.0)
    let p2 = start + delta * (2.0 / 3.0)
    return CubicBezier2(p0: start, p1: p1, p2: p2, p3: end)
}
