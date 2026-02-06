import Foundation
import CP2Geometry
import CP2Skeleton
import CP2ResolveOverlap

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
    var capPlaneDebugs: [CapPlaneDebug]
    var railDebugSummary: RailDebugSummary?
    var railFrames: [RailSampleFrame]?
    var railCornerDebug: RailCornerDebug?
    var ringTopology: RingTopologyDebug?
    var resolveSelfOverlap: ResolveSelfOverlapDebug?
    var ringSelfXHit: RingSelfXHitDebug?
}

struct ResolveSelfOverlapDebug {
    let original: [Vec2]
    let resolved: [Vec2]
    let intersections: [Vec2]
    let selfBefore: Int
    let selfAfter: Int
    let selectedFaceId: Int
    let selectedAbsArea: Double
    let selectedBBoxMin: Vec2
    let selectedBBoxMax: Vec2
}

struct RingSelfXHitDebug {
    let ringIndex: Int
    let i: Int
    let j: Int
    let point: Vec2
    let a0: Vec2
    let a1: Vec2
    let b0: Vec2
    let b1: Vec2
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

struct RingTopologyDebug {
    struct RingInfo {
        let index: Int
        let area: Double
        let absArea: Double
        let winding: String
        let verts: Int
    }
    struct SelfIntersection {
        let ringIndex: Int
        let i: Int
        let j: Int
        let point: Vec2
    }
    let rings: [RingInfo]
    let selfIntersections: [SelfIntersection]
    let microRingIndices: [Int]
}

private func ringSelfIntersections(ring: [Vec2], ringIndex: Int, eps: Double) -> [RingTopologyDebug.SelfIntersection] {
    let n = ring.count
    guard n >= 4 else { return [] }
    let lastIsFirst = Epsilon.approxEqual(ring.first!, ring.last!)
    let edgeCount = lastIsFirst ? n - 1 : n
    func cross(_ a: Vec2, _ b: Vec2) -> Double { a.x * b.y - a.y * b.x }
    func segmentIntersection(_ a: Vec2, _ b: Vec2, _ c: Vec2, _ d: Vec2) -> Vec2? {
        let r = b - a
        let s = d - c
        let denom = cross(r, s)
        if abs(denom) <= eps { return nil }
        let t = cross(c - a, s) / denom
        let u = cross(c - a, r) / denom
        if t >= -eps && t <= 1.0 + eps && u >= -eps && u <= 1.0 + eps {
            return Vec2(a.x + r.x * t, a.y + r.y * t)
        }
        return nil
    }
    var hits: [RingTopologyDebug.SelfIntersection] = []
    for i in 0..<edgeCount {
        let a0 = ring[i]
        let a1 = ring[(i + 1) % edgeCount]
        if (a1 - a0).length <= eps { continue }
        if i + 2 >= edgeCount { continue }
        for j in (i + 2)..<edgeCount {
            if i == 0 && j == edgeCount - 1 { continue }
            let b0 = ring[j]
            let b1 = ring[(j + 1) % edgeCount]
            if (b1 - b0).length <= eps { continue }
            if let hit = segmentIntersection(a0, a1, b0, b1) {
                if Epsilon.approxEqual(hit, a0, eps: eps)
                    || Epsilon.approxEqual(hit, a1, eps: eps)
                    || Epsilon.approxEqual(hit, b0, eps: eps)
                    || Epsilon.approxEqual(hit, b1, eps: eps) {
                    continue
                }
                hits.append(RingTopologyDebug.SelfIntersection(ringIndex: ringIndex, i: i, j: j, point: hit))
            }
        }
    }
    return hits
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
    var capPlaneDebugs: [CapPlaneDebug] = []
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
                debugCapPlane: options.debugCapBoundary ? { capPlaneDebugs.append($0) } : nil,
                capNamespace: capNamespace,
                capLocalIndex: 0,
                startCap: startCap,
                endCap: endCap,
                capFilletArcSegments: options.capFilletArcSegments,
                capRoundArcSegments: options.capRoundArcSegments,
                penShape: options.penShape
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
                debugCapPlane: options.debugCapBoundary ? { capPlaneDebugs.append($0) } : nil,
                capNamespace: capNamespace,
                capLocalIndex: 0,
                startCap: startCap,
                endCap: endCap,
                capFilletArcSegments: options.capFilletArcSegments,
                capRoundArcSegments: options.capRoundArcSegments,
                penShape: options.penShape
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

    var rings = traceLoops(
        segments: segmentsUsed,
        eps: 1.0e-6,
        debugStep: options.debugTraceJumpStep ? { traceSteps.append($0) } : nil
    )
    var ring: [Vec2] = []
    if rings.count == 1 {
        ring = rings[0]
    } else if rings.count > 1 {
        let selection = selectFinalRing(rings: rings)
        ring = selection.ring
        if options.debugRingTopology {
            print(String(format: "RING_SELECT outer=%d absArea=%.6f", selection.index, selection.absArea))
        }
    }

    var resolveSelfOverlapDebug: ResolveSelfOverlapDebug? = nil
    if options.resolveSelfOverlap, let example = options.example, example.hasPrefix("line_") {
        let before = ringSelfIntersections(ring: ring, ringIndex: 0, eps: 1.0e-6).count
        if before > 0 {
            let resolvedPenShape: PenShape = {
                switch options.penShape {
                case .auto:
                    return plan.angleMode == .relative ? .railsOnly : .rectCorners
                default:
                    return options.penShape
                }
            }()
            let selectionPolicy: ResolveSelfOverlapSelectionPolicy =
                resolvedPenShape == .rectCorners
                ? .rectCornersBBox(minAreaRatio: 0.01, minBBoxRatio: 0.01)
                : .lineGalleryMaxAbsAreaFace(minAreaRatio: 0.01)
            let resolved = resolveSelfOverlap(ring: ring, eps: 1.0e-6, selectionPolicy: selectionPolicy)
            if resolved.success {
                let after = ringSelfIntersections(ring: resolved.ring, ringIndex: 0, eps: 1.0e-6).count
                print(String(format: "RESOLVE_SELF_OVERLAP enabled=true ringSelfXBefore=%d ringSelfXAfter=%d vertsBefore=%d vertsAfter=%d", before, after, ring.count, resolved.ring.count))
                let bounds = ringBounds(resolved.ring)
                resolveSelfOverlapDebug = ResolveSelfOverlapDebug(
                    original: ring,
                    resolved: resolved.ring,
                    intersections: resolved.intersections,
                    selfBefore: before,
                    selfAfter: after,
                    selectedFaceId: resolved.selectedFaceId,
                    selectedAbsArea: resolved.selectedAbsArea,
                    selectedBBoxMin: bounds.min,
                    selectedBBoxMax: bounds.max
                )
                ring = resolved.ring
                rings = [ring]
            } else {
                print(String(format: "RESOLVE_SELF_OVERLAP_FALLBACK reason=%@", resolved.failureReason ?? "unknown"))
            }
        }
    }

    var ringTopology: RingTopologyDebug? = nil
    if options.debugRingTopology {
        var ringInfos: [RingTopologyDebug.RingInfo] = []
        var intersections: [RingTopologyDebug.SelfIntersection] = []
        var microRings: [Int] = []
        for (index, ringItem) in rings.enumerated() {
            let area = signedArea(ringItem)
            let absArea = abs(area)
            let winding = area >= 0.0 ? "CCW" : "CW"
            ringInfos.append(RingTopologyDebug.RingInfo(index: index, area: area, absArea: absArea, winding: winding, verts: ringItem.count))
            intersections.append(contentsOf: ringSelfIntersections(ring: ringItem, ringIndex: index, eps: 1.0e-6))
            if absArea < 1.0 {
                microRings.append(index)
            }
        }
        ringTopology = RingTopologyDebug(rings: ringInfos, selfIntersections: intersections, microRingIndices: microRings)
        print("RING_TOPO ringCount=\(rings.count)")
        for info in ringInfos {
            print(String(format: "RING_TOPO ring=%d absArea=%.6f winding=%@ verts=%d", info.index, info.absArea, info.winding, info.verts))
        }
        let grouped = Dictionary(grouping: intersections, by: { $0.ringIndex })
        for info in ringInfos {
            let hits = grouped[info.index] ?? []
            print(String(format: "RING_SELF_X ring=%d count=%d", info.index, hits.count))
            for hit in hits {
                print(String(format: "RING_SELF_X hit ring=%d i=%d j=%d P=(%.6f,%.6f)", hit.ringIndex, hit.i, hit.j, hit.point.x, hit.point.y))
            }
        }
        for index in microRings {
            if let info = ringInfos.first(where: { $0.index == index }) {
                print(String(format: "RING_MICRO ring=%d absArea=%.6f", info.index, info.absArea))
            }
        }
    }
    var ringSelfXHit: RingSelfXHitDebug? = nil
    if let k = options.debugRingSelfXHit {
        var intersections: [RingTopologyDebug.SelfIntersection] = []
        for (index, ringItem) in rings.enumerated() {
            intersections.append(contentsOf: ringSelfIntersections(ring: ringItem, ringIndex: index, eps: 1.0e-6))
        }
        if k >= 0 && k < intersections.count {
            let hit = intersections[k]
            if hit.ringIndex < rings.count, let first = rings[hit.ringIndex].first {
                let ring = rings[hit.ringIndex]
                let lastIsFirst = Epsilon.approxEqual(first, ring.last ?? first)
                let edgeCount = lastIsFirst ? max(1, ring.count - 1) : ring.count
                let a0 = ring[hit.i]
                let a1 = ring[(hit.i + 1) % edgeCount]
                let b0 = ring[hit.j]
                let b1 = ring[(hit.j + 1) % edgeCount]
                ringSelfXHit = RingSelfXHitDebug(
                    ringIndex: hit.ringIndex,
                    i: hit.i,
                    j: hit.j,
                    point: hit.point,
                    a0: a0,
                    a1: a1,
                    b0: b0,
                    b1: b1
                )
                print(String(format: "RING_SELF_X_HIT k=%d ring=%d i=%d j=%d P=(%.6f,%.6f) A0=(%.6f,%.6f) A1=(%.6f,%.6f) B0=(%.6f,%.6f) B1=(%.6f,%.6f)", k, hit.ringIndex, hit.i, hit.j, hit.point.x, hit.point.y, a0.x, a0.y, a1.x, a1.y, b0.x, b0.y, b1.x, b1.y))
            }
        } else {
            print(String(format: "RING_SELF_X_HIT k=%d out_of_range count=%d", k, intersections.count))
        }
    }
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
        capPlaneDebugs: capPlaneDebugs,
        railDebugSummary: railDebugSummary,
        railFrames: railFrames,
        railCornerDebug: railCornerDebug,
        ringTopology: ringTopology,
        resolveSelfOverlap: resolveSelfOverlapDebug,
        ringSelfXHit: ringSelfXHit
    )
}

private func selectFinalRing(rings: [[Vec2]]) -> (index: Int, ring: [Vec2], absArea: Double, bboxArea: Double) {
    var bestIndex = 0
    var bestAbsArea = -Double.greatestFiniteMagnitude
    var bestBBoxArea = -Double.greatestFiniteMagnitude
    for (index, ring) in rings.enumerated() {
        let absArea = abs(signedArea(ring))
        let bounds = ringBounds(ring)
        let bboxArea = max(0.0, bounds.max.x - bounds.min.x) * max(0.0, bounds.max.y - bounds.min.y)
        if absArea > bestAbsArea ||
            (absArea == bestAbsArea && bboxArea > bestBBoxArea) ||
            (absArea == bestAbsArea && bboxArea == bestBBoxArea && index < bestIndex) {
            bestIndex = index
            bestAbsArea = absArea
            bestBBoxArea = bboxArea
        }
    }
    return (bestIndex, rings[bestIndex], bestAbsArea, bestBBoxArea)
}
