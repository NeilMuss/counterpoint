import Foundation
import CP2Geometry
import CP2Skeleton

struct SoupBuildResult {
    var segments: [Segment2]
    var soupLaneSegments: Int
    var soupPerimeterSegments: Int
    var soupTotalSegments: Int
    var sampling: SamplingResult?
    var traceSteps: [TraceStepInfo]
    var capEndpointsDebug: CapEndpointsDebug?
    var capFillets: [CapFilletDebug]
    var capBoundaryDebugs: [CapBoundaryDebug]
    var capPlaneDebugs: [CapPlaneDebug]
    var railDebugSummary: RailDebugSummary?
    var railFrames: [RailSampleFrame]?
    var railCornerDebug: RailCornerDebug?
    var penStamps: PenStampsDebug?
}
