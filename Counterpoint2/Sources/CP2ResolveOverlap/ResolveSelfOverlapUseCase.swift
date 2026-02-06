import Foundation
import CP2Domain
import CP2Geometry

public struct ResolveSelfOverlapPipelineArtifacts: Equatable, Sendable {
    public let planar: PlanarizedSegmentsArtifact
    public let graph: HalfEdgeGraphArtifact
    public let faceSet: FaceSetArtifact
    public let selection: SelectionResultArtifact
    public let intersections: [Vec2]

    public init(planar: PlanarizedSegmentsArtifact, graph: HalfEdgeGraphArtifact, faceSet: FaceSetArtifact, selection: SelectionResultArtifact, intersections: [Vec2]) {
        self.planar = planar
        self.graph = graph
        self.faceSet = faceSet
        self.selection = selection
        self.intersections = intersections
    }
}

public enum ResolveSelfOverlapUseCase {
    public static func run(
        ring input: [Vec2],
        policy: DeterminismPolicy,
        selectionPolicy: ResolveSelfOverlapSelectionPolicy,
        includeDebug: Bool
    ) -> (ResolveSelfOverlapResult, ResolveSelfOverlapPipelineArtifacts?) {
        guard input.count >= 4 else {
            return (ResolveSelfOverlapResult(ring: input, intersections: [], faces: 0, insideFaces: 0, selectedFaceId: -1, selectedAbsArea: 0.0, success: false, failureReason: "ringTooSmall"), nil)
        }

        var ring = input
        if !Epsilon.approxEqual(ring.first!, ring.last!) {
            ring.append(ring.first!)
        }

        let planarOutput = SegmentPlanarizer.planarize(ring: ring, policy: policy, sourceRingId: ArtifactID("inputRing"), includeDebug: includeDebug)
        let planarArtifact = planarOutput.artifact
        if planarArtifact.segments.isEmpty {
            return (ResolveSelfOverlapResult(ring: ring, intersections: planarOutput.intersections, faces: 0, insideFaces: 0, selectedFaceId: -1, selectedAbsArea: 0.0, success: false, failureReason: "noEdges"), nil)
        }

        let (graphArtifactBase, graphIndex) = HalfEdgeGraphBuilder.build(planar: planarArtifact, includeDebug: false)
        let faceResult = FaceEnumerator.enumerate(graph: graphIndex, policy: policy, graphId: graphArtifactBase.id, includeDebug: includeDebug)

        var graphDebug: DebugBundle? = graphArtifactBase.debug
        if includeDebug {
            var bundle = DebugBundle()
            let payload = GraphDebugPayload(vertices: graphIndex.vertices.count, halfEdges: graphIndex.halfEdges.count, twinsPaired: graphIndex.halfEdges.count, faces: faceResult.faceSet.faces.count)
            try? bundle.add(payload)
            graphDebug = bundle
        }

        let faceRecords = faceResult.faceSet.faces.map { FaceRecord(anyHalfEdge: $0.halfEdgeCycle.first ?? 0) }
        let graphArtifact = HalfEdgeGraphArtifact(
            id: graphArtifactBase.id,
            policy: policy,
            planarId: planarArtifact.id,
            vertices: graphArtifactBase.vertices,
            halfEdges: graphArtifactBase.halfEdges,
            faces: faceRecords,
            debug: graphDebug
        )

        let (selectionResult, selectionDebug) = SelectionPolicy.select(
            policy: selectionPolicy,
            originalRing: ring,
            faces: faceResult.faceSet.faces,
            determinism: policy,
            includeDebug: includeDebug
        )

        let selectionArtifact = SelectionResultArtifact(
            id: ArtifactID("selectionResult"),
            policy: policy,
            faceSetId: faceResult.faceSet.id,
            selectedFaceId: selectionResult.selectedFaceId,
            selectedRing: selectionResult.ring,
            rejectedFaceIds: selectionResult.rejectedFaceIds,
            debug: selectionDebug
        )

        let pipelineArtifacts = ResolveSelfOverlapPipelineArtifacts(
            planar: planarArtifact,
            graph: graphArtifact,
            faceSet: faceResult.faceSet,
            selection: selectionArtifact,
            intersections: planarOutput.intersections
        )

        if let reason = selectionResult.failureReason {
            return (ResolveSelfOverlapResult(ring: ring, intersections: planarOutput.intersections, faces: faceResult.faceSet.faces.count, insideFaces: 0, selectedFaceId: selectionResult.selectedFaceId, selectedAbsArea: selectionResult.absArea, success: false, failureReason: reason), pipelineArtifacts)
        }

        return (ResolveSelfOverlapResult(ring: selectionResult.ring.points, intersections: planarOutput.intersections, faces: faceResult.faceSet.faces.count, insideFaces: 0, selectedFaceId: selectionResult.selectedFaceId, selectedAbsArea: selectionResult.absArea, success: true, failureReason: nil), pipelineArtifacts)
    }
}
