import Foundation
import CP2Geometry
import CP2Skeleton
import CP2ResolveOverlap

enum SamplingModeError: Error, CustomStringConvertible {
    case fixedNotAllowed(String)

    var description: String {
        switch self {
        case .fixedNotAllowed(let message):
            return message
        }
    }
}

func validateSamplingOptions(_ options: CLIOptions) throws {
    if !options.adaptiveSampling && !options.allowFixedSampling {
        throw SamplingModeError.fixedNotAllowed("adaptive sampling is required; to use fixed sampling pass --allow-fixed-sampling --no-adaptive-sampling")
    }
    if options.arcSamplesWasSet && !options.allowFixedSampling {
        throw SamplingModeError.fixedNotAllowed("--arc-samples requires --allow-fixed-sampling")
    }
    if options.adaptiveSampling && options.arcSamplesWasSet {
        throw SamplingModeError.fixedNotAllowed("--arc-samples cannot be used with adaptive sampling")
    }
}

private func dumpSoupNode(
    label: String,
    key: SnapKey,
    pos: Vec2,
    neighbors: [TraceStepNeighbor],
    emit: (String) -> Void
) {
    emit(String(format: "soupNode %@ key=(%d,%d) pos=(%.6f,%.6f) degree=%d", label, key.x, key.y, pos.x, pos.y, neighbors.count))
    for (index, neighbor) in neighbors.enumerated() {
        emit(String(format: "  out[%d] -> key=(%d,%d) pos=(%.6f,%.6f) len=%.6f dir=(%.6f,%.6f)", index, neighbor.key.x, neighbor.key.y, neighbor.pos.x, neighbor.pos.y, neighbor.length, neighbor.dir.x, neighbor.dir.y))
    }
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

private func formatDegreeHistogram(_ histogram: [Int: Int]) -> String {
    let deg0 = histogram[0, default: 0]
    let deg1 = histogram[1, default: 0]
    let deg2 = histogram[2, default: 0]
    let deg3 = histogram[3, default: 0]
    let deg4plus = histogram.filter { $0.key >= 4 }.map { $0.value }.reduce(0, +)
    return String(format: "deg0=%d deg1=%d deg2=%d deg3=%d deg4+=%d", deg0, deg1, deg2, deg3, deg4plus)
}

private func ensureClosedRing(_ ring: [Vec2]) -> [Vec2] {
    guard !ring.isEmpty else { return [] }
    if let first = ring.first, let last = ring.last, !Epsilon.approxEqual(first, last) {
        return ring + [first]
    }
    return ring
}

private func normalizedRing(_ ring: [Vec2], clockwise: Bool) -> [Vec2] {
    let closed = ensureClosedRing(ring)
    guard closed.count >= 3 else { return closed }
    let area = signedArea(closed)
    if clockwise {
        if area > Epsilon.defaultValue { return closed.reversed() }
    } else {
        if area < -Epsilon.defaultValue { return closed.reversed() }
    }
    return closed
}

private func ringCentroid(_ ring: [Vec2]) -> Vec2 {
    guard !ring.isEmpty else { return Vec2(0, 0) }
    var sum = Vec2(0, 0)
    for point in ring {
        sum = sum + point
    }
    let denom = Double(ring.count)
    return Vec2(sum.x / denom, sum.y / denom)
}

private func pointInRing(_ point: Vec2, ring: [Vec2]) -> Bool {
    guard ring.count >= 3 else { return false }
    var inside = false
    var j = ring.count - 1
    for i in 0..<ring.count {
        let pi = ring[i]
        let pj = ring[j]
        let denom = max(Epsilon.defaultValue, (pj.y - pi.y))
        let intersects = ((pi.y > point.y) != (pj.y > point.y))
            && (point.x < (pj.x - pi.x) * (point.y - pi.y) / denom + pi.x)
        if intersects {
            inside.toggle()
        }
        j = i
    }
    return inside
}

private func counterIsInsideInk(counter: [Vec2], inkRings: [[Vec2]]) -> Bool {
    guard !counter.isEmpty, !inkRings.isEmpty else { return false }
    let probe = ringCentroid(counter)
    for ring in inkRings {
        if pointInRing(probe, ring: ring) { return true }
    }
    return false
}

private func sampleRingPoints(for segment: InkSegment, steps: Int) -> [Vec2] {
    switch segment {
    case .line(let line):
        return [vec(line.p0), vec(line.p1)]
    case .cubic(let cubic):
        return sampleInkCubicPoints(cubic, steps: steps)
    }
}

private func ringFromSegments(_ segments: [InkSegment], steps: Int) -> [Vec2] {
    var points: [Vec2] = []
    for segment in segments {
        let segmentPoints = sampleRingPoints(for: segment, steps: steps)
        if points.isEmpty {
            points.append(contentsOf: segmentPoints)
        } else if let last = points.last, let first = segmentPoints.first, Epsilon.approxEqual(last, first) {
            points.append(contentsOf: segmentPoints.dropFirst())
        } else {
            points.append(contentsOf: segmentPoints)
        }
    }
    return ensureClosedRing(points)
}

private func counterRings(
    counters: CounterSet,
    strokeOutputs: [(
        stroke: ResolvedStroke,
        pathParam: SkeletonPathParameterization,
        plan: SweepPlan
    )],
    options: CLIOptions,
    warn: (String) -> Void
) -> [(ring: [Vec2], appliesTo: [String]?)] {
    let steps = max(8, options.arcSamples)
    let counterInk = Ink(stem: nil, entries: counters.entries.compactMapValues { primitive in
        if case .ink(let ink, _) = primitive { return ink }
        return nil
    })
    var rings: [(ring: [Vec2], appliesTo: [String]?)] = []
    for key in counters.entries.keys.sorted() {
        guard let primitive = counters.entries[key] else { continue }
        switch primitive {
        case .ink(let inkPrimitive, let appliesTo):
            switch inkPrimitive {
            case .line(let line):
                rings.append((ensureClosedRing([vec(line.p0), vec(line.p1)]), appliesTo))
            case .cubic(let cubic):
                rings.append((ensureClosedRing(sampleInkCubicPoints(cubic, steps: steps)), appliesTo))
            case .path(let path):
                let ring = ringFromSegments(path.segments, steps: steps)
                if !ring.isEmpty { rings.append((ring, appliesTo)) }
            case .heartline(let heartline):
                do {
                    let resolved = try resolveHeartline(
                        name: key,
                        heartline: heartline,
                        ink: counterInk,
                        strict: options.strictHeartline,
                        warn: warn
                    )
                    for subpath in resolved.subpaths {
                        let ring = ringFromSegments(subpath, steps: steps)
                        if !ring.isEmpty { rings.append((ring, appliesTo)) }
                    }
                } catch {
                    warn("counter heartline resolve failed: \(key) error=\(error)")
                }
            }
        case .ellipse(let ellipse):
            if let ring = ellipseRing(ellipse, strokeOutputs: strokeOutputs, warn: warn) {
                rings.append((ring, ellipse.appliesTo))
            }
        }
    }
    return rings
}

private func ellipseRing(
    _ ellipse: CounterEllipse,
    strokeOutputs: [(
        stroke: ResolvedStroke,
        pathParam: SkeletonPathParameterization,
        plan: SweepPlan
    )],
    warn: (String) -> Void
) -> [Vec2]? {
    let target: (
        pathParam: SkeletonPathParameterization,
        plan: SweepPlan
    )?
    if let strokeId = ellipse.at.stroke {
        target = strokeOutputs.first(where: { $0.stroke.id == strokeId }).map { ($0.pathParam, $0.plan) }
    } else if let inkName = ellipse.at.ink {
        target = strokeOutputs.first(where: { $0.stroke.inkName == inkName }).map { ($0.pathParam, $0.plan) }
    } else {
        warn("counter ellipse missing stroke or ink anchor")
        return nil
    }
    guard let target else {
        warn("counter ellipse anchor not found")
        return nil
    }

    let gt = max(0.0, min(1.0, ellipse.at.t))
    let styleAtGT: (Double) -> SweepStyle = { t in
        SweepStyle(
            width: target.plan.scaledWidthAtT(t),
            widthLeft: target.plan.scaledWidthLeftAtT(t),
            widthRight: target.plan.scaledWidthRightAtT(t),
            height: target.plan.sweepHeight,
            angle: target.plan.thetaAtT(t),
            offset: target.plan.offsetAtT(t),
            angleIsRelative: target.plan.angleMode == .relative
        )
    }
    let frame = railSampleFrameAtGlobalT(
        param: target.pathParam,
        warpGT: target.plan.warpT,
        styleAtGT: styleAtGT,
        gt: gt,
        index: -1
    )
    let offset = ellipse.offset ?? CounterOffset(t: 0.0, n: 0.0)
    let center = frame.center + frame.tangent * offset.t + frame.normal * offset.n
    let angle = ellipse.rotateDeg * Double.pi / 180.0
    let cosR = cos(angle)
    let sinR = sin(angle)
    let sampleCount = 64
    var points: [Vec2] = []
    points.reserveCapacity(sampleCount)
    for i in 0..<sampleCount {
        let theta = (Double(i) / Double(sampleCount)) * Double.pi * 2.0
        let x = ellipse.rx * cos(theta)
        let y = ellipse.ry * sin(theta)
        let xr = x * cosR - y * sinR
        let yr = x * sinR + y * cosR
        let point = center + frame.tangent * xr + frame.normal * yr
        points.append(point)
    }
    return ensureClosedRing(points)
}


private func inkPrimitiveSummary(_ primitive: InkPrimitive) -> String {
    switch primitive {
    case .line(let line):
        return "line p0=\(formatVec2(vec(line.p0))) p1=\(formatVec2(vec(line.p1)))"
    case .cubic(let cubic):
        return "cubic p0=\(formatVec2(vec(cubic.p0))) p3=\(formatVec2(vec(cubic.p3)))"
    case .path(let path):
        if let first = path.segments.first, let last = path.segments.last {
            return "path segments=\(path.segments.count) start=\(formatVec2(inkSegmentStart(first))) end=\(formatVec2(inkSegmentEnd(last)))"
        }
        return "path segments=0"
    case .heartline(let heartline):
        let names = heartline.parts.map { $0.partName }
        return "heartline parts=\(names)"
    }
}

private func segmentKind(_ segment: InkSegment) -> String {
    switch segment {
    case .line:
        return "line"
    case .cubic:
        return "cubic"
    }
}

private func dumpHeartlineResolve(
    specPath: String?,
    spec: CP2Spec?,
    options: CLIOptions
) {
    let pathText = specPath ?? "none"
    print("heartlineResolve specPath=\(pathText)")
    guard let spec else {
        print("heartlineResolve spec=none")
        return
    }
    guard let ink = spec.ink else {
        print("heartlineResolve inkKeys=[]")
        return
    }
    let keys = ink.entries.keys.sorted()
    print("heartlineResolve inkKeys=[\(keys.joined(separator: ", "))]")
    for key in keys {
        guard let primitive = ink.entries[key] else { continue }
        if case .heartline(let heartline) = primitive {
            let names = heartline.parts.map { $0.partName }
            print("heartlineResolve name=\(key) parts=\(names)")
            for partRef in heartline.parts {
                let partName = partRef.partName
                if let part = ink.entries[partName] {
                    let knot = partRef.joinKnot.map { "\($0)" } ?? "none"
                    print("  part \(partName) joinKnot=\(knot) RESOLVED \(inkPrimitiveSummary(part))")
                } else {
                    print("  part \(partName) MISSING")
                }
            }
        }
    }
    if let strokes = spec.strokes {
        for stroke in strokes {
            print("strokeResolve id=\(stroke.id) ink=\(stroke.ink)")
            do {
                let segments = try resolveInkSegments(
                    name: stroke.ink,
                    ink: ink,
                    strict: options.strictHeartline,
                    warn: { _ in }
                )
                let kinds = segments.map { segmentKind($0) }.joined(separator: ",")
                print("  resolvedSegments count=\(segments.count) kinds=[\(kinds)]")
            } catch {
                print("  resolveError \(error)")
            }
        }
    }
}

public func renderSVGString(
    options: CLIOptions,
    spec: CP2Spec?,
    warnSink: ((String) -> Void)? = nil
) throws -> String {
    var options = options
    if options.viewCenterlineOnly {
        options.debugCenterline = true
    }
    let warnHandler: (String) -> Void = { message in
        if let warnSink {
            warnSink(message)
        } else {
            warn(message)
        }
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
            endCap: stroke.endCap
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

    let strokeEntries: [(index: Int, stroke: ResolvedStroke, ring: [Vec2])] = strokeOutputs.enumerated().compactMap { index, output in
        let points = output.result.finalContour.points
        guard !points.isEmpty else { return nil }
        return (index, output.stroke, normalizedRing(points, clockwise: true))
    }
    let inkRingsNormalized: [[Vec2]] = strokeEntries.map { $0.ring }
    var counterRingsNormalized: [(ring: [Vec2], appliesTo: [String]?)] = []
    if let counters = spec?.counters, !options.viewCenterlineOnly {
        let counterOutputs = strokeOutputs.map { (stroke: $0.stroke, pathParam: $0.pathParam, plan: $0.plan) }
        let rawCounters = counterRings(counters: counters, strokeOutputs: counterOutputs, options: options, warn: warnHandler)
        counterRingsNormalized = rawCounters
            .filter { !$0.ring.isEmpty }
            .map { (normalizedRing($0.ring, clockwise: false), $0.appliesTo) }
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
        if let planarStats = result.planarizeStats {
            print(String(format: "PLANARIZE intersections=%d splitSegmentsBefore=%d after=%d", planarStats.intersections, planarStats.segments, planarStats.splitEdges))
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

    if options.refFitToFrame, let viewBox = referenceViewBox, let layer = referenceLayer {
        let fit = fitReferenceTransform(referenceViewBox: viewBox, to: frame)
        print(String(format: "ref-fit translate=(%.6f,%.6f) scale=%.6f", fit.translate.x, fit.translate.y, fit.scale))
        if let writePath = options.refFitWritePath {
            var outSpec = spec ?? CP2Spec()
            outSpec.reference = ReferenceLayer(path: layer.path, translateWorld: fit.translate, scale: fit.scale, rotateDeg: layer.rotateDeg, opacity: layer.opacity, lockPlacement: layer.lockPlacement)
            writeSpec(outSpec, path: writePath)
        }
    }

    let viewMinX = frame.minX, viewMinY = frame.minY, viewWidth = frame.width, viewHeight = frame.height
    let strokeInkContent: String = {
        if strokeEntries.isEmpty { return "" }

        let counterGroups: [(key: String, appliesTo: [String]?, counters: [[Vec2]])] = {
            guard !counterRingsNormalized.isEmpty else { return [] }
            var map: [String: (appliesTo: [String]?, rings: [[Vec2]])] = [:]
            for item in counterRingsNormalized {
                let appliesTo = item.appliesTo?.sorted()
                let key = appliesTo?.joined(separator: "|") ?? "*"
                if var existing = map[key] {
                    existing.rings.append(item.ring)
                    map[key] = existing
                } else {
                    map[key] = (appliesTo, [item.ring])
                }
            }
            return map.keys.sorted().compactMap { key in
                guard let value = map[key] else { return nil }
                return (key, value.appliesTo, value.rings)
            }
        }()

        var usedStrokeIndices: Set<Int> = []
        var parts: [String] = []
        var groupIndex = 0

        func emitCompound(
            inkRings: [[Vec2]],
            counterRings: [[Vec2]],
            idSuffix: String
        ) {
            let inkPathData = inkRings
                .map { svgPath(for: $0) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            let counterPathData = counterRings
                .map { svgPath(for: $0) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")

            if options.clipCountersToInk, !inkPathData.isEmpty, !counterPathData.isEmpty {
                let inkId = idSuffix.isEmpty ? "ink-shape" : "ink-shape-\(idSuffix)"
                let clipId = idSuffix.isEmpty ? "clip-ink" : "clip-ink-\(idSuffix)"
                let counterId = idSuffix.isEmpty ? "counter-shape" : "counter-shape-\(idSuffix)"
                parts.append("""
    <path id="\(inkId)" d="\(inkPathData)" fill="black" stroke="none" fill-rule="nonzero" />
    <defs>
      <clipPath id="\(clipId)">
        <use href="#\(inkId)" />
      </clipPath>
    </defs>
    <path id="\(counterId)" d="\(counterPathData)" fill="white" stroke="none" clip-path="url(#\(clipId))" />
""")
                return
            }

            let compoundRings = inkRings + counterRings
            let compoundPathData = compoundRings
                .map { svgPath(for: $0) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            if compoundPathData.isEmpty { return }
            let idToken = idSuffix.isEmpty ? "ink-compound" : "ink-compound-\(idSuffix)"
            parts.append("    <path id=\"\(idToken)\" d=\"\(compoundPathData)\" fill=\"black\" stroke=\"none\" fill-rule=\"nonzero\" />")
        }

        if counterGroups.isEmpty {
            emitCompound(inkRings: strokeEntries.map { $0.ring }, counterRings: [], idSuffix: "")
            return parts.joined(separator: "\n")
        }

        for group in counterGroups {
            let targetIds = group.appliesTo
            var groupStrokeIndices: [Int] = []
            if let targetIds {
                let set = Set(targetIds)
                groupStrokeIndices = strokeEntries.filter { entry in
                    if let id = entry.stroke.id { return set.contains(id) }
                    return false
                }.map { $0.index }
                let missing = targetIds.filter { id in !strokeEntries.contains(where: { $0.stroke.id == id }) }
                if !missing.isEmpty {
                    warnHandler("counter appliesTo missing stroke ids: \(missing.joined(separator: ", "))")
                }
            } else {
                groupStrokeIndices = strokeEntries.map { $0.index }
            }

            let freshIndices = groupStrokeIndices.filter { !usedStrokeIndices.contains($0) }
            if freshIndices.count != groupStrokeIndices.count {
                warnHandler("counter appliesTo overlaps previously scoped strokes; rendering first occurrence only")
            }
            if freshIndices.isEmpty { continue }
            for index in freshIndices { usedStrokeIndices.insert(index) }

            let groupInkRings = strokeEntries.filter { freshIndices.contains($0.index) }.map { $0.ring }
            emitCompound(
                inkRings: groupInkRings,
                counterRings: group.counters,
                idSuffix: groupIndex == 0 ? "" : "g\(groupIndex)"
            )
            groupIndex += 1
        }

        let remaining = strokeEntries.filter { !usedStrokeIndices.contains($0.index) }
        for entry in remaining {
            let rawId = entry.stroke.id ?? entry.stroke.inkName ?? "stroke-\(entry.index)"
            let idToken = rawId.replacingOccurrences(of: " ", with: "-")
            let pathData = svgPath(for: entry.ring)
            parts.append("    <path id=\"stroke-ink-\(idToken)\" d=\"\(pathData)\" fill=\"black\" stroke=\"none\" data-stroke-id=\"\(rawId)\" />")
        }

        return parts.joined(separator: "\n")
    }()
    let clipId = "frameClip"
    let clipPath = renderSettings.clipToFrame ? """
  <clipPath id="\(clipId)">
    <rect x="\(String(format: "%.4f", viewMinX))" y="\(String(format: "%.4f", viewMinY))" width="\(String(format: "%.4f", viewWidth))" height="\(String(format: "%.4f", viewHeight))" />
  </clipPath>
""" : ""

    let referenceFillGroup: String = {
        guard let layer = referenceLayer, let referenceSVG = referenceSVG else { return "" }
        let transform = svgTransformString(referenceTransformMatrix(layer))
        return """
  <g id="reference-fill" opacity="\(String(format: "%.4f", layer.opacity))" transform="\(transform)">
\(referenceSVG)
  </g>
"""
    }()
    let referenceOutlineGroup: String = {
        guard (options.debugCompare || options.debugCompareAll),
              referenceLayer != nil,
              let referenceSVG = referenceSVG else { return "" }
        let transform = svgTransformString(referenceTransformMatrix(referenceLayer!))
        return """
  <g id="reference-outline" transform="\(transform)" style="fill:none;stroke:#ff66cc;stroke-width:1;vector-effect:non-scaling-stroke">
\(referenceSVG)
  </g>
"""
    }()
    
    let debugSVG = debugOverlay?.svg ?? ""
    let glyphGroup = options.viewCenterlineOnly ? "" : (renderSettings.clipToFrame ? """
  <g id="glyph" clip-path="url(#\(clipId))">
    <g id="stroke-ink">
\(strokeInkContent)
    </g>
  </g>
""" : """
  <g id="stroke-ink">
\(strokeInkContent)
  </g>
""")
    let debugGroup = renderSettings.clipToFrame ? """
  <g id="debug-overlays" clip-path="url(#\(clipId))">
\(debugSVG)
  </g>
""" : """
  <g id="debug-overlays">
\(debugSVG)
  </g>
"""

    let viewTokens: [String] = {
        var tokens: [String] = []
        if options.debugCompareAll {
            tokens.append("compareAll")
        } else if options.debugCompare {
            tokens.append("compare")
        }
        if options.debugRingSpine { tokens.append("ringSpine") }
        if options.debugRingJump { tokens.append("ringJump") }
        if options.debugSamplingWhy { tokens.append("samplingWhy") }
        if options.debugCenterline { tokens.append("centerline") }
        if options.debugInkControls { tokens.append("inkControls") }
        if options.debugSVG { tokens.append("debugSVG") }
        if options.debugSoloWhy { tokens.append("soloWhy") }
        if options.debugCounters { tokens.append("counters") }
        return tokens
    }()
    let viewLabel = viewTokens.isEmpty ? "none" : viewTokens.joined(separator: ",")
    let exampleLabel = exampleName ?? "none"
    let infoLabel = options.viewCenterlineOnly ? "" : """
  <text x="20" y="20" font-size="14" fill="#111">example=\(exampleLabel) view=\(viewLabel) solo=\(options.debugSoloWhy)</text>
"""
    let legendLabel: String = {
        if options.viewCenterlineOnly { return "" }
        let wantsLegend = options.debugCompare || options.debugCompareAll || options.debugSVG || options.debugCenterline || options.debugInkControls || options.debugRingSpine || options.debugRingJump || options.debugSamplingWhy || options.debugCounters
        guard wantsLegend else { return "" }
        var lines: [(String, String)] = []
        if referenceLayer != nil {
            lines.append(("reference fill", "#111"))
            lines.append(("reference outline", "#ff66cc"))
        }
        lines.append(("ink fill", "#111"))
        if options.debugCenterline { lines.append(("centerline", "orange")) }
        if options.debugInkControls { lines.append(("ink controls", "gray")) }
        if options.debugRingSpine { lines.append(("ring spine", "#00c853")) }
        if options.debugRingJump { lines.append(("ring jump", "#ff1744")) }
        if options.debugCounters { lines.append(("counter paths", "#d81b60")) }
        if options.debugSamplingWhy {
            lines.append(("why: flatness", "red"))
            lines.append(("why: rail deviation", "blue"))
            lines.append(("why: both", "purple"))
            lines.append(("why: forced stop", "gray"))
        }
        var y = 40
        var text = "  <g id=\"debug-legend\">"
        for (label, color) in lines {
            text += "\n    <text x=\"20\" y=\"\(y)\" font-size=\"12\" fill=\"\(color)\">\(label)</text>"
            y += 16
        }
        text += "\n  </g>"
        return text
    }()

    return """
<svg xmlns="http://www.w3.org/2000/svg" width="\(renderSettings.canvasPx.width)" height="\(renderSettings.canvasPx.height)" viewBox="\(String(format: "%.4f", viewMinX)) \(String(format: "%.4f", viewMinY)) \(String(format: "%.4f", viewWidth)) \(String(format: "%.4f", viewHeight))">
\(clipPath)
\(referenceFillGroup)
\(glyphGroup)
\(referenceOutlineGroup)
\(debugGroup)
\(infoLabel)
\(legendLabel)
</svg>
"""
}

private struct AngleModeDebugMetrics {
    let minIndex: Int
    let minGT: Double
    let minSep: Double
    let maxSep: Double
    let meanSep: Double
    let minLeft: Vec2
    let minRight: Vec2
    let minTangent: Vec2
    let minTheta: Double
}

private func emitAngleModeDebug(
    options: CLIOptions,
    pathParam: SkeletonPathParameterization,
    plan: SweepPlan,
    sampling: SamplingResult?
) -> AngleModeDebugMetrics? {
    let angleMode = plan.angleMode == .relative ? "relative" : "absolute"
    print("ANGLE_MODE mode=\(angleMode)")
    let ts = sampling?.ts ?? [0.0, 0.5, 1.0]
    let picks: [Double] = {
        guard ts.count >= 3 else { return ts }
        return [ts.first!, ts[ts.count / 2], ts.last!]
    }()
    func styleAtGT(_ gt: Double) -> SweepStyle {
        SweepStyle(
            width: plan.scaledWidthAtT(gt),
            widthLeft: plan.scaledWidthLeftAtT(gt),
            widthRight: plan.scaledWidthRightAtT(gt),
            height: plan.sweepHeight,
            angle: plan.thetaAtT(gt),
            offset: plan.offsetAtT(gt),
            angleIsRelative: plan.angleMode == .relative
        )
    }
    for (index, gt) in picks.enumerated() {
        let frame = railSampleFrameAtGlobalT(
            param: pathParam,
            warpGT: plan.warpT,
            styleAtGT: styleAtGT,
            gt: gt,
            index: index
        )
        let tangent = frame.tangent
        let normal = frame.normal
        let cross = frame.crossAxis
        let theta = plan.thetaAtT(gt)
        let dotT = cross.dot(tangent)
        let dotN = cross.dot(normal)
        let heightScalar = styleAtGT(plan.warpT(gt)).height
        let tangentAngle = atan2(tangent.y, tangent.x)
        print(String(format: "ANGLE_MODE sample=%d gt=%.6f tangent=(%.6f,%.6f) tangentDeg=%.3f theta=%.6f cross=(%.6f,%.6f) normal=(%.6f,%.6f) dotT=%.6f dotN=%.6f height=%.6f", index, gt, tangent.x, tangent.y, tangentAngle * 180.0 / Double.pi, theta, cross.x, cross.y, normal.x, normal.y, dotT, dotN, heightScalar))
    }

    var minSep = Double.greatestFiniteMagnitude
    var maxSep = 0.0
    var sumSep = 0.0
    var minIndex = 0
    var minGT = ts.first ?? 0.0
    var minLeft = Vec2(0, 0)
    var minRight = Vec2(0, 0)
    var minTangent = Vec2(1, 0)
    var minTheta = 0.0

    for (index, gt) in ts.enumerated() {
        let frame = railSampleFrameAtGlobalT(
            param: pathParam,
            warpGT: plan.warpT,
            styleAtGT: styleAtGT,
            gt: gt,
            index: index
        )
        let sep = (frame.right - frame.left).length
        sumSep += sep
        if sep < minSep {
            minSep = sep
            minIndex = index
            minGT = gt
            minLeft = frame.left
            minRight = frame.right
            minTangent = frame.tangent
            minTheta = plan.thetaAtT(gt)
        }
        if sep > maxSep { maxSep = sep }
    }
    let meanSep = ts.isEmpty ? 0.0 : (sumSep / Double(ts.count))
    print(String(format: "RAIL_SEP min=%.6f at=%d gt=%.6f max=%.6f mean=%.6f", minSep, minIndex, minGT, maxSep, meanSep))
    let tangentDeg = atan2(minTangent.y, minTangent.x) * 180.0 / Double.pi
    let thetaDeg = minTheta * 180.0 / Double.pi
    print(String(format: "RAIL_SEP_ARGMIN i=%d gt=%.6f left=(%.6f,%.6f) right=(%.6f,%.6f) tangentDeg=%.3f thetaDeg=%.3f", minIndex, minGT, minLeft.x, minLeft.y, minRight.x, minRight.y, tangentDeg, thetaDeg))

    return AngleModeDebugMetrics(
        minIndex: minIndex,
        minGT: minGT,
        minSep: minSep,
        maxSep: maxSep,
        meanSep: meanSep,
        minLeft: minLeft,
        minRight: minRight,
        minTangent: minTangent,
        minTheta: minTheta
    )
}

func renderStoryboardCels(
    options: CLIOptions,
    spec: CP2Spec?,
    stages: [StoryStage],
    contextMode: StoryboardContextMode,
    warnSink: ((String) -> Void)? = nil
) throws -> [StoryboardCel] {
    let options = options
    let warnHandler: (String) -> Void = { message in
        if let warnSink {
            warnSink(message)
        } else {
            warn(message)
        }
    }

    var (renderSettings, referenceLayer) = resolveEffectiveSettings(options: options, spec: spec)
    if options.viewCenterlineOnly {
        referenceLayer = nil
    }

    let (exampleName, resolvedStrokes) = try resolveEffectiveStrokes(
        options: options,
        spec: spec,
        warn: warnHandler
    )
    let primaryStroke = resolvedStrokes.first!

    typealias StrokeOutput = (
        stroke: ResolvedStroke,
        pathParam: SkeletonPathParameterization,
        plan: SweepPlan,
        result: SweepResult
    )
    var strokeOutputs: [StrokeOutput] = []
    var combinedGlyphBounds: AABB? = nil

    for (index, stroke) in resolvedStrokes.enumerated() {
        let path = stroke.path
        let pathParam = SkeletonPathParameterization(path: path, samplesPerSegment: options.arcSamples)
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
        let capNamespace = stroke.id ?? stroke.inkName ?? "stroke-\(index)"
        let result = runSweep(
            path: path,
            plan: plan,
            options: options,
            capNamespace: capNamespace,
            startCap: stroke.startCap,
            endCap: stroke.endCap
        )
        strokeOutputs.append((stroke: stroke, pathParam: pathParam, plan: plan, result: result))
        if let glyphBounds = result.glyphBounds {
            combinedGlyphBounds = combinedGlyphBounds?.union(glyphBounds) ?? glyphBounds
        }
    }

    let primaryOutput = strokeOutputs[0]

    var referenceViewBox: WorldRect? = nil
    if let layer = referenceLayer {
        if let asset = loadReferenceAsset(layer: layer, warn: warnHandler) {
            referenceViewBox = asset.viewBox
        }
    }
    let referenceBoundsAABB = (referenceViewBox != nil && referenceLayer != nil) ? referenceBounds(viewBox: referenceViewBox!, layer: referenceLayer!) : nil
    let frame = resolveWorldFrame(
        settings: renderSettings,
        glyphBounds: combinedGlyphBounds,
        referenceBounds: referenceBoundsAABB,
        debugBounds: nil
    )

    let railSamples = primaryOutput.result.sampling?.ts ?? []
    let railTs = railSamples.isEmpty ? stride(from: 0, through: 1.0, by: 0.05).map { $0 } : railSamples
    var railsLeft: [Vec2] = []
    var railsRight: [Vec2] = []
    if !railTs.isEmpty {
        railsLeft.reserveCapacity(railTs.count)
        railsRight.reserveCapacity(railTs.count)
        let styleAtGT: (Double) -> SweepStyle = { t in
            SweepStyle(
                width: primaryOutput.plan.scaledWidthAtT(t),
                widthLeft: primaryOutput.plan.scaledWidthLeftAtT(t),
                widthRight: primaryOutput.plan.scaledWidthRightAtT(t),
                height: primaryOutput.plan.sweepHeight,
                angle: primaryOutput.plan.thetaAtT(t),
                offset: primaryOutput.plan.offsetAtT(t),
                angleIsRelative: primaryOutput.plan.angleMode == .relative
            )
        }
        for (index, gt) in railTs.enumerated() {
            let frame = railSampleFrameAtGlobalT(
                param: primaryOutput.pathParam,
                warpGT: primaryOutput.plan.warpT,
                styleAtGT: styleAtGT,
                gt: gt,
                index: index
            )
            railsLeft.append(frame.left)
            railsRight.append(frame.right)
        }
    }
    let soupChains: [[Vec2]]? = primaryOutput.result.segmentsUsed.isEmpty ? nil : primaryOutput.result.segmentsUsed.map { [$0.a, $0.b] }
    let resolveBefore = primaryOutput.result.resolveSelfOverlap?.original
    let resolveAfter = primaryOutput.result.resolveSelfOverlap?.resolved
    let resolveIntersections = primaryOutput.result.resolveSelfOverlap?.intersections
    let capabilities = StoryCapabilities(
        hasRails: !railsLeft.isEmpty && !railsRight.isEmpty,
        hasSoup: soupChains != nil,
        hasRings: !primaryOutput.result.rings.isEmpty,
        hasResolve: resolveAfter != nil
    )

    let context = StoryContext(
        canvas: renderSettings.canvasPx,
        frame: frame,
        path: primaryStroke.path,
        pathParam: primaryOutput.pathParam,
        plan: primaryOutput.plan,
        params: primaryStroke.params,
        sampling: primaryOutput.result.sampling,
        ring: primaryOutput.result.finalContour.points,
        railsLeft: railsLeft.isEmpty ? nil : railsLeft,
        railsRight: railsRight.isEmpty ? nil : railsRight,
        soupChains: soupChains,
        rings: primaryOutput.result.rings,
        resolveBefore: resolveBefore,
        resolveAfter: resolveAfter,
        resolveIntersections: resolveIntersections,
        capabilities: capabilities
    )
    for stage in stages {
        if let reason = StoryboardRenderer.placeholderReason(stage: stage, context: context) {
            warnHandler("STORYBOARD missingStage=\(stage.rawValue) reason=\(reason)")
        }
    }
    return StoryboardRenderer.renderCels(context: context, stages: stages, contextMode: contextMode)
}

public func runCLI() {
    // NOTE: CLIOptions.parse currently understands --spec and --example.
    // We also support positional *.json as specPath here to avoid silent fallback.
    var options = parseArgs(Array(CommandLine.arguments.dropFirst()))
    if options.specPath == nil {
        if let positional = CommandLine.arguments.dropFirst().first(where: { $0.hasSuffix(".json") && !$0.hasPrefix("--") }) {
            options.specPath = positional
        }
    }
    if options.specPath == nil, options.galleryLinesBoth || options.galleryLinesWavy || options.example?.lowercased() == "gallery_lines" {
        do {
            let mode: GalleryLinesMode
            if options.galleryLinesBoth {
                mode = .both
            } else if options.galleryLinesWavy {
                mode = .wavy
            } else {
                mode = .straight
            }
            try renderGalleryLines(options: options, mode: mode)
            exit(0)
        } catch {
            warn("gallery render failed")
            warn("error: \(error)")
            exit(1)
        }
    }
    if options.specPath == nil, let example = options.example {
        let galleryPath = "Fixtures/glyphs/gallery_lines/\(example).v0.json"
        if FileManager.default.fileExists(atPath: galleryPath) {
            options.specPath = galleryPath
        }
    }
    if options.specPath == nil, options.example?.lowercased() == "e" {
        options.specPath = "Fixtures/glyphs/e.v0.json"
    }
    do {
        try validateSamplingOptions(options)
    } catch {
        warn("invalid sampling options")
        warn("error: \(error)")
        exit(1)
    }

    let outURL = URL(fileURLWithPath: options.outPath)

    do {
        let spec: CP2Spec?
        if let path = options.specPath {
            spec = try loadSpecOrThrow(path: path)
            if let spec {
                warnKeyframeTimesOutOfRange(spec: spec, warnHandler: warn)
            }
        } else {
            spec = nil
        }

        if let outDirPath = options.outDirPath {
            let stages = options.storyboardStages.isEmpty ? [StoryStage.skeleton, .keyframes, .samples, .final] : options.storyboardStages
            let cels = try renderStoryboardCels(options: options, spec: spec, stages: stages, contextMode: options.storyboardContext)
            let outDir = URL(fileURLWithPath: outDirPath)
            try StoryboardRenderer.writeCels(cels: cels, outDir: outDir)
            if options.verbose {
                print("Exported storyboard to: \(outDir.path)")
            }
            exit(0)
        }

        let svg = try renderSVGString(options: options, spec: spec)

        try FileManager.default.createDirectory(
            at: outURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        guard let data = svg.data(using: .utf8) else {
            warn("Failed to encode SVG to UTF-8")
            exit(1)
        }

        try data.write(to: outURL, options: .atomic)

        if options.verbose {
            print("Exported \(data.count) bytes to: \(outURL.path)")
        }
    } catch {
        warn("export failed")
        warn("error: \(error)")
        warn("path: \(outURL.path)")
        warn("cwd: \(FileManager.default.currentDirectoryPath)")
        exit(1)
    }
}

private enum GalleryLinesMode {
    case straight
    case wavy
    case both
}

private func renderGalleryLines(options: CLIOptions, mode: GalleryLinesMode) throws {
    let galleryDir = "Fixtures/glyphs/gallery_lines"
    let allFiles = try FileManager.default.contentsOfDirectory(atPath: galleryDir)
        .filter { $0.hasSuffix(".json") }
        .sorted()
    if allFiles.isEmpty {
        throw NSError(domain: "cp2-cli.gallery", code: 1, userInfo: [NSLocalizedDescriptionKey: "no gallery fixtures found in \(galleryDir)"])
    }

    func renderSubset(files: [String], outDir: URL) throws {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        for file in files {
            let path = "\(galleryDir)/\(file)"
            let spec = try loadSpecOrThrow(path: path)
            var perOptions = options
            perOptions.example = nil
            perOptions.specPath = path
            let svg = try renderSVGString(options: perOptions, spec: spec)
            let outPath = outDir.appendingPathComponent(file.replacingOccurrences(of: ".json", with: ".svg"))
            guard let data = svg.data(using: .utf8) else {
                throw NSError(domain: "cp2-cli.gallery", code: 2, userInfo: [NSLocalizedDescriptionKey: "failed to encode SVG for \(file)"])
            }
            try data.write(to: outPath, options: .atomic)
            if options.verbose {
                print("Exported \(data.count) bytes to: \(outPath.path)")
            }
        }
    }
    let outURL = URL(fileURLWithPath: options.outPath)
    let baseOutDir: URL
    if options.outPath.lowercased().hasSuffix(".svg") {
        baseOutDir = outURL.deletingLastPathComponent().appendingPathComponent("gallery_lines", isDirectory: true)
    } else {
        baseOutDir = outURL
    }

    let straightFiles = allFiles.filter { !$0.contains("_wavy.v0.json") && !$0.contains("_wavy.json") }
    let wavyFiles = allFiles.filter { $0.contains("_wavy.v0.json") || $0.contains("_wavy.json") }

    switch mode {
    case .straight:
        try renderSubset(files: straightFiles, outDir: baseOutDir)
    case .wavy:
        try renderSubset(files: wavyFiles, outDir: baseOutDir)
    case .both:
        try renderSubset(files: straightFiles, outDir: baseOutDir.appendingPathComponent("straight", isDirectory: true))
        try renderSubset(files: wavyFiles, outDir: baseOutDir.appendingPathComponent("wavy", isDirectory: true))
    }
}

// MARK: - Settings / Path resolution

private func resolveEffectiveSettings(
    options: CLIOptions,
    spec: CP2Spec?
) -> (render: RenderSettings, reference: ReferenceLayer?) {
    var renderSettings = spec?.render ?? RenderSettings()
    if let canvas = options.canvasOverride { renderSettings.canvasPx = canvas }
    if let fit = options.fitOverride { renderSettings.fitMode = fit }
    if let padding = options.paddingOverride { renderSettings.paddingWorld = padding }
    if let clip = options.clipOverride { renderSettings.clipToFrame = clip }
    if let worldFrame = options.worldFrameOverride { renderSettings.worldFrame = worldFrame }

    var referenceLayer = spec?.reference
    if let refPath = options.referencePath ?? referenceLayer?.path {
        let base = referenceLayer ?? ReferenceLayer(path: refPath)
        referenceLayer = ReferenceLayer(
            path: refPath,
            translateWorld: options.referenceTranslate ?? base.translateWorld,
            scale: options.referenceScale ?? base.scale,
            rotateDeg: options.referenceRotateDeg ?? base.rotateDeg,
            opacity: options.referenceOpacity ?? base.opacity,
            lockPlacement: options.referenceLockOverride ?? base.lockPlacement
        )
    }
    return (renderSettings, referenceLayer)
}

private func resolveEffectivePath(
    options: CLIOptions,
    spec: CP2Spec?,
    warn: (String) -> Void
) throws -> (
    exampleName: String?,
    primitive: InkPrimitive?,
    path: SkeletonPath,
    resolvedHeartline: ResolvedHeartline?
) {
    let exampleName = options.example ?? spec?.example
    let preferredInkName = options.inkName ?? spec?.strokes?.first?.ink
    let inkSelection = pickInkPrimitive(spec?.ink, name: preferredInkName)
    if let preferredInkName, inkSelection == nil {
        throw InkContinuityError.missingInk(name: preferredInkName)
    }
    let inkPrimitive = inkSelection?.primitive
    var inkPaths: [SkeletonPath] = []
    var resolvedHeartline: ResolvedHeartline? = nil
    
    if let inkSelection, let primitive = inkSelection.primitive as InkPrimitive? {
        switch primitive {
        case .heartline(let heartline):
            let resolved = try resolveHeartline(
                name: inkSelection.name,
                heartline: heartline,
                ink: spec?.ink ?? Ink(stem: nil, entries: [:]),
                strict: options.strictHeartline,
                warn: warn
            )
            resolvedHeartline = resolved
            for subpath in resolved.subpaths {
                let segments = subpath.map { cubicForSegment($0) }
                if !segments.isEmpty { inkPaths.append(SkeletonPath(segments: segments)) }
            }
        default:
            inkPaths = try buildSkeletonPaths(
                name: inkSelection.name,
                primitive: primitive,
                strict: options.strictInk,
                epsilon: 1.0e-4,
                warn: warn
            )
        }
    }
    
    let path: SkeletonPath
    if let inkPath = inkPaths.first {
        if inkPaths.count > 1 {
            warn("ink continuity warning: multiple subpaths detected; sweeping first only")
            if options.strictInk || options.strictHeartline {
                throw InkContinuityError.discontinuity(name: inkSelection?.name ?? "ink", index: 0, dist: 0.0)
            }
        }
        path = inkPath
    } else if exampleName?.lowercased() == "scurve" {
        path = SkeletonPath(segments: [sCurveFixtureCubic()])
    } else if exampleName?.lowercased() == "fast_scurve" {
        path = SkeletonPath(segments: [fastSCurveFixtureCubic()])
    } else if exampleName?.lowercased() == "fast_scurve2" {
        path = SkeletonPath(segments: [fastSCurve2FixtureCubic()])
    } else if exampleName?.lowercased() == "twoseg" {
        path = twoSegFixturePath()
    } else if exampleName?.lowercased() == "jstem" {
        path = jStemFixturePath()
    } else if exampleName?.lowercased() == "j" {
        path = jFullFixturePath()
    } else if exampleName?.lowercased() == "j_serif_only" {
        path = jSerifOnlyFixturePath()
    } else if exampleName?.lowercased() == "poly3" {
        path = poly3FixturePath()
    } else {
        path = SkeletonPath(segments: [lineCubic(from: Vec2(0, 0), to: Vec2(0, 100))])
    }
    
    return (exampleName, inkPrimitive, path, resolvedHeartline)
}

private struct ResolvedStroke {
    let id: String?
    let inkName: String?
    let inkPrimitive: InkPrimitive?
    let resolvedHeartline: ResolvedHeartline?
    let path: SkeletonPath
    let params: StrokeParams?
    let startCap: CapStyle
    let endCap: CapStyle
}

private func resolveEffectiveStrokes(
    options: CLIOptions,
    spec: CP2Spec?,
    warn: (String) -> Void
) throws -> (
    exampleName: String?,
    strokes: [ResolvedStroke]
) {
    let exampleName = options.example ?? spec?.example
    if let strokes = spec?.strokes, !strokes.isEmpty {
        guard let ink = spec?.ink else {
            throw InkContinuityError.missingInk(name: strokes[0].ink)
        }
        var resolved: [ResolvedStroke] = []
        for stroke in strokes {
            guard let primitive = ink.entries[stroke.ink] else {
                throw InkContinuityError.missingInk(name: stroke.ink)
            }
            var resolvedHeartline: ResolvedHeartline? = nil
            var inkPaths: [SkeletonPath] = []
            switch primitive {
            case .heartline(let heartline):
                let resolvedHL = try resolveHeartline(
                    name: stroke.ink,
                    heartline: heartline,
                    ink: ink,
                    strict: options.strictHeartline,
                    warn: warn
                )
                resolvedHeartline = resolvedHL
                for subpath in resolvedHL.subpaths {
                    let segments = subpath.map { cubicForSegment($0) }
                    if !segments.isEmpty { inkPaths.append(SkeletonPath(segments: segments)) }
                }
            default:
                inkPaths = try buildSkeletonPaths(
                    name: stroke.ink,
                    primitive: primitive,
                    strict: options.strictInk,
                    epsilon: 1.0e-4,
                    warn: warn
                )
            }

            guard let path = inkPaths.first else {
                throw InkContinuityError.emptyHeartline(name: stroke.ink)
            }
            if inkPaths.count > 1 {
                warn("ink continuity warning: \(stroke.ink) multiple subpaths detected; sweeping first only")
                if options.strictInk || options.strictHeartline {
                    throw InkContinuityError.discontinuity(name: stroke.ink, index: 0, dist: 0.0)
                }
            }
            resolved.append(
                ResolvedStroke(
                    id: stroke.id,
                    inkName: stroke.ink,
                    inkPrimitive: primitive,
                    resolvedHeartline: resolvedHeartline,
                    path: path,
                    params: stroke.params,
                    startCap: stroke.params?.startCap ?? .butt,
                    endCap: stroke.params?.endCap ?? .butt
                )
            )
        }
        return (exampleName, resolved)
    }

    let (resolvedExample, inkPrimitive, path, resolvedHeartline) = try resolveEffectivePath(
        options: options,
        spec: spec,
        warn: warn
    )
    let fallback = ResolvedStroke(
        id: nil,
        inkName: nil,
        inkPrimitive: inkPrimitive,
        resolvedHeartline: resolvedHeartline,
        path: path,
        params: spec?.strokes?.first?.params,
        startCap: spec?.strokes?.first?.params?.startCap ?? .butt,
        endCap: spec?.strokes?.first?.params?.endCap ?? .butt
    )
    return (resolvedExample, [fallback])
}
