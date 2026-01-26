import XCTest
@testable import CP2Skeleton

final class KeyframeSamplingTests: XCTestCase {
    func testKeyframeInjectionAddsAndDedupesSamples() {
        let base: [Double] = [0.0, 0.5, 1.0]
        let keyframes: [Double] = [0.013, 0.2, 1.0]
        let merged = injectKeyframeSamples(base, keyframes: keyframes, eps: 1.0e-9)

        XCTAssertTrue(merged.contains(0.0))
        XCTAssertTrue(merged.contains(0.5))
        XCTAssertTrue(merged.contains(1.0))
        XCTAssertTrue(merged.contains(0.013))
        XCTAssertTrue(merged.contains(0.2))

        for i in 1..<merged.count {
            XCTAssertLessThan(merged[i - 1], merged[i])
        }
    }
}
