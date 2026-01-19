import CP2Geometry

public struct CubicBezier2: Equatable, Codable {
    public var p0: Vec2
    public var p1: Vec2
    public var p2: Vec2
    public var p3: Vec2

    public init(p0: Vec2, p1: Vec2, p2: Vec2, p3: Vec2) {
        self.p0 = p0
        self.p1 = p1
        self.p2 = p2
        self.p3 = p3
    }

    public func evaluate(_ u: Double) -> Vec2 {
        let a = p0.lerp(to: p1, t: u)
        let b = p1.lerp(to: p2, t: u)
        let c = p2.lerp(to: p3, t: u)
        let d = a.lerp(to: b, t: u)
        let e = b.lerp(to: c, t: u)
        return d.lerp(to: e, t: u)
    }

    public func derivative(_ u: Double) -> Vec2 {
        let oneMinus = 1.0 - u
        let a = (p1 - p0) * (3.0 * oneMinus * oneMinus)
        let b = (p2 - p1) * (6.0 * oneMinus * u)
        let c = (p3 - p2) * (3.0 * u * u)
        return a + b + c
    }

    public func tangent(_ u: Double) -> Vec2 {
        derivative(u).normalized()
    }
}
