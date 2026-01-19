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

public func jFullFixturePath() -> SkeletonPath {
    let hook = CubicBezier2(
        p0: Vec2(12, -8),
        p1: Vec2(-12, -8),
        p2: Vec2(-18, 8),
        p3: Vec2(0, 25)
    )
    let stem = CubicBezier2(
        p0: Vec2(0, 25),
        p1: Vec2(2, 45),
        p2: Vec2(2, 70),
        p3: Vec2(0, 95)
    )
    let head = CubicBezier2(
        p0: Vec2(0, 95),
        p1: Vec2(-2, 105),
        p2: Vec2(-2, 115),
        p3: Vec2(0, 125)
    )
    return SkeletonPath(segments: [hook, stem, head])
}

public func jSerifOnlyFixturePath() -> SkeletonPath {
    let stem = CubicBezier2(
        p0: Vec2(0, 25),
        p1: Vec2(2, 45),
        p2: Vec2(2, 70),
        p3: Vec2(0, 95)
    )
    let head = CubicBezier2(
        p0: Vec2(0, 95),
        p1: Vec2(-2, 105),
        p2: Vec2(-2, 115),
        p3: Vec2(0, 125)
    )
    return SkeletonPath(segments: [stem, head])
}

public func poly3FixturePath() -> SkeletonPath {
    let a = CubicBezier2(
        p0: Vec2(0, 0),
        p1: Vec2(0, 20),
        p2: Vec2(0, 40),
        p3: Vec2(0, 60)
    )
    let b = CubicBezier2(
        p0: Vec2(0, 60),
        p1: Vec2(0, 67),
        p2: Vec2(0, 73),
        p3: Vec2(0, 80)
    )
    let c = CubicBezier2(
        p0: Vec2(0, 80),
        p1: Vec2(0, 100),
        p2: Vec2(0, 120),
        p3: Vec2(0, 140)
    )
    return SkeletonPath(segments: [a, b, c])
}
