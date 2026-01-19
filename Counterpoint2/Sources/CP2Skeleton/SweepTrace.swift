import Foundation
import CP2Geometry

public struct Segment2: Equatable, Codable {
    public let a: Vec2
    public let b: Vec2

    public init(_ a: Vec2, _ b: Vec2) {
        self.a = a
        self.b = b
    }
}

public func boundarySoup(
    path: SkeletonPath,
    width: Double,
    height: Double,
    effectiveAngle: Double,
    sampleCount: Int
) -> [Segment2] {
    let count = max(2, sampleCount)
    let arclen = ArcLengthParameterization(path: path)
    let tableU = arclen.uTable()
    let tableP = arclen.sampleTable()
    let tableCount = max(2, tableU.count)
    var left: [Vec2] = []
    var right: [Vec2] = []
    left.reserveCapacity(count)
    right.reserveCapacity(count)

    for i in 0..<count {
        let t = Double(i) / Double(count - 1)
        let tableIndex = Int(round(t * Double(tableCount - 1)))
        let u = tableU[tableIndex]
        let point = tableP[tableIndex]
        let tangent = path.tangent(u).normalized()
        let normal = Vec2(-tangent.y, tangent.x)
        let corners = rectangleCorners(
            center: point,
            tangent: tangent,
            normal: normal,
            width: width,
            height: height,
            effectiveAngle: effectiveAngle
        )
        var minDot = Double.greatestFiniteMagnitude
        var maxDot = -Double.greatestFiniteMagnitude
        var leftPoint = point
        var rightPoint = point
        for corner in corners {
            let d = corner.dot(normal)
            if d < minDot {
                minDot = d
                leftPoint = corner
            }
            if d > maxDot {
                maxDot = d
                rightPoint = corner
            }
        }
        left.append(leftPoint)
        right.append(rightPoint)
    }

    var segments: [Segment2] = []
    segments.reserveCapacity(count * 2 + 2)
    for i in 0..<(count - 1) {
        segments.append(Segment2(left[i], left[i + 1]))
        segments.append(Segment2(right[i], right[i + 1]))
    }
    segments.append(Segment2(left[0], right[0]))
    segments.append(Segment2(right[count - 1], left[count - 1]))
    return segments
}

private func rectangleCorners(
    center: Vec2,
    tangent: Vec2,
    normal: Vec2,
    width: Double,
    height: Double,
    effectiveAngle: Double
) -> [Vec2] {
    let halfW = width * 0.5
    let halfH = height * 0.5
    let localCorners: [Vec2] = [
        Vec2(-halfW, -halfH),
        Vec2(halfW, -halfH),
        Vec2(halfW, halfH),
        Vec2(-halfW, halfH)
    ]
    let cosA = cos(effectiveAngle)
    let sinA = sin(effectiveAngle)
    return localCorners.map { corner in
        let rotated = Vec2(
            corner.x * cosA - corner.y * sinA,
            corner.x * sinA + corner.y * cosA
        )
        let world = tangent * rotated.y + normal * rotated.x
        return center + world
    }
}

public func traceLoops(segments: [Segment2], eps: Double) -> [[Vec2]] {
    guard !segments.isEmpty else { return [] }

    var pointForKey: [SnapKey: Vec2] = [:]
    var adjacency: [SnapKey: [SnapKey]] = [:]
    var edges: Set<EdgeKey> = []

    for seg in segments {
        let aKey = Epsilon.snapKey(seg.a, eps: eps)
        let bKey = Epsilon.snapKey(seg.b, eps: eps)
        pointForKey[aKey] = pointForKey[aKey] ?? seg.a
        pointForKey[bKey] = pointForKey[bKey] ?? seg.b
        adjacency[aKey, default: []].append(bKey)
        adjacency[bKey, default: []].append(aKey)
        edges.insert(EdgeKey(aKey, bKey))
    }

    for (key, list) in adjacency {
        adjacency[key] = list.sorted(by: snapKeyLess)
    }

    var rings: [[SnapKey]] = []
    while let startEdge = edges.sorted(by: edgeLess).first {
        edges.remove(startEdge)
        let start = startEdge.a
        let next = startEdge.b
        var ring: [SnapKey] = [start, next]
        var prev = start
        var curr = next
        while curr != start {
            guard let neighbors = adjacency[curr] else { break }
            var candidates = neighbors.filter { edges.contains(EdgeKey(curr, $0)) }
            if candidates.count > 1 {
                let nonPrev = candidates.filter { $0 != prev }
                candidates = nonPrev.isEmpty ? candidates : nonPrev
            }
            guard let chosen = candidates.sorted(by: snapKeyLess).first else { break }
            edges.remove(EdgeKey(curr, chosen))
            ring.append(chosen)
            prev = curr
            curr = chosen
        }
        if ring.first != ring.last {
            ring.append(ring.first!)
        }
        rings.append(ring)
    }

    let worldRings = rings.map { ringKeys in
        ringKeys.compactMap { pointForKey[$0] }
    }.map(dedupRing)
    return worldRings.filter { $0.count >= 4 }
}

public func signedArea(_ ring: [Vec2]) -> Double {
    guard ring.count >= 3 else { return 0.0 }
    var area = 0.0
    for i in 0..<(ring.count - 1) {
        let a = ring[i]
        let b = ring[i + 1]
        area += (a.x * b.y - b.x * a.y)
    }
    return area * 0.5
}

private struct EdgeKey: Hashable {
    let a: SnapKey
    let b: SnapKey

    init(_ p0: SnapKey, _ p1: SnapKey) {
        if snapKeyLess(p0, p1) {
            a = p0
            b = p1
        } else {
            a = p1
            b = p0
        }
    }
}

private func snapKeyLess(_ a: SnapKey, _ b: SnapKey) -> Bool {
    if a.x != b.x { return a.x < b.x }
    return a.y < b.y
}

private func edgeLess(_ a: EdgeKey, _ b: EdgeKey) -> Bool {
    if snapKeyLess(a.a, b.a) { return true }
    if snapKeyLess(b.a, a.a) { return false }
    return snapKeyLess(a.b, b.b)
}

private func dedupRing(_ ring: [Vec2]) -> [Vec2] {
    guard !ring.isEmpty else { return [] }
    var result: [Vec2] = [ring[0]]
    for point in ring.dropFirst() where !Epsilon.approxEqual(point, result.last!) {
        result.append(point)
    }
    if let first = result.first, let last = result.last, !Epsilon.approxEqual(first, last) {
        result.append(first)
    }
    return result
}
