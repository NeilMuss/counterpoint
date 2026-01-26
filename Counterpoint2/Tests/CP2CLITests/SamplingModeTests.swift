import XCTest
@testable import cp2_cli

final class SamplingModeTests: XCTestCase {
    func testDefaultAdaptiveSamplingIsOn() {
        let options = parseArgs([])
        XCTAssertTrue(options.adaptiveSampling)
    }

    func testArcSamplesWithoutAllowFixedThrows() {
        let options = parseArgs(["--arc-samples", "128"])
        XCTAssertThrowsError(try validateSamplingOptions(options))
    }

    func testNoAdaptiveWithoutAllowFixedThrows() {
        let options = parseArgs(["--no-adaptive-sampling"])
        XCTAssertThrowsError(try validateSamplingOptions(options))
    }

    func testAllowFixedSamplingPermitsFixedMode() {
        let options = parseArgs(["--no-adaptive-sampling", "--allow-fixed-sampling", "--arc-samples", "128"])
        XCTAssertNoThrow(try validateSamplingOptions(options))
    }
}
