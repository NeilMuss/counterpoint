import Foundation

public enum ResolveSelfOverlapSelectionPolicy: Equatable {
    case lineGalleryMaxAbsAreaFace(minAreaRatio: Double)
}

public struct ResolveSelfOverlapSelectionResult: Equatable {
    public let ring: [Vec2]
    public let absArea: Double
    public let verts: Int
    public let failureReason: String?
}

public enum SelectionPolicy {
    public static func select(policy: ResolveSelfOverlapSelectionPolicy, originalRing: [Vec2], vertices: [PlanarVertex], faces: [FaceCycle]) -> ResolveSelfOverlapSelectionResult {
        switch policy {
        case .lineGalleryMaxAbsAreaFace(let minAreaRatio):
            let originalAbsArea = abs(signedArea(originalRing))
            guard let best = faces.max(by: { $0.absArea < $1.absArea }) else {
                return ResolveSelfOverlapSelectionResult(ring: originalRing, absArea: 0.0, verts: originalRing.count, failureReason: "noFaces")
            }
            let bestAbsArea = best.absArea
            let minArea = originalAbsArea * minAreaRatio
            if bestAbsArea < minArea {
                return ResolveSelfOverlapSelectionResult(ring: originalRing, absArea: bestAbsArea, verts: best.vertexIds.count, failureReason: "areaTooSmall")
            }
            var ring: [Vec2] = best.vertexIds.compactMap { idx in
                if idx >= 0 && idx < vertices.count {
                    return vertices[idx].pos
                }
                return nil
            }
            if let first = ring.first { ring.append(first) }
            if signedArea(ring) < 0.0 {
                ring = ring.reversed()
            }
            return ResolveSelfOverlapSelectionResult(ring: ring, absArea: bestAbsArea, verts: best.vertexIds.count, failureReason: nil)
        }
    }

    private static func signedArea(_ ring: [Vec2]) -> Double {
        guard ring.count >= 3 else { return 0.0 }
        var area = 0.0
        for i in 0..<(ring.count - 1) {
            let a = ring[i]
            let b = ring[i + 1]
            area += (a.x * b.y - b.x * a.y)
        }
        return area * 0.5
    }
}
