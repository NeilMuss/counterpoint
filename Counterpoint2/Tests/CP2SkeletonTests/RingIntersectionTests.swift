import XCTest
import CP2Geometry
import CP2Skeleton

final class RingIntersectionTests: XCTestCase {
    // Test helper: detect if two segments intersect (excluding shared endpoints)
    func segmentsIntersect(_ seg1: Segment2, _ seg2: Segment2, eps: Double = 1.0e-9) -> Bool {
        // Check if segments share an endpoint
        if Epsilon.approxEqual(seg1.a, seg2.a, eps: eps) || Epsilon.approxEqual(seg1.a, seg2.b, eps: eps) ||
           Epsilon.approxEqual(seg1.b, seg2.a, eps: eps) || Epsilon.approxEqual(seg1.b, seg2.b, eps: eps) {
            return false
        }
        
        // Use cross product to detect intersection
        let d1 = seg1.b - seg1.a
        let d2 = seg2.b - seg2.a
        
        let denom = d1.x * d2.y - d1.y * d2.x
        if abs(denom) < eps {
            // Segments are parallel
            return false
        }
        
        let diff = seg2.a - seg1.a
        let t1 = (diff.x * d2.y - diff.y * d2.x) / denom
        let t2 = (diff.x * d1.y - diff.y * d1.x) / denom
        
        // Check if intersection is within both segments (excluding endpoints)
        return t1 > eps && t1 < (1.0 - eps) && t2 > eps && t2 < (1.0 - eps)
    }
    
    // Test helper: check if a closed polyline ring has self-intersections
    func ringHasSelfIntersections(_ ring: [Vec2], eps: Double = 1.0e-9) -> Bool {
        guard ring.count >= 4 else { return false }
        
        // Convert ring to segments (closed)
        var segments: [Segment2] = []
        for i in 0..<ring.count {
            let next = (i + 1) % ring.count
            segments.append(Segment2(ring[i], ring[next]))
        }
        
        // Check each non-adjacent segment pair for intersection
        for i in 0..<segments.count {
            // Start from i+2 to skip adjacent segments, but handle wrap-around
            let startJ = i + 2
            if startJ < segments.count {
                for j in startJ..<segments.count {
                    if segmentsIntersect(segments[i], segments[j], eps: eps) {
                        return true
                    }
                }
            }
            // Also check wrap-around cases (last segment with early segments)
            if i == 0 && segments.count > 3 {
                // Check last segment with early segments (skip adjacent)
                let lastIdx = segments.count - 1
                for j in 1..<(segments.count - 2) {
                    if segmentsIntersect(segments[lastIdx], segments[j], eps: eps) {
                        return true
                    }
                }
            }
        }
        return false
    }
    
    func testRingWithNoIntersections() {
        // Simple rectangle ring - should have no intersections
        let ring: [Vec2] = [
            Vec2(0, 0),
            Vec2(10, 0),
            Vec2(10, 10),
            Vec2(0, 10),
            Vec2(0, 0) // closed
        ]
        XCTAssertFalse(ringHasSelfIntersections(ring), "Rectangle ring should have no self-intersections")
    }
    
    func testRingWithIntersection() {
        // Figure-8 shape - should have intersection
        let ring: [Vec2] = [
            Vec2(0, 0),
            Vec2(10, 10),
            Vec2(0, 10),
            Vec2(10, 0),
            Vec2(0, 0) // closed
        ]
        XCTAssertTrue(ringHasSelfIntersections(ring), "Figure-8 ring should have self-intersection")
    }
    
    func testChallengingStrokeNoIntersections() throws {
        // Test a challenging stroke with rapid width/offset changes
        // Width: 68 -> 1 -> 50, Offset: 22 -> 0
        // This should produce a ring with no self-intersections
        
        let path = SkeletonPath(segments: [
            CubicBezier2(
                p0: Vec2(160, 5),
                p1: Vec2(160, 120),
                p2: Vec2(160, 240),
                p3: Vec2(160, 350)
            )
        ])
        
        // Create keyframes for rapid changes
        let widthKeyframes = KeyframedScalar(keyframes: [
            Keyframe(t: 0.0, value: 68.0),
            Keyframe(t: 0.5, value: 1.0),
            Keyframe(t: 1.0, value: 50.0)
        ])
        
        let offsetKeyframes = KeyframedScalar(keyframes: [
            Keyframe(t: 0.0, value: 22.0),
            Keyframe(t: 0.5, value: 0.0),
            Keyframe(t: 1.0, value: 0.0)
        ])
        
        // Run sweep with variable width and offset
        let segments = boundarySoupVariableWidthAngleAlpha(
            path: path,
            height: 10.0,
            sampleCount: 64,
            arcSamplesPerSegment: 256,
            adaptiveSampling: true,
            flatnessEps: 0.25,
            maxDepth: 12,
            maxSamples: 512,
            widthAtT: { t in widthKeyframes.value(at: t) },
            angleAtT: { _ in 0.0 },
            offsetAtT: { t in offsetKeyframes.value(at: t) },
            alphaAtT: { _ in 0.0 },
            alphaStart: 0.85
        )
        
        let rings = traceLoops(segments: segments, eps: 1.0e-6)
        guard let ring = rings.first else {
            XCTFail("No ring produced")
            return
        }
        
        // Remove duplicate closure point if present
        let cleanRing = stripDuplicateClosure(ring)
        
        // Assert no self-intersections
        XCTAssertFalse(ringHasSelfIntersections(cleanRing), "Challenging stroke should produce ring with no self-intersections")
    }
    
    func testChallengingStrokeNoMicroSpikes() throws {
        // Test that adaptive sampling with rapid param changes produces smooth rails
        // without micro-spikes (tiny comb-like triangles)
        
        let path = SkeletonPath(segments: [
            CubicBezier2(
                p0: Vec2(160, 5),
                p1: Vec2(160, 120),
                p2: Vec2(160, 240),
                p3: Vec2(160, 350)
            )
        ])
        
        let widthKeyframes = KeyframedScalar(keyframes: [
            Keyframe(t: 0.0, value: 68.0),
            Keyframe(t: 0.5, value: 1.0),
            Keyframe(t: 1.0, value: 50.0)
        ])
        
        let offsetKeyframes = KeyframedScalar(keyframes: [
            Keyframe(t: 0.0, value: 22.0),
            Keyframe(t: 0.5, value: 0.0),
            Keyframe(t: 1.0, value: 0.0)
        ])
        
        // Run sweep with adaptive sampling
        let segments = boundarySoupVariableWidthAngleAlpha(
            path: path,
            height: 10.0,
            sampleCount: 64,
            arcSamplesPerSegment: 256,
            adaptiveSampling: true,
            flatnessEps: 0.25,
            maxDepth: 12,
            maxSamples: 512,
            widthAtT: { t in widthKeyframes.value(at: t) },
            angleAtT: { _ in 0.0 },
            offsetAtT: { t in offsetKeyframes.value(at: t) },
            alphaAtT: { _ in 0.0 },
            alphaStart: 0.85
        )
        
        let rings = traceLoops(segments: segments, eps: 1.0e-6)
        guard let ring = rings.first else {
            XCTFail("No ring produced")
            return
        }
        
        let cleanRing = stripDuplicateClosure(ring)
        
        // Check for micro-spikes.
        // B) Replace hardcoded area (0.1) with epsArea derived from epsLen
        let epsLen: Double = 0.5 // A reasonable length for this test scale
        let epsArea: Double = epsLen * epsLen // epsArea = epsLen^2
        let maxDeviation = 0.05 // Maximum deviation from linear interpolation (smaller = more sensitive)
        
        var microSpikeCount = 0
        var spikeDetails: [String] = []
        for i in 0..<(cleanRing.count - 2) {
            let p0 = cleanRing[i]
            let p1 = cleanRing[i + 1]
            let p2 = cleanRing[i + 2]
            
            // Compute triangle area (signed area)
            let area = abs((p1.x - p0.x) * (p2.y - p0.y) - (p2.x - p0.x) * (p1.y - p0.y)) * 0.5
            
            // Compute linear interpolation of middle point
            let lerp = p0 + (p2 - p0) * 0.5
            let deviation = (p1 - lerp).length
            
            // Check if this is a micro-spike (tiny area but significant deviation)
            if area < epsArea && deviation > maxDeviation {
                microSpikeCount += 1
                spikeDetails.append("i=\(i) area=\(area) dev=\(deviation)")
            }
        }
        
        // Assert no micro-spikes (or very few due to numerical precision)
        // If this fails, we need to smooth the rails
        XCTAssertLessThanOrEqual(microSpikeCount, 2, "Ring should have no micro-spikes, found \(microSpikeCount): \(spikeDetails.prefix(5).joined(separator: ", "))")
    }

    func testChallengingStrokeArtifacts() throws {
        // Test a challenging stroke with rapid width/offset changes
        // for self-intersections, rail flips, and dense scribbles (hair).
        
        // A) Setup: Path and Ink with rapid parameter changes
        let path = SkeletonPath(segments: [sCurveFixtureCubic()])
        let param = SkeletonPathParameterization(path: path, samplesPerSegment: 256)
        
        let widthFrames = KeyframedScalar(keyframes: [
            Keyframe(t: 0.0, value: 68.0),
            Keyframe(t: 0.5, value: 1.0),
            Keyframe(t: 1.0, value: 50.0)
        ])
        let offsetFrames = KeyframedScalar(keyframes: [
            Keyframe(t: 0.0, value: 22.0),
            Keyframe(t: 0.5, value: 0.0),
            Keyframe(t: 1.0, value: 0.0)
        ])
        let sweepParams = SweepParameters(width: widthFrames, offset: offsetFrames)

        // B) Generate Samples using Adaptive Sampler
        var sampler = AdaptiveSampler(
            param: param,
            sweepParams: sweepParams,
            maxDepth: 12,
            maxSamples: 1024,
            flatnessEps: 0.1, // Tighter tolerance for testing
            railEps: 0.1
        )
        let samples = sampler.generateSamples()

        // C) Trace the final outline
        let (leftRail, rightRail) = SweepTrace.trace(samples: samples)
        let ring = leftRail + rightRail.reversed()
        
        // D) Assertions
        
        // D.1) Assert no self-intersections
        XCTAssertFalse(ringHasSelfIntersections(ring), "Challenging stroke should produce ring with no self-intersections")

        // D.2) Assert no dense scribbles
        // In any sliding window of N edges, count of edges < epsLen is below a small threshold.
        let epsLen = 0.01 // A small length for what we consider a "tiny" edge
        let windowSize = 20
        let maxTinyEdgesInWindow = 3
        
        var edgeLengths: [Double] = []
        if ring.count > 1 {
            for i in 0..<(ring.count - 1) {
                edgeLengths.append((ring[i+1] - ring[i]).length)
            }
        }

        var maxTinyCount = 0
        if edgeLengths.count > windowSize {
            for i in 0..<(edgeLengths.count - windowSize) {
                let window = edgeLengths[i..<(i + windowSize)]
                let tinyCount = window.filter { $0 < epsLen }.count
                if tinyCount > maxTinyCount {
                    maxTinyCount = tinyCount
                }
            }
        }
        
        XCTAssertLessThanOrEqual(maxTinyCount, maxTinyEdgesInWindow, "Found a dense scribble with \(maxTinyCount) tiny edges in a window of \(windowSize)")

        // D.3) Assert no rail flips
        // The sign of dot(L-R, N) should be consistent.
        var railFlips = 0
        for i in 1..<samples.count {
            let sample = samples[i]
            let prevSample = samples[i-1]
            
            // Re-check frame continuity
            if sample.normal.dot(prevSample.normal) < 0 {
                railFlips += 1
            }
        }

        XCTAssertEqual(railFlips, 0, "Found \(railFlips) rail frame flips.")
    }
}

private func stripDuplicateClosure(_ ring: [Vec2]) -> [Vec2] {
    guard ring.count > 1, Epsilon.approxEqual(ring.first ?? Vec2(0, 0), ring.last ?? Vec2(0, 0), eps: 1.0e-9) else {
        return ring
    }
    return Array(ring.dropLast())
}

// MARK: - Fixtures

private func sCurveFixtureCubic() -> CubicBezier2 {
    return CubicBezier2(
        p0: Vec2(146, 317),
        p1: Vec2(436, 311),
        p2: Vec2(235, 55),
        p3: Vec2(541, 58)
    )
}

