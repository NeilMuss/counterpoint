public struct Vec2: Equatable, Codable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    public static func + (lhs: Vec2, rhs: Vec2) -> Vec2 {
        Vec2(lhs.x + rhs.x, lhs.y + rhs.y)
    }

    public static func - (lhs: Vec2, rhs: Vec2) -> Vec2 {
        Vec2(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    public static func * (lhs: Vec2, rhs: Double) -> Vec2 {
        Vec2(lhs.x * rhs, lhs.y * rhs)
    }

    public static func * (lhs: Double, rhs: Vec2) -> Vec2 {
        Vec2(lhs * rhs.x, lhs * rhs.y)
    }

    public func dot(_ other: Vec2) -> Double {
        x * other.x + y * other.y
    }

    public var length: Double {
        (x * x + y * y).squareRoot()
    }

    public func normalized(eps: Double = Epsilon.defaultValue) -> Vec2 {
        let len = length
        if len <= eps { return Vec2(0, 0) }
        return Vec2(x / len, y / len)
    }

    public func lerp(to other: Vec2, t: Double) -> Vec2 {
        Vec2(x + (other.x - x) * t, y + (other.y - y) * t)
    }
}
