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
        let railsConfig = try parseScurveOptions([
            "--svg", "out.svg",
            "--view", "envelope,rails",
            "--envelope-mode", "rails",
            "--angle-start", "-60",
            "--angle-end", "60",
            "--size-start", "10",
            "--size-end", "10"
        ])
        var unionConfig = railsConfig
        unionConfig.envelopeMode = .union
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
