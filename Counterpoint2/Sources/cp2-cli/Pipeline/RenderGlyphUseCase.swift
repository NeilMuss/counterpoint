import Foundation
import CP2Domain
import CP2Geometry
import CP2Skeleton
import CP2ResolveOverlap

struct RenderGlyphUseCase {
    static func render(
        options: CLIOptions,
        spec: CP2Spec?,
        warnHandler: @escaping (String) -> Void,
        traceSink: TraceSink? = nil
    ) throws -> RenderGlyphModel {
        var options = options
        if options.viewCenterlineOnly {
            options.debugCenterline = true
        }
        if options.debugHeartlineResolve {
            dumpHeartlineResolve(specPath: options.specPath, spec: spec, options: options)
        }

        // 1. Resolve Settings
        var (renderSettings, referenceLayer) = resolveEffectiveSettings(options: options, spec: spec)
        if options.viewCenterlineOnly {
            referenceLayer = nil
        }

        // 2. Resolve Strokes
        let (exampleName, resolvedStrokes) = try resolveEffectiveStrokes(
            options: options,
            spec: spec,
            warn: warnHandler
        )
        let primaryStroke = resolvedStrokes.first!

        // 3. Build Parameterization & Plan per Stroke
        typealias StrokeOutput = (
            stroke: ResolvedStroke,
            pathParam: SkeletonPathParameterization,
            plan: SweepPlan,
            result: SweepResult,
            joinGTs: [Double]
        )
        var strokeOutputs: [StrokeOutput] = []
        var combinedGlyphBounds: AABB? = nil

        for (index, stroke) in resolvedStrokes.enumerated() {
            let path = stroke.path
            let pathParam = SkeletonPathParameterization(path: path, samplesPerSegment: options.arcSamples)

            if index == 0, (options.verbose || options.debugParam) {
                print("param segments=\(path.segments.count) totalLength=\(String(format: "%.6f", pathParam.totalLength)) arcSamples=\(options.arcSamples)")
                let lengths = path.segments.map { ArcLengthParameterization(path: SkeletonPath($0), samplesPerSegment: options.arcSamples).totalLength }
                print("param segmentLengths=[\(lengths.map { String(format: "%.6f", $0) }.joined(separator: ", "))]")
            }

            var joinGTs: [Double] = []
            if options.debugSweep, path.segments.count > 1 {
                let lengths = path.segments.map { ArcLengthParameterization(path: SkeletonPath($0), samplesPerSegment: options.arcSamples).totalLength }
                let total = max(Epsilon.defaultValue, lengths.reduce(0.0, +))
                var accumulated = 0.0
                for i in 0..<lengths.count-1 {
                    accumulated += lengths[i]
                    joinGTs.append(accumulated / total)
                }
            }

            if index == 0, options.debugParam {
                let count = max(1, options.probeCount)
                let probes = count == 1 ? [0.0] : (0..<count).map { Double($0) / Double(count - 1) }
                for gt in probes {
                    let mapping = pathParam.map(globalT: gt)
                    let pos = pathParam.position(globalT: gt)
                    print(String(format: "param probe gt=%.4f seg=%d u=%.6f pos=(%.6f,%.6f)", gt, mapping.segmentIndex, mapping.localU, pos.x, pos.y))
                }
            }

            let provider: StrokeParamProvider
            if let params = stroke.params {
                provider = SpecParamProvider(params: params)
            } else {
                provider = ExampleParamProvider()
            }
            let funcs = provider.makeParamFuncs(options: options, exampleName: exampleName, sweepWidth: 20.0)

            let plan = makeSweepPlan(
                options: options,
                funcs: funcs,
                baselineWidth: 20.0,
                sweepWidth: 20.0,
                sweepHeight: 10.0,
                sweepSampleCount: 64
            )

            if index == 0, (options.verbose || options.debugSVG) {
                if options.adaptiveSampling {
                    print(String(format: "samplingMode=adaptive flatnessEps=%.6f maxDepth=%d maxSamples=%d", options.flatnessEps, options.maxDepth, options.maxSamples))
                } else {
                    print(String(format: "samplingMode=fixed sampleCount=%d", plan.sweepSampleCount))
                }
            }

            if index == 0, options.debugParams {
                let count = max(1, options.probeCount)
                let probes = count == 1 ? [0.0] : (0..<count).map { Double($0) / Double(count - 1) }
                for gt in probes {
                    let styleAtGT: (Double) -> SweepStyle = { t in
                        return SweepStyle(
                            width: plan.scaledWidthAtT(t),
                            widthLeft: plan.scaledWidthLeftAtT(t),
                            widthRight: plan.scaledWidthRightAtT(t),
                            height: plan.sweepHeight,
                            angle: plan.thetaAtT(t),
                            offset: plan.offsetAtT(t),
                            angleIsRelative: plan.angleMode == .relative
                        )
                    }
                    let frame = railSampleFrameAtGlobalT(
                        param: pathParam,
                        warpGT: plan.warpT,
                        styleAtGT: styleAtGT,
                        gt: gt,
                        index: -1
                    )
                    let thetaDeg = plan.thetaAtT(gt) * 180.0 / Double.pi
                    let widthLegacy = plan.widthAtT(gt)
                    let widthLeft = plan.scaledWidthLeftAtT(gt)
                    let widthRight = plan.scaledWidthRightAtT(gt)
                    let widthLeftAlpha = plan.widthLeftSegmentAlphaAtT(gt)
                    let widthRightAlpha = plan.widthRightSegmentAlphaAtT(gt)
                    let widthSum = widthLeft + widthRight
                    let offset = plan.offsetAtT(gt)
                    let dist = (frame.right - frame.left).length
                    print(String(format: "paramEval gt=%.2f C=(%.6f,%.6f) T=(%.6f,%.6f) N=(%.6f,%.6f) thetaRawDeg=%.6f thetaEffectiveRad=%.6f widthLegacy=%.6f widthLeft=%.6f widthRight=%.6f segAlphaL=%.6f segAlphaR=%.6f sumWidth=%.6f offset=%.6f vRot=(%.6f,%.6f) L=(%.6f,%.6f) R=(%.6f,%.6f) dist=%.6f", gt, frame.center.x, frame.center.y, frame.tangent.x, frame.tangent.y, frame.normal.x, frame.normal.y, thetaDeg, frame.effectiveAngle, widthLegacy, widthLeft, widthRight, widthLeftAlpha, widthRightAlpha, widthSum, offset, frame.crossAxis.x, frame.crossAxis.y, frame.left.x, frame.left.y, frame.right.x, frame.right.y, dist))
                }
            }

            // 4. Run Sweep
            let capNamespace = stroke.id ?? stroke.inkName ?? "stroke-\(index)"
            let result = runSweep(
                path: path,
                plan: plan,
                options: options,
                capNamespace: capNamespace,
                startCap: stroke.startCap,
                endCap: stroke.endCap,
                traceSink: traceSink
            )
            strokeOutputs.append((stroke: stroke, pathParam: pathParam, plan: plan, result: result, joinGTs: joinGTs))
            if let glyphBounds = result.glyphBounds {
                combinedGlyphBounds = combinedGlyphBounds?.union(glyphBounds) ?? glyphBounds
            }
        }
        let primaryOutput = strokeOutputs[0]
        let inkPrimitive = primaryStroke.inkPrimitive
        let resolvedHeartline = primaryStroke.resolvedHeartline
        let path = primaryStroke.path
        let pathParam = primaryOutput.pathParam
        let plan = primaryOutput.plan
        let result = primaryOutput.result
        let joinGTs = primaryOutput.joinGTs

        let strokeEntries: [StrokeInkEntry] = strokeOutputs.enumerated().compactMap { index, output in
            let points = output.result.finalContour.points
            guard !points.isEmpty else { return nil }
            return StrokeInkEntry(index: index, strokeId: output.stroke.id, inkName: output.stroke.inkName, ring: normalizedRing(points, clockwise: true))
        }
        let inkRingsNormalized: [[Vec2]] = strokeEntries.map { $0.ring }
        var counterRingsNormalized: [CounterRingEntry] = []
        if let counters = spec?.counters, !options.viewCenterlineOnly {
            let counterOutputs = strokeOutputs.map { (stroke: $0.stroke, pathParam: $0.pathParam, plan: $0.plan) }
            let rawCounters = counterRings(counters: counters, strokeOutputs: counterOutputs, options: options, warn: warnHandler)
            counterRingsNormalized = rawCounters
                .filter { !$0.ring.isEmpty }
                .map { CounterRingEntry(ring: normalizedRing($0.ring, clockwise: false), appliesTo: $0.appliesTo) }
            for (index, ring) in counterRingsNormalized.enumerated() {
                if !counterIsInsideInk(counter: ring.ring, inkRings: inkRingsNormalized) {
                    warnHandler("counter ring \(index) is not inside ink")
                }
            }
        }

        // 5. Diagnostics
        emitSweepDiagnostics(
            options: options,
            path: path,
            pathParam: pathParam,
            plan: plan,
            result: result,
            joinGTs: joinGTs
        )

        if options.debugSoupPreRepair {
            let stats = computeSoupDegreeStats(segments: result.segmentsUsed, eps: 1.0e-6)
            print(String(format: "soupPreRepair nodes=%d edges=%d", stats.nodeCount, stats.edgeCount))
            print("soupPreRepair degreeHistogram \(formatDegreeHistogram(stats.degreeHistogram))")
            print(String(format: "soupPreRepair anomalies count=%d (showing up to 200)", stats.anomalies.count))
            for anomaly in stats.anomalies {
                let deg = anomaly.outCount
                print(String(format: "  node key=(%d,%d) pos=(%.6f,%.6f) out=%d in=%d deg=%d", anomaly.key.x, anomaly.key.y, anomaly.pos.x, anomaly.pos.y, anomaly.outCount, anomaly.inCount, deg))
                for (index, edge) in anomaly.outNeighbors.enumerated() {
                    print(String(format: "    out[%d] -> key=(%d,%d) pos=(%.6f,%.6f) len=%.6f src=%@", index, edge.to.x, edge.to.y, edge.toPos.x, edge.toPos.y, edge.len, edge.source.description))
                }
                for (index, edge) in anomaly.inNeighbors.enumerated() {
                    print(String(format: "    in[%d]  -> key=(%d,%d) pos=(%.6f,%.6f) len=%.6f src=%@", index, edge.to.x, edge.to.y, edge.toPos.x, edge.toPos.y, edge.len, edge.source.description))
                }
            }
        }

        if options.adaptiveSampling, let sampling = result.sampling, sampling.stats.forcedStops > 0 {
            var sawMaxSamples = false
            var sawMaxDepth = false
            for decision in sampling.trace where decision.action == .forcedStop {
                for reason in decision.reasons {
                    switch reason {
                    case .maxSamplesHit:
                        sawMaxSamples = true
                    case .maxDepthHit:
                        sawMaxDepth = true
                    default:
                        continue
                    }
                }
            }
            let reason: String
            if sawMaxSamples {
                reason = "maxSamples"
            } else if sawMaxDepth {
                reason = "maxDepth"
            } else {
                reason = "unknown"
            }
            print(String(format: "adaptiveSampling capped: reason=%@ producedSamples=%d requestedEps=%.6f", reason, sampling.ts.count, options.flatnessEps))
        }

        // 6. Debug Overlay
        let soloWhy = options.debugSoloWhy
        let wantsSamplingWhy = soloWhy || options.debugSamplingWhy
        let soloMaxDots = 200
        let soloLabelDots = 12
        var overlays: [DebugOverlay] = []
        var capFilletOverlay: DebugOverlay? = nil
        let centerlineInkSegments: [InkSegment]? = {
            guard options.viewCenterlineOnly, let inkPrimitive else { return nil }
            switch inkPrimitive {
            case .line(let line): return [.line(line)]
            case .cubic(let cubic): return [.cubic(cubic)]
            case .path(let path): return path.segments
            case .heartline: return nil
            }
        }()
        if options.viewCenterlineOnly {
            overlays.append(makeCenterlineDebugOverlay(options: options, path: path, pathParam: pathParam, plan: plan, inkSegments: centerlineInkSegments))
            if !primaryOutput.result.capFillets.isEmpty {
                capFilletOverlay = debugOverlayForCapFillets(primaryOutput.result.capFillets, steps: 32)
            }
        } else if !soloWhy && (options.debugSVG || options.debugCenterline || options.debugInkControls) {
            if let inkPrimitive, (options.debugCenterline || options.debugInkControls) {
                switch inkPrimitive {
                case .path(let inkPath): overlays.append(debugOverlayForInkPath(inkPath, steps: 64))
                case .heartline: if let resolved = resolvedHeartline { overlays.append(debugOverlayForHeartline(resolved, steps: 64)) }
                default: overlays.append(debugOverlayForInk(inkPrimitive, steps: 64))
                }
                if options.debugCenterline, !primaryOutput.result.capFillets.isEmpty {
                    capFilletOverlay = debugOverlayForCapFillets(primaryOutput.result.capFillets, steps: 32)
                }
            } else {
                overlays.append(makeCenterlineDebugOverlay(options: options, path: path, pathParam: pathParam, plan: plan))
            }
        }
        if !soloWhy && options.debugKeyframes && !options.viewCenterlineOnly {
            if let params = primaryStroke.params {
                overlays.append(makeKeyframesOverlay(params: params, pathParam: pathParam, plan: plan, labels: options.keyframesLabels))
            } else {
                overlays.append(DebugOverlay(svg: "<g id=\"debug-keyframes\"></g>", bounds: AABB.empty))
            }
        }
        if !soloWhy && options.debugParamsPlot && !options.viewCenterlineOnly {
            if let params = primaryStroke.params {
                overlays.append(makeParamsPlotOverlay(params: params, plan: plan, glyphBounds: result.glyphBounds))
            } else {
                overlays.append(DebugOverlay(svg: "<g id=\"debug-params-plot\"></g>", bounds: AABB.empty))
            }
        }
        if !soloWhy && options.debugCounters && !options.viewCenterlineOnly {
            if let counters = spec?.counters {
                overlays.append(debugOverlayForCounters(counters, steps: 64, warn: warnHandler))
            } else {
                overlays.append(DebugOverlay(svg: "<g id=\"debug-counters\"></g>", bounds: AABB.empty))
            }
        }
        if !soloWhy && options.debugPenStamps && !options.viewCenterlineOnly {
            if let penStamps = primaryOutput.result.penStamps {
                let selected = selectPenStamps(
                    stamps: penStamps.samples,
                    options: options
                )
                overlays.append(debugOverlayForPenStamps(
                    stamps: selected,
                    showVertices: options.debugPenStampsShowVertices,
                    showConnectors: options.debugPenStampsShowConnectors
                ))
            } else {
                overlays.append(DebugOverlay(svg: "<g id=\"debug-pen-stamps\"></g>", bounds: AABB.empty))
            }
        }
        if let capFilletOverlay {
            overlays.append(capFilletOverlay)
        }
        if options.debugCapBoundary {
            let debugCaps = strokeOutputs.flatMap { $0.result.capBoundaryDebugs }
            if !debugCaps.isEmpty {
                overlays.append(debugOverlayForCapBoundary(debugCaps))
            }
            let planeDebugs = strokeOutputs.flatMap { $0.result.capPlaneDebugs }
            if !planeDebugs.isEmpty {
                overlays.append(debugOverlayForCapPlane(planeDebugs))
            }
        }
        if options.debugAngleMode {
            overlays.append(debugOverlayForCrossAxis(
                pathParam: primaryOutput.pathParam,
                plan: primaryOutput.plan,
                sampling: primaryOutput.result.sampling,
                tickStride: 6,
                tickLength: 8.0
            ))
        }
        if options.debugRingTopology, let ringDebug = result.ringTopology, !options.viewCenterlineOnly {
            overlays.append(debugOverlayForRingTopology(rings: result.rings, debug: ringDebug))
        }
        if options.debugEnvelopeCandidateOutline, !options.viewCenterlineOnly {
            let candidate = (result.envelopeIndex >= 0 && result.envelopeIndex < result.rings.count) ? result.rings[result.envelopeIndex] : []
            overlays.append(debugOverlayForEnvelopeCandidateOutline(ring: candidate, ringIndex: result.envelopeIndex))
        }
        if options.debugResolvedFacesAll, let faces = result.resolvedFaces, !options.viewCenterlineOnly {
            let selectedFaceId: Int? = {
                if case let .resolvedFace(faceId) = result.finalContour.provenance {
                    return faceId
                }
                return nil
            }()
            overlays.append(debugOverlayForResolvedFacesAll(faces: faces, selectedFaceId: selectedFaceId))
        }
        if options.debugPlanarizationHeatmap, !options.viewCenterlineOnly {
            if let heatmap = result.planarizationHeatmap {
                overlays.append(debugOverlayForPlanarizationHeatmap(debug: heatmap))
            } else {
                overlays.append(DebugOverlay(svg: "<g id=\"debug-planarization-heatmap\"></g>", bounds: AABB.empty))
            }
        }
        if options.debugRingOutputOutline, !options.viewCenterlineOnly {
            overlays.append(debugOverlayForRingOutputOutline(ring: result.finalContour.points))
        }
        if options.debugRingOutputSelfX, !options.viewCenterlineOnly {
            overlays.append(debugOverlayForRingOutputSelfX(ring: result.finalContour.points))
        }
        if let ringSelfXHit = result.ringSelfXHit, !options.viewCenterlineOnly {
            overlays.append(debugOverlayForRingSelfXHit(debug: ringSelfXHit))
        }
        if spec?.example?.lowercased() == "cap_fillet_line", options.capFilletFixtureOverlays {
            for (index, output) in strokeOutputs.enumerated() {
                let label = output.stroke.id ?? "stroke-\(index)"
                overlays.append(overlayForRailsAndHeartline(pathParam: output.pathParam, plan: output.plan, sampleCount: 64, label: label))
                let fillets = output.result.capFillets.filter { $0.success }
                if !fillets.isEmpty {
                    overlays.append(overlayForCapFilletArcPoints(fillets: fillets, label: label))
                }
            }
            if let filletOutput = strokeOutputs.first(where: { ($0.stroke.id ?? "").lowercased() == "fillet" }) {
                let endLeft = filletOutput.result.capFillets.first { $0.kind == "end" && $0.side == "left" && $0.success }
                let endRight = filletOutput.result.capFillets.first { $0.kind == "end" && $0.side == "right" && $0.success }
                if let left = endLeft, let right = endRight {
                    let endpoint = (left.corner + right.corner) * 0.5
                    let radius = max(left.radius, right.radius)
                    let window = radius * 2.0
                    var printedAny = false
                    for (ringIndex, ring) in filletOutput.result.rings.enumerated() {
                        let near = ring.filter { ( $0 - endpoint).length <= window }
                        if !near.isEmpty {
                            let head = near.prefix(6).map { String(format: "(%.3f,%.3f)", $0.x, $0.y) }.joined(separator: ", ")
                            print("capFilletRingNeighborhood ring=\(ringIndex) center=(\(String(format: "%.3f", endpoint.x)),\(String(format: "%.3f", endpoint.y))) r=\(String(format: "%.3f", window)) count=\(near.count) head=[\(head)]")
                            printedAny = true
                        }
                    }
                    if !printedAny {
                        print("capFilletRingNeighborhood ring=none center=(\(String(format: "%.3f", endpoint.x)),\(String(format: "%.3f", endpoint.y))) r=\(String(format: "%.3f", window)) count=0")
                    }
                    let chordA = right.p
                    let chordB = left.q
                    let chordAText = String(format: "(%.3f,%.3f)", chordA.x, chordA.y)
                    let chordBText = String(format: "(%.3f,%.3f)", chordB.x, chordB.y)
                    let capEdges = filletOutput.result.segmentsUsed.filter { seg in
                        if case .capEndEdge = seg.source { return true }
                        return false
                    }
                    if !capEdges.isEmpty {
                        print("capFilletEndcapEdges count=\(capEdges.count) chordA=\(chordAText) chordB=\(chordBText)")
                        for (edgeIndex, seg) in capEdges.enumerated() {
                            let len = (seg.a - seg.b).length
                            print(String(format: "  edge[%d] len=%.6f a=(%.3f,%.3f) b=(%.3f,%.3f) src=%@", edgeIndex, len, seg.a.x, seg.a.y, seg.b.x, seg.b.y, seg.source.description))
                        }
                    }
                } else {
                    print("capFilletRingNeighborhood missing end fillets left=\(endLeft != nil) right=\(endRight != nil)")
                }
            }
        }
        let angleDebugMetrics = options.debugAngleMode ? emitAngleModeDebug(
            options: options,
            pathParam: primaryOutput.pathParam,
            plan: primaryOutput.plan,
            sampling: primaryOutput.result.sampling
        ) : nil
        if let angleDebugMetrics {
            overlays.append(debugOverlayForRailSeparation(
                pathParam: primaryOutput.pathParam,
                plan: primaryOutput.plan,
                sampling: primaryOutput.result.sampling,
                minIndex: angleDebugMetrics.minIndex,
                tickStride: 25
            ))
        }

        if options.debugSummary {
            let sampleCount = primaryOutput.result.sampling?.ts.count ?? 0
            let penShapeText: String = {
                switch options.penShape {
                case .railsOnly: return "railsOnly"
                case .rectCorners: return "rectCorners"
                case .auto: return "auto"
                }
            }()
            let hasCorners = options.penShape != .railsOnly && sampleCount > 0
            let stripPoints = hasCorners ? (sampleCount * 2 + 1) : 0
            let soupSegments = strokeOutputs.reduce(0) { $0 + $1.result.segmentsUsed.count }
            let soupPoints = strokeOutputs.reduce(0) { total, output in
                total + output.result.segmentsUsed.count * 2
            }
            let ringAreas = result.rings.map { abs(signedArea($0)) }
            let maxRingArea = ringAreas.max() ?? 0.0
            var minP = Vec2(0, 0)
            var maxP = Vec2(0, 0)
            if let ring = result.rings.max(by: { abs(signedArea($0)) < abs(signedArea($1)) }), let first = ring.first {
                minP = first
                maxP = first
                for p in ring {
                    minP = Vec2(min(minP.x, p.x), min(minP.y, p.y))
                    maxP = Vec2(max(maxP.x, p.x), max(maxP.y, p.y))
                }
            }
            print(String(format: "SAMPLES count=%d", sampleCount))
            print(String(format: "PEN_SHAPE shape=%@", penShapeText))
            if hasCorners {
                print(String(format: "CORNERS sampleCount=%d cornersPerSample=4", sampleCount))
                print(String(format: "STRIPS loops=4 pointsPerLoopMin=%d pointsPerLoopMax=%d", stripPoints, stripPoints))
                var minRectArea = Double.greatestFiniteMagnitude
                var minEdgeLen = Double.greatestFiniteMagnitude
                var minRectIndex: Int = 0
                var minCorners: PenCornerSet? = nil
                var twistCount = 0
                var minQuadArea = Double.greatestFiniteMagnitude
                var maxQuadArea = 0.0
                if let sampling = primaryOutput.result.sampling {
                    let pathParam = primaryOutput.pathParam
                    func styleAtGT(_ gt: Double) -> SweepStyle {
                        SweepStyle(
                            width: primaryOutput.plan.scaledWidthAtT(gt),
                            widthLeft: primaryOutput.plan.scaledWidthLeftAtT(gt),
                            widthRight: primaryOutput.plan.scaledWidthRightAtT(gt),
                            height: primaryOutput.plan.sweepHeight,
                            angle: primaryOutput.plan.thetaAtT(gt),
                            offset: primaryOutput.plan.offsetAtT(gt),
                            angleIsRelative: primaryOutput.plan.angleMode == .relative
                        )
                    }
                    var cornerSets: [PenCornerSet] = []
                    cornerSets.reserveCapacity(sampling.ts.count)
                    for (index, gt) in sampling.ts.enumerated() {
                        let frame = railSampleFrameAtGlobalT(
                            param: pathParam,
                            warpGT: primaryOutput.plan.warpT,
                            styleAtGT: styleAtGT,
                            gt: gt,
                            index: index
                        )
                        let style = styleAtGT(gt)
                        let halfWidth = style.width * 0.5
                        let wL = style.widthLeft > 0.0 ? style.widthLeft : halfWidth
                        let wR = style.widthRight > 0.0 ? style.widthRight : halfWidth
                        let corners = penCorners(
                            center: frame.center,
                            crossAxis: frame.crossAxis,
                            widthLeft: wL,
                            widthRight: wR,
                            height: style.height
                        )
                        cornerSets.append(corners)
                        let e1 = corners.c1 - corners.c0
                        let e2 = corners.c3 - corners.c0
                        let area = abs(e1.x * e2.y - e1.y * e2.x)
                        let edgeH = (corners.c0 - corners.c1).length
                        let edgeW = (corners.c0 - corners.c3).length
                        if area < minRectArea {
                            minRectArea = area
                            minEdgeLen = min(edgeH, edgeW)
                            minRectIndex = index
                            minCorners = corners
                        } else {
                            minEdgeLen = min(minEdgeLen, min(edgeH, edgeW))
                        }
                    }

                    func segmentsIntersect(_ a0: Vec2, _ a1: Vec2, _ b0: Vec2, _ b1: Vec2) -> Bool {
                        func orient(_ p: Vec2, _ q: Vec2, _ r: Vec2) -> Double {
                            (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x)
                        }
                        let o1 = orient(a0, a1, b0)
                        let o2 = orient(a0, a1, b1)
                        let o3 = orient(b0, b1, a0)
                        let o4 = orient(b0, b1, a1)
                        return (o1 > 0 && o2 < 0 || o1 < 0 && o2 > 0) && (o3 > 0 && o4 < 0 || o3 < 0 && o4 > 0)
                    }

                    if cornerSets.count >= 2 {
                        for i in 0..<(cornerSets.count - 1) {
                            let a = cornerSets[i]
                            let b = cornerSets[i + 1]
                            let current = [a.c0, a.c1, a.c2, a.c3]
                            let next = [b.c0, b.c1, b.c2, b.c3]
                            for k in 0..<4 {
                                let a0 = current[k]
                                let a1 = next[k]
                                let b0 = current[(k + 1) % 4]
                                let b1 = next[(k + 1) % 4]
                                if segmentsIntersect(a0, a1, b0, b1) {
                                    twistCount += 1
                                }
                                let quad = [a0, b0, b1, a1, a0]
                                var area = 0.0
                                for q in 0..<(quad.count - 1) {
                                    let p0 = quad[q]
                                    let p1 = quad[q + 1]
                                    area += (p0.x * p1.y - p1.x * p0.y)
                                }
                                let absArea = abs(area * 0.5)
                                minQuadArea = min(minQuadArea, absArea)
                                maxQuadArea = max(maxQuadArea, absArea)
                            }
                        }
                    }
                }
                if minRectArea.isFinite && minEdgeLen.isFinite {
                    print(String(format: "RECT minRectArea=%.6f minEdgeLen=%.6f", minRectArea, minEdgeLen))
                    if let corners = minCorners {
                        let widthEdges = [
                            (corners.c0 - corners.c3).length,
                            (corners.c1 - corners.c2).length
                        ]
                        let heightEdges = [
                            (corners.c0 - corners.c1).length,
                            (corners.c3 - corners.c2).length
                        ]
                        let cornerList = [
                            corners.c0, corners.c1, corners.c2, corners.c3
                        ].map { String(format: "(%.4f,%.4f)", $0.x, $0.y) }.joined(separator: ", ")
                        let widthList = widthEdges.map { String(format: "%.4f", $0) }.joined(separator: ", ")
                        let heightList = heightEdges.map { String(format: "%.4f", $0) }.joined(separator: ", ")
                        print("RECT_MIN k=\(minRectIndex) corners=[\(cornerList)] widthEdges=[\(widthList)] heightEdges=[\(heightList)]")
                    }
                    if minQuadArea.isFinite {
                        print(String(format: "STRIPS_DIAG minQuadArea=%.6f maxQuadArea=%.6f twistCount=%d", minQuadArea, maxQuadArea, twistCount))
                    } else {
                        print("STRIPS_DIAG minQuadArea=0.000000 maxQuadArea=0.000000 twistCount=0")
                    }
                } else {
                    print("RECT minRectArea=0.000000 minEdgeLen=0.000000")
                    print("STRIPS_DIAG minQuadArea=0.000000 maxQuadArea=0.000000 twistCount=0")
                }
            } else {
                print("CORNERS sampleCount=0 cornersPerSample=0")
                print("STRIPS loops=0 pointsPerLoopMin=0 pointsPerLoopMax=0")
                print("RECT minRectArea=0.000000 minEdgeLen=0.000000")
            }
            print(String(format: "SOUP chainCount=%d totalPoints=%d totalSegments=%d", soupSegments, soupPoints, soupSegments))
            if result.soupTotalSegments > 0 {
                print(String(format: "SOUP_EDGES laneSegments=%d perimeterSegments=%d totalSegments=%d", result.soupLaneSegments, result.soupPerimeterSegments, result.soupTotalSegments))
            }
            if let planarStats = result.planarizeStats {
                print(String(format: "PLANARIZE intersections=%d splitSegmentsBefore=%d after=%d", planarStats.intersections, planarStats.segments, planarStats.splitEdges))
            }
            if let heatmap = result.planarizationHeatmap {
                print(String(format: "PLANARIZE_HEATMAP vertices=%d maxDegree=%d avgDegree=%.3f", heatmap.vertices.count, heatmap.maxDegree, heatmap.avgDegree))
            }
            print(String(format: "RINGS count=%d maxAbsArea=%.6f bbox=(%.6f,%.6f,%.6f,%.6f)", result.rings.count, maxRingArea, minP.x, minP.y, maxP.x, maxP.y))
            if let faces = result.resolvedFaces, !faces.isEmpty {
                var bestFaceId = faces.first?.faceId ?? -1
                var bestAbsArea = -Double.greatestFiniteMagnitude
                var bestBBoxArea = -Double.greatestFiniteMagnitude
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
                    }
                }
                print(String(format: "FACES count=%d maxAbsAreaFaceId=%d maxAbsArea=%.6f", faces.count, bestFaceId, bestAbsArea))
            }
            if result.envelopeIndex >= 0 {
                print(String(format: "ENVELOPE_CANDIDATE ringIndex=%d absArea=%.6f bbox=(%.6f,%.6f,%.6f,%.6f) selfX=%d",
                             result.envelopeIndex,
                             result.envelopeAbsArea,
                             result.envelopeBBoxMin.x, result.envelopeBBoxMin.y, result.envelopeBBoxMax.x, result.envelopeBBoxMax.y,
                             result.envelopeSelfX))
            }
            for (index, ring) in result.rings.enumerated() {
                let absArea = abs(signedArea(ring))
                let bounds = ringBounds(ring)
                let selfX = ringSelfIntersectionCount(ring)
                print(String(format: "RING_DIAG ringIndex=%d absArea=%.6f bbox=(%.6f,%.6f,%.6f,%.6f) selfX=%d", index, absArea, bounds.min.x, bounds.min.y, bounds.max.x, bounds.max.y, selfX))
            }
            if let first = result.finalContour.points.first {
                var outMin = first
                var outMax = first
                for p in result.finalContour.points {
                    outMin = Vec2(min(outMin.x, p.x), min(outMin.y, p.y))
                    outMax = Vec2(max(outMax.x, p.x), max(outMax.y, p.y))
                }
                let outArea = abs(signedArea(result.finalContour.points))
                let outSelfX = result.finalContour.selfX
                switch result.finalContour.provenance {
                case .tracedRing(let index):
                    print(String(format: "OUTPUT ringIndex=%d absArea=%.6f bbox=(%.6f,%.6f,%.6f,%.6f) selfX=%d reason=%@", index, outArea, outMin.x, outMin.y, outMax.x, outMax.y, outSelfX, result.finalContour.reason))
                case .resolvedFace(let faceId):
                    print(String(format: "OUTPUT faceId=%d absArea=%.6f bbox=(%.6f,%.6f,%.6f,%.6f) selfX=%d reason=%@", faceId, outArea, outMin.x, outMin.y, outMax.x, outMax.y, outSelfX, result.finalContour.reason))
                case .none:
                    print(String(format: "OUTPUT ringIndex=-1 absArea=%.6f bbox=(%.6f,%.6f,%.6f,%.6f) selfX=%d reason=%@", outArea, outMin.x, outMin.y, outMax.x, outMax.y, outSelfX, result.finalContour.reason))
                }
                if result.resolveFacesCount > 0 {
                    print(String(format: "RESOLVE faces=%d", result.resolveFacesCount))
                }
                print(String(format: "OUTPUT_DIAG selfX=%d reason=%@", outSelfX, result.finalContour.reason))
            } else {
                print("OUTPUT ringIndex=-1 absArea=0.000000 bbox=(0.000000,0.000000,0.000000,0.000000) selfX=0 reason=none")
                print("OUTPUT_DIAG selfX=0 reason=none")
            }
            if let resolve = result.resolveSelfOverlap {
                print(String(format: "RESOLVE beforeRings=%d afterRings=%d", resolve.selfBefore, resolve.selfAfter))
                print(String(format: "FINAL selectedAbsArea=%.6f selectedBBox=(%.6f,%.6f,%.6f,%.6f) selectedFaceId=%d", resolve.selectedAbsArea, resolve.selectedBBoxMin.x, resolve.selectedBBoxMin.y, resolve.selectedBBoxMax.x, resolve.selectedBBoxMax.y, resolve.selectedFaceId))
            }
        }

        if !soloWhy && (options.debugRingSpine || options.debugRingJump || options.debugTraceJumpStep) && !options.viewCenterlineOnly {
            let ringJumps = (options.debugRingJump || options.debugTraceJumpStep) ? computeRingJumps(rings: result.rings) : []
            for (index, ring) in result.rings.enumerated() {
                let closure = ring.count > 1 ? (ring.last! - ring.first!).length : 0.0
                if options.debugRingSpine {
                    print(String(format: "ringSpine ring=%d verts=%d closure=%.6f", index, ring.count, closure))
                }
            }
            if options.debugRingJump {
                for jump in ringJumps {
                    print(String(format: "ringJump ring=%d verts=%d maxSegIndex=%d len=%.6f a=%d b=%d ax=%.6f ay=%.6f bx=%.6f by=%.6f", jump.ringIndex, jump.verts, jump.maxSegIndex, jump.length, jump.aIndex, jump.bIndex, jump.a.x, jump.a.y, jump.b.x, jump.b.y))
                }
            }
            if options.debugTraceJumpStep {
                print(String(format: "keyQuant eps=%.6g method=round", 1.0e-6))
                for jump in ringJumps {
                    let steps = result.traceSteps.filter { $0.ringIndex == jump.ringIndex }
                    if let step = steps.first(where: { $0.stepIndex == jump.maxSegIndex }) {
                        print(String(format: "traceJumpStep ring=%d k=%d len=%.6f candidates=%d", jump.ringIndex, jump.maxSegIndex, jump.length, step.candidates.count))
                        let incoming = step.incoming.normalized()
                        print(String(format: "traceJumpStep P=(%.6f,%.6f) Q=(%.6f,%.6f) incoming=(%.6f,%.6f) fromKey=(%d,%d) toKey=(%d,%d)", step.from.x, step.from.y, step.to.x, step.to.y, incoming.x, incoming.y, step.fromKey.x, step.fromKey.y, step.toKey.x, step.toKey.y))
                        for (index, candidate) in step.candidates.enumerated() {
                            let dir = (candidate.to - step.from).normalized()
                            let mark = candidate.isChosen ? "*" : " "
                            print(String(format: "traceJumpStep cand%@ idx=%d key=(%d,%d) pos=(%.6f,%.6f) dir=(%.6f,%.6f) len=%.6f angle=%.6f src=%@ scoreKey=(%d,%d)", mark, index, candidate.toKey.x, candidate.toKey.y, candidate.to.x, candidate.to.y, dir.x, dir.y, candidate.length, candidate.angle, candidate.source.description, candidate.scoreKey.x, candidate.scoreKey.y))
                        }
                        dumpSoupNode(label: "from", key: step.fromKey, pos: step.from, neighbors: step.fromNeighbors) { print($0) }
                        dumpSoupNode(label: "to", key: step.toKey, pos: step.to, neighbors: step.toNeighbors) { print($0) }
                    } else {
                        print(String(format: "traceJumpStep ring=%d k=%d len=%.6f candidates=0 (no step info)", jump.ringIndex, jump.maxSegIndex, jump.length))
                    }
                    let pReport = computeSoupNeighborhood(
                        segments: result.segmentsUsed,
                        eps: 1.0e-6,
                        center: jump.a,
                        radius: 5.0
                    )
                    emitSoupNeighborhood(pReport, label: "jumpP")
                    let qReport = computeSoupNeighborhood(
                        segments: result.segmentsUsed,
                        eps: 1.0e-6,
                        center: jump.b,
                        radius: 5.0
                    )
                    emitSoupNeighborhood(qReport, label: "jumpQ")
                }
            }
            if options.debugDumpCapSegments {
                let keyQuant: (Vec2) -> SnapKey = { Epsilon.snapKey($0, eps: 1.0e-6) }
                let capFilter: (EdgeSource) -> Bool = { source in
                    switch source {
                    case .capStart, .capEnd, .capStartEdge, .capEndEdge:
                        return true
                    default:
                        return false
                    }
                }
                if options.debugTraceJumpStep || options.debugRingJump {
                    for jump in ringJumps {
                        let matchA = keyQuant(jump.a)
                        let matchB = keyQuant(jump.b)
                        let hits = spotlightCapSegments(
                            segments: result.segmentsUsed,
                            keyQuant: keyQuant,
                            matchA: matchA,
                            matchB: matchB,
                            sources: capFilter,
                            topN: options.debugDumpCapSegmentsTop
                        )
                        print(String(format: "capDump label=matchJump ring=%d aKey=(%d,%d) bKey=(%d,%d) count=%d", jump.ringIndex, matchA.x, matchA.y, matchB.x, matchB.y, hits.count))
                        for (index, spot) in hits.enumerated() {
                            print(String(format: "  [%d] src=%@ len=%.6f aKey=(%d,%d) bKey=(%d,%d) a=(%.6f,%.6f) b=(%.6f,%.6f)", index, spot.seg.source.description, spot.len, spot.aKey.x, spot.aKey.y, spot.bKey.x, spot.bKey.y, spot.seg.a.x, spot.seg.a.y, spot.seg.b.x, spot.seg.b.y))
                        }
                    }
                } else {
                    let hits = spotlightCapSegments(
                        segments: result.segmentsUsed,
                        keyQuant: keyQuant,
                        matchA: nil,
                        matchB: nil,
                        sources: capFilter,
                        topN: options.debugDumpCapSegmentsTop
                    )
                    print(String(format: "capDump label=topN count=%d", hits.count))
                    for (index, spot) in hits.enumerated() {
                        print(String(format: "  [%d] src=%@ len=%.6f aKey=(%d,%d) bKey=(%d,%d) a=(%.6f,%.6f) b=(%.6f,%.6f)", index, spot.seg.source.description, spot.len, spot.aKey.x, spot.aKey.y, spot.bKey.x, spot.bKey.y, spot.seg.a.x, spot.seg.a.y, spot.seg.b.x, spot.seg.b.y))
                    }
                }
            }
            if options.debugDumpCapEndpoints {
                if let capInfo = result.capEndpointsDebug {
                    let s = capInfo.intendedStart
                    let e = capInfo.intendedEnd
                    print(String(format: "capEndpoints capIndex=0 eps=%.6g", capInfo.eps))
                    print(String(format: "  intended start: L0=(%.6f,%.6f) key=(%d,%d) R0=(%.6f,%.6f) key=(%d,%d) dist=%.6f", s.left.x, s.left.y, s.leftKey.x, s.leftKey.y, s.right.x, s.right.y, s.rightKey.x, s.rightKey.y, s.distance))
                    print(String(format: "  intended end:   L1=(%.6f,%.6f) key=(%d,%d) R1=(%.6f,%.6f) key=(%d,%d) dist=%.6f", e.left.x, e.left.y, e.leftKey.x, e.leftKey.y, e.right.x, e.right.y, e.rightKey.x, e.rightKey.y, e.distance))
                    if let startJoin = capInfo.emittedStartJoin {
                        print(String(format: "  emitted capStart.joinLR: src=%@ A=(%.6f,%.6f) key=(%d,%d) B=(%.6f,%.6f) key=(%d,%d) len=%.6f", startJoin.source.description, startJoin.a.x, startJoin.a.y, startJoin.aKey.x, startJoin.aKey.y, startJoin.b.x, startJoin.b.y, startJoin.bKey.x, startJoin.bKey.y, startJoin.length))
                    } else {
                        print("  emitted capStart.joinLR: <none>")
                    }
                    if let endJoin = capInfo.emittedEndJoin {
                        print(String(format: "  emitted capEnd.joinLR:   src=%@ A=(%.6f,%.6f) key=(%d,%d) B=(%.6f,%.6f) key=(%d,%d) len=%.6f", endJoin.source.description, endJoin.a.x, endJoin.a.y, endJoin.aKey.x, endJoin.aKey.y, endJoin.b.x, endJoin.b.y, endJoin.bKey.x, endJoin.bKey.y, endJoin.length))
                    } else {
                        print("  emitted capEnd.joinLR:   <none>")
                    }
                } else {
                    print("capEndpoints <none>")
                }
            }
            if options.debugDumpRailEndpoints {
                if let railSummary = result.railDebugSummary {
                    let prefixCount = max(1, min(options.debugDumpRailEndpointsPrefix, railSummary.prefix.count))
                    let start = railSummary.start
                    let end = railSummary.end
                    print(String(format: "railDebug count=%d", railSummary.count))
                    print(String(format: "railDebug start idx=%d L=(%.6f,%.6f) key=(%d,%d) R=(%.6f,%.6f) key=(%d,%d) dist=%.6f", start.index, start.left.x, start.left.y, start.leftKey.x, start.leftKey.y, start.right.x, start.right.y, start.rightKey.x, start.rightKey.y, start.distance))
                    print(String(format: "railDebug end idx=%d L=(%.6f,%.6f) key=(%d,%d) R=(%.6f,%.6f) key=(%d,%d) dist=%.6f", end.index, end.left.x, end.left.y, end.leftKey.x, end.leftKey.y, end.right.x, end.right.y, end.rightKey.x, end.rightKey.y, end.distance))
                    print(String(format: "railDebug prefix count=%d", prefixCount))
                    for i in 0..<prefixCount {
                        let item = railSummary.prefix[i]
                        print(String(format: "  [%d] L=(%.6f,%.6f) key=(%d,%d) R=(%.6f,%.6f) key=(%d,%d) dist=%.6f", item.index, item.left.x, item.left.y, item.leftKey.x, item.leftKey.y, item.right.x, item.right.y, item.rightKey.x, item.rightKey.y, item.distance))
                    }
                } else {
                    print("railDebug <none>")
                }
            }
            if options.debugDumpRailFrames || options.debugRailInvariants {
                let frames = result.railFrames ?? []
                if frames.isEmpty {
                    print("railFrames <none>")
                } else {
                    let prefixCount = max(1, min(options.debugDumpRailFramesPrefix, frames.count))
                    if options.debugDumpRailFrames {
                        print(String(format: "railFrames count=%d (showing first %d)", frames.count, prefixCount))
                        for i in 0..<prefixCount {
                            let f = frames[i]
                            let dist = (f.right - f.left).length
                            let dotTR = (f.right - f.left).dot(f.tangent)
                            let widthExpected = (f.widthLeft > 0.0 || f.widthRight > 0.0) ? (f.widthLeft + f.widthRight) : f.widthTotal
                            let widthErr = dist - widthExpected
                            print(String(format: "  [%d] C=(%.6f,%.6f) T=(%.6f,%.6f) N=(%.6f,%.6f) wL=%.6f wR=%.6f wTot=%.6f", f.index, f.center.x, f.center.y, f.tangent.x, f.tangent.y, f.normal.x, f.normal.y, f.widthLeft, f.widthRight, f.widthTotal))
                            print(String(format: "      L=(%.6f,%.6f) R=(%.6f,%.6f) dist=%.6f dotTR=%.6f widthErr=%.6f |N|=%.6f", f.left.x, f.left.y, f.right.x, f.right.y, dist, dotTR, widthErr, f.normal.length))
                        }
                    }
                    if options.debugRailInvariants {
                        let diag = computeRailFrameDiagnostics(
                            frames: frames,
                            widthEps: options.debugRailWidthEps,
                            perpEps: options.debugRailPerpEps,
                            unitEps: options.debugRailUnitEps
                        )
                        var widthFails = 0
                        var perpFails = 0
                        var unitFails = 0
                        for check in diag.checks {
                            if abs(check.widthErr) > options.debugRailWidthEps { widthFails += 1 }
                            if abs(check.alignment) > options.debugRailPerpEps { perpFails += 1 }
                            if abs(check.normalLen - 1.0) > options.debugRailUnitEps { unitFails += 1 }
                        }
                        print(String(format: "railInvSummary frames=%d widthFails=%d perpFails=%d unitFails=%d", diag.frames.count, widthFails, perpFails, unitFails))
                        let onlyFails = options.debugRailInvariantsOnlyFails
                        for check in diag.checks {
                            let widthFail = abs(check.widthErr) > options.debugRailWidthEps
                            let perpFail = abs(check.alignment) > options.debugRailPerpEps
                            let unitFail = abs(check.normalLen - 1.0) > options.debugRailUnitEps
                            if onlyFails && !(widthFail || perpFail || unitFail) {
                                continue
                            }
                            print(String(format: "  [%d] dist=%.6f expected=%.6f widthErr=%.6f alignErr=%.6f |N|=%.6f", check.index, check.distLR, check.expectedWidth, check.widthErr, check.alignment, check.normalLen))
                        }
                    }
                }
            }
            if options.debugDumpRailCorners {
                if let corner = result.railCornerDebug {
                    print(String(format: "railCornerDebug idx=%d", corner.index))
                    print(String(format: "  C=(%.6f,%.6f) T=(%.6f,%.6f) N=(%.6f,%.6f)", corner.center.x, corner.center.y, corner.tangent.x, corner.tangent.y, corner.normal.x, corner.normal.y))
                    print(String(format: "  u=(%.6f,%.6f) v=(%.6f,%.6f)", corner.u.x, corner.u.y, corner.v.x, corner.v.y))
                    print(String(format: "  effectiveAngle=%.6f", corner.effectiveAngle))
                    print(String(format: "  uRot=(%.6f,%.6f) vRot=(%.6f,%.6f)", corner.uRot.x, corner.uRot.y, corner.vRot.x, corner.vRot.y))
                    print(String(format: "  widths: wL=%.6f wR=%.6f expected=%.6f", corner.widthLeft, corner.widthRight, corner.widthTotal))
                    print("  corners:")
                    for (idx, c) in corner.corners.enumerated() {
                        let delta = c - corner.center
                        let dotT = delta.dot(corner.tangent)
                        let dotN = delta.dot(corner.normal)
                        print(String(format: "    c%d=(%.6f,%.6f) dotT=%.6f dotN=%.6f", idx, c.x, c.y, dotT, dotN))
                    }
                    let decomp = decomposeDelta(
                        left: corner.left,
                        right: corner.right,
                        tangent: corner.tangent,
                        normal: corner.normal,
                        expectedWidth: corner.widthTotal
                    )
                    print(String(format: "  chosen: L=(%.6f,%.6f) R=(%.6f,%.6f)", corner.left.x, corner.left.y, corner.right.x, corner.right.y))
                    print(String(format: "    delta=(%.6f,%.6f) dotT=%.6f dotN=%.6f len=%.6f widthErr=%.6f", decomp.delta.x, decomp.delta.y, decomp.dotT, decomp.dotN, decomp.len, decomp.widthErr))
                } else {
                    print("railCornerDebug <none>")
                }
            }
            if options.debugRingSpine {
                overlays.append(makeRingSpineOverlay(rings: result.rings))
            }
            if options.debugRingJump {
                overlays.append(makeRingJumpOverlay(jumps: ringJumps))
            }
        }
        if wantsSamplingWhy && !options.viewCenterlineOnly {
            if let sampling = result.sampling {
                let paramEps = max(options.adaptiveAttrEps, options.adaptiveAttrEpsAngleDeg * Double.pi / 180.0)
                let dotsAll = samplingWhyDots(
                    result: sampling,
                    flatnessEps: options.flatnessEps,
                    railEps: options.flatnessEps,
                    paramEps: paramEps,
                    positionAtS: { pathParam.position(globalT: $0) }
                )
                let worst = dotsAll.max { $0.severity < $1.severity }?.severity ?? 0.0
                let dots: [SamplingWhyDot]
                let labelCount: Int
                let geomCount = sampling.stats.subdividedByFlatness + sampling.stats.subdividedByRail
                let attrCount = sampling.stats.subdividedByParam
                let keyframeHits = sampling.stats.keyframeHits
                if soloWhy {
                    let sorted = dotsAll.sorted {
                        if $0.severity == $1.severity { return $0.s < $1.s }
                        return $0.severity > $1.severity
                    }
                    dots = Array(sorted.prefix(soloMaxDots))
                    labelCount = min(soloLabelDots, dots.count)
                    print(String(format: "samplingWhy total=%d drawn=%d labeled=%d worst=%.3f geometry=%d attr=%d keyframeHits=%d", dotsAll.count, dots.count, labelCount, worst, geomCount, attrCount, keyframeHits))
                    overlays.append(makeSamplingWhyOverlay(
                        dots: dots,
                        labelCount: labelCount,
                        minRadius: 2.0,
                        maxRadius: 10.0,
                        useLogRadius: true,
                        renderAsRings: true,
                        ringStrokeWidth: 0.7,
                        ringOpacity: 0.85,
                        addLabelCenters: false
                    ))
                } else {
                    print(String(format: "samplingWhy count=%d worst=%.3f geometry=%d attr=%d keyframeHits=%d", dotsAll.count, worst, geomCount, attrCount, keyframeHits))
                    overlays.append(makeSamplingWhyOverlay(dots: dotsAll))
                }
            } else {
                let countLine = soloWhy ? "samplingWhy total=0 drawn=0 labeled=0 worst=0.000 (no sampling result)" : "samplingWhy count=0 (no sampling result)"
                print(countLine)
                overlays.append(makeSamplingWhyOverlay(dots: []))
            }
        }
        let debugOverlay = mergeDebugOverlays(overlays)

        // 7. Reference Asset
        var referenceSVG: String? = nil
        var referenceViewBox: WorldRect? = nil
        if let layer = referenceLayer {
            if let asset = loadReferenceAsset(layer: layer, warn: warnHandler) {
                referenceSVG = asset.inner
                referenceViewBox = asset.viewBox
            }
        }

        // 8. Visual Assembly
        let referenceBoundsAABB = (referenceViewBox != nil && referenceLayer != nil) ? referenceBounds(viewBox: referenceViewBox!, layer: referenceLayer!) : nil

        let frame = resolveWorldFrame(
            settings: renderSettings,
            glyphBounds: combinedGlyphBounds,
            referenceBounds: referenceBoundsAABB,
            debugBounds: debugOverlay?.bounds
        )

        return RenderGlyphModel(
            effectiveOptions: options,
            renderSettings: renderSettings,
            frame: frame,
            referenceLayer: referenceLayer,
            referenceSVGInner: referenceSVG,
            referenceViewBox: referenceViewBox,
            strokeEntries: strokeEntries,
            counterRingsNormalized: counterRingsNormalized,
            debugOverlaySVG: debugOverlay?.svg ?? "",
            combinedGlyphBounds: combinedGlyphBounds,
            exampleName: exampleName
        )
    }
}
