import Foundation

public enum BridgeError: LocalizedError {
    case vertexCountMismatch(expected: Int, actual: Int)

    public var errorDescription: String? {
        switch self {
        case .vertexCountMismatch(let expected, let actual):
            return "Bridge vertex count mismatch (expected \(expected), got \(actual))."
        }
    }
}

public struct BridgeBuilder {
    public init() {}

    public func bridgeRings(from ringA: Ring, to ringB: Ring, epsilon: Double = 1.0e-9) throws -> [Ring] {
        let countA = ringA.count
        let countB = ringB.count
        guard countA == countB else {
            throw BridgeError.vertexCountMismatch(expected: countA, actual: countB)
        }
        guard countA >= 3 else { return [] }

        var bridges: [Ring] = []
        bridges.reserveCapacity(countA)

        let ringAClosed = closeRingIfNeeded(ringA)
        let ringBClosed = closeRingIfNeeded(ringB)
        let vertexCount = min(ringAClosed.count, ringBClosed.count) - 1

        for i in 0..<vertexCount {
            let i2 = (i + 1) % vertexCount
            let a0 = ringAClosed[i]
            let a1 = ringAClosed[i2]
            let b0 = ringBClosed[i]
            let b1 = ringBClosed[i2]

            if isSelfIntersectingQuad(a0: a0, a1: a1, b1: b1, b0: b0, epsilon: epsilon) {
                let tri1 = closeRingIfNeeded([a0, a1, b0])
                let tri2 = closeRingIfNeeded([a1, b1, b0])
                appendIfNonDegenerate(tri1, epsilon: epsilon, to: &bridges)
                appendIfNonDegenerate(tri2, epsilon: epsilon, to: &bridges)
            } else {
                let quad = closeRingIfNeeded([a0, a1, b1, b0])
                appendIfNonDegenerate(quad, epsilon: epsilon, to: &bridges)
            }
        }

        return bridges
    }
}

public func closeRingIfNeeded(_ ring: Ring) -> Ring {
    guard let first = ring.first else { return ring }
    if ring.last != first {
        return ring + [first]
    }
    return ring
}

public func ringAreaSigned(_ ring: Ring) -> Double {
    let closed = closeRingIfNeeded(ring)
    guard closed.count >= 4 else { return 0.0 }
    var sum = 0.0
    for i in 0..<(closed.count - 1) {
        let a = closed[i]
        let b = closed[i + 1]
        sum += (a.x * b.y) - (b.x * a.y)
    }
    return 0.5 * sum
}

public func segmentsIntersect(_ p1: Point, _ p2: Point, _ p3: Point, _ p4: Point, epsilon: Double) -> Bool {
    let d1 = direction(p3, p4, p1)
    let d2 = direction(p3, p4, p2)
    let d3 = direction(p1, p2, p3)
    let d4 = direction(p1, p2, p4)

    if crosses(d1, d2, epsilon: epsilon) && crosses(d3, d4, epsilon: epsilon) {
        return true
    }

    return onSegment(p3, p4, p1, epsilon: epsilon) ||
        onSegment(p3, p4, p2, epsilon: epsilon) ||
        onSegment(p1, p2, p3, epsilon: epsilon) ||
        onSegment(p1, p2, p4, epsilon: epsilon)
}

private func isSelfIntersectingQuad(a0: Point, a1: Point, b1: Point, b0: Point, epsilon: Double) -> Bool {
    let e1 = segmentsIntersect(a0, a1, b1, b0, epsilon: epsilon)
    let e2 = segmentsIntersect(a1, b1, b0, a0, epsilon: epsilon)
    return e1 || e2
}

private func appendIfNonDegenerate(_ ring: Ring, epsilon: Double, to rings: inout [Ring]) {
    if abs(ringAreaSigned(ring)) > epsilon {
        rings.append(ring)
    }
}

private func direction(_ a: Point, _ b: Point, _ c: Point) -> Double {
    (c.x - a.x) * (b.y - a.y) - (b.x - a.x) * (c.y - a.y)
}

private func crosses(_ d1: Double, _ d2: Double, epsilon: Double) -> Bool {
    (d1 > epsilon && d2 < -epsilon) || (d1 < -epsilon && d2 > epsilon)
}

private func onSegment(_ a: Point, _ b: Point, _ c: Point, epsilon: Double) -> Bool {
    let minX = min(a.x, b.x) - epsilon
    let maxX = max(a.x, b.x) + epsilon
    let minY = min(a.y, b.y) - epsilon
    let maxY = max(a.y, b.y) + epsilon
    let cross = direction(a, b, c)
    if abs(cross) > epsilon { return false }
    return (c.x >= minX && c.x <= maxX && c.y >= minY && c.y <= maxY)
}
