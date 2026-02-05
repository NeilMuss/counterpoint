import Foundation

public struct PlanarVertex: Equatable {
    public let key: SnapKey
    public let pos: Vec2
}

public struct PlanarEdge: Equatable {
    public let u: Int
    public let v: Int
}

public struct SegmentPlanarizerStats: Equatable {
    public let segments: Int
    public let intersections: Int
    public let splitMin: Int
    public let splitMax: Int
    public let splitAvg: Double
    public let splitVerts: Int
    public let splitEdges: Int
    public let droppedZeroLength: Int
}

public struct SegmentPlanarizerResult: Equatable {
    public let vertices: [PlanarVertex]
    public let edges: [PlanarEdge]
    public let intersections: [Vec2]
    public let stats: SegmentPlanarizerStats
}

public enum SegmentPlanarizer {
    private struct SegmentRef {
        let index: Int
        let a: Vec2
        let b: Vec2
    }

    private struct SplitPoint {
        let t: Double
        let point: Vec2
    }

    private struct EdgeKey: Hashable {
        let a: Int
        let b: Int
        init(_ u: Int, _ v: Int) {
            if u <= v { a = u; b = v } else { a = v; b = u }
        }
    }

    private static func segmentIntersection(_ a: Vec2, _ b: Vec2, _ c: Vec2, _ d: Vec2, eps: Double) -> (t: Double, u: Double, point: Vec2)? {
        let r = b - a
        let s = d - c
        let denom = r.x * s.y - r.y * s.x
        if abs(denom) <= eps { return nil }
        let ac = c - a
        let t = (ac.x * s.y - ac.y * s.x) / denom
        let u = (ac.x * r.y - ac.y * r.x) / denom
        if t < -eps || t > 1.0 + eps || u < -eps || u > 1.0 + eps { return nil }
        let p = Vec2(a.x + r.x * t, a.y + r.y * t)
        return (t, u, p)
    }

    public static func planarize(ring input: [Vec2], eps: Double) -> SegmentPlanarizerResult {
        guard input.count >= 4 else {
            return SegmentPlanarizerResult(
                vertices: [],
                edges: [],
                intersections: [],
                stats: SegmentPlanarizerStats(segments: max(0, input.count - 1), intersections: 0, splitMin: 0, splitMax: 0, splitAvg: 0.0, splitVerts: 0, splitEdges: 0, droppedZeroLength: 0)
            )
        }
        var ring = input
        if !Epsilon.approxEqual(ring.first!, ring.last!) {
            ring.append(ring.first!)
        }

        let segCount = ring.count - 1
        var segments: [SegmentRef] = []
        segments.reserveCapacity(segCount)
        for i in 0..<segCount {
            segments.append(SegmentRef(index: i, a: ring[i], b: ring[i + 1]))
        }

        var splitPoints: [[SplitPoint]] = Array(repeating: [], count: segCount)
        for i in 0..<segCount {
            splitPoints[i].append(SplitPoint(t: 0.0, point: segments[i].a))
            splitPoints[i].append(SplitPoint(t: 1.0, point: segments[i].b))
        }

        var intersections: [Vec2] = []
        for i in 0..<segCount {
            for j in (i + 1)..<segCount {
                if j == i || j == i + 1 { continue }
                if i == 0 && j == segCount - 1 { continue }
                let si = segments[i]
                let sj = segments[j]
                guard let hit = segmentIntersection(si.a, si.b, sj.a, sj.b, eps: eps) else { continue }
                let t = max(0.0, min(1.0, hit.t))
                let u = max(0.0, min(1.0, hit.u))
                if (abs(t) <= eps || abs(t - 1.0) <= eps) && (abs(u) <= eps || abs(u - 1.0) <= eps) {
                    continue
                }
                splitPoints[i].append(SplitPoint(t: t, point: hit.point))
                splitPoints[j].append(SplitPoint(t: u, point: hit.point))
                intersections.append(hit.point)
            }
        }

        var vertices: [PlanarVertex] = []
        var vertexIndex: [SnapKey: Int] = [:]
        func vertexFor(_ p: Vec2) -> Int {
            let key = Epsilon.snapKey(p, eps: eps)
            if let idx = vertexIndex[key] { return idx }
            let idx = vertices.count
            vertexIndex[key] = idx
            vertices.append(PlanarVertex(key: key, pos: p))
            return idx
        }

        var edges: [PlanarEdge] = []
        var edgeSet: Set<EdgeKey> = []
        var splitCounts: [Int] = []
        splitCounts.reserveCapacity(segCount)
        var droppedZeroLength = 0
        for i in 0..<segCount {
            let parts = splitPoints[i].sorted { lhs, rhs in
                if abs(lhs.t - rhs.t) > 1.0e-9 { return lhs.t < rhs.t }
                if lhs.point.x != rhs.point.x { return lhs.point.x < rhs.point.x }
                return lhs.point.y < rhs.point.y
            }
            var splitCount = 0
            var last: SplitPoint? = nil
            for part in parts {
                if let last = last, (part.point - last.point).length <= eps {
                    continue
                }
                if let last = last {
                    let a = vertexFor(last.point)
                    let b = vertexFor(part.point)
                    if a != b {
                        let key = EdgeKey(a, b)
                        if !edgeSet.contains(key) {
                            let len = (vertices[a].pos - vertices[b].pos).length
                            if len > eps {
                                edgeSet.insert(key)
                                edges.append(PlanarEdge(u: a, v: b))
                            } else {
                                droppedZeroLength += 1
                            }
                        }
                    }
                }
                splitCount += 1
                last = part
            }
            splitCounts.append(splitCount)
        }

        let minSplit = splitCounts.min() ?? 0
        let maxSplit = splitCounts.max() ?? 0
        let avgSplit = splitCounts.isEmpty ? 0.0 : Double(splitCounts.reduce(0, +)) / Double(splitCounts.count)
        let stats = SegmentPlanarizerStats(
            segments: segCount,
            intersections: intersections.count,
            splitMin: minSplit,
            splitMax: maxSplit,
            splitAvg: avgSplit,
            splitVerts: vertices.count,
            splitEdges: edges.count,
            droppedZeroLength: droppedZeroLength
        )

        return SegmentPlanarizerResult(vertices: vertices, edges: edges, intersections: intersections, stats: stats)
    }
}
