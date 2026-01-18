import Foundation

public struct RingSanitizeStats: Equatable {
    public let droppedDuplicates: Int
    public let droppedHairpins: Int
    public let droppedHairpinIndices: [Int]

    public init(droppedDuplicates: Int, droppedHairpins: Int, droppedHairpinIndices: [Int]) {
        self.droppedDuplicates = droppedDuplicates
        self.droppedHairpins = droppedHairpins
        self.droppedHairpinIndices = droppedHairpinIndices
    }
}

public func sanitizeRing(
    _ ring: [Point],
    eps: Double,
    hairpinAngleDeg: Double,
    hairpinSpanTol: Double
) -> [Point] {
    sanitizeRingWithStats(ring, eps: eps, hairpinAngleDeg: hairpinAngleDeg, hairpinSpanTol: hairpinSpanTol).ring
}

public func sanitizeRingWithStats(
    _ ring: [Point],
    eps: Double,
    hairpinAngleDeg: Double,
    hairpinSpanTol: Double
) -> (ring: [Point], stats: RingSanitizeStats) {
    guard ring.count >= 2 else {
        return (ring, RingSanitizeStats(droppedDuplicates: 0, droppedHairpins: 0, droppedHairpinIndices: []))
    }
    let epsSquared = eps * eps
    let edgeTol = max(5.0 * eps, 0.02)
    let edgeTolSquared = edgeTol * edgeTol

    let firstDelta = ring.first! - ring.last!
    let isClosed = firstDelta.dot(firstDelta) <= epsSquared
    let basePoints = isClosed ? Array(ring.dropLast()) : ring

    var deduped: [(point: Point, index: Int)] = []
    deduped.reserveCapacity(basePoints.count)
    var droppedDup = 0
    for (idx, point) in basePoints.enumerated() {
        if let last = deduped.last {
            let delta = point - last.point
            if delta.dot(delta) <= epsSquared {
                droppedDup += 1
                continue
            }
        }
        deduped.append((point, idx))
    }

    var stack: [(point: Point, index: Int)] = []
    stack.reserveCapacity(deduped.count)
    var droppedHairpin = 0
    var droppedHairpinIndices: [Int] = []

    func angleDegrees(a: Point, b: Point, c: Point) -> Double? {
        let v1 = b - a
        let v2 = c - b
        let len1 = v1.length
        let len2 = v2.length
        if len1 <= 1.0e-12 || len2 <= 1.0e-12 { return nil }
        let dot = max(-1.0, min(1.0, v1.dot(v2) / (len1 * len2)))
        return acos(dot) * 180.0 / Double.pi
    }

    for item in deduped {
        stack.append(item)
        var didRemove = true
        while didRemove, stack.count >= 3 {
            didRemove = false
            let c = stack[stack.count - 1]
            let b = stack[stack.count - 2]
            let a = stack[stack.count - 3]
            let span = a.point - c.point
            let ab = a.point - b.point
            let bc = b.point - c.point
            let spanSq = span.dot(span)
            let abSq = ab.dot(ab)
            let bcSq = bc.dot(bc)
            guard spanSq <= hairpinSpanTol * hairpinSpanTol else { continue }
            guard abSq <= edgeTolSquared, bcSq <= edgeTolSquared else { continue }
            guard let angle = angleDegrees(a: a.point, b: b.point, c: c.point) else { continue }
            if angle >= hairpinAngleDeg {
                stack.remove(at: stack.count - 2)
                droppedHairpin += 1
                if droppedHairpinIndices.count < 6 {
                    droppedHairpinIndices.append(b.index)
                }
                didRemove = true
            }
        }
    }

    let uniqueCount = stack.count
    guard uniqueCount >= 3 else {
        return (ring, RingSanitizeStats(droppedDuplicates: droppedDup, droppedHairpins: droppedHairpin, droppedHairpinIndices: droppedHairpinIndices))
    }

    var cleaned = stack.map { $0.point }
    if isClosed {
        if let first = cleaned.first {
            cleaned.append(first)
        }
    }
    return (
        cleaned,
        RingSanitizeStats(
            droppedDuplicates: droppedDup,
            droppedHairpins: droppedHairpin,
            droppedHairpinIndices: droppedHairpinIndices
        )
    )
}
