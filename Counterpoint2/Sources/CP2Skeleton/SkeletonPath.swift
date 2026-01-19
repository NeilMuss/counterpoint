import CP2Geometry

public struct SkeletonPath: Equatable, Codable {
    public var segments: [CubicBezier2]

    public init(segments: [CubicBezier2]) {
        self.segments = segments
    }

    public func evaluate(_ u: Double) -> Vec2 {
        guard let first = segments.first else { return Vec2(0, 0) }
        return first.evaluate(u)
    }

    public func tangent(_ u: Double) -> Vec2 {
        guard let first = segments.first else { return Vec2(1, 0) }
        return first.tangent(u)
    }
}
