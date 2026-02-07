import Foundation
import CP2Geometry
import CP2Skeleton
import CP2ResolveOverlap

struct PlanarizationResult {
    var planarizeStats: SegmentPlanarizerStats?
    var planarizationHeatmap: PlanarizationHeatmapDebug?
    var planarSegments: [Segment2]
    var rings: [[Vec2]]
    var faces: [FaceLoop]
}
