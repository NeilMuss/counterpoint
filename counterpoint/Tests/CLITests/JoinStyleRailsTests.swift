import XCTest
import Domain
@testable import CounterpointCLI

final class JoinStyleRailsTests: XCTestCase {
    func testKinkedRailsJoinStylesDiffer() throws {
        let path = kinkPath()
        var config = try parseScurveOptions([
            "--svg", "out.svg",
            "--view", "envelope",
            "--envelope-mode", "rails",
            "--quality", "preview",
            "--outline-fit", "none"
        ])
        config.view = [.envelope]
        config.envelopeMode = .rails
        config.outlineFit = .none

        config.joinStyle = .bevel
        let bevel = try buildPlaygroundGeometry(path: path, config: config)
        config.joinStyle = .miter(miterLimit: 4.0)
        let miter = try buildPlaygroundGeometry(path: path, config: config)
        config.joinStyle = .round
        let round = try buildPlaygroundGeometry(path: path, config: config)

        let bevelBounds = bounds(of: bevel.envelopeOutline)
        let miterBounds = bounds(of: miter.envelopeOutline)
        let roundBounds = bounds(of: round.envelopeOutline)

        XCTAssertLessThanOrEqual(bevelBounds.maxX, roundBounds.maxX + 1.0e-6)
        XCTAssertLessThanOrEqual(bevelBounds.maxY, roundBounds.maxY + 1.0e-6)
        XCTAssertLessThanOrEqual(roundBounds.maxX, miterBounds.maxX + 1.0e-6)
        XCTAssertLessThanOrEqual(roundBounds.maxY, miterBounds.maxY + 1.0e-6)
        XCTAssertGreaterThan(round.envelopeOutline.count, bevel.envelopeOutline.count)
        XCTAssertFalse(hasSelfIntersection(miter.envelopeOutline))
    }

    private func kinkPath() -> BezierPath {
        BezierPath(segments: [
            lineSegment(from: Point(x: 0, y: 0), to: Point(x: 120, y: 0)),
            lineSegment(from: Point(x: 120, y: 0), to: Point(x: 120, y: 120))
        ])
    }

    private func lineSegment(from start: Point, to end: Point) -> CubicBezier {
        let delta = end - start
        let p1 = start + delta * (1.0 / 3.0)
        let p2 = start + delta * (2.0 / 3.0)
        return CubicBezier(p0: start, p1: p1, p2: p2, p3: end)
    }

    private func bounds(of points: [Point]) -> (minX: Double, maxX: Double, minY: Double, maxY: Double) {
        guard let first = points.first else {
            return (0.0, 0.0, 0.0, 0.0)
        }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return (minX, maxX, minY, maxY)
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
