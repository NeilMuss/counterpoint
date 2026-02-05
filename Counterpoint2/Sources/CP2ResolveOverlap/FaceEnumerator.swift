import Foundation
import CP2Domain
import CP2Geometry

public struct FaceEnumerationResult: Equatable, Sendable {
    public let faceSet: FaceSetArtifact
    public let smallFaceCount: Int
}

public enum FaceEnumerator {
    public static func enumerate(graph: HalfEdgeGraphIndex, policy: DeterminismPolicy, graphId: ArtifactID, includeDebug: Bool) -> FaceEnumerationResult {
        var faceIdForEdge: [Int: Int] = [:]
        var faces: [FaceLoop] = []
        var smallFaces = 0
        let halfEdges = graph.halfEdges

        for edgeId in 0..<halfEdges.count {
            if faceIdForEdge[edgeId] != nil { continue }
            var cycle: [Int] = []
            var verts: [Int] = []
            var current = edgeId
            var safety = 0
            var visited: Set<Int> = []
            while safety < halfEdges.count + 2 {
                safety += 1
                if visited.contains(current) {
                    break
                }
                visited.insert(current)
                cycle.append(current)
                verts.append(halfEdges[current].origin)
                let next = halfEdges[current].next
                if next < 0 || next >= halfEdges.count {
                    break
                }
                current = next
                if current == edgeId { break }
            }
            if current == edgeId, verts.count >= 3 {
                let area = signedAreaForVertices(verts, vertices: graph.vertices)
                let winding: RingWinding = area >= 0.0 ? .ccw : .cw
                var boundary: [Vec2] = verts.map { graph.vertices[$0] }
                if let first = boundary.first { boundary.append(first) }
                let face = FaceLoop(faceId: faces.count, boundary: boundary, area: area, winding: winding, halfEdgeCycle: cycle)
                let faceIndex = faces.count
                faces.append(face)
                for edge in cycle {
                    faceIdForEdge[edge] = faceIndex
                }
            } else {
                if verts.count < 3 { smallFaces += 1 }
            }
        }

        var debug: DebugBundle? = nil
        if includeDebug {
            var bundle = DebugBundle()
            let top = faces.map { $0.area }.map { abs($0) }.sorted(by: >).prefix(3)
            let payload = FaceEnumDebugPayload(faces: faces.count, smallFaces: smallFaces, topAbsAreas: Array(top))
            try? bundle.add(payload)
            debug = bundle
        }

        let faceSet = FaceSetArtifact(
            id: ArtifactID("faceSet"),
            policy: policy,
            graphId: graphId,
            faces: faces,
            debug: debug
        )
        return FaceEnumerationResult(faceSet: faceSet, smallFaceCount: smallFaces)
    }

    private static func signedAreaForVertices(_ verts: [Int], vertices: [Vec2]) -> Double {
        guard verts.count >= 3 else { return 0.0 }
        var area = 0.0
        for i in 0..<verts.count {
            let a = vertices[verts[i]]
            let b = vertices[verts[(i + 1) % verts.count]]
            area += (a.x * b.y - b.x * a.y)
        }
        return area * 0.5
    }
}
