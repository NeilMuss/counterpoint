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
}
