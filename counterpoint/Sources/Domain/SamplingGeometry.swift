import Foundation

public func pointInRing(_ point: Point, ring: Ring) -> Bool {
    let closed = closeRingIfNeeded(ring)
    guard closed.count >= 4 else { return false }
    var inside = false
    var j = closed.count - 1
    for i in 0..<(closed.count - 1) {
        let pi = closed[i]
        let pj = closed[j]
        let intersects = ((pi.y > point.y) != (pj.y > point.y)) &&
            (point.x < (pj.x - pi.x) * (point.y - pi.y) / ((pj.y - pi.y) + 1.0e-12) + pi.x)
        if intersects {
            inside.toggle()
        }
        j = i
    }
    return inside
}

public func distancePointToSegment(_ point: Point, _ a: Point, _ b: Point) -> Double {
    let ab = b - a
    let ap = point - a
    let abLen2 = ab.x * ab.x + ab.y * ab.y
    if abLen2 <= 1.0e-12 {
        return (point - a).length
    }
    let t = max(0.0, min(1.0, ap.dot(ab) / abLen2))
    let proj = Point(x: a.x + ab.x * t, y: a.y + ab.y * t)
    return (point - proj).length
}

public func minDistanceToRingEdges(_ point: Point, ring: Ring) -> Double {
    let closed = closeRingIfNeeded(ring)
    guard closed.count >= 4 else { return Double.greatestFiniteMagnitude }
    var minDistance = Double.greatestFiniteMagnitude
    for i in 0..<(closed.count - 1) {
        let d = distancePointToSegment(point, closed[i], closed[i + 1])
        minDistance = min(minDistance, d)
    }
    return minDistance
}

public func pointInsideOrNearRing(_ point: Point, ring: Ring, tolerance: Double) -> Bool {
    if pointInRing(point, ring: ring) { return true }
    return minDistanceToRingEdges(point, ring: ring) <= tolerance
}
