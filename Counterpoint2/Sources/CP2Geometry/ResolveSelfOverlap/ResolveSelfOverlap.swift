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

public func resolveSelfOverlap(ring input: [Vec2], eps: Double) -> ResolveSelfOverlapResult {
    let debugLog = true
    guard input.count >= 4 else {
        return ResolveSelfOverlapResult(ring: input, intersections: [], faces: 0, insideFaces: 0, success: false, failureReason: "ringTooSmall")
    }

    var ring = input
    if !Epsilon.approxEqual(ring.first!, ring.last!) {
        ring.append(ring.first!)
    }

    let planar = SegmentPlanarizer.planarize(ring: ring, eps: eps)
    if debugLog {
        let stats = planar.stats
        print(String(format: "RESOLVE_SELF_OVERLAP_DIAG segments=%d intersections=%d", stats.segments, stats.intersections))
        print(String(format: "RESOLVE_SELF_OVERLAP_DIAG splitPoints min=%.1f avg=%.2f max=%.1f", Double(stats.splitMin), stats.splitAvg, Double(stats.splitMax)))
        print(String(format: "RESOLVE_SELF_OVERLAP_DIAG splitVerts=%d splitEdges=%d", stats.splitVerts, stats.splitEdges))
    }

    if planar.edges.isEmpty {
        return ResolveSelfOverlapResult(ring: ring, intersections: planar.intersections, faces: 0, insideFaces: 0, success: false, failureReason: "noEdges")
    }

    let graph = HalfEdgeGraph(vertices: planar.vertices, edges: planar.edges)
    if debugLog {
        var minDeg = Int.max
        var maxDeg = 0
        var sumDeg = 0
        var lowDeg = 0
        for edgesAt in graph.outgoing {
            let deg = edgesAt.count
            minDeg = min(minDeg, deg)
            maxDeg = max(maxDeg, deg)
            sumDeg += deg
            if deg < 2 { lowDeg += 1 }
        }
        let avgDeg = graph.outgoing.isEmpty ? 0.0 : Double(sumDeg) / Double(graph.outgoing.count)
        print(String(format: "RESOLVE_SELF_OVERLAP_DIAG vertices=%d outDegree min=%d avg=%.2f max=%d deg<2=%d", graph.outgoing.count, minDeg == Int.max ? 0 : minDeg, avgDeg, maxDeg, lowDeg))
    }

    let faceResult = FaceEnumerator.enumerate(graph: graph)
    if debugLog {
        for (index, face) in faceResult.faces.enumerated() {
            print(String(format: "FACE %d verts=%d area=%.6f absArea=%.6f", index, face.vertexIds.count, face.signedArea, face.absArea))
        }
        let top = faceResult.faces.enumerated()
            .sorted { $0.element.absArea > $1.element.absArea }
            .prefix(3)
        var topText: [String] = []
        for entry in top {
            let sign = entry.element.signedArea >= 0.0 ? "+" : "-"
            topText.append(String(format: "%d abs=%.3f verts=%d sign=%@", entry.offset, entry.element.absArea, entry.element.vertexIds.count, sign))
        }
        if !topText.isEmpty {
            print("FACE_TOP " + topText.joined(separator: " | "))
        }
        print(String(format: "RESOLVE_SELF_OVERLAP_DIAG halfEdges=%d twinsPaired=%d faces=%d", graph.halfEdges.count, graph.twinsPaired, faceResult.faces.count))
        print(String(format: "RESOLVE_SELF_OVERLAP_DIAG twinsUnpaired=%d faceHistogram small(<3)=%d ok=%d", graph.missingTwins.count, faceResult.smallFaceCount, faceResult.faces.count))
        print(String(format: "RESOLVE_SELF_OVERLAP_DIAG intersections=%d splitVerts=%d splitEdges=%d halfEdges=%d twinsPaired=%d faces=%d", planar.stats.intersections, planar.stats.splitVerts, planar.stats.splitEdges, graph.halfEdges.count, graph.twinsPaired, faceResult.faces.count))
    }

    if faceResult.faces.isEmpty {
        return ResolveSelfOverlapResult(ring: ring, intersections: planar.intersections, faces: 0, insideFaces: 0, success: false, failureReason: "noFaces")
    }

    let originalAbsArea = abs(signedArea(ring))
    let selection = SelectionPolicy.select(
        policy: .lineGalleryMaxAbsAreaFace(minAreaRatio: 0.01),
        originalRing: ring,
        vertices: graph.vertices,
        faces: faceResult.faces
    )
    if debugLog {
        print(String(format: "RESOLVE_SELF_OVERLAP_SELECT candidates=%d bestAbsArea=%.6f originalAbsArea=%.6f bestVerts=%d", faceResult.faces.count, selection.absArea, originalAbsArea, selection.verts))
    }
    if let reason = selection.failureReason {
        if debugLog, reason == "areaTooSmall" {
            print(String(format: "RESOLVE_SELF_OVERLAP_FALLBACK reason=areaTooSmall bestArea=%.6f originalAbsArea=%.6f", selection.absArea, originalAbsArea))
        }
        return ResolveSelfOverlapResult(ring: ring, intersections: planar.intersections, faces: faceResult.faces.count, insideFaces: 0, success: false, failureReason: reason)
    }

    let resolved = selection.ring
    return ResolveSelfOverlapResult(
        ring: resolved,
        intersections: planar.intersections,
        faces: faceResult.faces.count,
        insideFaces: 0,
        success: true,
        failureReason: nil
    )
}
