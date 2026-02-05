import XCTest
import CP2Domain
import CP2Geometry

final class ArtifactsTests: XCTestCase {
    func testDeterminismPolicyCodableRoundTrip() throws {
        let policy = DeterminismPolicy(eps: 1.0e-6, stableSort: .lexicographicXYThenIndex)
        let data = try JSONEncoder().encode(policy)
        let decoded = try JSONDecoder().decode(DeterminismPolicy.self, from: data)
        XCTAssertEqual(policy, decoded)
    }

    private struct DummyDebugPayload: DebugPayload {
        static var kind: String { "dummy" }
        let value: Int
    }

    func testDebugBundleRoundTrip() throws {
        var bundle = DebugBundle()
        try bundle.add(DummyDebugPayload(value: 7))
        let data = try JSONEncoder().encode(bundle)
        let decoded = try JSONDecoder().decode(DebugBundle.self, from: data)
        XCTAssertEqual(bundle, decoded)
        XCTAssertNotNil(decoded.entries["dummy"])
    }

    func testSamplesArtifactRequiresEndpointSamples() throws {
        let policy = DeterminismPolicy(eps: 1.0e-6, stableSort: .lexicographicXYThenIndex)
        let samples = [
            SamplePoint(globalT: 0.1, pos: Vec2(0, 0), attrs: SampleAttributes()),
            SamplePoint(globalT: 0.9, pos: Vec2(1, 0), attrs: SampleAttributes())
        ]
        let artifact = SamplesArtifact(id: ArtifactID("s"), policy: policy, skeletonId: ArtifactID("sk"), samples: samples)
        XCTAssertThrowsError(try artifact.validate())
    }

    func testSamplesArtifactGlobalTStrictlyIncreasing() throws {
        let policy = DeterminismPolicy(eps: 1.0e-6, stableSort: .lexicographicXYThenIndex)
        let samples = [
            SamplePoint(globalT: 0.0, pos: Vec2(0, 0), attrs: SampleAttributes()),
            SamplePoint(globalT: 0.5, pos: Vec2(1, 0), attrs: SampleAttributes()),
            SamplePoint(globalT: 0.5, pos: Vec2(2, 0), attrs: SampleAttributes()),
            SamplePoint(globalT: 1.0, pos: Vec2(3, 0), attrs: SampleAttributes())
        ]
        let artifact = SamplesArtifact(id: ArtifactID("s"), policy: policy, skeletonId: ArtifactID("sk"), samples: samples)
        XCTAssertThrowsError(try artifact.validate())
    }

    func testSamplesArtifactIncludes0And1WithinEps() throws {
        let policy = DeterminismPolicy(eps: 1.0e-6, stableSort: .lexicographicXYThenIndex)
        let samples = [
            SamplePoint(globalT: 0.0, pos: Vec2(0, 0), attrs: SampleAttributes()),
            SamplePoint(globalT: 0.5, pos: Vec2(1, 0), attrs: SampleAttributes()),
            SamplePoint(globalT: 1.0, pos: Vec2(2, 0), attrs: SampleAttributes())
        ]
        let artifact = SamplesArtifact(id: ArtifactID("s"), policy: policy, skeletonId: ArtifactID("sk"), samples: samples)
        XCTAssertNoThrow(try artifact.validate())
    }

    func testRingRequiresClosureWithinEps() throws {
        let policy = DeterminismPolicy(eps: 1.0e-6, stableSort: .lexicographicXYThenIndex)
        let ring = Ring(points: [Vec2(0, 0), Vec2(1, 0), Vec2(0, 1), Vec2(2, 2)], winding: .ccw, area: 1.0)
        let artifact = RingsArtifact(id: ArtifactID("r"), policy: policy, soupId: ArtifactID("soup"), rings: [ring])
        XCTAssertThrowsError(try artifact.validate())
    }

    func testRingRequiresNonZeroArea() throws {
        let policy = DeterminismPolicy(eps: 1.0e-6, stableSort: .lexicographicXYThenIndex)
        let points = [Vec2(0, 0), Vec2(1, 0), Vec2(2, 0), Vec2(0, 0)]
        let ring = Ring(points: points, winding: .ccw, area: 0.0)
        let artifact = RingsArtifact(id: ArtifactID("r"), policy: policy, soupId: ArtifactID("soup"), rings: [ring])
        XCTAssertThrowsError(try artifact.validate())
    }

    func testSkeletonRequiresNonEmptySegments() throws {
        let policy = DeterminismPolicy(eps: 1.0e-6, stableSort: .lexicographicXYThenIndex)
        let artifact = SkeletonArtifact(id: ArtifactID("sk"), policy: policy, segments: [], totalLength: 1.0)
        XCTAssertThrowsError(try artifact.validate())
    }

    func testSkeletonRequiresPositiveTotalLength() throws {
        let policy = DeterminismPolicy(eps: 1.0e-6, stableSort: .lexicographicXYThenIndex)
        let segments: [SkeletonSegment] = [.line(p0: Vec2(0, 0), p1: Vec2(1, 0))]
        let artifact = SkeletonArtifact(id: ArtifactID("sk"), policy: policy, segments: segments, totalLength: 0.0)
        XCTAssertThrowsError(try artifact.validate())
    }

    func testSkeletonContinuityCheck() throws {
        let policy = DeterminismPolicy(eps: 1.0e-6, stableSort: .lexicographicXYThenIndex)
        let segments: [SkeletonSegment] = [
            .line(p0: Vec2(0, 0), p1: Vec2(1, 0)),
            .line(p0: Vec2(2, 0), p1: Vec2(3, 0))
        ]
        let artifact = SkeletonArtifact(id: ArtifactID("sk"), policy: policy, segments: segments, totalLength: 2.0)
        XCTAssertThrowsError(try artifact.validate())
    }
}
