import Foundation

public struct CubicBezier: Codable, Equatable {
    public var p0: Point
    public var p1: Point
    public var p2: Point
    public var p3: Point

    public init(p0: Point, p1: Point, p2: Point, p3: Point) {
        self.p0 = p0
        self.p1 = p1
        self.p2 = p2
        self.p3 = p3
    }

    public func point(at u: Double) -> Point {
        let t = max(0.0, min(1.0, u))
        let mt = 1.0 - t
        let a = mt * mt * mt
        let b = 3.0 * mt * mt * t
        let c = 3.0 * mt * t * t
        let d = t * t * t
        return Point(
            x: a * p0.x + b * p1.x + c * p2.x + d * p3.x,
            y: a * p0.y + b * p1.y + c * p2.y + d * p3.y
        )
    }

    public func derivative(at u: Double) -> Point {
        let t = max(0.0, min(1.0, u))
        let mt = 1.0 - t
        let a = 3.0 * mt * mt
        let b = 6.0 * mt * t
        let c = 3.0 * t * t
        return Point(
            x: a * (p1.x - p0.x) + b * (p2.x - p1.x) + c * (p3.x - p2.x),
            y: a * (p1.y - p0.y) + b * (p2.y - p1.y) + c * (p3.y - p2.y)
        )
    }

    public func subdivided() -> (left: CubicBezier, right: CubicBezier) {
        let q0 = midpoint(p0, p1)
        let q1 = midpoint(p1, p2)
        let q2 = midpoint(p2, p3)
        let r0 = midpoint(q0, q1)
        let r1 = midpoint(q1, q2)
        let s = midpoint(r0, r1)
        let left = CubicBezier(p0: p0, p1: q0, p2: r0, p3: s)
        let right = CubicBezier(p0: s, p1: r1, p2: q2, p3: p3)
        return (left, right)
    }

    public func flatness() -> Double {
        let baseline = p3 - p0
        let baselineLength = hypot(baseline.x, baseline.y)
        if baselineLength == 0 { return 0 }
        let d1 = distanceFromLine(point: p1, lineStart: p0, lineEnd: p3)
        let d2 = distanceFromLine(point: p2, lineStart: p0, lineEnd: p3)
        return max(d1, d2)
    }

    private func midpoint(_ a: Point, _ b: Point) -> Point {
        Point(x: (a.x + b.x) * 0.5, y: (a.y + b.y) * 0.5)
    }

    private func distanceFromLine(point: Point, lineStart: Point, lineEnd: Point) -> Double {
        let dx = lineEnd.x - lineStart.x
        let dy = lineEnd.y - lineStart.y
        let lengthSquared = dx * dx + dy * dy
        if lengthSquared == 0 {
            return hypot(point.x - lineStart.x, point.y - lineStart.y)
        }
        let t = ((point.x - lineStart.x) * dx + (point.y - lineStart.y) * dy) / lengthSquared
        let projection = Point(x: lineStart.x + t * dx, y: lineStart.y + t * dy)
        return hypot(point.x - projection.x, point.y - projection.y)
    }
}

public struct BezierPath: Codable, Equatable {
    public var segments: [CubicBezier]

    public init(segments: [CubicBezier]) {
        self.segments = segments
    }
}
