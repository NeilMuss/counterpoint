import Foundation

public struct SimplifyPolylineResult: Equatable, Sendable {
    public let points: [Vec2]
    public let removedCount: Int

    public init(points: [Vec2], removedCount: Int) {
        self.points = points
        self.removedCount = removedCount
    }
}

public func simplifyOpenPolylineForCorners(
    _ points: [Vec2],
    epsLen: Double,
    epsAngleRad: Double
) -> SimplifyPolylineResult {
    guard points.count >= 3 else {
        return SimplifyPolylineResult(points: points, removedCount: 0)
    }
    var cleaned: [Vec2] = []
    cleaned.reserveCapacity(points.count)
    var removed = 0
    for point in points {
        if let last = cleaned.last, (point - last).length < epsLen {
            removed += 1
            continue
        }
        cleaned.append(point)
    }
    guard cleaned.count >= 3 else {
        return SimplifyPolylineResult(points: points, removedCount: removed)
    }
    var simplified: [Vec2] = []
    simplified.reserveCapacity(cleaned.count)
    simplified.append(cleaned[0])
    for i in 1..<(cleaned.count - 1) {
        let prev = cleaned[i - 1]
        let current = cleaned[i]
        let next = cleaned[i + 1]
        let u = (current - prev).normalized()
        let v = (next - current).normalized()
        let dot = max(-1.0, min(1.0, u.dot(v)))
        let angle = acos(dot)
        if abs(Double.pi - angle) < epsAngleRad || angle < epsAngleRad {
            removed += 1
            continue
        }
        simplified.append(current)
    }
    simplified.append(cleaned[cleaned.count - 1])
    if simplified.count < 3 {
        return SimplifyPolylineResult(points: points, removedCount: removed)
    }
    return SimplifyPolylineResult(points: simplified, removedCount: removed)
}
