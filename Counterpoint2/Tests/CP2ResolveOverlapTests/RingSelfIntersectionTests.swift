import XCTest
import CP2ResolveOverlap
import CP2Geometry

final class RingSelfIntersectionTests: XCTestCase {
    func testRingSelfIntersectionCountSimpleIsZero() {
        let square: [Vec2] = [
            Vec2(0, 0),
            Vec2(2, 0),
            Vec2(2, 2),
            Vec2(0, 2),
            Vec2(0, 0)
        ]
        XCTAssertEqual(ringSelfIntersectionCount(square), 0)
    }

    func testRingSelfIntersectionCountBowtieIsNonZero() {
        let bowtie: [Vec2] = [
            Vec2(0, 0),
            Vec2(2, 2),
            Vec2(0, 2),
            Vec2(2, 0),
            Vec2(0, 0)
        ]
        XCTAssertGreaterThan(ringSelfIntersectionCount(bowtie), 0)
    }
}
