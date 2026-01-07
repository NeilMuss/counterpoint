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
            edgeEps: 0.0
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
            edgeEps: 0.0
        )
        XCTAssertEqual(result.stats.tinyRingCount, 2)
        XCTAssertEqual(result.stats.dedupRingCount, 1)
        XCTAssertEqual(result.rings.count, 1)
    }

    func testSilhouetteKeepsLargestK() {
        let small: Ring = closeRingIfNeeded([
            Point(x: 0.0, y: 0.0),
            Point(x: 5.0, y: 0.0),
            Point(x: 5.0, y: 5.0),
            Point(x: 0.0, y: 5.0)
        ])
        let medium: Ring = closeRingIfNeeded([
            Point(x: 0.0, y: 0.0),
            Point(x: 10.0, y: 0.0),
            Point(x: 10.0, y: 10.0),
            Point(x: 0.0, y: 10.0)
        ])
        let large: Ring = closeRingIfNeeded([
            Point(x: 0.0, y: 0.0),
            Point(x: 20.0, y: 0.0),
            Point(x: 20.0, y: 20.0),
            Point(x: 0.0, y: 20.0)
        ])
        let filtered = applySilhouetteFilter([small, large, medium], k: 2, dropContained: false)
        XCTAssertEqual(filtered.rings.count, 2)
        XCTAssertEqual(filtered.stats.inputCount, 3)
        XCTAssertEqual(filtered.stats.keptCount, 2)
        let keptAreas = filtered.rings.map { ring in
            let xs = ring.map { $0.x }
            let ys = ring.map { $0.y }
            let width = (xs.max() ?? 0.0) - (xs.min() ?? 0.0)
            let height = (ys.max() ?? 0.0) - (ys.min() ?? 0.0)
            return width * height
        }
        XCTAssertTrue(keptAreas.contains(100.0))
        XCTAssertTrue(keptAreas.contains(400.0))
    }

    func testSilhouetteDropsContained() {
        let outer: Ring = closeRingIfNeeded([
            Point(x: 0.0, y: 0.0),
            Point(x: 10.0, y: 0.0),
            Point(x: 10.0, y: 10.0),
            Point(x: 0.0, y: 10.0)
        ])
        let inner: Ring = closeRingIfNeeded([
            Point(x: 2.0, y: 2.0),
            Point(x: 4.0, y: 2.0),
            Point(x: 4.0, y: 4.0),
            Point(x: 2.0, y: 4.0)
        ])
        let filtered = applySilhouetteFilter([outer, inner], k: 2, dropContained: true)
        XCTAssertEqual(filtered.rings.count, 1)
        XCTAssertEqual(filtered.stats.containedDropCount, 1)
    }
}
