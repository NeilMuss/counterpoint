import CP2Geometry

public func jStemFixturePath() -> SkeletonPath {
    let a = CubicBezier2(
        p0: Vec2(0, 0),
        p1: Vec2(2, 25),
        p2: Vec2(2, 55),
        p3: Vec2(0, 75)
    )
    let b = CubicBezier2(
        p0: Vec2(0, 75),
        p1: Vec2(-2, 90),
        p2: Vec2(-2, 105),
        p3: Vec2(0, 120)
    )
    return SkeletonPath(segments: [a, b])
}
