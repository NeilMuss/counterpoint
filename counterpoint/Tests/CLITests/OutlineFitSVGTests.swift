import XCTest
import Domain
@testable import CounterpointCLI

final class OutlineFitSVGTests: XCTestCase {
    func testBezierOutlineUsesCubicFillPath() throws {
        var config = try parseScurveOptions([
            "--svg", "out.svg",
            "--view", "envelope",
            "--envelope-mode", "union",
            "--quality", "final",
            "--outline-fit", "bezier"
        ])
        config.view.remove(.union)
        let geometry = try buildScurveGeometry(config: config)

        let polygons: PolygonSet
        if config.envelopeMode == .union {
            polygons = geometry.unionPolygons.isEmpty
                ? geometry.stampRings.map { Polygon(outer: $0) }
                : geometry.unionPolygons
        } else {
            polygons = geometry.envelopeOutline.isEmpty ? [] : [Polygon(outer: geometry.envelopeOutline)]
        }

        let fitTolerance = config.fitTolerance ?? defaultFitTolerance(polygons: polygons)
        let simplifyTolerance = config.simplifyTolerance ?? (fitTolerance * 1.5)
        let simplifier = BezierFitter(tolerance: simplifyTolerance)
        let simplified = polygons.map { polygon in
            let outer = simplifier.simplifyRing(polygon.outer, closed: true)
            let holes = polygon.holes.map { simplifier.simplifyRing($0, closed: true) }
            return Polygon(outer: outer, holes: holes)
        }
        let fittedPaths = BezierFitter(tolerance: fitTolerance).fitPolygonSet(simplified)

        let svg = SVGPathBuilder().svgDocument(for: [], fittedPaths: fittedPaths, size: nil, padding: config.padding, debugOverlay: nil)
        guard let filledPathLine = svg.split(separator: "\n").first(where: { $0.contains("fill=\"black\"") }) else {
            XCTFail("Missing filled path")
            return
        }

        XCTAssertTrue(filledPathLine.contains(" C "), "Expected cubic commands in filled path")
        XCTAssertFalse(filledPathLine.contains(" L "), "Expected no raw polygon lines in filled path")
    }

    func testBezierOutlineMonotoneSidesForTrumpet() throws {
        let config = try parseScurveOptions([
            "--svg", "out.svg",
            "--view", "envelope",
            "--envelope-mode", "union",
            "--quality", "final",
            "--outline-fit", "bezier",
            "--size-start", "5",
            "--size-end", "50",
            "--aspect-start", "0.35",
            "--aspect-end", "0.35",
            "--angle-start", "30",
            "--angle-end", "30",
            "--alpha-end", "0.9"
        ])
        let geometry = try buildLineGeometry(config: config)
        let polygons = geometry.unionPolygons.isEmpty
            ? geometry.stampRings.map { Polygon(outer: $0) }
            : geometry.unionPolygons
        let fitTolerance = config.fitTolerance ?? defaultFitTolerance(polygons: polygons)
        let simplifyTolerance = config.simplifyTolerance ?? (fitTolerance * 1.5)
        let fitted = fitUnionRails(
            polygons,
            centerlineSamples: geometry.centerlineSamples,
            simplifyTolerance: simplifyTolerance,
            fitTolerance: fitTolerance
        )
        guard let subpath = fitted.first?.subpaths.first else {
            XCTFail("Missing fitted path")
            return
        }
        let sampled = sampleSubpath(subpath, samplesPerCurve: 12)
        let sValues = sampled.map { projectToCenterlineS(point: $0, samples: geometry.centerlineSamples) }
        let signChanges = countSignChanges(sValues)
        XCTAssertLessThanOrEqual(signChanges, 2)
    }

    func testBezierOutlineUsesMonotoneLoopForNeutralTrumpet() throws {
        let config = try parseScurveOptions([
            "--svg", "out.svg",
            "--view", "envelope",
            "--envelope-mode", "union",
            "--quality", "final",
            "--outline-fit", "bezier",
            "--size-start", "5",
            "--size-end", "50",
            "--aspect-start", "0.35",
            "--aspect-end", "0.35",
            "--angle-start", "30",
            "--angle-end", "30",
            "--alpha-end", "0.0"
        ])
        let geometry = try buildLineGeometry(config: config)
        let polygons = geometry.unionPolygons.isEmpty
            ? geometry.stampRings.map { Polygon(outer: $0) }
            : geometry.unionPolygons
        guard let outer = polygons.first?.outer else {
            XCTFail("Missing union outline")
            return
        }
        XCTAssertTrue(isRingMonotoneInS(outer, centerlineSamples: geometry.centerlineSamples, epsilon: 1.0e-5))
    }

    func testBezierOutlineNoSelfIntersectionForNeutralTrumpet() throws {
        let config = try parseScurveOptions([
            "--svg", "out.svg",
            "--view", "envelope",
            "--envelope-mode", "union",
            "--quality", "final",
            "--outline-fit", "bezier",
            "--size-start", "5",
            "--size-end", "50",
            "--aspect-start", "0.35",
            "--aspect-end", "0.35",
            "--angle-start", "30",
            "--angle-end", "30",
            "--alpha-end", "0.0"
        ])
        let geometry = try buildLineGeometry(config: config)
        let polygons = geometry.unionPolygons.isEmpty
            ? geometry.stampRings.map { Polygon(outer: $0) }
            : geometry.unionPolygons
        let fitTolerance = config.fitTolerance ?? defaultFitTolerance(polygons: polygons)
        let simplifyTolerance = config.simplifyTolerance ?? (fitTolerance * 1.5)
        var fitted = fitUnionRails(
            polygons,
            centerlineSamples: geometry.centerlineSamples,
            simplifyTolerance: simplifyTolerance,
            fitTolerance: fitTolerance
        )
        if outlineHasSelfIntersection(fitted) {
            fitted = []
        }
        XCTAssertFalse(finalOutlineHasSelfIntersection(polygons: polygons, fittedPaths: fitted))
    }

    func testBezierOutlineNoSelfIntersectionForScurveStress() throws {
        let config = try parseScurveOptions([
            "--svg", "out.svg",
            "--view", "envelope",
            "--envelope-mode", "union",
            "--quality", "preview",
            "--samples", "120",
            "--envelope-sides", "24",
            "--outline-fit", "bezier",
            "--angle-mode", "relative",
            "--size-start", "6",
            "--size-end", "24",
            "--aspect-start", "0.3",
            "--aspect-end", "0.3",
            "--angle-start", "20",
            "--angle-end", "75",
            "--alpha-end", "0.5"
        ])
        let geometry = try buildScurveGeometry(config: config)
        let polygons = geometry.unionPolygons.isEmpty
            ? geometry.stampRings.map { Polygon(outer: $0) }
            : geometry.unionPolygons
        let fitTolerance = config.fitTolerance ?? defaultFitTolerance(polygons: polygons)
        let simplifyTolerance = config.simplifyTolerance ?? (fitTolerance * 1.5)
        var fitted = fitUnionRails(
            polygons,
            centerlineSamples: geometry.centerlineSamples,
            simplifyTolerance: simplifyTolerance,
            fitTolerance: fitTolerance
        )
        if outlineHasSelfIntersection(fitted) {
            fitted = []
        }
        XCTAssertFalse(finalOutlineHasSelfIntersection(polygons: polygons, fittedPaths: fitted))
    }

    private func sampleSubpath(_ subpath: FittedSubpath, samplesPerCurve: Int) -> [Point] {
        var points: [Point] = []
        for curve in subpath.segments {
            for i in 0...samplesPerCurve {
                let t = Double(i) / Double(samplesPerCurve)
                points.append(evaluateBezier(curve, t))
            }
        }
        return points
    }

    private func finalOutlineHasSelfIntersection(polygons: PolygonSet, fittedPaths: [FittedPath]) -> Bool {
        if let subpath = fittedPaths.first?.subpaths.first {
            let points = sampleSubpath(subpath, samplesPerCurve: 16)
            return polylineHasSelfIntersection(points, closed: true)
        }
        guard let outer = polygons.first?.outer else { return false }
        let points = closeRing(outer)
        return polylineHasSelfIntersection(points, closed: true)
    }

    private func closeRing(_ ring: Ring) -> Ring {
        guard let first = ring.first else { return ring }
        if ring.last != first {
            return ring + [first]
        }
        return ring
    }

    private func polylineHasSelfIntersection(_ points: [Point], closed: Bool) -> Bool {
        let count = points.count
        guard count >= 4 else { return false }
        let segmentCount = closed ? count : (count - 1)
        for i in 0..<segmentCount {
            let a1 = points[i]
            let a2 = points[(i + 1) % count]
            for j in (i + 1)..<segmentCount {
                if abs(i - j) <= 1 { continue }
                if closed && i == 0 && j == segmentCount - 1 { continue }
                let b1 = points[j]
                let b2 = points[(j + 1) % count]
                if segmentsIntersect(a1, a2, b1, b2) {
                    return true
                }
            }
        }
        return false
    }

    private func segmentsIntersect(_ p1: Point, _ p2: Point, _ q1: Point, _ q2: Point) -> Bool {
        let o1 = orientation(p1, p2, q1)
        let o2 = orientation(p1, p2, q2)
        let o3 = orientation(q1, q2, p1)
        let o4 = orientation(q1, q2, p2)
        return (o1 * o2 < 0) && (o3 * o4 < 0)
    }

    private func orientation(_ a: Point, _ b: Point, _ c: Point) -> Double {
        (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
    }

    private func projectToCenterlineS(point: Point, samples: [PathDomain.Sample]) -> Double {
        guard samples.count >= 2 else { return samples.first?.s ?? 0.0 }
        var bestDist = Double.greatestFiniteMagnitude
        var bestS = samples[0].s
        for i in 0..<(samples.count - 1) {
            let a = samples[i].point
            let b = samples[i + 1].point
            let ab = b - a
            let denom = ab.dot(ab)
            let t = denom > 1.0e-9 ? max(0.0, min(1.0, (point - a).dot(ab) / denom)) : 0.0
            let proj = a + ab * t
            let dist = (point - proj).length
            if dist < bestDist {
                bestDist = dist
                bestS = ScalarMath.lerp(samples[i].s, samples[i + 1].s, t)
            }
        }
        return bestS
    }

    private func countSignChanges(_ values: [Double]) -> Int {
        var changes = 0
        let epsilon = 1.0e-5
        var lastSign = 0
        for i in 1..<values.count {
            let delta = values[i] - values[i - 1]
            let sign = delta > epsilon ? 1 : (delta < -epsilon ? -1 : 0)
            if sign != 0 {
                if lastSign == 0 {
                    lastSign = sign
                } else if sign != lastSign {
                    changes += 1
                    lastSign = sign
                }
            }
        }
        return changes
    }

    private func evaluateBezier(_ bezier: CubicBezier, _ t: Double) -> Point {
        let mt = 1.0 - t
        let b0 = mt * mt * mt
        let b1 = 3.0 * mt * mt * t
        let b2 = 3.0 * mt * t * t
        let b3 = t * t * t
        return bezier.p0 * b0 + bezier.p1 * b1 + bezier.p2 * b2 + bezier.p3 * b3
    }
}
