import Foundation
import CP2Domain
import CP2Geometry

public struct SegmentRef: Codable, Equatable, Sendable {
    public let a: Int
    public let b: Int
    public init(a: Int, b: Int) {
        self.a = a
        self.b = b
    }
}

public struct PlanarizedSegmentsArtifact: Codable, Equatable, Sendable, InvariantCheckable {
    public let id: ArtifactID
    public let policy: DeterminismPolicy
    public let sourceRingId: ArtifactID
    public let vertices: [Vec2]
    public let segments: [SegmentRef]
    public let debug: DebugBundle?

    public init(id: ArtifactID, policy: DeterminismPolicy, sourceRingId: ArtifactID, vertices: [Vec2], segments: [SegmentRef], debug: DebugBundle? = nil) {
        self.id = id
        self.policy = policy
        self.sourceRingId = sourceRingId
        self.vertices = vertices
        self.segments = segments
        self.debug = debug
    }

    public func validate() throws {
        if vertices.count < 2 {
            throw CP2InvariantError("planarized vertices must be >= 2")
        }
        if segments.isEmpty {
            throw CP2InvariantError("planarized segments must be non-empty")
        }
        for (idx, v) in vertices.enumerated() {
            if !v.x.isFinite || !v.y.isFinite {
                throw CP2InvariantError("planarized vertex must be finite", context: "index=\(idx)")
            }
        }
        for (idx, s) in segments.enumerated() {
            if s.a == s.b {
                throw CP2InvariantError("segment endpoints must be distinct", context: "segment=\(idx)")
            }
            if s.a < 0 || s.a >= vertices.count || s.b < 0 || s.b >= vertices.count {
                throw CP2InvariantError("segment indices out of range", context: "segment=\(idx)")
            }
        }
    }
}

public struct HalfEdge: Codable, Equatable, Sendable {
    public let origin: Int
    public let twin: Int
    public let next: Int
    public let prev: Int
    public let face: Int

    public init(origin: Int, twin: Int, next: Int, prev: Int, face: Int) {
        self.origin = origin
        self.twin = twin
        self.next = next
        self.prev = prev
        self.face = face
    }
}

public struct FaceRecord: Codable, Equatable, Sendable {
    public let anyHalfEdge: Int
    public init(anyHalfEdge: Int) {
        self.anyHalfEdge = anyHalfEdge
    }
}

public struct HalfEdgeGraphArtifact: Codable, Equatable, Sendable, InvariantCheckable {
    public let id: ArtifactID
    public let policy: DeterminismPolicy
    public let planarId: ArtifactID
    public let vertices: [Vec2]
    public let halfEdges: [HalfEdge]
    public let faces: [FaceRecord]
    public let debug: DebugBundle?

    public init(id: ArtifactID, policy: DeterminismPolicy, planarId: ArtifactID, vertices: [Vec2], halfEdges: [HalfEdge], faces: [FaceRecord], debug: DebugBundle? = nil) {
        self.id = id
        self.policy = policy
        self.planarId = planarId
        self.vertices = vertices
        self.halfEdges = halfEdges
        self.faces = faces
        self.debug = debug
    }

    public func validate() throws {
        if halfEdges.isEmpty {
            throw CP2InvariantError("halfEdges must be non-empty")
        }
        if halfEdges.count % 2 != 0 {
            throw CP2InvariantError("halfEdges count must be even")
        }
        for (idx, he) in halfEdges.enumerated() {
            if he.origin < 0 || he.origin >= vertices.count {
                throw CP2InvariantError("halfEdge origin out of range", context: "edge=\(idx)")
            }
            if he.twin < 0 || he.twin >= halfEdges.count {
                throw CP2InvariantError("halfEdge twin out of range", context: "edge=\(idx)")
            }
            if he.next < 0 || he.next >= halfEdges.count {
                throw CP2InvariantError("halfEdge next out of range", context: "edge=\(idx)")
            }
            if he.prev < 0 || he.prev >= halfEdges.count {
                throw CP2InvariantError("halfEdge prev out of range", context: "edge=\(idx)")
            }
            let twin = halfEdges[he.twin]
            if twin.twin != idx {
                throw CP2InvariantError("halfEdge twin mismatch", context: "edge=\(idx)")
            }
            if halfEdges[he.next].prev != idx {
                throw CP2InvariantError("halfEdge next/prev mismatch", context: "edge=\(idx)")
            }
            if halfEdges[he.prev].next != idx {
                throw CP2InvariantError("halfEdge prev/next mismatch", context: "edge=\(idx)")
            }
        }
        for (idx, face) in faces.enumerated() {
            if face.anyHalfEdge < 0 || face.anyHalfEdge >= halfEdges.count {
                throw CP2InvariantError("face anyHalfEdge out of range", context: "face=\(idx)")
            }
        }
    }
}

public struct FaceLoop: Codable, Equatable, Sendable, InvariantCheckable {
    public let faceId: Int
    public let boundary: [Vec2]
    public let area: Double
    public let winding: RingWinding
    public let halfEdgeCycle: [Int]

    public init(faceId: Int, boundary: [Vec2], area: Double, winding: RingWinding, halfEdgeCycle: [Int]) {
        self.faceId = faceId
        self.boundary = boundary
        self.area = area
        self.winding = winding
        self.halfEdgeCycle = halfEdgeCycle
    }

    public func validate() throws {
        if boundary.count < 4 {
            throw CP2InvariantError("face boundary must have >= 4 points (including closure)", context: "face=\(faceId)")
        }
        if !Epsilon.approxEqual(boundary.first ?? Vec2(0, 0), boundary.last ?? Vec2(0, 0)) {
            throw CP2InvariantError("face boundary must be closed", context: "face=\(faceId)")
        }
        if abs(area) <= 1.0e-9 {
            throw CP2InvariantError("face area must be non-zero", context: "face=\(faceId)")
        }
        if halfEdgeCycle.isEmpty {
            throw CP2InvariantError("face halfEdgeCycle must be non-empty", context: "face=\(faceId)")
        }
    }
}

public struct FaceSetArtifact: Codable, Equatable, Sendable, InvariantCheckable {
    public let id: ArtifactID
    public let policy: DeterminismPolicy
    public let graphId: ArtifactID
    public let faces: [FaceLoop]
    public let debug: DebugBundle?

    public init(id: ArtifactID, policy: DeterminismPolicy, graphId: ArtifactID, faces: [FaceLoop], debug: DebugBundle? = nil) {
        self.id = id
        self.policy = policy
        self.graphId = graphId
        self.faces = faces
        self.debug = debug
    }

    public func validate() throws {
        for face in faces {
            try face.validate()
        }
    }
}

public struct SelectionResultArtifact: Codable, Equatable, Sendable, InvariantCheckable {
    public let id: ArtifactID
    public let policy: DeterminismPolicy
    public let faceSetId: ArtifactID
    public let selectedFaceId: Int
    public let selectedRing: Ring
    public let rejectedFaceIds: [Int]
    public let debug: DebugBundle?

    public init(id: ArtifactID, policy: DeterminismPolicy, faceSetId: ArtifactID, selectedFaceId: Int, selectedRing: Ring, rejectedFaceIds: [Int], debug: DebugBundle? = nil) {
        self.id = id
        self.policy = policy
        self.faceSetId = faceSetId
        self.selectedFaceId = selectedFaceId
        self.selectedRing = selectedRing
        self.rejectedFaceIds = rejectedFaceIds
        self.debug = debug
    }

    public func validate() throws {
        if selectedRing.points.count < 4 {
            throw CP2InvariantError("selected ring must have >= 4 points including closure", context: "face=\(selectedFaceId)")
        }
        if !Epsilon.approxEqual(selectedRing.points.first ?? Vec2(0, 0), selectedRing.points.last ?? Vec2(0, 0), eps: policy.eps) {
            throw CP2InvariantError("selected ring must be closed within eps", context: "face=\(selectedFaceId)")
        }
        if abs(selectedRing.area) <= policy.eps {
            throw CP2InvariantError("selected ring must have non-zero area", context: "face=\(selectedFaceId)")
        }
    }
}
