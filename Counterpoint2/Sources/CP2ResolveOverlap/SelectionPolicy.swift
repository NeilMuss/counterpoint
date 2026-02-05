import Foundation
import CP2Domain
import CP2Geometry

public enum ResolveSelfOverlapSelectionPolicy: Equatable, Sendable {
    case lineGalleryMaxAbsAreaFace(minAreaRatio: Double)
}

public struct ResolveSelfOverlapSelectionResult: Equatable, Sendable {
    public let selectedFaceId: Int
    public let ring: Ring
    public let absArea: Double
    public let rejectedFaceIds: [Int]
    public let failureReason: String?
}

public enum SelectionPolicy {
    public static func select(policy: ResolveSelfOverlapSelectionPolicy, originalRing: [Vec2], faces: [FaceLoop], determinism: DeterminismPolicy, includeDebug: Bool) -> (ResolveSelfOverlapSelectionResult, DebugBundle?) {
        switch policy {
        case .lineGalleryMaxAbsAreaFace(let minAreaRatio):
            let originalAbsArea = abs(signedArea(originalRing))
            guard let best = faces.max(by: { lhs, rhs in
                let la = abs(lhs.area)
                let ra = abs(rhs.area)
                if la == ra { return lhs.faceId < rhs.faceId }
                return la < ra
            }) else {
                let ring = Ring(points: originalRing, winding: .ccw, area: originalAbsArea)
                var debug: DebugBundle? = nil
                if includeDebug {
                    var bundle = DebugBundle()
                    let payload = SelectionDebugPayload(candidates: 0, selectedFaceId: -1, selectedAbsArea: 0.0, rejectedCount: 0, failureReason: "noFaces")
                    try? bundle.add(payload)
                    debug = bundle
                }
                return (ResolveSelfOverlapSelectionResult(selectedFaceId: -1, ring: ring, absArea: 0.0, rejectedFaceIds: [], failureReason: "noFaces"), debug)
            }
            let bestAbsArea = abs(best.area)
            let minArea = originalAbsArea * minAreaRatio
            if bestAbsArea < minArea {
                let ring = Ring(points: originalRing, winding: .ccw, area: originalAbsArea)
                let rejected = faces.map { $0.faceId }
                var debug: DebugBundle? = nil
                if includeDebug {
                    var bundle = DebugBundle()
                    let payload = SelectionDebugPayload(candidates: faces.count, selectedFaceId: best.faceId, selectedAbsArea: bestAbsArea, rejectedCount: rejected.count, failureReason: "areaTooSmall")
                    try? bundle.add(payload)
                    debug = bundle
                }
                return (ResolveSelfOverlapSelectionResult(selectedFaceId: best.faceId, ring: ring, absArea: bestAbsArea, rejectedFaceIds: rejected, failureReason: "areaTooSmall"), debug)
            }
            var ringPoints = best.boundary
            if signedArea(ringPoints) < 0.0 {
                ringPoints = ringPoints.reversed()
            }
            let winding: RingWinding = signedArea(ringPoints) >= 0.0 ? .ccw : .cw
            let ring = Ring(points: ringPoints, winding: winding, area: signedArea(ringPoints))
            let rejected = faces.filter { $0.faceId != best.faceId }.map { $0.faceId }

            var debug: DebugBundle? = nil
            if includeDebug {
                var bundle = DebugBundle()
                let payload = SelectionDebugPayload(candidates: faces.count, selectedFaceId: best.faceId, selectedAbsArea: bestAbsArea, rejectedCount: rejected.count, failureReason: nil)
                try? bundle.add(payload)
                debug = bundle
            }
            return (ResolveSelfOverlapSelectionResult(selectedFaceId: best.faceId, ring: ring, absArea: bestAbsArea, rejectedFaceIds: rejected, failureReason: nil), debug)
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
