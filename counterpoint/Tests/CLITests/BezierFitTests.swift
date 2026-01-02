import XCTest
import Domain
@testable import CounterpointCLI

final class BezierFitTests: XCTestCase {
    func testBezierFitAccuracyWithinTolerance() {
        let radius = 50.0
        let steps = 12
        var points: [Point] = []
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let angle = t * (.pi / 2.0)
            points.append(Point(x: radius * cos(angle), y: radius * sin(angle)))
        }
        let tolerance = 0.5
        let fitter = BezierFitter(tolerance: tolerance, cornerThresholdDegrees: 80.0)
        let subpath = fitter.fitRing(points, closed: false)

        XCTAssertFalse(subpath.segments.isEmpty)
        let maxDistance = maxDistanceFromCurves(to: points, curves: subpath.segments, samplesPerCurve: 8)
        XCTAssertLessThanOrEqual(maxDistance, tolerance * 1.5)
    }

    func testCornerPreservationSplits() {
        let ring: Ring = [
            Point(x: 0, y: 0),
            Point(x: 50, y: 0),
            Point(x: 50, y: 50),
            Point(x: 0, y: 50),
            Point(x: 0, y: 0)
        ]
        let fitter = BezierFitter(tolerance: 0.2, cornerThresholdDegrees: 45.0)
        let subpath = fitter.fitRing(ring, closed: true)
        XCTAssertGreaterThan(subpath.segments.count, 1)

        let corner = Point(x: 50, y: 0)
        let hasCorner = subpath.segments.contains { segment in
            abs(segment.p3.x - corner.x) < 1.0e-6 && abs(segment.p3.y - corner.y) < 1.0e-6
        }
        XCTAssertTrue(hasCorner)
    }

    func testFitDeterminism() {
        let ring: Ring = [
            Point(x: 0, y: 0),
            Point(x: 20, y: 10),
            Point(x: 40, y: 0),
            Point(x: 60, y: 20),
            Point(x: 80, y: 0),
            Point(x: 0, y: 0)
        ]
        let fitter = BezierFitter(tolerance: 0.5, cornerThresholdDegrees: 70.0)
        let a = fitter.fitRing(ring, closed: true)
        let b = fitter.fitRing(ring, closed: true)
        XCTAssertEqual(a, b)
    }

    private func maxDistanceFromCurves(to polyline: [Point], curves: [CubicBezier], samplesPerCurve: Int) -> Double {
        var maxDist = 0.0
        for curve in curves {
            for i in 0...samplesPerCurve {
                let t = Double(i) / Double(samplesPerCurve)
                let p = evaluateBezier(curve, t)
                let dist = distanceToPolyline(point: p, polyline: polyline)
                if dist > maxDist { maxDist = dist }
            }
        }
        return maxDist
    }

    private func distanceToPolyline(point: Point, polyline: [Point]) -> Double {
        guard polyline.count >= 2 else { return .greatestFiniteMagnitude }
        var minDist = Double.greatestFiniteMagnitude
        for i in 0..<(polyline.count - 1) {
            let a = polyline[i]
            let b = polyline[i + 1]
            let dist = distancePointToSegment(point, a, b)
            if dist < minDist { minDist = dist }
        }
        return minDist
    }

    private func evaluateBezier(_ bezier: CubicBezier, _ t: Double) -> Point {
        let mt = 1.0 - t
        let b0 = mt * mt * mt
        let b1 = 3.0 * mt * mt * t
        let b2 = 3.0 * mt * t * t
        let b3 = t * t * t
        return bezier.p0 * b0 + bezier.p1 * b1 + bezier.p2 * b2 + bezier.p3 * b3
    }

    private func distancePointToSegment(_ p: Point, _ a: Point, _ b: Point) -> Double {
        let ab = b - a
        let ap = p - a
        let denom = ab.dot(ab)
        if denom <= 1.0e-12 { return ap.length }
        let t = max(0.0, min(1.0, ap.dot(ab) / denom))
        let proj = a + ab * t
        return (p - proj).length
    }
}
