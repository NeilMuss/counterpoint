import XCTest
import Domain
@testable import CounterpointCLI

final class UnionPrepTests: XCTestCase {
    func testSliverFilterDropsThinRing() {
        let sliver: Ring = closeRingIfNeeded([
            Point(x: 0.0, y: 0.0),
            Point(x: 100.0, y: 100.0),
            Point(x: 100.1, y: 100.0),
            Point(x: 0.1, y: 0.0)
        ])
        let box: Ring = closeRingIfNeeded([
            Point(x: 0.0, y: 0.0),
            Point(x: 10.0, y: 0.0),
            Point(x: 10.0, y: 10.0),
            Point(x: 0.0, y: 10.0)
        ])
        let result = cleanupRingsForUnion(
            [sliver, box],
            areaEps: 0.0,
            minRingArea: 0.0,
            weldEps: 0.0,
            edgeEps: 0.0,
            inputFilter: .none
        )
        XCTAssertEqual(result.stats.cleanedRingCount, 2)
        XCTAssertEqual(result.stats.sliverRingCount, 1)
        XCTAssertEqual(result.rings.count, 1)
    }

    func testDedupDropsNearIdenticalRings() {
        let ringA: Ring = closeRingIfNeeded([
            Point(x: 0.0, y: 0.0),
            Point(x: 10.0, y: 0.0),
            Point(x: 10.0, y: 10.0),
            Point(x: 0.0, y: 10.0)
        ])
        let ringB: Ring = closeRingIfNeeded([
            Point(x: 0.02, y: 0.01),
            Point(x: 10.01, y: -0.01),
            Point(x: 10.02, y: 10.01),
            Point(x: -0.01, y: 10.02)
        ])
        let result = cleanupRingsForUnion(
            [ringA, ringB],
            areaEps: 0.0,
            minRingArea: 0.0,
            weldEps: 0.0,
            edgeEps: 0.0,
            inputFilter: .none
        )
        XCTAssertEqual(result.stats.tinyRingCount, 2)
        XCTAssertEqual(result.stats.dedupRingCount, 1)
        XCTAssertEqual(result.rings.count, 1)
    }
}
