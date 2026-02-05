import Foundation
import CP2Domain
import CP2Geometry

public struct HalfEdgeGraphIndex: Equatable, Sendable {
    public let vertices: [Vec2]
    public let halfEdges: [HalfEdge]
}

public enum HalfEdgeGraphBuilder {
    private struct HalfEdgeInternal {
        let origin: Int
        let to: Int
        let twin: Int
        let angle: Double
    }

    public static func build(planar: PlanarizedSegmentsArtifact, includeDebug: Bool) -> (artifact: HalfEdgeGraphArtifact, index: HalfEdgeGraphIndex) {
        let vertices = planar.vertices
        let edges = planar.segments
        var halfEdgesInternal: [HalfEdgeInternal] = []
        halfEdgesInternal.reserveCapacity(edges.count * 2)
        var outgoing: [[Int]] = Array(repeating: [], count: vertices.count)

        for edge in edges {
            let a = edge.a
            let b = edge.b
            let pa = vertices[a]
            let pb = vertices[b]
            let angleAB = atan2(pb.y - pa.y, pb.x - pa.x)
            let angleBA = atan2(pa.y - pb.y, pa.x - pb.x)
            let idxAB = halfEdgesInternal.count
            let idxBA = idxAB + 1
            halfEdgesInternal.append(HalfEdgeInternal(origin: a, to: b, twin: idxBA, angle: angleAB))
            halfEdgesInternal.append(HalfEdgeInternal(origin: b, to: a, twin: idxAB, angle: angleBA))
            outgoing[a].append(idxAB)
            outgoing[b].append(idxBA)
        }

        for v in 0..<outgoing.count {
            outgoing[v].sort {
                let la = halfEdgesInternal[$0]
                let lb = halfEdgesInternal[$1]
                if la.angle != lb.angle { return la.angle < lb.angle }
                if la.to != lb.to { return la.to < lb.to }
                return $0 < $1
            }
        }

        var outgoingIndex: [[Int: Int]] = Array(repeating: [:], count: vertices.count)
        for v in 0..<outgoing.count {
            var map: [Int: Int] = [:]
            for (idx, edgeId) in outgoing[v].enumerated() {
                map[edgeId] = idx
            }
            outgoingIndex[v] = map
        }

        var next: [Int] = Array(repeating: -1, count: halfEdgesInternal.count)
        for (edgeId, edge) in halfEdgesInternal.enumerated() {
            let v = edge.to
            let edgesAt = outgoing[v]
            guard !edgesAt.isEmpty else { continue }
            let twin = edge.twin
            guard let twinIndex = outgoingIndex[v][twin] else { continue }
            let nextIndex = (twinIndex + 1) % edgesAt.count
            let nextId = edgesAt[nextIndex]
            next[edgeId] = nextId
        }

        var prev: [Int] = Array(repeating: -1, count: halfEdgesInternal.count)
        for (edgeId, nextId) in next.enumerated() {
            if nextId >= 0 && nextId < prev.count {
                prev[nextId] = edgeId
            }
        }

        var halfEdges: [HalfEdge] = []
        halfEdges.reserveCapacity(halfEdgesInternal.count)
        for (idx, edge) in halfEdgesInternal.enumerated() {
            let nextId = next[idx]
            let prevId = prev[idx]
            halfEdges.append(HalfEdge(origin: edge.origin, twin: edge.twin, next: nextId, prev: prevId, face: -1))
        }

        var debug: DebugBundle? = nil
        if includeDebug {
            var bundle = DebugBundle()
            let payload = GraphDebugPayload(
                vertices: vertices.count,
                halfEdges: halfEdges.count,
                twinsPaired: halfEdges.count,
                faces: 0
            )
            try? bundle.add(payload)
            debug = bundle
        }

        let artifact = HalfEdgeGraphArtifact(
            id: ArtifactID("halfEdgeGraph"),
            policy: planar.policy,
            planarId: planar.id,
            vertices: vertices,
            halfEdges: halfEdges,
            faces: [],
            debug: debug
        )

        let index = HalfEdgeGraphIndex(vertices: vertices, halfEdges: halfEdges)
        return (artifact, index)
    }
}
