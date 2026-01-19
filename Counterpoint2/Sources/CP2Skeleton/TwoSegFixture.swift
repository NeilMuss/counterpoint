import CP2Geometry

public func twoSegFixturePath() -> SkeletonPath {
    let a = CubicBezier2(
        p0: Vec2(0, 0),
        p1: Vec2(16.6666666667, 0),
        p2: Vec2(33.3333333333, 0),
        p3: Vec2(50, 0)
    )
    let b = CubicBezier2(
        p0: Vec2(50, 0),
        p1: Vec2(50, 33.3333333333),
        p2: Vec2(50, 66.6666666667),
        p3: Vec2(50, 100)
    )
    return SkeletonPath(segments: [a, b])
}
