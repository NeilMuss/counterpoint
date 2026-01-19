import CP2Geometry

public func sCurveFixtureCubic() -> CubicBezier2 {
    return CubicBezier2(
        p0: Vec2(0, 0),
        p1: Vec2(50, 0),
        p2: Vec2(-50, 100),
        p3: Vec2(0, 100)
    )
}

public func fastSCurveFixtureCubic() -> CubicBezier2 {
    return CubicBezier2(
        p0: Vec2(0, 0),
        p1: Vec2(70, 0),
        p2: Vec2(-70, 100),
        p3: Vec2(0, 100)
    )
}

public func fastSCurve2FixtureCubic() -> CubicBezier2 {
    return CubicBezier2(
        p0: Vec2(0, 0),
        p1: Vec2(100, 0),
        p2: Vec2(-40, 100),
        p3: Vec2(0, 100)
    )
}
