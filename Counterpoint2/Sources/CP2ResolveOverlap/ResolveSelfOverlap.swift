import Foundation
import CP2Domain
import CP2Geometry

public struct ResolveSelfOverlapResult: Equatable {
    public let ring: [Vec2]
    public let intersections: [Vec2]
    public let faces: Int
    public let insideFaces: Int
    public let selectedFaceId: Int
    public let selectedAbsArea: Double
    public let success: Bool
    public let failureReason: String?

    public init(
        ring: [Vec2],
        intersections: [Vec2],
        faces: Int,
        insideFaces: Int,
        selectedFaceId: Int,
        selectedAbsArea: Double,
        success: Bool,
        failureReason: String?
    ) {
        self.ring = ring
        self.intersections = intersections
        self.faces = faces
        self.insideFaces = insideFaces
        self.selectedFaceId = selectedFaceId
        self.selectedAbsArea = selectedAbsArea
        self.success = success
        self.failureReason = failureReason
    }
}

public func resolveSelfOverlap(
    ring input: [Vec2],
    eps: Double,
    selectionPolicy: ResolveSelfOverlapSelectionPolicy = .lineGalleryMaxAbsAreaFace(minAreaRatio: 0.01)
) -> ResolveSelfOverlapResult {
    let policy = DeterminismPolicy(eps: eps, stableSort: .lexicographicXYThenIndex)
    let (result, _) = ResolveSelfOverlapUseCase.run(ring: input, policy: policy, selectionPolicy: selectionPolicy, includeDebug: false)
    return result
}
