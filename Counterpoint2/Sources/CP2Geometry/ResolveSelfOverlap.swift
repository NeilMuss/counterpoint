import Foundation

public struct ResolveSelfOverlapResult: Equatable {
    public let ring: [Vec2]
    public let intersections: [Vec2]
    public let faces: Int
    public let insideFaces: Int
    public let success: Bool
    public let failureReason: String?

    public init(
        ring: [Vec2],
        intersections: [Vec2],
        faces: Int,
        insideFaces: Int,
        success: Bool,
        failureReason: String?
    ) {
        self.ring = ring
        self.intersections = intersections
        self.faces = faces
        self.insideFaces = insideFaces
        self.success = success
        self.failureReason = failureReason
    }
}

private func signedArea(_ ring: [Vec2]) -> Double {
    guard ring.count >= 3 else { return 0.0 }
    var area = 0.0
    for i in 0..<(ring.count - 1) {
        let a = ring[i]
        let b = ring[i + 1]
        area += (a.x * b.y - b.x * a.y)
    }
    return area * 0.5
}

private struct SegmentRef {
    let index: Int
    let a: Vec2
    let b: Vec2
}

private struct SplitPoint {
    let t: Double
    let point: Vec2
}

private struct Node {
    let key: SnapKey
    let pos: Vec2
}

private struct HalfEdge {
    let from: Int
    let to: Int
    let angle: Double
    var twin: Int
    var face: Int
}

private func segmentIntersection(_ a: Vec2, _ b: Vec2, _ c: Vec2, _ d: Vec2, eps: Double) -> (t: Double, u: Double, point: Vec2)? {
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

private func windingNumber(point: Vec2, ring: [Vec2]) -> Int {
    guard ring.count >= 3 else { return 0 }
    var winding = 0
    for i in 0..<(ring.count - 1) {
        let a = ring[i]
        let b = ring[i + 1]
        if a.y <= point.y {
            if b.y > point.y {
                let isLeft = (b.x - a.x) * (point.y - a.y) - (point.x - a.x) * (b.y - a.y)
                if isLeft > 0 { winding += 1 }
            }
        } else {
            if b.y <= point.y {
                let isLeft = (b.x - a.x) * (point.y - a.y) - (point.x - a.x) * (b.y - a.y)
                if isLeft < 0 { winding -= 1 }
            }
        }
    }
    return winding
}

public func resolveSelfOverlap(ring input: [Vec2], eps: Double) -> ResolveSelfOverlapResult {
    let debugLog = true
    guard input.count >= 4 else {
        return ResolveSelfOverlapResult(ring: input, intersections: [], faces: 0, insideFaces: 0, success: false, failureReason: "ringTooSmall")
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

    if debugLog {
        print(String(format: "RESOLVE_SELF_OVERLAP_DIAG segments=%d intersections=%d", segCount, intersections.count))
    }

    var nodes: [Node] = []
    var nodeIndex: [SnapKey: Int] = [:]
    func nodeFor(_ p: Vec2) -> Int {
        let key = Epsilon.snapKey(p, eps: eps)
        if let idx = nodeIndex[key] { return idx }
        let idx = nodes.count
        nodeIndex[key] = idx
        nodes.append(Node(key: key, pos: p))
        return idx
    }

    var undirectedEdges: [(Int, Int)] = []
    var splitCounts: [Int] = []
    splitCounts.reserveCapacity(segCount)
    struct EdgeKey: Hashable {
        let a: Int
        let b: Int
        init(_ u: Int, _ v: Int) {
            if u <= v { a = u; b = v } else { a = v; b = u }
        }
    }
    var edgeSet: Set<EdgeKey> = []
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
                let a = nodeFor(last.point)
                let b = nodeFor(part.point)
                if a != b {
                    let key = EdgeKey(a, b)
                    if !edgeSet.contains(key) {
                        edgeSet.insert(key)
                        undirectedEdges.append((a, b))
                    }
                }
            }
            splitCount += 1
            last = part
        }
        splitCounts.append(splitCount)
    }

    if debugLog {
        let minSplit = splitCounts.min() ?? 0
        let maxSplit = splitCounts.max() ?? 0
        let avgSplit = splitCounts.isEmpty ? 0.0 : Double(splitCounts.reduce(0, +)) / Double(splitCounts.count)
        print(String(format: "RESOLVE_SELF_OVERLAP_DIAG splitPoints min=%.1f avg=%.2f max=%.1f", Double(minSplit), avgSplit, Double(maxSplit)))
        print(String(format: "RESOLVE_SELF_OVERLAP_DIAG splitVerts=%d splitEdges=%d", nodes.count, undirectedEdges.count))
    }

    if undirectedEdges.isEmpty {
        return ResolveSelfOverlapResult(ring: ring, intersections: intersections, faces: 0, insideFaces: 0, success: false, failureReason: "noEdges")
    }

    var halfEdges: [HalfEdge] = []
    halfEdges.reserveCapacity(undirectedEdges.count * 2)
    var outgoing: [[Int]] = Array(repeating: [], count: nodes.count)
    for (a, b) in undirectedEdges {
        let pa = nodes[a].pos
        let pb = nodes[b].pos
        let angleAB = atan2(pb.y - pa.y, pb.x - pa.x)
        let angleBA = atan2(pa.y - pb.y, pa.x - pb.x)
        let idxAB = halfEdges.count
        let idxBA = idxAB + 1
        halfEdges.append(HalfEdge(from: a, to: b, angle: angleAB, twin: idxBA, face: -1))
        halfEdges.append(HalfEdge(from: b, to: a, angle: angleBA, twin: idxAB, face: -1))
        outgoing[a].append(idxAB)
        outgoing[b].append(idxBA)
    }

    for i in 0..<outgoing.count {
        outgoing[i].sort {
            let la = halfEdges[$0]
            let lb = halfEdges[$1]
            if la.angle != lb.angle { return la.angle < lb.angle }
            if la.to != lb.to { return la.to < lb.to }
            return $0 < $1
        }
    }
    var outgoingIndex: [[Int: Int]] = Array(repeating: [:], count: nodes.count)
    for v in 0..<outgoing.count {
        var map: [Int: Int] = [:]
        for (idx, edgeId) in outgoing[v].enumerated() {
            map[edgeId] = idx
        }
        outgoingIndex[v] = map
    }

    if debugLog {
        var minDeg = Int.max
        var maxDeg = 0
        var sumDeg = 0
        var lowDeg = 0
        for edgesAt in outgoing {
            let deg = edgesAt.count
            minDeg = min(minDeg, deg)
            maxDeg = max(maxDeg, deg)
            sumDeg += deg
            if deg < 2 { lowDeg += 1 }
        }
        let avgDeg = outgoing.isEmpty ? 0.0 : Double(sumDeg) / Double(outgoing.count)
        print(String(format: "RESOLVE_SELF_OVERLAP_DIAG vertices=%d outDegree min=%d avg=%.2f max=%d deg<2=%d", outgoing.count, minDeg == Int.max ? 0 : minDeg, avgDeg, maxDeg, lowDeg))
    }

    func nextEdgeCCW(from edgeIndex: Int) -> Int? {
        let edge = halfEdges[edgeIndex]
        let v = edge.to
        let edgesAt = outgoing[v]
        guard !edgesAt.isEmpty else { return nil }
        let twin = halfEdges[edgeIndex].twin
        guard let twinIndex = outgoingIndex[v][twin] else { return nil }
        let nextIndex = (twinIndex + 1) % edgesAt.count
        return edgesAt[nextIndex]
    }

    var faces: [[Int]] = []
    var firstFailure: String? = nil
    var firstPath: [Int] = []
    var smallFaces = 0
    for i in 0..<halfEdges.count {
        if halfEdges[i].face != -1 { continue }
        var face: [Int] = []
        var path: [Int] = []
        var current = i
        var safety = 0
        while safety < halfEdges.count + 1 {
            safety += 1
            if path.contains(current) {
                if current != i {
                    if firstFailure == nil { firstFailure = "loopTooShort" }
                }
                break
            }
            if halfEdges[current].face != -1 { break }
            path.append(current)
            face.append(current)
            guard let next = nextEdgeCCW(from: current) else {
                if firstFailure == nil { firstFailure = "noNextEdgeAtVertex" }
                break
            }
            current = next
            if current == i { break }
        }
        if current == i && face.count >= 3 {
            let faceIndex = faces.count
            for edgeIndex in face {
                halfEdges[edgeIndex].face = faceIndex
            }
            faces.append(face)
        } else {
            for edgeIndex in face {
                halfEdges[edgeIndex].face = -1
            }
            if firstPath.isEmpty {
                firstPath = Array(path.prefix(10))
            }
            if face.count < 3 {
                smallFaces += 1
            }
        }
    }

    if faces.isEmpty {
        if debugLog {
            let reason = firstFailure ?? "visitedAllEdgesNoCycles"
            print(String(format: "RESOLVE_SELF_OVERLAP_DIAG faces=0 reason=%@", reason))
            if !firstPath.isEmpty {
                print("RESOLVE_SELF_OVERLAP_DIAG sampleWalk:")
                for edgeIndex in firstPath {
                    let edge = halfEdges[edgeIndex]
                    let a = nodes[edge.from].pos
                    let b = nodes[edge.to].pos
                    print(String(format: "  edge %d: (%.4f,%.4f)->(%.4f,%.4f)", edgeIndex, a.x, a.y, b.x, b.y))
                }
            }
        }
        return ResolveSelfOverlapResult(ring: ring, intersections: intersections, faces: 0, insideFaces: 0, success: false, failureReason: "noFaces")
    }

    if debugLog {
        let pairedTwins = halfEdges.filter { $0.twin >= 0 && $0.twin < halfEdges.count }.count
        let missingTwins = halfEdges.enumerated().filter { $0.element.twin < 0 || $0.element.twin >= halfEdges.count }
        print(String(format: "RESOLVE_SELF_OVERLAP_DIAG halfEdges=%d twinsPaired=%d faces=%d", halfEdges.count, pairedTwins, faces.count))
        print(String(format: "RESOLVE_SELF_OVERLAP_DIAG twinsUnpaired=%d faceHistogram small(<3)=%d ok=%d", missingTwins.count, smallFaces, faces.count))
        if !missingTwins.isEmpty {
            print(String(format: "RESOLVE_SELF_OVERLAP_DIAG missingTwins=%d", missingTwins.count))
            for (idx, edge) in missingTwins.prefix(10) {
                let a = nodes[edge.from].pos
                let b = nodes[edge.to].pos
                print(String(format: "  missingTwin edge=%d (%.4f,%.4f)->(%.4f,%.4f)", idx, a.x, a.y, b.x, b.y))
            }
        }
        print(String(format: "RESOLVE_SELF_OVERLAP_DIAG intersections=%d splitVerts=%d splitEdges=%d halfEdges=%d twinsPaired=%d faces=%d", intersections.count, nodes.count, undirectedEdges.count, halfEdges.count, pairedTwins, faces.count))
    }

    var faceInside: [Bool] = Array(repeating: false, count: faces.count)
    var facePolys: [[Vec2]] = Array(repeating: [], count: faces.count)
    var faceAreas: [Double] = Array(repeating: 0.0, count: faces.count)
    var insideCount = 0
    for (index, face) in faces.enumerated() {
        var poly: [Vec2] = []
        poly.reserveCapacity(face.count + 1)
        for edgeIndex in face {
            poly.append(nodes[halfEdges[edgeIndex].from].pos)
        }
        if poly.count >= 3 {
            poly.append(poly.first!)
            let area = signedArea(poly)
            faceAreas[index] = area
            facePolys[index] = poly
            let centroid = poly.dropLast().reduce(Vec2(0, 0)) { $0 + $1 } * (1.0 / Double(max(1, poly.count - 1)))
            let winding = windingNumber(point: centroid, ring: ring)
            if winding != 0 {
                faceInside[index] = true
                insideCount += 1
            }
        }
    }
    if debugLog {
        for (index, poly) in facePolys.enumerated() where !poly.isEmpty {
            let area = faceAreas[index]
            print(String(format: "FACE %d verts=%d area=%.6f absArea=%.6f", index, max(0, poly.count - 1), area, abs(area)))
        }
        let top = faceAreas.enumerated()
            .filter { !facePolys[$0.offset].isEmpty }
            .sorted { abs($0.element) > abs($1.element) }
            .prefix(3)
        var topText: [String] = []
        for entry in top {
            let idx = entry.offset
            let area = entry.element
            let verts = max(0, facePolys[idx].count - 1)
            let sign = area >= 0.0 ? "+" : "-"
            topText.append(String(format: "%d abs=%.3f verts=%d sign=%@", idx, abs(area), verts, sign))
        }
        if !topText.isEmpty {
            print("FACE_TOP " + topText.joined(separator: " | "))
        }
    }

    var boundaryEdges: [Int] = []
    for i in 0..<halfEdges.count {
        let f = halfEdges[i].face
        if f < 0 { continue }
        let twin = halfEdges[i].twin
        let fTwin = halfEdges[twin].face
        let inA = f >= 0 && faceInside[f]
        let inB = fTwin >= 0 && faceInside[fTwin]
        if inA != inB {
            if inA {
                boundaryEdges.append(i)
            }
        }
    }

    if boundaryEdges.isEmpty {
        return ResolveSelfOverlapResult(ring: ring, intersections: intersections, faces: faces.count, insideFaces: insideCount, success: false, failureReason: "noBoundary")
    }

    var boundaryOutgoing: [Int: [Int]] = [:]
    for edgeIndex in boundaryEdges {
        let from = halfEdges[edgeIndex].from
        boundaryOutgoing[from, default: []].append(edgeIndex)
    }

    var boundaryCycles: [[Vec2]] = []
    var visitedEdges: Set<Int> = []
    for edgeIndex in boundaryEdges {
        if visitedEdges.contains(edgeIndex) { continue }
        var cycle: [Vec2] = []
        var current = edgeIndex
        var safety = 0
        while safety < boundaryEdges.count + 2 {
            safety += 1
            if visitedEdges.contains(current) { break }
            visitedEdges.insert(current)
            let from = halfEdges[current].from
            let to = halfEdges[current].to
            cycle.append(nodes[from].pos)
            if let nextEdges = boundaryOutgoing[to], !nextEdges.isEmpty {
                let next = nextEdges[0]
                current = next
            } else {
                break
            }
        }
        if cycle.count >= 3 {
            cycle.append(cycle.first!)
            boundaryCycles.append(cycle)
        }
    }

    if boundaryCycles.isEmpty {
        return ResolveSelfOverlapResult(ring: ring, intersections: intersections, faces: faces.count, insideFaces: insideCount, success: false, failureReason: "noBoundaryCycles")
    }

    if debugLog {
        for (idx, cycle) in boundaryCycles.enumerated() {
            let area = abs(signedArea(cycle))
            print(String(format: "CAND %d verts=%d absArea=%.6f", idx, max(0, cycle.count - 1), area))
        }
    }

    let originalAbsArea = abs(signedArea(ring))
    var candidateCycles: [[Vec2]] = boundaryCycles
    if let bestFaceIndex = faceAreas.enumerated().filter({ !facePolys[$0.offset].isEmpty }).max(by: { abs($0.element) < abs($1.element) })?.offset {
        let faceCycle = facePolys[bestFaceIndex]
        if faceCycle.count >= 4 {
            candidateCycles = [faceCycle]
        }
    }
    var bestIndex = 0
    var bestArea = -Double.greatestFiniteMagnitude
    for (idx, cycle) in candidateCycles.enumerated() {
        let area = abs(signedArea(cycle))
        if area > bestArea {
            bestArea = area
            bestIndex = idx
        }
    }
    if debugLog {
        let bestVerts = candidateCycles[bestIndex].count
        print(String(format: "RESOLVE_SELF_OVERLAP_SELECT candidates=%d bestAbsArea=%.6f originalAbsArea=%.6f bestVerts=%d", candidateCycles.count, bestArea, originalAbsArea, bestVerts))
    }
    let minArea = originalAbsArea * 0.01
    if bestArea < minArea {
        if debugLog {
            print(String(format: "RESOLVE_SELF_OVERLAP_FALLBACK reason=areaTooSmall bestArea=%.6f originalAbsArea=%.6f", bestArea, originalAbsArea))
        }
        return ResolveSelfOverlapResult(ring: ring, intersections: intersections, faces: faces.count, insideFaces: insideCount, success: false, failureReason: "areaTooSmall")
    }
    var resolved = candidateCycles[bestIndex]
    if signedArea(resolved) < 0.0 {
        resolved = resolved.reversed()
    }
    let success = resolved.count >= 4
    return ResolveSelfOverlapResult(
        ring: resolved,
        intersections: intersections,
        faces: faces.count,
        insideFaces: insideCount,
        success: success,
        failureReason: success ? nil : "invalidResolved"
    )
}
