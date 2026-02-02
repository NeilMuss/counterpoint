import XCTest
import CP2Geometry
import CP2Skeleton

final class CapFilletBothFixtureTests: XCTestCase {
    func testStraightLineEndCapBothCornersFilleted() {
        let leftRail = [Vec2(0, 40), Vec2(200, 40)]
        let rightRail = [Vec2(0, -40), Vec2(200, -40)]

        let base = baseCapPolyline(leftRail: leftRail, rightRail: rightRail, atStart: false)
        XCTAssertEqual(base.count, 4)

        var fillets: [CapFilletDebug] = []
        let caps = buildCaps(
            leftRail: leftRail,
            rightRail: rightRail,
            capNamespace: "straight",
            capLocalIndex: 0,
            widthStart: 80.0,
            widthEnd: 80.0,
            startCap: .butt,
            endCap: .fillet(radius: 5.0, corner: .both),
            capFilletArcSegments: 32,
            debugFillet: { fillets.append($0) }
        )

        let endLeft = fillets.first { $0.kind == "end" && $0.side == "left" }
        let endRight = fillets.first { $0.kind == "end" && $0.side == "right" }
        XCTAssertNotNil(endLeft)
        XCTAssertNotNil(endRight)
        XCTAssertTrue(endLeft?.success ?? false)
        XCTAssertTrue(endRight?.success ?? false)
        if let left = endLeft, let right = endRight {
            XCTAssertGreaterThan(left.theta, 1.4)
            XCTAssertGreaterThan(right.theta, 1.4)
            XCTAssertGreaterThanOrEqual(left.insertedPoints, 20)
            XCTAssertGreaterThanOrEqual(right.insertedPoints, 20)
        }
        XCTAssertGreaterThanOrEqual(endLeft?.arcSegments ?? 0, 6)
        XCTAssertGreaterThanOrEqual(endRight?.arcSegments ?? 0, 6)
        if let left = endLeft, let right = endRight {
            XCTAssertTrue(pointInPolygon(left.arcMidpoint, polygon: base))
            XCTAssertTrue(pointInPolygon(right.arcMidpoint, polygon: base))
            assertPQInvariant(left)
            assertPQInvariant(right)
            assertSmoothArc(left, segments: left.arcSegments)
            assertSmoothArc(right, segments: right.arcSegments)
        }

        let endSegments = caps.segments.filter { seg in
            if case .capEndEdge = seg.source { return true }
            return false
        }
        if let leftEnd = leftRail.last, let rightEnd = rightRail.last {
            let hasDirect = endSegments.contains { seg in
                (Epsilon.approxEqual(seg.a, leftEnd) && Epsilon.approxEqual(seg.b, rightEnd)) ||
                (Epsilon.approxEqual(seg.a, rightEnd) && Epsilon.approxEqual(seg.b, leftEnd))
            }
            XCTAssertFalse(hasDirect)
        }
        XCTAssertTrue(endSegments.contains { $0.source.description.contains("fillet-left") })
        XCTAssertTrue(endSegments.contains { $0.source.description.contains("fillet-right") })

        let buttCaps = buildCaps(
            leftRail: leftRail,
            rightRail: rightRail,
            capNamespace: "straight",
            capLocalIndex: 0,
            widthStart: 80.0,
            widthEnd: 80.0,
            startCap: .butt,
            endCap: .butt
        )
        let buttEndSegments = buttCaps.segments.filter { seg in
            if case .capEndEdge = seg.source { return true }
            return false
        }
        XCTAssertGreaterThan(endSegments.count, buttEndSegments.count)
    }
}

private func pointInPolygon(_ point: Vec2, polygon: [Vec2]) -> Bool {
    guard polygon.count >= 3 else { return false }
    var inside = false
    var j = polygon.count - 1
    for i in 0..<polygon.count {
        let pi = polygon[i]
        let pj = polygon[j]
        let intersects = ((pi.y > point.y) != (pj.y > point.y)) &&
            (point.x < (pj.x - pi.x) * (point.y - pi.y) / ((pj.y - pi.y) + 1.0e-12) + pi.x)
        if intersects { inside.toggle() }
        j = i
    }
    return inside
}

private func assertPQInvariant(_ fillet: CapFilletDebug, file: StaticString = #filePath, line: UInt = #line) {
    let inDir = (fillet.b - fillet.a).normalized()
    let outDir = (fillet.c - fillet.b).normalized()
    XCTAssertGreaterThan((fillet.p - fillet.b).normalized().dot(inDir * -1.0), 0.999, file: file, line: line)
    XCTAssertGreaterThan((fillet.q - fillet.b).normalized().dot(outDir), 0.999, file: file, line: line)
    if let bridge = fillet.bridge {
        let start = bridge.evaluate(0.0)
        let end = bridge.evaluate(1.0)
        XCTAssertLessThan((start - fillet.p).length, 1.0e-9, file: file, line: line)
        XCTAssertLessThan((end - fillet.q).length, 1.0e-9, file: file, line: line)
    }
}

private func assertSmoothArc(_ fillet: CapFilletDebug, segments: Int, file: StaticString = #filePath, line: UInt = #line) {
    guard let bridge = fillet.bridge else { return }
    let count = max(2, segments + 1)
    var points: [Vec2] = []
    points.reserveCapacity(count)
    for i in 0..<count {
        let t = Double(i) / Double(count - 1)
        points.append(bridge.evaluate(t))
    }
    XCTAssertGreaterThanOrEqual(points.count, 20, file: file, line: line)
    for i in 1..<(points.count - 1) {
        let a = (points[i] - points[i - 1]).normalized()
        let b = (points[i + 1] - points[i]).normalized()
        XCTAssertGreaterThan(a.dot(b), -0.2, file: file, line: line)
    }
    if let first = points.first, let last = points.last, points.count >= 3 {
        var maxDist = 0.0
        for point in points.dropFirst().dropLast() {
            maxDist = max(maxDist, distancePointToSegment(point, first, last))
        }
        XCTAssertGreaterThan(maxDist, 0.5, file: file, line: line)
    }
}

private func distancePointToSegment(_ p: Vec2, _ a: Vec2, _ b: Vec2) -> Double {
    let ab = b - a
    let denom = max(Epsilon.defaultValue, ab.dot(ab))
    let t = max(0.0, min(1.0, (p - a).dot(ab) / denom))
    let proj = a + ab * t
    return (p - proj).length
}
