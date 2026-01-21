import Foundation
import CP2Geometry
import CP2Skeleton

struct SweepResult {
    var segmentsUsed: [Segment2]
    var rings: [[Vec2]]
    var ring: [Vec2]
    var glyphBounds: AABB?
}

func runSweep(
    path: SkeletonPath,
    plan: SweepPlan,
    options: CLIOptions
) -> SweepResult {
    let segmentsUsed: [Segment2] = {
        switch plan.mode {
        case .variableWidthAngleAlpha:
            return boundarySoupVariableWidthAngleAlpha(
                path: path,
                height: plan.sweepHeight,
                sampleCount: plan.sweepSampleCount,
                arcSamplesPerSegment: plan.paramSamplesPerSegment,
                adaptiveSampling: options.adaptiveSampling,
                flatnessEps: options.flatnessEps,
                maxDepth: options.maxDepth,
                maxSamples: options.maxSamples,
                widthAtT: { t in plan.scaledWidthAtT(plan.warpT(t)) },
                angleAtT: { t in plan.thetaAtT(plan.warpT(t)) },
                alphaAtT: plan.alphaAtT,
                alphaStart: plan.alphaStartGT
            )
        case .constant:
            return boundarySoup(
                path: path,
                width: plan.sweepWidth,
                height: plan.sweepHeight,
                effectiveAngle: plan.sweepAngle,
                sampleCount: plan.sweepSampleCount,
                arcSamplesPerSegment: plan.paramSamplesPerSegment,
                adaptiveSampling: options.adaptiveSampling,
                flatnessEps: options.flatnessEps,
                maxDepth: options.maxDepth,
                maxSamples: options.maxSamples
            )
        }
    }()

    let rings = traceLoops(segments: segmentsUsed, eps: 1.0e-6)
    let ring = rings.first ?? []
    let glyphBounds = ring.isEmpty ? nil : ringBounds(ring)

    return SweepResult(
        segmentsUsed: segmentsUsed,
        rings: rings,
        ring: ring,
        glyphBounds: glyphBounds
    )
}
