import Foundation

public struct Point: Codable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static func + (lhs: Point, rhs: Point) -> Point {
        Point(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    public static func - (lhs: Point, rhs: Point) -> Point {
        Point(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    public static func * (lhs: Point, rhs: Double) -> Point {
        Point(x: lhs.x * rhs, y: lhs.y * rhs)
    }
}

public extension Point {
    var length: Double { hypot(x, y) }

    func normalized(epsilon: Double = 1.0e-9) -> Point? {
        let len = length
        if len <= epsilon { return nil }
        return Point(x: x / len, y: y / len)
    }

    func dot(_ other: Point) -> Double {
        x * other.x + y * other.y
    }

    func leftNormal() -> Point {
        Point(x: -y, y: x)
    }
}

public typealias Ring = [Point]

public struct Polygon: Codable, Equatable {
    public var outer: Ring
    public var holes: [Ring]

    public init(outer: Ring, holes: [Ring] = []) {
        self.outer = outer
        self.holes = holes
    }
}

public typealias PolygonSet = [Polygon]

public enum AngleMath {
    public static func wrapPi(_ value: Double) -> Double {
        var wrapped = value.truncatingRemainder(dividingBy: 2.0 * .pi)
        if wrapped <= -.pi { wrapped += 2.0 * .pi }
        if wrapped > .pi { wrapped -= 2.0 * .pi }
        return wrapped
    }

    public static func shortestDelta(from start: Double, to end: Double) -> Double {
        wrapPi(end - start)
    }

    public static func angularDifference(_ a: Double, _ b: Double) -> Double {
        wrapPi(a - b)
    }

    public static func directionVector(unitTangent: Point, angleDegrees: Double, mode: AngleMode) -> Point {
        switch mode {
        case .absolute:
            return GeometryMath.unitVectorFromAngleDegrees(angleDegrees)
        case .tangentRelative:
            let radians = angleDegrees * .pi / 180.0
            return GeometryMath.rotate(point: unitTangent, by: radians)
        }
    }
}

public enum GeometryMath {
    public static func rotate(point: Point, by angle: Double) -> Point {
        let c = cos(angle)
        let s = sin(angle)
        return Point(x: point.x * c - point.y * s, y: point.x * s + point.y * c)
    }

    public static func unitVectorFromAngleDegrees(_ degrees: Double) -> Point {
        let radians = degrees * .pi / 180.0
        return Point(x: cos(radians), y: sin(radians))
    }
}

public enum ScalarMath {
    public static func clamp01(_ value: Double) -> Double {
        min(max(value, 0.0), 1.0)
    }

    public static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }
}
