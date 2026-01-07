import Foundation

public func isClosed(_ ring: Ring, tol: Double = 0) -> Bool {
    guard let first = ring.first, let last = ring.last else { return false }
    return pointsEqual(first, last, tol: tol)
}

public func closeRingIfNeeded(_ ring: Ring, tol: Double = 0) -> Ring {
    guard let first = ring.first else { return ring }
    if isClosed(ring, tol: tol) {
        return ring
    }
    return ring + [first]
}

public func removeConsecutiveDuplicates(_ ring: Ring, tol: Double = 0) -> Ring {
    guard !ring.isEmpty else { return ring }
    var result: Ring = []
    result.reserveCapacity(ring.count)
    var last = ring[0]
    result.append(last)
    for point in ring.dropFirst() {
        if !pointsEqual(point, last, tol: tol) {
            result.append(point)
            last = point
        }
    }
    return result
}

public func signedArea(_ ring: Ring) -> Double {
    guard ring.count >= 3 else { return 0.0 }
    let count = pointsEqual(ring.first!, ring.last!, tol: 0) ? ring.count - 1 : ring.count
    if count < 3 { return 0.0 }
    var sum = 0.0
    for i in 0..<count {
        let a = ring[i]
        let b = ring[(i + 1) % count]
        sum += (a.x * b.y) - (b.x * a.y)
    }
    return 0.5 * sum
}

public func normalizeRing(_ ring: Ring, tol: Double = 0) -> Ring? {
    let trimmed = removeConsecutiveDuplicates(ring, tol: tol)
    let closed = closeRingIfNeeded(trimmed, tol: tol)
    let normalized = removeConsecutiveDuplicates(closed, tol: tol)
    if normalized.count < 4 { return nil }
    let area = signedArea(normalized)
    if abs(area) <= tol { return nil }
    return normalized
}

public func boundingBox(_ ring: Ring) -> (min: Point, max: Point)? {
    guard let first = ring.first else { return nil }
    var minPoint = first
    var maxPoint = first
    for point in ring.dropFirst() {
        minPoint.x = min(minPoint.x, point.x)
        minPoint.y = min(minPoint.y, point.y)
        maxPoint.x = max(maxPoint.x, point.x)
        maxPoint.y = max(maxPoint.y, point.y)
    }
    return (min: minPoint, max: maxPoint)
}

private func pointsEqual(_ a: Point, _ b: Point, tol: Double) -> Bool {
    if tol <= 0 {
        return a == b
    }
    let dx = a.x - b.x
    let dy = a.y - b.y
    return (dx * dx + dy * dy) <= (tol * tol)
}
