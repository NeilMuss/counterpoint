import XCTest
import CP2Skeleton

final class AlphaWarpTests: XCTestCase {
    func testWarpIdentityAtZeroAlpha() {
        let samples: [Double] = [0.0, 0.25, 0.5, 0.75, 1.0]
        for t in samples {
            XCTAssertEqual(warpT(t: t, alpha: 0.0), t, accuracy: 1.0e-12)
        }
    }

    func testWarpShiftsEarlyForPositiveAlpha() {
        let warped = warpT(t: 0.5, alpha: 0.5)
        XCTAssertLessThan(warped, 0.5)
    }

    func testWarpShiftsLateForNegativeAlpha() {
        let warped = warpT(t: 0.5, alpha: -0.5)
        XCTAssertGreaterThan(warped, 0.5)
    }

    func testWarpPreservesEndpoints() {
        XCTAssertEqual(warpT(t: 0.0, alpha: 2.0), 0.0, accuracy: 1.0e-12)
        XCTAssertEqual(warpT(t: 1.0, alpha: -2.0), 1.0, accuracy: 1.0e-12)
    }

    func testWarpMonotone() {
        let t0 = warpT(t: 0.2, alpha: 0.7)
        let t1 = warpT(t: 0.6, alpha: 0.7)
        XCTAssertGreaterThan(t1, t0)

        let t2 = warpT(t: 0.2, alpha: -0.7)
        let t3 = warpT(t: 0.6, alpha: -0.7)
        XCTAssertGreaterThan(t3, t2)
    }
}
