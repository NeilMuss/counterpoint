import Foundation

public struct JoinCapBuilder {
    public let arcSegments: Int

    public init(arcSegments: Int = 16) {
        self.arcSegments = max(8, arcSegments)
    }

    public func capRings(point: Point, direction: Point, radius: Double, style: CapStyle) -> [Ring] {
        guard let dir = direction.normalized(), radius > 0 else { return [] }
        let normal = dir.leftNormal()

        switch style {
        case .butt:
            return []
        case .square:
            let center = point + dir * radius
            let half = radius
            let p0 = center + dir * half + normal * half
            let p1 = center + dir * half - normal * half
            let p2 = center - dir * half - normal * half
            let p3 = center - dir * half + normal * half
            return [closeRingIfNeeded([p0, p1, p2, p3])]
        case .round:
            return [halfDisk(point: point, direction: dir, radius: radius)]
        }
    }

    public func joinRings(point: Point, dirIn: Point, dirOut: Point, radius: Double, style: JoinStyle) -> [Ring] {
        guard radius > 0 else { return [] }
        guard let d0 = dirIn.normalized(), let d1 = dirOut.normalized() else { return [] }
        let dot = max(-1.0, min(1.0, d0.dot(d1)))
        if abs(1.0 - abs(dot)) < 1.0e-6 { return [] }

        let left = joinSide(point: point, d0: d0, d1: d1, radius: radius, style: style, sign: 1.0)
        let right = joinSide(point: point, d0: d0, d1: d1, radius: radius, style: style, sign: -1.0)
        return left + right
    }

    private func joinSide(point: Point, d0: Point, d1: Point, radius: Double, style: JoinStyle, sign: Double) -> [Ring] {
        let n0 = d0.leftNormal() * sign
        let n1 = d1.leftNormal() * sign

        switch style {
        case .bevel:
            return []
        case .round:
            return [roundWedge(point: point, from: n0, to: n1, radius: radius)]
        case .miter(let limit):
            let miter = (n0 + n1).normalized()
            guard let miter else {
                return []
            }
            let denom = max(1.0e-6, miter.dot(n1))
            let length = radius / denom
            if length > limit * radius {
                return [triangle(point: point, a: n0, b: n1, radius: radius)]
            }
            let a = point + n0 * radius
            let b = point + miter * length
            let c = point + n1 * radius
            return [closeRingIfNeeded([a, b, c])]
        }
    }

    private func triangle(point: Point, a: Point, b: Point, radius: Double) -> Ring {
        let p0 = point + a * radius
        let p1 = point + b * radius
        return closeRingIfNeeded([p0, p1, point])
    }

    private func roundWedge(point: Point, from n0: Point, to n1: Point, radius: Double) -> Ring {
        let start = atan2(n0.y, n0.x)
        let end = atan2(n1.y, n1.x)
        let (a0, a1) = shortestArc(start: start, end: end)
        let steps = arcSegments
        var points: [Point] = [point]
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let angle = a0 + (a1 - a0) * t
            let p = Point(x: point.x + cos(angle) * radius, y: point.y + sin(angle) * radius)
            points.append(p)
        }
        return closeRingIfNeeded(points)
    }

    private func halfDisk(point: Point, direction: Point, radius: Double) -> Ring {
        let angle = atan2(direction.y, direction.x)
        let start = angle - .pi / 2.0
        let end = angle + .pi / 2.0
        let steps = arcSegments
        var points: [Point] = [point]
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let a = start + (end - start) * t
            let p = Point(x: point.x + cos(a) * radius, y: point.y + sin(a) * radius)
            points.append(p)
        }
        return closeRingIfNeeded(points)
    }

    private func shortestArc(start: Double, end: Double) -> (Double, Double) {
        let delta = AngleMath.shortestDelta(from: start, to: end)
        return (start, start + delta)
    }
}
