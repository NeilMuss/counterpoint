import Foundation
import CP2Geometry
import CP2Skeleton
import CP2ResolveOverlap
import CP2Domain

struct SweepResult {
    var segmentsUsed: [Segment2]
    var rings: [[Vec2]]
    var ring: [Vec2]
    var finalContour: FinalContour
    var envelopeIndex: Int
    var envelopeAbsArea: Double
    var envelopeBBoxMin: Vec2
    var envelopeBBoxMax: Vec2
    var envelopeSelfX: Int
    var resolveFacesCount: Int
    var resolvedFaces: [FaceLoop]?
    var planarizeStats: SegmentPlanarizerStats?
    var planarizationHeatmap: PlanarizationHeatmapDebug?
    var soupLaneSegments: Int
    var soupPerimeterSegments: Int
    var soupTotalSegments: Int
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
    var penStamps: PenStampsDebug?
    var ringTopology: RingTopologyDebug?
    var resolveSelfOverlap: ResolveSelfOverlapDebug?
    var ringSelfXHit: RingSelfXHitDebug?
}

enum FinalContourProvenance: Equatable, Sendable {
    case tracedRing(index: Int)
    case resolvedFace(faceId: Int)
    case none
}

struct FinalContour: Equatable, Sendable {
    let points: [Vec2]
    let absArea: Double
    let bboxMin: Vec2
    let bboxMax: Vec2
    let selfX: Int
    let reason: String
    let provenance: FinalContourProvenance
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

private func makeSoupNeighborhoodEvent(_ report: SoupNeighborhoodReport, label: String) -> TraceEvent {
    let nodes = report.nodes.map { node in
        let edges = node.edges.map { edge in
            TraceSoupNeighborhoodEdge(
                toKeyX: edge.toKey.x,
                toKeyY: edge.toKey.y,
                toPos: edge.toPos,
                len: edge.len,
                dir: edge.dir,
                sourceDescription: edge.source.description,
                segmentIndex: edge.segmentIndex
            )
        }
        return TraceSoupNeighborhoodNode(
            keyX: node.key.x,
            keyY: node.key.y,
            pos: node.pos,
            degree: node.degree,
            edges: edges
        )
    }
    let collisions = report.collisions.map { collision in
        TraceSoupNeighborhoodCollision(
            keyX: collision.key.x,
            keyY: collision.key.y,
            positions: collision.positions
        )
    }
    let payload = TraceSoupNeighborhood(
        label: label,
        center: report.center,
        radius: report.radius,
        nodes: nodes,
        collisions: collisions
    )
    return .soupNeighborhood(payload)
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

private struct EnvelopeCandidate {
    let index: Int
    let ring: [Vec2]
    let absArea: Double
    let bboxMin: Vec2
    let bboxMax: Vec2
    let selfX: Int
}

private func selectEnvelopeCandidate(rings: [[Vec2]]) -> EnvelopeCandidate? {
    guard !rings.isEmpty else { return nil }
    var bestIndex = 0
    var bestAbsArea = -Double.greatestFiniteMagnitude
    var bestBBoxArea = -Double.greatestFiniteMagnitude
    var bestMin = Vec2(0, 0)
    var bestMax = Vec2(0, 0)
    var bestSelfX = 0
    for (index, ring) in rings.enumerated() {
        let absArea = abs(signedArea(ring))
        let bounds = ringBounds(ring)
        let bboxArea = max(0.0, bounds.max.x - bounds.min.x) * max(0.0, bounds.max.y - bounds.min.y)
        let selfX = ringSelfIntersectionCount(ring)
        if absArea > bestAbsArea ||
            (absArea == bestAbsArea && bboxArea > bestBBoxArea) ||
            (absArea == bestAbsArea && bboxArea == bestBBoxArea && index < bestIndex) {
            bestIndex = index
            bestAbsArea = absArea
            bestBBoxArea = bboxArea
            bestMin = bounds.min
            bestMax = bounds.max
            bestSelfX = selfX
        }
    }
    return EnvelopeCandidate(index: bestIndex, ring: rings[bestIndex], absArea: bestAbsArea, bboxMin: bestMin, bboxMax: bestMax, selfX: bestSelfX)
}

private func selectOuterFace(faces: [FaceLoop]) -> FaceLoop? {
    guard !faces.isEmpty else { return nil }
    var best: FaceLoop? = nil
    var bestAbsArea = -Double.greatestFiniteMagnitude
    var bestBBoxArea = -Double.greatestFiniteMagnitude
    var bestFaceId = Int.max
    for face in faces {
        let absArea = abs(face.area)
        let bounds = ringBounds(face.boundary)
        let bboxArea = max(0.0, bounds.max.x - bounds.min.x) * max(0.0, bounds.max.y - bounds.min.y)
        if absArea > bestAbsArea ||
            (absArea == bestAbsArea && bboxArea > bestBBoxArea) ||
            (absArea == bestAbsArea && bboxArea == bestBBoxArea && face.faceId < bestFaceId) {
            bestAbsArea = absArea
            bestBBoxArea = bboxArea
            bestFaceId = face.faceId
            best = face
        }
    }
    return best
}

func buildSoup(
    path: SkeletonPath,
    plan: SweepPlan,
    options: CLIOptions,
    capNamespace: String,
    startCap: CapStyle,
    endCap: CapStyle,
    traceSink: TraceSink?
) -> SoupBuildResult {
    var capturedSampling: SamplingResult? = nil
    var capEndpointsDebug: CapEndpointsDebug? = nil
    var capFillets: [CapFilletDebug] = []
    var capBoundaryDebugs: [CapBoundaryDebug] = []
    var capPlaneDebugs: [CapPlaneDebug] = []
    var railDebugSummary: RailDebugSummary? = nil
    var railFrames: [RailSampleFrame]? = nil
    var railCornerDebug: RailCornerDebug? = nil
    var penStamps: PenStampsDebug? = nil
    let wantsRailFrames = options.debugDumpRailFrames || options.debugRailInvariants || options.debugDumpRailEndpoints
    let wantsRailCorner = options.debugDumpRailCorners
    let wantsPenStamps = options.debugPenStamps && options.penShape == .rectCorners

    let segments: [Segment2] = {
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
                debugPenStamps: wantsPenStamps ? { penStamps = $0 } : nil,
                debugCapFillet: {
                    capFillets.append($0)
                    if options.debugDumpCapEndpoints || options.debugSweep {
                        let info = $0
                        if info.success {
                            traceSink?.emit(.capFilletSuccess(TraceCapFilletSuccess(
                                kind: info.kind,
                                side: info.side,
                                radius: info.radius,
                                theta: info.theta,
                                d: info.d,
                                corner: info.corner,
                                p: info.p,
                                q: info.q
                            )))
                        } else {
                            let reason = info.failureReason ?? "unknown"
                            traceSink?.emit(.capFilletFailure(TraceCapFilletFailure(
                                kind: info.kind,
                                side: info.side,
                                radius: info.radius,
                                reason: reason
                            )))
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
            debugPenStamps: wantsPenStamps ? { penStamps = $0 } : nil,
            debugCapFillet: {
                capFillets.append($0)
                if options.debugDumpCapEndpoints || options.debugSweep {
                    let info = $0
                    if info.success {
                        traceSink?.emit(.capFilletSuccess(TraceCapFilletSuccess(
                            kind: info.kind,
                            side: info.side,
                            radius: info.radius,
                            theta: info.theta,
                            d: info.d,
                            corner: info.corner,
                            p: info.p,
                            q: info.q
                        )))
                    } else {
                        let reason = info.failureReason ?? "unknown"
                        traceSink?.emit(.capFilletFailure(TraceCapFilletFailure(
                            kind: info.kind,
                            side: info.side,
                            radius: info.radius,
                            reason: reason
                        )))
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
    }()

    var soupLaneSegments = 0
    var soupPerimeterSegments = 0
    for seg in segments {
        switch seg.source {
        case .penStrip:
            soupLaneSegments += 1
        case .penCap:
            soupPerimeterSegments += 1
        default:
            break
        }
    }
    let soupTotalSegments = segments.count

    if let center = options.debugSoupNeighborhoodCenter {
        let report = computeSoupNeighborhood(
            segments: segments,
            eps: 1.0e-6,
            center: center,
            radius: options.debugSoupNeighborhoodRadius
        )
        traceSink?.emit(makeSoupNeighborhoodEvent(report, label: "manual"))
    }

    return SoupBuildResult(
        segments: segments,
        soupLaneSegments: soupLaneSegments,
        soupPerimeterSegments: soupPerimeterSegments,
        soupTotalSegments: soupTotalSegments,
        sampling: capturedSampling,
        traceSteps: [],
        capEndpointsDebug: capEndpointsDebug,
        capFillets: capFillets,
        capBoundaryDebugs: capBoundaryDebugs,
        capPlaneDebugs: capPlaneDebugs,
        railDebugSummary: railDebugSummary,
        railFrames: railFrames,
        railCornerDebug: railCornerDebug,
        penStamps: penStamps
    )
}

func planarizeAndExtractFaces(
    segments: [Segment2],
    debugStep: ((TraceStepInfo) -> Void)?
) -> PlanarizationResult {
    let policy = DeterminismPolicy(eps: 1.0e-6, stableSort: .lexicographicXYThenIndex)
    let segmentPairs = segments.map { ($0.a, $0.b) }
    let planar = SegmentPlanarizer.planarize(segments: segmentPairs, policy: policy, sourceRingId: ArtifactID("soupSegments"), includeDebug: false)
    let heatmap = buildPlanarizationHeatmap(artifact: planar.artifact)
    guard !planar.artifact.segments.isEmpty else {
        return PlanarizationResult(
            planarizeStats: planar.stats,
            planarizationHeatmap: heatmap,
            planarSegments: [],
            rings: [],
            faces: []
        )
    }
    let planarSegments = planar.artifact.segments.map { seg in
        Segment2(planar.artifact.vertices[seg.a], planar.artifact.vertices[seg.b], source: .unknown("planarized"))
    }
    let rings = traceLoops(
        segments: planarSegments,
        eps: 1.0e-6,
        debugStep: debugStep
    )
    let (graphArtifact, graphIndex) = HalfEdgeGraphBuilder.build(planar: planar.artifact, includeDebug: false)
    let faceResult = FaceEnumerator.enumerate(graph: graphIndex, policy: policy, graphId: graphArtifact.id, includeDebug: false)
    return PlanarizationResult(
        planarizeStats: planar.stats,
        planarizationHeatmap: heatmap,
        planarSegments: planarSegments,
        rings: rings,
        faces: faceResult.faceSet.faces
    )
}

func runSweep(
    path: SkeletonPath,
    plan: SweepPlan,
    options: CLIOptions,
    capNamespace: String,
    startCap: CapStyle,
    endCap: CapStyle,
    traceSink: TraceSink? = nil
) -> SweepResult {
    let soup = buildSoup(
        path: path,
        plan: plan,
        options: options,
        capNamespace: capNamespace,
        startCap: startCap,
        endCap: endCap,
        traceSink: traceSink
    )
    var traceSteps: [TraceStepInfo] = soup.traceSteps
    let segmentsUsed = soup.segments

    if capNamespace == "fillet", case .fillet = endCap {
        let endLeft = soup.capFillets.first { $0.kind == "end" && $0.side == "left" && $0.success }
        let endRight = soup.capFillets.first { $0.kind == "end" && $0.side == "right" && $0.success }
        if let left = endLeft, let right = endRight {
            let midA = right.p
            let midB = left.q
            var midMatches: [Segment2] = []
            for seg in segmentsUsed {
                let direct = Epsilon.approxEqual(seg.a, midA) && Epsilon.approxEqual(seg.b, midB)
                let reverse = Epsilon.approxEqual(seg.a, midB) && Epsilon.approxEqual(seg.b, midA)
                if direct || reverse {
                    midMatches.append(seg)
                }
            }
            traceSink?.emit(.capFilletMidSegmentFound(TraceCapFilletMidSegment(
                count: midMatches.count,
                midA: midA,
                midB: midB
            )))
            for seg in midMatches {
                let len = (seg.a - seg.b).length
                traceSink?.emit(.capFilletMidSegmentDetail(TraceCapFilletSegmentDetail(
                    len: len,
                    a: seg.a,
                    b: seg.b,
                    sourceDescription: seg.source.description
                )))
            }
            let bypassA = left.corner
            let bypassB = right.corner
            var bypassMatches: [Segment2] = []
            for seg in segmentsUsed {
                let direct = Epsilon.approxEqual(seg.a, bypassA) && Epsilon.approxEqual(seg.b, bypassB)
                let reverse = Epsilon.approxEqual(seg.a, bypassB) && Epsilon.approxEqual(seg.b, bypassA)
                if direct || reverse {
                    bypassMatches.append(seg)
                }
            }
            traceSink?.emit(.capFilletBypassEdgesFound(TraceCapFilletBypass(
                count: bypassMatches.count,
                cornerA: bypassA,
                cornerB: bypassB
            )))
            for seg in bypassMatches {
                let len = (seg.a - seg.b).length
                traceSink?.emit(.capFilletBypassDetail(TraceCapFilletSegmentDetail(
                    len: len,
                    a: seg.a,
                    b: seg.b,
                    sourceDescription: seg.source.description
                )))
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
                traceSink?.emit(.capFilletConnectivity(ok: ok))
            }
            let eps = 1.0e-6
            var touchingX: [Segment2] = []
            for seg in segmentsUsed {
                let aNear = abs(seg.a.x - 200.0) <= eps
                let bNear = abs(seg.b.x - 200.0) <= eps
                if aNear || bNear {
                    touchingX.append(seg)
                }
            }
            traceSink?.emit(.capFilletXTouch(TraceCapFilletXTouch(
                count: touchingX.count,
                x: 200.0,
                eps: eps
            )))
            for seg in touchingX {
                let len = (seg.a - seg.b).length
                traceSink?.emit(.capFilletXTouchDetail(TraceCapFilletSegmentDetail(
                    len: len,
                    a: seg.a,
                    b: seg.b,
                    sourceDescription: seg.source.description
                )))
            }
        }
    }

    let rawRings = traceLoops(
        segments: segmentsUsed,
        eps: 1.0e-6,
        debugStep: options.debugTraceJumpStep ? { traceSteps.append($0) } : nil
    )
    var rings = rawRings
    var ring: [Vec2] = []
    var finalContour = FinalContour(points: [], absArea: 0.0, bboxMin: Vec2(0, 0), bboxMax: Vec2(0, 0), selfX: 0, reason: "none", provenance: .none)
    var envelopeIndex = -1
    var envelopeAbsArea = 0.0
    var envelopeBBoxMin = Vec2(0, 0)
    var envelopeBBoxMax = Vec2(0, 0)
    var envelopeSelfX = 0
    var resolveFacesCount = 0
    var resolvedFaces: [FaceLoop]? = nil
    var planarizeStats: SegmentPlanarizerStats? = nil
    var planarizationHeatmap: PlanarizationHeatmapDebug? = nil

    let envelope = selectEnvelopeCandidate(rings: rawRings)
    if let envelope {
        ring = envelope.ring
        envelopeIndex = envelope.index
        envelopeAbsArea = envelope.absArea
        envelopeBBoxMin = envelope.bboxMin
        envelopeBBoxMax = envelope.bboxMax
        envelopeSelfX = envelope.selfX
        let reason = envelope.selfX == 0 ? "max-area-simple" : "max-area"
        finalContour = FinalContour(
            points: envelope.ring,
            absArea: envelope.absArea,
            bboxMin: envelope.bboxMin,
            bboxMax: envelope.bboxMax,
            selfX: envelope.selfX,
            reason: reason,
            provenance: .tracedRing(index: envelope.index)
        )
    }

    var resolveSelfOverlapDebug: ResolveSelfOverlapDebug? = nil
    let resolvedPenShape: PenShape = {
        switch options.penShape {
        case .auto:
            return plan.angleMode == .relative ? .railsOnly : .rectCorners
        default:
            return options.penShape
        }
    }()

    if resolvedPenShape == .rectCorners, !segmentsUsed.isEmpty {
        let planar = planarizeAndExtractFaces(
            segments: segmentsUsed,
            debugStep: options.debugTraceJumpStep ? { traceSteps.append($0) } : nil
        )
        planarizeStats = planar.planarizeStats
        planarizationHeatmap = planar.planarizationHeatmap
        if !planar.planarSegments.isEmpty {
            rings = planar.rings
            resolvedFaces = planar.faces
            if let outer = selectOuterFace(faces: planar.faces) {
                let bounds = ringBounds(outer.boundary)
                let selfX = ringSelfIntersectionCount(outer.boundary)
                finalContour = FinalContour(
                    points: outer.boundary,
                    absArea: abs(outer.area),
                    bboxMin: bounds.min,
                    bboxMax: bounds.max,
                    selfX: selfX,
                    reason: "planarized-outer-face",
                    provenance: .resolvedFace(faceId: outer.faceId)
                )
                ring = outer.boundary
            }
        }
    }

    let envelopeNeedsResolve = envelopeSelfX > 0
    let allowAutoResolve = resolvedPenShape == .rectCorners
    let shouldResolve = options.resolveSelfOverlap || ((finalContour.provenance == .none) && (allowAutoResolve && envelopeNeedsResolve))
    if shouldResolve, !ring.isEmpty {
        let before = ringSelfIntersections(ring: ring, ringIndex: 0, eps: 1.0e-6).count
        let selectionPolicy: ResolveSelfOverlapSelectionPolicy = .lineGalleryMaxAbsAreaFace(minAreaRatio: 0.0)
        let policy = DeterminismPolicy(eps: 1.0e-6, stableSort: .lexicographicXYThenIndex)
        let (resolved, artifacts) = ResolveSelfOverlapUseCase.run(
            ring: ring,
            policy: policy,
            selectionPolicy: selectionPolicy,
            includeDebug: false
        )
        resolveFacesCount = artifacts?.faceSet.faces.count ?? 0
        resolvedFaces = artifacts?.faceSet.faces
        if resolved.success {
            let after = ringSelfIntersections(ring: resolved.ring, ringIndex: 0, eps: 1.0e-6).count
            traceSink?.emit(.resolveSelfOverlap(TraceResolveSelfOverlap(
                enabledExplicit: options.resolveSelfOverlap,
                ringSelfXBefore: before,
                ringSelfXAfter: after,
                vertsBefore: ring.count,
                vertsAfter: resolved.ring.count
            )))
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
            finalContour = FinalContour(
                points: resolved.ring,
                absArea: abs(signedArea(resolved.ring)),
                bboxMin: bounds.min,
                bboxMax: bounds.max,
                selfX: after,
                reason: options.resolveSelfOverlap ? "resolved" : "resolved-outer-face",
                provenance: .resolvedFace(faceId: resolved.selectedFaceId)
            )
            ring = resolved.ring
        } else {
            traceSink?.emit(.resolveSelfOverlapFallback(reason: resolved.failureReason ?? "unknown"))
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
        traceSink?.emit(.ringTopoCount(count: rings.count))
        for info in ringInfos {
            traceSink?.emit(.ringTopoInfo(TraceRingTopoInfo(
                index: info.index,
                absArea: info.absArea,
                winding: info.winding,
                verts: info.verts
            )))
        }
        let grouped = Dictionary(grouping: intersections, by: { $0.ringIndex })
        for info in ringInfos {
            let hits = grouped[info.index] ?? []
            traceSink?.emit(.ringSelfXCount(ringIndex: info.index, count: hits.count))
            for hit in hits {
                traceSink?.emit(.ringSelfXHit(TraceRingSelfXHit(
                    ringIndex: hit.ringIndex,
                    i: hit.i,
                    j: hit.j,
                    point: hit.point
                )))
            }
        }
        for index in microRings {
            if let info = ringInfos.first(where: { $0.index == index }) {
                traceSink?.emit(.ringMicro(ringIndex: info.index, absArea: info.absArea))
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
                traceSink?.emit(.ringSelfXHitDetail(TraceRingSelfXHitDetail(
                    k: k,
                    ringIndex: hit.ringIndex,
                    i: hit.i,
                    j: hit.j,
                    point: hit.point,
                    a0: a0,
                    a1: a1,
                    b0: b0,
                    b1: b1
                )))
            }
        } else {
            traceSink?.emit(.ringSelfXHitOutOfRange(k: k, count: intersections.count))
        }
    }
    let glyphBounds = ring.isEmpty ? nil : ringBounds(ring)

    return SweepResult(
        segmentsUsed: segmentsUsed,
        rings: rings,
        ring: ring,
        finalContour: finalContour,
        envelopeIndex: envelopeIndex,
        envelopeAbsArea: envelopeAbsArea,
        envelopeBBoxMin: envelopeBBoxMin,
        envelopeBBoxMax: envelopeBBoxMax,
        envelopeSelfX: envelopeSelfX,
        resolveFacesCount: resolveFacesCount,
        resolvedFaces: resolvedFaces,
        planarizeStats: planarizeStats,
        planarizationHeatmap: planarizationHeatmap,
        soupLaneSegments: soup.soupLaneSegments,
        soupPerimeterSegments: soup.soupPerimeterSegments,
        soupTotalSegments: soup.soupTotalSegments,
        glyphBounds: glyphBounds,
        sampling: soup.sampling,
        traceSteps: traceSteps,
        capEndpointsDebug: soup.capEndpointsDebug,
        capFillets: soup.capFillets,
        capBoundaryDebugs: soup.capBoundaryDebugs,
        capPlaneDebugs: soup.capPlaneDebugs,
        railDebugSummary: soup.railDebugSummary,
        railFrames: soup.railFrames,
        railCornerDebug: soup.railCornerDebug,
        penStamps: soup.penStamps,
        ringTopology: ringTopology,
        resolveSelfOverlap: resolveSelfOverlapDebug,
        ringSelfXHit: ringSelfXHit
    )
}

private func selectFinalRing(rings: [[Vec2]]) -> (index: Int, ring: [Vec2], absArea: Double, bboxArea: Double, reason: String) {
    var candidates: [(index: Int, ring: [Vec2], absArea: Double, bboxArea: Double, selfX: Int)] = []
    candidates.reserveCapacity(rings.count)
    for (index, ring) in rings.enumerated() {
        let absArea = abs(signedArea(ring))
        let bounds = ringBounds(ring)
        let bboxArea = max(0.0, bounds.max.x - bounds.min.x) * max(0.0, bounds.max.y - bounds.min.y)
        let selfX = ringSelfIntersectionCount(ring)
        candidates.append((index, ring, absArea, bboxArea, selfX))
    }
    let preferred: [(index: Int, ring: [Vec2], absArea: Double, bboxArea: Double, selfX: Int)]
    if candidates.contains(where: { $0.selfX == 0 }) {
        preferred = candidates.filter { $0.selfX == 0 }
    } else {
        preferred = candidates
    }
    let reason = preferred.count < candidates.count ? "simple-first" : "max-area"
    let best = preferred.max { lhs, rhs in
        if lhs.absArea == rhs.absArea {
            if lhs.bboxArea == rhs.bboxArea { return lhs.index < rhs.index }
            return lhs.bboxArea < rhs.bboxArea
        }
        return lhs.absArea < rhs.absArea
    } ?? candidates[0]
    return (best.index, best.ring, best.absArea, best.bboxArea, reason)
}
