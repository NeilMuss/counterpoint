import Foundation
import CP2Geometry
import CP2Skeleton

struct SweepResult {
    var segmentsUsed: [Segment2]
    var rings: [[Vec2]]
    var ring: [Vec2]
    var glyphBounds: AABB?
    var sampling: SamplingResult?
    var traceSteps: [TraceStepInfo]
    var capEndpointsDebug: CapEndpointsDebug?
    var railDebugSummary: RailDebugSummary?
    var railFrames: [RailSampleFrame]?
    var railCornerDebug: RailCornerDebug?
}

func runSweep(
    path: SkeletonPath,
    plan: SweepPlan,
    options: CLIOptions
) -> SweepResult {
    var capturedSampling: SamplingResult? = nil
    var traceSteps: [TraceStepInfo] = []
    var capEndpointsDebug: CapEndpointsDebug? = nil
    var railDebugSummary: RailDebugSummary? = nil
    var railFrames: [RailSampleFrame]? = nil
    var railCornerDebug: RailCornerDebug? = nil
    let wantsRailFrames = options.debugDumpRailFrames || options.debugRailInvariants || options.debugDumpRailEndpoints
    let wantsRailCorner = options.debugDumpRailCorners

    let segmentsUsed: [Segment2] = {
        if plan.usesVariableWidthAngleAlpha {
            return boundarySoupVariableWidthAngleAlpha(
                path: path,
                height: plan.sweepHeight,
                sampleCount: plan.sweepSampleCount,
                arcSamplesPerSegment: plan.paramSamplesPerSegment,
                adaptiveSampling: options.adaptiveSampling,
                flatnessEps: options.flatnessEps,
                railEps: options.flatnessEps,
                maxDepth: options.maxDepth,
                maxSamples: options.maxSamples,
                widthAtT: plan.scaledWidthAtT,
                widthLeftAtT: plan.scaledWidthLeftAtT,
                widthRightAtT: plan.scaledWidthRightAtT,
                angleAtT: plan.thetaAtT,
                offsetAtT: plan.offsetAtT,
                alphaAtT: plan.alphaAtT,
                alphaStart: plan.alphaStartGT,
                angleIsRelative: plan.angleMode == .relative,
                keyframeTs: plan.paramKeyframeTs,
                debugSampling: { capturedSampling = $0 },
                debugCapEndpoints: options.debugDumpCapEndpoints ? { capEndpointsDebug = $0 } : nil,
                debugRailSummary: options.debugDumpRailEndpoints ? { railDebugSummary = $0 } : nil,
                debugRailFrames: wantsRailFrames ? { railFrames = $0 } : nil,
                debugRailCornerIndex: wantsRailCorner ? options.debugDumpRailCornersIndex : nil,
                debugRailCorner: wantsRailCorner ? { railCornerDebug = $0 } : nil
            )
        } else {
            return boundarySoup(
                path: path,
                width: plan.sweepWidth,
                height: plan.sweepHeight,
                effectiveAngle: plan.sweepAngle,
                sampleCount: plan.sweepSampleCount,
                arcSamplesPerSegment: plan.paramSamplesPerSegment,
                adaptiveSampling: options.adaptiveSampling,
                flatnessEps: options.flatnessEps,
                railEps: options.flatnessEps,
                maxDepth: options.maxDepth,
                maxSamples: options.maxSamples,
                debugSampling: { capturedSampling = $0 },
                debugCapEndpoints: options.debugDumpCapEndpoints ? { capEndpointsDebug = $0 } : nil,
                debugRailSummary: options.debugDumpRailEndpoints ? { railDebugSummary = $0 } : nil,
                debugRailFrames: wantsRailFrames ? { railFrames = $0 } : nil,
                debugRailCornerIndex: wantsRailCorner ? options.debugDumpRailCornersIndex : nil,
                debugRailCorner: wantsRailCorner ? { railCornerDebug = $0 } : nil
            )
        }
    }()

    let rings = traceLoops(
        segments: segmentsUsed,
        eps: 1.0e-6,
        debugStep: options.debugTraceJumpStep ? { traceSteps.append($0) } : nil
    )
    let ring = rings.first ?? []
    let glyphBounds = ring.isEmpty ? nil : ringBounds(ring)

    return SweepResult(
        segmentsUsed: segmentsUsed,
        rings: rings,
        ring: ring,
        glyphBounds: glyphBounds,
        sampling: capturedSampling,
        traceSteps: traceSteps,
        capEndpointsDebug: capEndpointsDebug,
        railDebugSummary: railDebugSummary,
        railFrames: railFrames,
        railCornerDebug: railCornerDebug
    )
}
