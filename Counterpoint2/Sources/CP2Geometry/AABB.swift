public struct AABB: Equatable, Codable {
    public var min: Vec2
    public var max: Vec2

    public static let empty = AABB(
        min: Vec2(Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude),
        max: Vec2(-Double.greatestFiniteMagnitude, -Double.greatestFiniteMagnitude)
    )

    public init(min: Vec2, max: Vec2) {
        self.min = min
        self.max = max
    }

    public mutating func expand(by point: Vec2) {
        min = Vec2(Swift.min(min.x, point.x), Swift.min(min.y, point.y))
        max = Vec2(Swift.max(max.x, point.x), Swift.max(max.y, point.y))
    }

    public func union(_ other: AABB) -> AABB {
        AABB(
            min: Vec2(Swift.min(min.x, other.min.x), Swift.min(min.y, other.min.y)),
            max: Vec2(Swift.max(max.x, other.max.x), Swift.max(max.y, other.max.y))
        )
    }

    public var width: Double { max.x - min.x }
    public var height: Double { max.y - min.y }
}
