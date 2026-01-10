import Foundation
import Domain

func catmullRomFittedPath(from ring: Ring, epsilon: Double = 1.0e-9) -> FittedPath? {
    let deduped = removeConsecutiveDuplicates(ring, tol: epsilon)
    let closed = closeRingIfNeeded(deduped, tol: epsilon)
    guard closed.count >= 4 else { return nil }
    var points = closed
    if points.count > 1, points.first == points.last {
        points.removeLast()
    }
    let count = points.count
    guard count >= 2 else { return nil }
    var segments: [CubicBezier] = []
    segments.reserveCapacity(count)
    for i in 0..<count {
        let p0 = points[(i - 1 + count) % count]
        let p1 = points[i]
        let p2 = points[(i + 1) % count]
        let p3 = points[(i + 2) % count]
        let c1 = p1 + (p2 - p0) * (1.0 / 6.0)
        let c2 = p2 - (p3 - p1) * (1.0 / 6.0)
        segments.append(CubicBezier(p0: p1, p1: c1, p2: c2, p3: p2))
    }
    return FittedPath(subpaths: [FittedSubpath(segments: segments)])
}
