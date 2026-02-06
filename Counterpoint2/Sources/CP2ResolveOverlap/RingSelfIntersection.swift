import CP2Geometry

public func ringSelfIntersectionPoints(_ ring: [Vec2], eps: Double = 1.0e-9) -> [Vec2] {
    let n = ring.count
    guard n >= 4 else { return [] }
    let lastIsFirst = Epsilon.approxEqual(ring.first!, ring.last!, eps: eps)
    let edgeCount = lastIsFirst ? n - 1 : n
    func cross(_ a: Vec2, _ b: Vec2) -> Double { a.x * b.y - a.y * b.x }
    func segmentIntersection(_ a: Vec2, _ b: Vec2, _ c: Vec2, _ d: Vec2) -> Vec2? {
        let r = b - a
        let s = d - c
        let denom = cross(r, s)
        if abs(denom) <= eps { return nil }
        let t = cross(c - a, s) / denom
        let u = cross(c - a, r) / denom
        if t >= -eps && t <= 1.0 + eps && u >= -eps && u <= 1.0 + eps {
            return Vec2(a.x + r.x * t, a.y + r.y * t)
        }
        return nil
    }

    var hits: [Vec2] = []
    for i in 0..<edgeCount {
        let a0 = ring[i]
        let a1 = ring[(i + 1) % edgeCount]
        if (a1 - a0).length <= eps { continue }
        if i + 2 >= edgeCount { continue }
        for j in (i + 2)..<edgeCount {
            if i == 0 && j == edgeCount - 1 { continue }
            let b0 = ring[j]
            let b1 = ring[(j + 1) % edgeCount]
            if (b1 - b0).length <= eps { continue }
            if let hit = segmentIntersection(a0, a1, b0, b1) {
                if Epsilon.approxEqual(hit, a0, eps: eps)
                    || Epsilon.approxEqual(hit, a1, eps: eps)
                    || Epsilon.approxEqual(hit, b0, eps: eps)
                    || Epsilon.approxEqual(hit, b1, eps: eps) {
                    continue
                }
                hits.append(hit)
            }
        }
    }
    return hits
}

public func ringSelfIntersectionCount(_ ring: [Vec2], eps: Double = 1.0e-9) -> Int {
    ringSelfIntersectionPoints(ring, eps: eps).count
}
