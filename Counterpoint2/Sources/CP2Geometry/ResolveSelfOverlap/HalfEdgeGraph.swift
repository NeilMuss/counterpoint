import Foundation

public struct HalfEdge: Equatable {
    public let id: Int
    public let from: Int
    public let to: Int
    public let angle: Double
    public let twinId: Int
}

public struct HalfEdgeGraph: Equatable {
    public let vertices: [PlanarVertex]
    public let edges: [PlanarEdge]
    public let halfEdges: [HalfEdge]
    public let outgoing: [[Int]]
    public let outgoingIndex: [[Int: Int]]
    public let twinsPaired: Int
    public let missingTwins: [Int]

    public init(vertices: [PlanarVertex], edges: [PlanarEdge]) {
        self.vertices = vertices
        self.edges = edges
        var halfEdges: [HalfEdge] = []
        halfEdges.reserveCapacity(edges.count * 2)
        var outgoing: [[Int]] = Array(repeating: [], count: vertices.count)
        for (edgeIndex, edge) in edges.enumerated() {
            let a = edge.u
            let b = edge.v
            let pa = vertices[a].pos
            let pb = vertices[b].pos
            let angleAB = atan2(pb.y - pa.y, pb.x - pa.x)
            let angleBA = atan2(pa.y - pb.y, pa.x - pb.x)
            let idxAB = halfEdges.count
            let idxBA = idxAB + 1
            halfEdges.append(HalfEdge(id: idxAB, from: a, to: b, angle: angleAB, twinId: idxBA))
            halfEdges.append(HalfEdge(id: idxBA, from: b, to: a, angle: angleBA, twinId: idxAB))
            outgoing[a].append(idxAB)
            outgoing[b].append(idxBA)
            _ = edgeIndex
        }
        for v in 0..<outgoing.count {
            outgoing[v].sort {
                let la = halfEdges[$0]
                let lb = halfEdges[$1]
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
        let missingTwins = halfEdges.enumerated().filter { $0.element.twinId < 0 || $0.element.twinId >= halfEdges.count }.map { $0.offset }
        self.halfEdges = halfEdges
        self.outgoing = outgoing
        self.outgoingIndex = outgoingIndex
        self.twinsPaired = halfEdges.count - missingTwins.count
        self.missingTwins = missingTwins
    }

    public func nextHalfEdgeKeepingLeftFace(from edgeId: Int) -> Int? {
        let edge = halfEdges[edgeId]
        let v = edge.to
        let edgesAt = outgoing[v]
        guard !edgesAt.isEmpty else { return nil }
        let twin = edge.twinId
        guard let twinIndex = outgoingIndex[v][twin] else { return nil }
        let nextIndex = (twinIndex + 1) % edgesAt.count
        let nextId = edgesAt[nextIndex]
        if nextId == twin { return nil }
        return nextId
    }
}
