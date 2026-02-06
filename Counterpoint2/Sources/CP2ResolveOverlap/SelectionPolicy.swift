import Foundation
import CP2Domain
import CP2Geometry

public enum ResolveSelfOverlapSelectionPolicy: Equatable, Sendable {
    case lineGalleryMaxAbsAreaFace(minAreaRatio: Double)
    case rectCornersBBox(minAreaRatio: Double, minBBoxRatio: Double)
}

public struct ResolveSelfOverlapSelectionResult: Equatable, Sendable {
    public let selectedFaceId: Int
    public let ring: Ring
    public let absArea: Double
    public let rejectedFaceIds: [Int]
    public let failureReason: String?
}

private struct RectCornersCandidate {
    let face: FaceLoop
    let absArea: Double
    let bboxArea: Double
    let selfX: Int
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
        case .rectCornersBBox(let minAreaRatio, let minBBoxRatio):
            let originalAbsArea = abs(signedArea(originalRing))
            let originalBBoxArea = bboxArea(for: originalRing)
            let minArea = originalAbsArea * minAreaRatio
            let minBBoxArea = originalBBoxArea * minBBoxRatio

            var candidates: [RectCornersCandidate] = []
            var rejected: [Int] = []
            for face in faces {
                let absArea = abs(face.area)
                let boxArea = bboxArea(for: face.boundary)
                if absArea < minArea || boxArea < minBBoxArea {
                    rejected.append(face.faceId)
                    continue
                }
                let selfX = ringSelfIntersectionCount(face.boundary)
                candidates.append(RectCornersCandidate(face: face, absArea: absArea, bboxArea: boxArea, selfX: selfX))
            }

            let preferredCandidates: [RectCornersCandidate]
            if candidates.contains(where: { $0.selfX == 0 }) {
                preferredCandidates = candidates.filter { $0.selfX == 0 }
            } else {
                preferredCandidates = candidates
            }

            guard let best = preferredCandidates.max(by: { lhs, rhs in
                if lhs.bboxArea == rhs.bboxArea {
                    if lhs.absArea == rhs.absArea { return lhs.face.faceId < rhs.face.faceId }
                    return lhs.absArea < rhs.absArea
                }
                return lhs.bboxArea < rhs.bboxArea
            }) else {
                let ring = Ring(points: originalRing, winding: .ccw, area: originalAbsArea)
                var debug: DebugBundle? = nil
                if includeDebug {
                    var bundle = DebugBundle()
                    let payload = RectCornersSelectionDebugPayload(
                        candidates: [],
                        selectedFaceId: -1,
                        selectedAbsArea: 0.0,
                        selectedBBoxArea: 0.0,
                        rejectedCount: rejected.count,
                        failureReason: "noFaces"
                    )
                    try? bundle.add(payload)
                    debug = bundle
                }
                return (ResolveSelfOverlapSelectionResult(selectedFaceId: -1, ring: ring, absArea: 0.0, rejectedFaceIds: rejected, failureReason: "noFaces"), debug)
            }

            let bestAbsArea = best.absArea
            if bestAbsArea < minArea {
                let ring = Ring(points: originalRing, winding: .ccw, area: originalAbsArea)
                var debug: DebugBundle? = nil
                if includeDebug {
                    var bundle = DebugBundle()
                    let topCandidates = topRectCandidates(candidates: candidates)
                    let payload = RectCornersSelectionDebugPayload(
                        candidates: topCandidates,
                        selectedFaceId: best.face.faceId,
                        selectedAbsArea: bestAbsArea,
                        selectedBBoxArea: best.bboxArea,
                        rejectedCount: rejected.count,
                        failureReason: "areaTooSmall"
                    )
                    try? bundle.add(payload)
                    debug = bundle
                }
                return (ResolveSelfOverlapSelectionResult(selectedFaceId: best.face.faceId, ring: ring, absArea: bestAbsArea, rejectedFaceIds: rejected, failureReason: "areaTooSmall"), debug)
            }

            var ringPoints = best.face.boundary
            if signedArea(ringPoints) < 0.0 {
                ringPoints = ringPoints.reversed()
            }
            let winding: RingWinding = signedArea(ringPoints) >= 0.0 ? .ccw : .cw
            let ring = Ring(points: ringPoints, winding: winding, area: signedArea(ringPoints))
            let rejectedIds = faces.filter { $0.faceId != best.face.faceId }.map { $0.faceId }

            var debug: DebugBundle? = nil
            if includeDebug {
                var bundle = DebugBundle()
                let topCandidates = topRectCandidates(candidates: candidates)
                let payload = RectCornersSelectionDebugPayload(
                    candidates: topCandidates,
                    selectedFaceId: best.face.faceId,
                    selectedAbsArea: bestAbsArea,
                    selectedBBoxArea: best.bboxArea,
                    rejectedCount: rejected.count,
                    failureReason: nil
                )
                try? bundle.add(payload)
                debug = bundle
            }
            return (ResolveSelfOverlapSelectionResult(selectedFaceId: best.face.faceId, ring: ring, absArea: bestAbsArea, rejectedFaceIds: rejectedIds, failureReason: nil), debug)
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

    private static func bboxArea(for ring: [Vec2]) -> Double {
        guard let first = ring.first else { return 0.0 }
        var minP = first
        var maxP = first
        for p in ring {
            minP = Vec2(min(minP.x, p.x), min(minP.y, p.y))
            maxP = Vec2(max(maxP.x, p.x), max(maxP.y, p.y))
        }
        let w = max(0.0, maxP.x - minP.x)
        let h = max(0.0, maxP.y - minP.y)
        return w * h
    }

    private static func topRectCandidates(candidates: [RectCornersCandidate], limit: Int = 5) -> [RectCornersSelectionCandidate] {
        let sorted = candidates.sorted { lhs, rhs in
            if lhs.bboxArea == rhs.bboxArea {
                if lhs.absArea == rhs.absArea { return lhs.face.faceId < rhs.face.faceId }
                return lhs.absArea > rhs.absArea
            }
            return lhs.bboxArea > rhs.bboxArea
        }
        return sorted.prefix(limit).map {
            RectCornersSelectionCandidate(faceId: $0.face.faceId, absArea: $0.absArea, bboxArea: $0.bboxArea)
        }
    }
}
