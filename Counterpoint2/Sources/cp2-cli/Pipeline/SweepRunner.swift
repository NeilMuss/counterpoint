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
    var capBoundaryDebugs: [CapBoundaryDebug]
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
    var capBoundaryDebugs: [CapBoundaryDebug] = []
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
                    attrEpsOffset: options.adaptiveAttrEps,
                    attrEpsWidth: options.adaptiveAttrEps,
                    attrEpsAngle: options.adaptiveAttrEpsAngleDeg * Double.pi / 180.0,
                    attrEpsAlpha: options.adaptiveAttrEps,
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
                debugCapBoundary: options.debugCapBoundary ? { capBoundaryDebugs.append($0) } : nil,
                capNamespace: capNamespace,
                capLocalIndex: 0,
                startCap: startCap,
                endCap: endCap,
                capFilletArcSegments: options.capFilletArcSegments
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
                    attrEpsOffset: options.adaptiveAttrEps,
                    attrEpsWidth: options.adaptiveAttrEps,
                    attrEpsAngle: options.adaptiveAttrEpsAngleDeg * Double.pi / 180.0,
                    attrEpsAlpha: options.adaptiveAttrEps,
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
                debugCapBoundary: options.debugCapBoundary ? { capBoundaryDebugs.append($0) } : nil,
                capNamespace: capNamespace,
                capLocalIndex: 0,
                startCap: startCap,
                endCap: endCap,
                capFilletArcSegments: options.capFilletArcSegments
            )
        }
    }()

    if capNamespace == "fillet", case .fillet = endCap {
        let endLeft = capFillets.first { $0.kind == "end" && $0.side == "left" && $0.success }
        let endRight = capFillets.first { $0.kind == "end" && $0.side == "right" && $0.success }
        if let left = endLeft, let right = endRight {
            let midA = right.p
            let midB = left.q
            let midAText = String(format: "(%.3f,%.3f)", midA.x, midA.y)
            let midBText = String(format: "(%.3f,%.3f)", midB.x, midB.y)
            var midMatches: [Segment2] = []
            for seg in segmentsUsed {
                let direct = Epsilon.approxEqual(seg.a, midA) && Epsilon.approxEqual(seg.b, midB)
                let reverse = Epsilon.approxEqual(seg.a, midB) && Epsilon.approxEqual(seg.b, midA)
                if direct || reverse {
                    midMatches.append(seg)
                }
            }
            print("capFilletMidSegmentFound count=\(midMatches.count) midA=\(midAText) midB=\(midBText)")
            for seg in midMatches {
                let len = (seg.a - seg.b).length
                print(String(format: "  mid len=%.6f a=(%.3f,%.3f) b=(%.3f,%.3f) src=%@", len, seg.a.x, seg.a.y, seg.b.x, seg.b.y, seg.source.description))
            }
            let bypassA = left.corner
            let bypassB = right.corner
            let bypassAText = String(format: "(%.3f,%.3f)", bypassA.x, bypassA.y)
            let bypassBText = String(format: "(%.3f,%.3f)", bypassB.x, bypassB.y)
            var bypassMatches: [Segment2] = []
            for seg in segmentsUsed {
                let direct = Epsilon.approxEqual(seg.a, bypassA) && Epsilon.approxEqual(seg.b, bypassB)
                let reverse = Epsilon.approxEqual(seg.a, bypassB) && Epsilon.approxEqual(seg.b, bypassA)
                if direct || reverse {
                    bypassMatches.append(seg)
                }
            }
            print("capFilletBypassEdgesFound count=\(bypassMatches.count) cornerA=\(bypassAText) cornerB=\(bypassBText)")
            for seg in bypassMatches {
                let len = (seg.a - seg.b).length
                print(String(format: "  bypass len=%.6f a=(%.3f,%.3f) b=(%.3f,%.3f) src=%@", len, seg.a.x, seg.a.y, seg.b.x, seg.b.y, seg.source.description))
            }
            let arcSteps = max(8, options.capFilletArcSegments)
            var arcInterior: [Vec2] = []
            if let bridge = left.bridge {
                let count = max(2, arcSteps + 1)
                let points = (0..<count).map { i -> Vec2 in
                    let t = Double(i) / Double(count - 1)
                    return bridge.evaluate(t)
                }
                arcInterior.append(contentsOf: points.dropFirst().dropLast())
            }
            if let bridge = right.bridge {
                let count = max(2, arcSteps + 1)
                let points = (0..<count).map { i -> Vec2 in
                    let t = Double(i) / Double(count - 1)
                    return bridge.evaluate(t)
                }
                arcInterior.append(contentsOf: points.dropFirst().dropLast())
            }
            if !arcInterior.isEmpty {
                let ok = soupConnectivity(segments: segmentsUsed, eps: 1.0e-6, from: midA, targets: arcInterior)
                print("capFilletConnectivity ok=\(ok)")
            }
            let eps = 1.0e-6
            let epsText = String(format: "%.1e", eps)
            var touchingX: [Segment2] = []
            for seg in segmentsUsed {
                let aNear = abs(seg.a.x - 200.0) <= eps
                let bNear = abs(seg.b.x - 200.0) <= eps
                if aNear || bNear {
                    touchingX.append(seg)
                }
            }
            print("capFilletXTouch count=\(touchingX.count) x=200 eps=\(epsText)")
            for seg in touchingX {
                let len = (seg.a - seg.b).length
                print(String(format: "  xTouch len=%.6f a=(%.3f,%.3f) b=(%.3f,%.3f) src=%@", len, seg.a.x, seg.a.y, seg.b.x, seg.b.y, seg.source.description))
            }
        }
    }

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
        capBoundaryDebugs: capBoundaryDebugs,
        railDebugSummary: railDebugSummary,
        railFrames: railFrames,
        railCornerDebug: railCornerDebug
    )
}
