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
    var capFillets: [CapFilletDebug]
    var railDebugSummary: RailDebugSummary?
    var railFrames: [RailSampleFrame]?
    var railCornerDebug: RailCornerDebug?
}

private func emitSoupNeighborhood(_ report: SoupNeighborhoodReport, label: String) {
    print(String(format: "soupNeighborhood label=%@ center=(%.6f,%.6f) r=%.6f nodes=%d collisions=%d", label, report.center.x, report.center.y, report.radius, report.nodes.count, report.collisions.count))
    for node in report.nodes {
        print(String(format: "  node key=(%d,%d) pos=(%.6f,%.6f) degree=%d", node.key.x, node.key.y, node.pos.x, node.pos.y, node.degree))
        for edge in node.edges {
            let segIndexText = edge.segmentIndex.map(String.init) ?? "none"
            print(String(format: "    out -> key=(%d,%d) pos=(%.6f,%.6f) len=%.6f dir=(%.6f,%.6f) src=%@ segIndex=%@", edge.toKey.x, edge.toKey.y, edge.toPos.x, edge.toPos.y, edge.len, edge.dir.x, edge.dir.y, edge.source.description, segIndexText))
        }
    }
    if !report.collisions.isEmpty {
        print(String(format: "soupNeighborhood collisions=%d", report.collisions.count))
        for collision in report.collisions {
            let positions = collision.positions.map { String(format: "(%.6f,%.6f)", $0.x, $0.y) }.joined(separator: ", ")
            print(String(format: "  collision key=(%d,%d) positions=[%@]", collision.key.x, collision.key.y, positions))
        }
    }
}

func runSweep(
    path: SkeletonPath,
    plan: SweepPlan,
    options: CLIOptions,
    capNamespace: String,
    startCap: CapStyle,
    endCap: CapStyle
) -> SweepResult {
    var capturedSampling: SamplingResult? = nil
    var traceSteps: [TraceStepInfo] = []
    var capEndpointsDebug: CapEndpointsDebug? = nil
    var capFillets: [CapFilletDebug] = []
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
                debugRailCorner: wantsRailCorner ? { railCornerDebug = $0 } : nil,
                debugCapFillet: {
                    capFillets.append($0)
                    if options.debugDumpCapEndpoints || options.debugSweep {
                        let info = $0
                        if info.success {
                            print(String(format: "capFillet kind=%@ side=%@ r=%.6f theta=%.6f d=%.6f corner=(%.6f,%.6f) P=(%.6f,%.6f) Q=(%.6f,%.6f)", info.kind, info.side, info.radius, info.theta, info.d, info.corner.x, info.corner.y, info.p.x, info.p.y, info.q.x, info.q.y))
                        } else {
                            let reason = info.failureReason ?? "unknown"
                            print(String(format: "capFillet kind=%@ side=%@ r=%.6f failed=%@", info.kind, info.side, info.radius, reason))
                        }
                    }
                },
                capNamespace: capNamespace,
                capLocalIndex: 0,
                startCap: startCap,
                endCap: endCap
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
                debugRailCorner: wantsRailCorner ? { railCornerDebug = $0 } : nil,
                debugCapFillet: {
                    capFillets.append($0)
                    if options.debugDumpCapEndpoints || options.debugSweep {
                        let info = $0
                        if info.success {
                            print(String(format: "capFillet kind=%@ side=%@ r=%.6f theta=%.6f d=%.6f corner=(%.6f,%.6f) P=(%.6f,%.6f) Q=(%.6f,%.6f)", info.kind, info.side, info.radius, info.theta, info.d, info.corner.x, info.corner.y, info.p.x, info.p.y, info.q.x, info.q.y))
                        } else {
                            let reason = info.failureReason ?? "unknown"
                            print(String(format: "capFillet kind=%@ side=%@ r=%.6f failed=%@", info.kind, info.side, info.radius, reason))
                        }
                    }
                },
                capNamespace: capNamespace,
                capLocalIndex: 0,
                startCap: startCap,
                endCap: endCap
            )
        }
    }()

    if let center = options.debugSoupNeighborhoodCenter {
        let report = computeSoupNeighborhood(
            segments: segmentsUsed,
            eps: 1.0e-6,
            center: center,
            radius: options.debugSoupNeighborhoodRadius
        )
        emitSoupNeighborhood(report, label: "manual")
    }

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
        capFillets: capFillets,
        railDebugSummary: railDebugSummary,
        railFrames: railFrames,
        railCornerDebug: railCornerDebug
    )
}
