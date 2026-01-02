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
        let fitted = fitUnionRails(
            polygons,
            centerlineSamples: geometry.centerlineSamples,
            simplifyTolerance: simplifyTolerance,
            fitTolerance: fitTolerance
        )
        XCTAssertFalse(outlineHasSelfIntersection(fitted))
    }

    func testBezierOutlineNoSelfIntersectionForScurveStress() throws {
        let config = try parseScurveOptions([
            "--svg", "out.svg",
            "--view", "envelope",
            "--envelope-mode", "union",
            "--quality", "final",
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
        let fitted = fitUnionRails(
            polygons,
            centerlineSamples: geometry.centerlineSamples,
            simplifyTolerance: simplifyTolerance,
            fitTolerance: fitTolerance
        )
        XCTAssertFalse(outlineHasSelfIntersection(fitted))
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
