import XCTest
import Domain
@testable import CounterpointCLI

final class ScurvePlaygroundTests: XCTestCase {
    func testParseViewModes() throws {
        let config = try parseScurveOptions(["--svg", "out.svg", "--view", "envelope,rays,centerline"])
        XCTAssertTrue(config.view.contains(.envelope))
        XCTAssertTrue(config.view.contains(.rays))
        XCTAssertTrue(config.view.contains(.centerline))
        XCTAssertFalse(config.view.contains(.samples))
    }

    func testDeterministicConfigParsing() throws {
        let args = ["--svg", "out.svg", "--quality", "final", "--view", "envelope,rails"]
        let a = try parseScurveOptions(args)
        let b = try parseScurveOptions(args)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.samplesPerSegment, b.samplesPerSegment)
    }

    func testValidationRejectsInvalidInputs() throws {
        let badSize = try parseScurveOptions(["--svg", "out.svg", "--size-start", "-1"])
        XCTAssertThrowsError(try validate(config: badSize))

        let badAlpha = try parseScurveOptions(["--svg", "out.svg", "--alpha-end", "2"])
        XCTAssertThrowsError(try validate(config: badAlpha))
    }

    func testEnvelopeModeParsing() throws {
        let config = try parseScurveOptions(["--svg", "out.svg", "--envelope-mode", "rails"])
        XCTAssertEqual(config.envelopeMode, .rails)
    }

    func testUnionEnvelopeBeatsRailsInCurveCase() throws {
        var railsConfig = try parseScurveOptions([
            "--svg", "out.svg",
            "--view", "envelope,rails",
            "--envelope-mode", "rails",
            "--angle-start", "-60",
            "--angle-end", "60",
            "--size-start", "10",
            "--size-end", "10"
        ])
        railsConfig.maxSamples = 40
        railsConfig.maxDepth = 4
        railsConfig.tolerance = 5.0

        var unionConfig = railsConfig
        unionConfig.envelopeMode = .union
        unionConfig.maxSamples = 200
        unionConfig.maxDepth = 10
        unionConfig.tolerance = 0.5
        unionConfig.view.insert(.envelope)

        let railsGeom = try buildScurveGeometry(config: railsConfig)
        let unionGeom = try buildScurveGeometry(config: unionConfig)

        let railsArea = abs(ringAreaSigned(railsGeom.envelopeOutline))
        let unionArea = unionGeom.unionPolygons.reduce(0.0) { sum, polygon in
            sum + abs(ringAreaSigned(polygon.outer))
        }

        XCTAssertGreaterThan(unionArea, railsArea * 1.01)
        for polygon in unionGeom.unionPolygons {
            XCTAssertFalse(hasSelfIntersection(polygon.outer))
        }
    }

    func testUnionEnvelopeNonEmptyForKnownCommand() throws {
        var config = try parseScurveOptions([
            "--svg", "out.svg",
            "--quality", "final",
            "--view", "envelope",
            "--envelope-mode", "union",
            "--angle-mode", "relative",
            "--angle-start", "20",
            "--angle-end", "75",
            "--size-start", "12",
            "--size-end", "30",
            "--alpha-end", "0.5"
        ])
        config.view.insert(.envelope)
        let geometry = try buildScurveGeometry(config: config)
        XCTAssertFalse(geometry.unionPolygons.isEmpty)
    }

    func testAdaptivePreviewLessThanFinal() throws {
        let preview = try parseScurveOptions(["--svg", "out.svg", "--quality", "preview"])
        let final = try parseScurveOptions(["--svg", "out.svg", "--quality", "final"])

        let previewGeom = try buildScurveGeometry(config: preview)
        let finalGeom = try buildScurveGeometry(config: final)
        XCTAssertLessThan(previewGeom.sValues.count, finalGeom.sValues.count)
    }

    func testAdaptiveRespectsCap() throws {
        let config = try parseScurveOptions(["--svg", "out.svg", "--samples", "12"])
        let geometry = try buildScurveGeometry(config: config)
        XCTAssertLessThanOrEqual(geometry.sValues.count, 12)
        XCTAssertEqual(geometry.sValues.first, 0.0)
        XCTAssertEqual(geometry.sValues.last, 1.0)
    }

    func testAdaptiveDeterminism() throws {
        let config = try parseScurveOptions(["--svg", "out.svg", "--quality", "preview"])
        let a = try buildScurveGeometry(config: config)
        let b = try buildScurveGeometry(config: config)
        XCTAssertEqual(a.sValues, b.sValues)
    }

    func testUnionOverlapConstraintPreventsGaps() throws {
        var config = try parseScurveOptions([
            "--svg", "out.svg",
            "--quality", "final",
            "--view", "envelope",
            "--envelope-mode", "union",
            "--angle-mode", "relative",
            "--angle-start", "-90",
            "--angle-end", "90",
            "--size-start", "4",
            "--size-end", "4",
            "--aspect-start", "0.6",
            "--aspect-end", "0.6"
        ])
        config.maxSamples = 800
        config.maxDepth = 14
        config.view.insert(.envelope)

        let geometry = try buildScurveGeometry(config: config)
        XCTAssertLessThanOrEqual(geometry.maxOverlapRatio, 0.82)
    }

    func testOffsetInterpolationOnLine() throws {
        let config = try parseScurveOptions([
            "--svg", "out.svg",
            "--view", "envelope,rails",
            "--angle-mode", "absolute",
            "--angle-start", "0",
            "--angle-end", "0",
            "--size-start", "12",
            "--size-end", "12",
            "--aspect-start", "1.0",
            "--aspect-end", "1.0",
            "--offset-start", "0",
            "--offset-end", "10"
        ])
        let geometry = try buildLineGeometry(config: config)
        guard let lastLeft = geometry.envelopeLeft.last,
              let lastRight = geometry.envelopeRight.last else {
            XCTFail("Missing envelope rails")
            return
        }
        let center = (lastLeft + lastRight) * 0.5
        let centerline = pointAtS(1.0, samples: geometry.centerlineSamples)
        let offset = center.y - centerline.y
        XCTAssertEqual(offset, 10.0, accuracy: 0.5)
    }

    func testOffsetShiftsEnvelopeBounds() throws {
        let baseConfig = try parseScurveOptions([
            "--svg", "out.svg",
            "--view", "envelope,rails",
            "--angle-mode", "absolute",
            "--angle-start", "0",
            "--angle-end", "0",
            "--size-start", "12",
            "--size-end", "12",
            "--aspect-start", "1.0",
            "--aspect-end", "1.0",
            "--offset-start", "0",
            "--offset-end", "0"
        ])
        var offsetConfig = baseConfig
        offsetConfig.offsetStart = 0.0
        offsetConfig.offsetEnd = 14.0

        let baseGeom = try buildLineGeometry(config: baseConfig)
        let offsetGeom = try buildLineGeometry(config: offsetConfig)

        let baseBounds = railsBounds(left: baseGeom.envelopeLeft, right: baseGeom.envelopeRight)
        let offsetBounds = railsBounds(left: offsetGeom.envelopeLeft, right: offsetGeom.envelopeRight)

        XCTAssertGreaterThan(offsetBounds.maxY, baseBounds.maxY)
    }

    private func hasSelfIntersection(_ ring: Ring) -> Bool {
        let closed = closeRingIfNeeded(ring)
        guard closed.count >= 4 else { return false }
        let n = closed.count - 1
        for i in 0..<n {
            let a1 = closed[i]
            let a2 = closed[(i + 1) % n]
            for j in (i + 1)..<n {
                if abs(i - j) <= 1 || (i == 0 && j == n - 1) { continue }
                let b1 = closed[j]
                let b2 = closed[(j + 1) % n]
                if segmentsIntersect(a1, a2, b1, b2, epsilon: 1.0e-9) {
                    return true
                }
            }
        }
        return false
    }

    private func pointAtS(_ s: Double, samples: [PathDomain.Sample]) -> Point {
        guard let first = samples.first else { return Point(x: 0, y: 0) }
        var best = first.point
        var bestDelta = Double.greatestFiniteMagnitude
        for sample in samples {
            let delta = abs(sample.s - s)
            if delta < bestDelta {
                bestDelta = delta
                best = sample.point
            }
        }
        return best
    }

    private func railsBounds(left: [Point], right: [Point]) -> (minY: Double, maxY: Double) {
        let all = left + right
        var minY = Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        for point in all {
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return (minY, maxY)
    }
}
