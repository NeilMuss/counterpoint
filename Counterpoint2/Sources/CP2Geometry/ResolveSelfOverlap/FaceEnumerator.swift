import Foundation

public struct FaceCycle: Equatable {
    public let halfEdgeIds: [Int]
    public let vertexIds: [Int]
    public let signedArea: Double
    public let absArea: Double
}

public struct FaceEnumerationResult: Equatable {
    public let faces: [FaceCycle]
    public let smallFaceCount: Int
}

public enum FaceEnumerator {
    public static func enumerate(graph: HalfEdgeGraph) -> FaceEnumerationResult {
        var faceIdForEdge: [Int: Int] = [:]
        var faces: [FaceCycle] = []
        var smallFaces = 0

        for edge in graph.halfEdges {
            if faceIdForEdge[edge.id] != nil { continue }
            var cycle: [Int] = []
            var verts: [Int] = []
            var current = edge.id
            var safety = 0
            var visited: Set<Int> = []
            while safety < graph.halfEdges.count + 2 {
                safety += 1
                if visited.contains(current) {
                    break
                }
                visited.insert(current)
                cycle.append(current)
                verts.append(graph.halfEdges[current].from)
                guard let next = graph.nextHalfEdgeKeepingLeftFace(from: current) else {
                    break
                }
                current = next
                if current == edge.id { break }
            }
            if current == edge.id, verts.count >= 3 {
                let area = signedAreaForVertices(verts, graph: graph)
                let face = FaceCycle(halfEdgeIds: cycle, vertexIds: verts, signedArea: area, absArea: abs(area))
                let faceIndex = faces.count
                faces.append(face)
                for edgeId in cycle {
                    faceIdForEdge[edgeId] = faceIndex
                }
            } else {
                if verts.count < 3 { smallFaces += 1 }
            }
        }
        return FaceEnumerationResult(faces: faces, smallFaceCount: smallFaces)
    }

    private static func signedAreaForVertices(_ verts: [Int], graph: HalfEdgeGraph) -> Double {
        guard verts.count >= 3 else { return 0.0 }
        var area = 0.0
        for i in 0..<verts.count {
            let a = graph.vertices[verts[i]].pos
            let b = graph.vertices[verts[(i + 1) % verts.count]].pos
            area += (a.x * b.y - b.x * a.y)
        }
        return area * 0.5
    }
}
