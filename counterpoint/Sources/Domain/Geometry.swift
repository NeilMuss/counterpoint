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
}

public enum GeometryMath {
    public static func rotate(point: Point, by angle: Double) -> Point {
        let c = cos(angle)
        let s = sin(angle)
        return Point(x: point.x * c - point.y * s, y: point.x * s + point.y * c)
    }
}
