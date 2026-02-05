import Foundation
import CP2Domain

public struct PlanarizerDebugPayload: DebugPayload, Equatable, Sendable {
    public static let kind = "ResolveOverlap.Planarizer"
    public let segments: Int
    public let intersections: Int
    public let splitMin: Int
    public let splitMax: Int
    public let splitAvg: Double
    public let splitVerts: Int
    public let splitEdges: Int
    public let droppedZeroLength: Int

    public init(segments: Int, intersections: Int, splitMin: Int, splitMax: Int, splitAvg: Double, splitVerts: Int, splitEdges: Int, droppedZeroLength: Int) {
        self.segments = segments
        self.intersections = intersections
        self.splitMin = splitMin
        self.splitMax = splitMax
        self.splitAvg = splitAvg
        self.splitVerts = splitVerts
        self.splitEdges = splitEdges
        self.droppedZeroLength = droppedZeroLength
    }
}

public struct GraphDebugPayload: DebugPayload, Equatable, Sendable {
    public static let kind = "ResolveOverlap.Graph"
    public let vertices: Int
    public let halfEdges: Int
    public let twinsPaired: Int
    public let faces: Int

    public init(vertices: Int, halfEdges: Int, twinsPaired: Int, faces: Int) {
        self.vertices = vertices
        self.halfEdges = halfEdges
        self.twinsPaired = twinsPaired
        self.faces = faces
    }
}

public struct FaceEnumDebugPayload: DebugPayload, Equatable, Sendable {
    public static let kind = "ResolveOverlap.FaceEnum"
    public let faces: Int
    public let smallFaces: Int
    public let topAbsAreas: [Double]

    public init(faces: Int, smallFaces: Int, topAbsAreas: [Double]) {
        self.faces = faces
        self.smallFaces = smallFaces
        self.topAbsAreas = topAbsAreas
    }
}

public struct SelectionDebugPayload: DebugPayload, Equatable, Sendable {
    public static let kind = "ResolveOverlap.Selection"
    public let candidates: Int
    public let selectedFaceId: Int
    public let selectedAbsArea: Double
    public let rejectedCount: Int
    public let failureReason: String?

    public init(candidates: Int, selectedFaceId: Int, selectedAbsArea: Double, rejectedCount: Int, failureReason: String?) {
        self.candidates = candidates
        self.selectedFaceId = selectedFaceId
        self.selectedAbsArea = selectedAbsArea
        self.rejectedCount = rejectedCount
        self.failureReason = failureReason
    }
}
