import Foundation
import CP2Geometry
import CP2Skeleton
import CP2ResolveOverlap
import CP2Domain

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

func dumpSoupNode(
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

func emitSoupNeighborhood(_ report: SoupNeighborhoodReport, label: String) {
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

func formatDegreeHistogram(_ histogram: [Int: Int]) -> String {
    let deg0 = histogram[0, default: 0]
    let deg1 = histogram[1, default: 0]
    let deg2 = histogram[2, default: 0]
    let deg3 = histogram[3, default: 0]
    let deg4plus = histogram.filter { $0.key >= 4 }.map { $0.value }.reduce(0, +)
    return String(format: "deg0=%d deg1=%d deg2=%d deg3=%d deg4+=%d", deg0, deg1, deg2, deg3, deg4plus)
}

func ensureClosedRing(_ ring: [Vec2]) -> [Vec2] {
    guard !ring.isEmpty else { return [] }
    if let first = ring.first, let last = ring.last, !Epsilon.approxEqual(first, last) {
        return ring + [first]
    }
    return ring
}

func normalizedRing(_ ring: [Vec2], clockwise: Bool) -> [Vec2] {
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

func ringCentroid(_ ring: [Vec2]) -> Vec2 {
    guard !ring.isEmpty else { return Vec2(0, 0) }
    var sum = Vec2(0, 0)
    for point in ring {
        sum = sum + point
    }
    let denom = Double(ring.count)
    return Vec2(sum.x / denom, sum.y / denom)
}

func pointInRing(_ point: Vec2, ring: [Vec2]) -> Bool {
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

func counterIsInsideInk(counter: [Vec2], inkRings: [[Vec2]]) -> Bool {
    guard !counter.isEmpty, !inkRings.isEmpty else { return false }
    let probe = ringCentroid(counter)
    for ring in inkRings {
        if pointInRing(probe, ring: ring) { return true }
    }
    return false
}

func sampleRingPoints(for segment: InkSegment, steps: Int) -> [Vec2] {
    switch segment {
    case .line(let line):
        return [vec(line.p0), vec(line.p1)]
    case .cubic(let cubic):
        return sampleInkCubicPoints(cubic, steps: steps)
    }
}

func ringFromSegments(_ segments: [InkSegment], steps: Int) -> [Vec2] {
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

func counterRings(
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

func ellipseRing(
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


func inkPrimitiveSummary(_ primitive: InkPrimitive) -> String {
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

func segmentKind(_ segment: InkSegment) -> String {
    switch segment {
    case .line:
        return "line"
    case .cubic:
        return "cubic"
    }
}

func dumpHeartlineResolve(
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
    let warnHandler: (String) -> Void = { message in
        if let warnSink {
            warnSink(message)
        } else {
            warn(message)
        }
    }

    let traceSink: TraceSink? = {
        let wantsTrace = options.debugDumpCapEndpoints ||
            options.debugSweep ||
            options.debugRingTopology ||
            options.debugRingSelfXHit != nil ||
            options.debugSoupNeighborhoodCenter != nil
        return wantsTrace ? StdoutTraceSink() : nil
    }()

    let model = try RenderGlyphUseCase.render(
        options: options,
        spec: spec,
        warnHandler: warnHandler,
        traceSink: traceSink
    )

    if model.effectiveOptions.refFitToFrame,
       let viewBox = model.referenceViewBox,
       let layer = model.referenceLayer {
        let fit = fitReferenceTransform(referenceViewBox: viewBox, to: model.frame)
        print(String(format: "ref-fit translate=(%.6f,%.6f) scale=%.6f", fit.translate.x, fit.translate.y, fit.scale))
        if let writePath = model.effectiveOptions.refFitWritePath {
            var outSpec = spec ?? CP2Spec()
            outSpec.reference = ReferenceLayer(path: layer.path, translateWorld: fit.translate, scale: fit.scale, rotateDeg: layer.rotateDeg, opacity: layer.opacity, lockPlacement: layer.lockPlacement)
            writeSpec(outSpec, path: writePath)
        }
    }

    return SVGRenderer.render(model: model, options: model.effectiveOptions, warn: warnHandler)
}

struct AngleModeDebugMetrics {
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

func emitAngleModeDebug(
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
    let traceSink: TraceSink? = {
        let wantsTrace = options.debugDumpCapEndpoints ||
            options.debugSweep ||
            options.debugRingTopology ||
            options.debugRingSelfXHit != nil ||
            options.debugSoupNeighborhoodCenter != nil
        return wantsTrace ? StdoutTraceSink() : nil
    }()

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
            endCap: stroke.endCap,
            traceSink: traceSink
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

func resolveEffectiveSettings(
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

struct ResolvedStroke {
    let id: String?
    let inkName: String?
    let inkPrimitive: InkPrimitive?
    let resolvedHeartline: ResolvedHeartline?
    let path: SkeletonPath
    let params: StrokeParams?
    let startCap: CapStyle
    let endCap: CapStyle
}

func resolveEffectiveStrokes(
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
