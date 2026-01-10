import XCTest
@testable import Domain

final class OutlineTraceMergeNearTests: XCTestCase {
    func testMergeNearDropsSmallNearbyPolygon() {
        let main = rectPolygon(x: 0, y: 0, w: 100, h: 100)
        let smallNear = rectPolygon(x: 101, y: 0, w: 5, h: 5)
        let result = mergeNearArtifacts([main, smallNear], pixelSize: 1.0, mergeDistanceMultiplier: 10.0)
        XCTAssertEqual(result.polygons.count, 1)
    }

    func testMergeNearKeepsFarPolygon() {
        let main = rectPolygon(x: 0, y: 0, w: 100, h: 100)
        let far = rectPolygon(x: 200, y: 0, w: 5, h: 5)
        let result = mergeNearArtifacts([main, far], pixelSize: 1.0, mergeDistanceMultiplier: 10.0)
        XCTAssertEqual(result.polygons.count, 2)
    }

    func testMergeNearKeepsLargeNearbyPolygonSafety() {
        let main = rectPolygon(x: 0, y: 0, w: 100, h: 100)
        let largeNear = rectPolygon(x: 101, y: 0, w: 60, h: 60)
        let result = mergeNearArtifacts([main, largeNear], pixelSize: 1.0, mergeDistanceMultiplier: 10.0)
        XCTAssertEqual(result.polygons.count, 2)
    }

    func testMergeNearKeepsDotAboveMain() {
        let main = rectPolygon(x: 0, y: 0, w: 100, h: 100)
        let dotAbove = rectPolygon(x: 20, y: 106, w: 5, h: 5)
        let result = mergeNearArtifacts([main, dotAbove], pixelSize: 1.0, mergeDistanceMultiplier: 10.0)
        XCTAssertEqual(result.polygons.count, 2)
    }

    func testBBoxDistanceComponents() {
        let a = (min: Point(x: 0, y: 0), max: Point(x: 10, y: 10))
        let b = (min: Point(x: 12, y: 14), max: Point(x: 20, y: 18))
        let components = bboxDistanceComponents(a, b)
        XCTAssertEqual(components.dx, 2.0, accuracy: 1.0e-9)
        XCTAssertEqual(components.dy, 4.0, accuracy: 1.0e-9)
        XCTAssertEqual(components.dist, (20.0).squareRoot(), accuracy: 1.0e-9)

        let c = (min: Point(x: 5, y: 5), max: Point(x: 12, y: 12))
        let overlap = bboxDistanceComponents(a, c)
        XCTAssertEqual(overlap.dx, 0.0, accuracy: 1.0e-9)
        XCTAssertEqual(overlap.dy, 0.0, accuracy: 1.0e-9)
        XCTAssertEqual(overlap.dist, 0.0, accuracy: 1.0e-9)
    }
}

private func rectPolygon(x: Double, y: Double, w: Double, h: Double) -> Domain.Polygon {
    let ring: Ring = [
        Point(x: x, y: y),
        Point(x: x + w, y: y),
        Point(x: x + w, y: y + h),
        Point(x: x, y: y + h),
        Point(x: x, y: y)
    ]
    return Domain.Polygon(outer: ring, holes: [])
}
