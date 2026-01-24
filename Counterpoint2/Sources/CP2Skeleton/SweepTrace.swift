import Foundation
import CP2Geometry

// NOTE:
// This file intentionally contains the boundary soup (stroke sweep as boundary segments)
// plus loop tracing helpers. It now supports Step 3.5 sampling diagnostics by emitting a
// SamplingResult (ts + trace) via an optional callback.
//
// Requirements:
// - CP2Skeleton must already define:
//   - SkeletonPath
//   - SkeletonPathParameterization (position/tangent at globalT)
//   - SamplingConfig, SamplingResult, SampleAction, SampleReason, SampleErrors
//   - GlobalTSampler
//   - RailProbe, RailSample
// - CP2Geometry defines Vec2, AABB, Epsilon, SnapKey, etc.

public enum CapEdgeRole: String, Codable, Equatable, Sendable {
    case joinLR
    case walkL
    case walkR
    case unknown
}

public enum EdgeSource: Equatable, Codable, CustomStringConvertible, Sendable {
    case railLeft
    case railRight
    case capStart
    case capEnd
    case capStartEdge(role: CapEdgeRole, detail: String)
    case capEndEdge(role: CapEdgeRole, detail: String)
    case join
    case sanitizeRemoveShort
    case sanitizeDedupe
    case repairStitch
    case repairCloseLoop
    case unknown(String)

    public var description: String {
        switch self {
        case .railLeft: return "railLeft"
        case .railRight: return "railRight"
        case .capStart: return "capStart"
        case .capEnd: return "capEnd"
        case .capStartEdge(let role, let detail): return "capStart.\(role.rawValue)(\(detail))"
        case .capEndEdge(let role, let detail): return "capEnd.\(role.rawValue)(\(detail))"
        case .join: return "join"
        case .sanitizeRemoveShort: return "sanitizeRemoveShort"
        case .sanitizeDedupe: return "sanitizeDedupe"
        case .repairStitch: return "repairStitch"
        case .repairCloseLoop: return "repairCloseLoop"
        case .unknown(let tag): return "unknown(\(tag))"
        }
    }

    public var isUnknown: Bool {
        if case .unknown = self { return true }
        return false
    }
}

public struct Segment2: Equatable, Codable, Sendable {
    public let a: Vec2
    public let b: Vec2
    public let source: EdgeSource

    public init(_ a: Vec2, _ b: Vec2, source: EdgeSource = .unknown("unspecified")) {
        self.a = a
        self.b = b
        self.source = source
    }
}

public struct CapEndpointPair: Equatable, Sendable {
    public let left: Vec2
    public let right: Vec2
    public let leftKey: SnapKey
    public let rightKey: SnapKey
    public let distance: Double

    public init(left: Vec2, right: Vec2, leftKey: SnapKey, rightKey: SnapKey, distance: Double) {
        self.left = left
        self.right = right
        self.leftKey = leftKey
        self.rightKey = rightKey
        self.distance = distance
    }
}

public struct CapJoinDebug: Equatable, Sendable {
    public let a: Vec2
    public let b: Vec2
    public let aKey: SnapKey
    public let bKey: SnapKey
    public let length: Double
    public let source: EdgeSource

    public init(a: Vec2, b: Vec2, aKey: SnapKey, bKey: SnapKey, length: Double, source: EdgeSource) {
        self.a = a
        self.b = b
        self.aKey = aKey
        self.bKey = bKey
        self.length = length
        self.source = source
    }
}

public struct CapEndpointsDebug: Equatable, Sendable {
    public let eps: Double
    public let intendedStart: CapEndpointPair
    public let intendedEnd: CapEndpointPair
    public let emittedStartJoin: CapJoinDebug?
    public let emittedEndJoin: CapJoinDebug?

    public init(
        eps: Double,
        intendedStart: CapEndpointPair,
        intendedEnd: CapEndpointPair,
        emittedStartJoin: CapJoinDebug?,
        emittedEndJoin: CapJoinDebug?
    ) {
        self.eps = eps
        self.intendedStart = intendedStart
        self.intendedEnd = intendedEnd
        self.emittedStartJoin = emittedStartJoin
        self.emittedEndJoin = emittedEndJoin
    }
}

public struct RailEndpointDebug: Equatable, Sendable {
    public let index: Int
    public let left: Vec2
    public let right: Vec2
    public let leftKey: SnapKey
    public let rightKey: SnapKey
    public let distance: Double

    public init(index: Int, left: Vec2, right: Vec2, leftKey: SnapKey, rightKey: SnapKey, distance: Double) {
        self.index = index
        self.left = left
        self.right = right
        self.leftKey = leftKey
        self.rightKey = rightKey
        self.distance = distance
    }
}

public struct RailDebugSummary: Equatable, Sendable {
    public let count: Int
    public let start: RailEndpointDebug
    public let end: RailEndpointDebug
    public let prefix: [RailEndpointDebug]

    public init(count: Int, start: RailEndpointDebug, end: RailEndpointDebug, prefix: [RailEndpointDebug]) {
        self.count = count
        self.start = start
        self.end = end
        self.prefix = prefix
    }
}

public struct RailSampleFrame: Equatable, Sendable {
    public let index: Int
    public let center: Vec2
    public let tangent: Vec2
    public let normal: Vec2
    public let widthLeft: Double
    public let widthRight: Double
    public let widthTotal: Double
    public let left: Vec2
    public let right: Vec2

    public init(
        index: Int,
        center: Vec2,
        tangent: Vec2,
        normal: Vec2,
        widthLeft: Double,
        widthRight: Double,
        widthTotal: Double,
        left: Vec2,
        right: Vec2
    ) {
        self.index = index
        self.center = center
        self.tangent = tangent
        self.normal = normal
        self.widthLeft = widthLeft
        self.widthRight = widthRight
        self.widthTotal = widthTotal
        self.left = left
        self.right = right
    }
}

public struct RailInvariantCheck: Equatable, Sendable {
    public let index: Int
    public let distLR: Double
    public let expectedWidth: Double
    public let widthErr: Double
    public let dotTR: Double
    public let normalLen: Double

    public init(
        index: Int,
        distLR: Double,
        expectedWidth: Double,
        widthErr: Double,
        dotTR: Double,
        normalLen: Double
    ) {
        self.index = index
        self.distLR = distLR
        self.expectedWidth = expectedWidth
        self.widthErr = widthErr
        self.dotTR = dotTR
        self.normalLen = normalLen
    }
}

public struct RailFrameDiagnostics: Equatable, Sendable {
    public let frames: [RailSampleFrame]
    public let checks: [RailInvariantCheck]

    public init(frames: [RailSampleFrame], checks: [RailInvariantCheck]) {
        self.frames = frames
        self.checks = checks
    }
}

public struct SweepStyle: Equatable, Codable {
    public let width: Double
    public let height: Double
    public let angle: Double
    public let offset: Double   // reserved; can be 0 for now

    public init(width: Double, height: Double, angle: Double, offset: Double) {
        self.width = width
        self.height = height
        self.angle = angle
        self.offset = offset
    }
}

public func buildCaps(
    leftRail: [Vec2],
    rightRail: [Vec2],
    capIndexBase: Int = 0
) -> [Segment2] {
    guard let leftStart = leftRail.first, let leftEnd = leftRail.last else {
        return []
    }
    guard let rightStart = rightRail.first, let rightEnd = rightRail.last else {
        return []
    }

    let startDistance = (leftStart - rightStart).length
    let startAltDistance = (leftStart - rightEnd).length
    let useReversedRight = startAltDistance + Epsilon.defaultValue < startDistance

    let rightForStart = useReversedRight ? rightEnd : rightStart
    let rightForEnd = useReversedRight ? rightStart : rightEnd

    let detail = "capIndex=\(capIndexBase)"
    return [
        Segment2(leftStart, rightForStart, source: .capStartEdge(role: .joinLR, detail: detail)),
        Segment2(rightForEnd, leftEnd, source: .capEndEdge(role: .joinLR, detail: detail))
    ]
}

/// General boundary soup generator that supports:
/// - uniform samples (fixed)
/// - adaptive samples (GlobalTSampler: flatness + rail deviation)
/// - optional alpha warp via warpGT
/// - optional sampling diagnostics via debugSampling callback
public func boundarySoupGeneral(
    path: SkeletonPath,
    sampleCount: Int,
    arcSamplesPerSegment: Int = 256,
    adaptiveSampling: Bool = false,
    flatnessEps: Double = 0.25,
    railEps: Double = 0.25,
    maxDepth: Int = 12,
    maxSamples: Int = 512,
    warpGT: @escaping (Double) -> Double = { $0 },
    styleAtGT: @escaping (Double) -> SweepStyle,
    debugSampling: ((SamplingResult) -> Void)? = nil,
    debugCapEndpoints: ((CapEndpointsDebug) -> Void)? = nil,
    debugRailSummary: ((RailDebugSummary) -> Void)? = nil,
    debugRailFrames: (([RailSampleFrame]) -> Void)? = nil
) -> [Segment2] {

    let param = SkeletonPathParameterization(path: path, samplesPerSegment: arcSamplesPerSegment)

    // ---- Sampling (Step 3+: GlobalTSampler) ----
    let positionAtGT: GlobalTSampler.PositionAtS = { gt in
        param.position(globalT: gt)
    }

    // RailProbe that matches EXACTLY how we will compute left/right points per GT.
    let probe = BoundarySoupRailProbe(param: param, warpGT: warpGT, styleAtGT: styleAtGT)

    var cfg = SamplingConfig()
    if adaptiveSampling {
        cfg.mode = .adaptive
    } else {
        cfg.mode = .fixed(count: max(2, sampleCount))
    }
    cfg.flatnessEps = flatnessEps
    cfg.railEps = railEps
    cfg.maxDepth = maxDepth
    cfg.maxSamples = maxSamples

    let sampler = GlobalTSampler()

    // IMPORTANT:
    // - When adaptiveSampling is false, we pass railProbe=nil to avoid doing
    //   any extra work or generating trace noise.
    let sampling = sampler.sampleGlobalT(
        config: cfg,
        positionAt: positionAtGT,
        railProbe: adaptiveSampling ? probe : nil
    )

    // Step 3.5: expose sampling trace to the caller (e.g., cp2-cli debug SVG)
    debugSampling?(sampling)

    // Preserve the older behavior: even in adaptive mode, ensure a minimum uniform density.
    let samples: [Double] = adaptiveSampling
        ? mergeWithUniformSamples(sampling.ts, minCount: max(2, sampleCount))
        : sampling.ts

    let count = max(2, samples.count)

    var left: [Vec2] = []
    var right: [Vec2] = []
    left.reserveCapacity(count)
    right.reserveCapacity(count)

    let wantsFrames = debugRailFrames != nil || debugRailSummary != nil
    var frames: [RailSampleFrame] = []
    if wantsFrames {
        frames.reserveCapacity(count)
    }

    // ---- Compute left/right rails at each sample ----
    for (index, gt) in samples.enumerated() {
        if wantsFrames {
            let (rail, frame) = computeRailSampleFrame(
                param: param,
                warpGT: warpGT,
                styleAtGT: styleAtGT,
                gt: gt,
                index: index
            )
            left.append(rail.left)
            right.append(rail.right)
            frames.append(frame)
        } else {
            let rail = probe.rails(atGlobalT: gt)
            left.append(rail.left)
            right.append(rail.right)
        }
    }
    if let debugRailFrames {
        debugRailFrames(frames)
    }
    if let debugRailSummary {
        let rails = zip(left, right).map { RailSample(left: $0.0, right: $0.1) }
        let summary = computeRailDebugSummary(
            rails: rails,
            keyOf: { Epsilon.snapKey($0, eps: Epsilon.defaultValue) },
            prefixCount: rails.count
        )
        debugRailSummary(summary)
    }

    // MARK: EDGE CREATION SITES
    // - boundarySoupGeneral: left forward (railLeft), right backward (railRight), caps (capStart/capEnd)
    // - traceLoops: consumes segments; no creation
    //
    // ---- Stitch boundary soup segments (left forward, right backward, caps) ----
    var segments: [Segment2] = []
    segments.reserveCapacity(count * 2 + 2)

    for i in 0..<(count - 1) {
        segments.append(Segment2(left[i], left[i + 1], source: .railLeft))
    }
    for i in stride(from: count - 1, to: 0, by: -1) {
        segments.append(Segment2(right[i], right[i - 1], source: .railRight))
    }
    let caps = buildCaps(leftRail: left, rightRail: right, capIndexBase: 0)
    segments.append(contentsOf: caps)
    if let debugCapEndpoints, let capInfo = computeCapEndpointsDebug(
        leftRail: left,
        rightRail: right,
        capSegments: caps,
        eps: Epsilon.defaultValue
    ) {
        debugCapEndpoints(capInfo)
    }

    return segments
}

public func boundarySoup(
    path: SkeletonPath,
    width: Double,
    height: Double,
    effectiveAngle: Double,
    sampleCount: Int,
    arcSamplesPerSegment: Int = 256,
    adaptiveSampling: Bool = false,
    flatnessEps: Double = 0.25,
    railEps: Double = 0.25,
    maxDepth: Int = 12,
    maxSamples: Int = 512,
    debugSampling: ((SamplingResult) -> Void)? = nil,
    debugCapEndpoints: ((CapEndpointsDebug) -> Void)? = nil,
    debugRailSummary: ((RailDebugSummary) -> Void)? = nil,
    debugRailFrames: (([RailSampleFrame]) -> Void)? = nil
) -> [Segment2] {
    boundarySoupGeneral(
        path: path,
        sampleCount: sampleCount,
        arcSamplesPerSegment: arcSamplesPerSegment,
        adaptiveSampling: adaptiveSampling,
        flatnessEps: flatnessEps,
        railEps: railEps,
        maxDepth: maxDepth,
        maxSamples: maxSamples,
        styleAtGT: { _ in SweepStyle(width: width, height: height, angle: effectiveAngle, offset: 0.0) },
        debugSampling: debugSampling,
        debugCapEndpoints: debugCapEndpoints,
        debugRailSummary: debugRailSummary,
        debugRailFrames: debugRailFrames
    )
}

public func boundarySoupVariableWidth(
    path: SkeletonPath,
    height: Double,
    effectiveAngle: Double,
    sampleCount: Int,
    arcSamplesPerSegment: Int = 256,
    adaptiveSampling: Bool = false,
    flatnessEps: Double = 0.25,
    railEps: Double = 0.25,
    maxDepth: Int = 12,
    maxSamples: Int = 512,
    widthAtT: @escaping (Double) -> Double,
    debugSampling: ((SamplingResult) -> Void)? = nil,
    debugCapEndpoints: ((CapEndpointsDebug) -> Void)? = nil,
    debugRailSummary: ((RailDebugSummary) -> Void)? = nil,
    debugRailFrames: (([RailSampleFrame]) -> Void)? = nil
) -> [Segment2] {
    boundarySoupGeneral(
        path: path,
        sampleCount: sampleCount,
        arcSamplesPerSegment: arcSamplesPerSegment,
        adaptiveSampling: adaptiveSampling,
        flatnessEps: flatnessEps,
        railEps: railEps,
        maxDepth: maxDepth,
        maxSamples: maxSamples,
        styleAtGT: { t in SweepStyle(width: widthAtT(t), height: height, angle: effectiveAngle, offset: 0.0) },
        debugSampling: debugSampling,
        debugCapEndpoints: debugCapEndpoints,
        debugRailSummary: debugRailSummary,
        debugRailFrames: debugRailFrames
    )
}

public func boundarySoupVariableWidthAngle(
    path: SkeletonPath,
    height: Double,
    sampleCount: Int,
    arcSamplesPerSegment: Int = 256,
    adaptiveSampling: Bool = false,
    flatnessEps: Double = 0.25,
    railEps: Double = 0.25,
    maxDepth: Int = 12,
    maxSamples: Int = 512,
    widthAtT: @escaping (Double) -> Double,
    angleAtT: @escaping (Double) -> Double,
    debugSampling: ((SamplingResult) -> Void)? = nil,
    debugCapEndpoints: ((CapEndpointsDebug) -> Void)? = nil,
    debugRailSummary: ((RailDebugSummary) -> Void)? = nil,
    debugRailFrames: (([RailSampleFrame]) -> Void)? = nil
) -> [Segment2] {
    boundarySoupGeneral(
        path: path,
        sampleCount: sampleCount,
        arcSamplesPerSegment: arcSamplesPerSegment,
        adaptiveSampling: adaptiveSampling,
        flatnessEps: flatnessEps,
        railEps: railEps,
        maxDepth: maxDepth,
        maxSamples: maxSamples,
        styleAtGT: { t in SweepStyle(width: widthAtT(t), height: height, angle: angleAtT(t), offset: 0.0) },
        debugSampling: debugSampling,
        debugCapEndpoints: debugCapEndpoints,
        debugRailSummary: debugRailSummary,
        debugRailFrames: debugRailFrames
    )
}

public func boundarySoupVariableWidthAngleAlpha(
    path: SkeletonPath,
    height: Double,
    sampleCount: Int,
    arcSamplesPerSegment: Int = 256,
    adaptiveSampling: Bool = false,
    flatnessEps: Double = 0.25,
    railEps: Double = 0.25,
    maxDepth: Int = 12,
    maxSamples: Int = 512,
    widthAtT: @escaping (Double) -> Double,
    angleAtT: @escaping (Double) -> Double,
    alphaAtT: @escaping (Double) -> Double,
    alphaStart: Double,
    debugSampling: ((SamplingResult) -> Void)? = nil,
    debugCapEndpoints: ((CapEndpointsDebug) -> Void)? = nil,
    debugRailSummary: ((RailDebugSummary) -> Void)? = nil,
    debugRailFrames: (([RailSampleFrame]) -> Void)? = nil
) -> [Segment2] {
    boundarySoupGeneral(
        path: path,
        sampleCount: sampleCount,
        arcSamplesPerSegment: arcSamplesPerSegment,
        adaptiveSampling: adaptiveSampling,
        flatnessEps: flatnessEps,
        railEps: railEps,
        maxDepth: maxDepth,
        maxSamples: maxSamples,
        warpGT: { gt in applyAlphaWarp(t: gt, alphaValue: alphaAtT(gt), alphaStart: alphaStart) },
        styleAtGT: { t in SweepStyle(width: widthAtT(t), height: height, angle: angleAtT(t), offset: 0.0) },
        debugSampling: debugSampling,
        debugCapEndpoints: debugCapEndpoints,
        debugRailSummary: debugRailSummary,
        debugRailFrames: debugRailFrames
    )
}

public struct BoundarySoupResult: Sendable {
    public let segments: [Segment2]
    public let sampling: SamplingResult?

    public init(segments: [Segment2], sampling: SamplingResult?) {
        self.segments = segments
        self.sampling = sampling
    }
}

// MARK: - Private RailProbe matching boundary soup rail selection

private struct BoundarySoupRailProbe: RailProbe {
    let param: SkeletonPathParameterization
    let warpGT: (Double) -> Double
    let styleAtGT: (Double) -> SweepStyle

    func rails(atGlobalT gt: Double) -> RailSample {
        computeRailSampleFrame(
            param: param,
            warpGT: warpGT,
            styleAtGT: styleAtGT,
            gt: gt,
            index: -1
        ).sample
    }
}

// MARK: - Geometry helpers

private func computeRailSampleFrame(
    param: SkeletonPathParameterization,
    warpGT: (Double) -> Double,
    styleAtGT: (Double) -> SweepStyle,
    gt: Double,
    index: Int
) -> (sample: RailSample, frame: RailSampleFrame) {
    let point = param.position(globalT: gt)
    let tangent = param.tangent(globalT: gt).normalized()
    let normal = Vec2(-tangent.y, tangent.x)

    let warped = warpGT(gt)
    let style = styleAtGT(warped)

    let center = point + normal * style.offset

    let corners = rectangleCorners(
        center: center,
        tangent: tangent,
        normal: normal,
        width: style.width,
        height: style.height,
        effectiveAngle: style.angle
    )

    var minDot = Double.greatestFiniteMagnitude
    var maxDot = -Double.greatestFiniteMagnitude
    var leftPoint = center
    var rightPoint = center

    for corner in corners {
        let d = corner.dot(normal)
        if d < minDot {
            minDot = d
            leftPoint = corner
        }
        if d > maxDot {
            maxDot = d
            rightPoint = corner
        }
    }

    let sample = RailSample(left: leftPoint, right: rightPoint)
    let halfWidth = 0.5 * style.width
    let frame = RailSampleFrame(
        index: index,
        center: center,
        tangent: tangent,
        normal: normal,
        widthLeft: halfWidth,
        widthRight: halfWidth,
        widthTotal: style.width,
        left: leftPoint,
        right: rightPoint
    )
    return (sample, frame)
}

private func rectangleCorners(
    center: Vec2,
    tangent: Vec2,
    normal: Vec2,
    width: Double,
    height: Double,
    effectiveAngle: Double
) -> [Vec2] {
    let halfW = width * 0.5
    let halfH = height * 0.5
    let localCorners: [Vec2] = [
        Vec2(-halfW, -halfH),
        Vec2(halfW, -halfH),
        Vec2(halfW, halfH),
        Vec2(-halfW, halfH)
    ]
    let cosA = cos(effectiveAngle)
    let sinA = sin(effectiveAngle)
    return localCorners.map { corner in
        let rotated = Vec2(
            corner.x * cosA - corner.y * sinA,
            corner.x * sinA + corner.y * cosA
        )
        let world = tangent * rotated.y + normal * rotated.x
        return center + world
    }
}

private func applyAlphaWarp(t: Double, alphaValue: Double, alphaStart: Double) -> Double {
    if t <= alphaStart || abs(alphaValue) <= Epsilon.defaultValue {
        return t
    }
    let span = max(Epsilon.defaultValue, 1.0 - alphaStart)
    let phase = max(0.0, min(1.0, (t - alphaStart) / span))
    let exponent = max(0.05, 1.0 + alphaValue)
    let biased = pow(phase, exponent)
    return alphaStart + biased * span
}

// MARK: - Sampling utilities (unchanged)

private func uniformSamples(count: Int) -> [Double] {
    let clamped = max(2, count)
    return (0..<clamped).map { Double($0) / Double(clamped - 1) }
}

private func mergeWithUniformSamples(_ samples: [Double], minCount: Int) -> [Double] {
    let minSamples = max(2, minCount)
    if samples.count >= minSamples {
        return samples
    }
    let combined = (samples + uniformSamples(count: minSamples)).sorted()
    var result: [Double] = []
    result.reserveCapacity(combined.count)
    var last: Double? = nil
    for t in combined {
        if let previous = last, abs(t - previous) <= 1.0e-9 {
            continue
        }
        result.append(t)
        last = t
    }
    return result
}

// MARK: - Loop tracing (unchanged from your pasted file)

public struct TraceStepCandidate: Equatable {
    public let toKey: SnapKey
    public let to: Vec2
    public let length: Double
    public let angle: Double
    public let scoreKey: SnapKey
    public let isChosen: Bool
    public let source: EdgeSource

    public init(
        toKey: SnapKey,
        to: Vec2,
        length: Double,
        angle: Double,
        scoreKey: SnapKey,
        isChosen: Bool,
        source: EdgeSource
    ) {
        self.toKey = toKey
        self.to = to
        self.length = length
        self.angle = angle
        self.scoreKey = scoreKey
        self.isChosen = isChosen
        self.source = source
    }
}

public struct TraceStepNeighbor: Equatable {
    public let key: SnapKey
    public let pos: Vec2
    public let length: Double
    public let dir: Vec2
    public let source: EdgeSource

    public init(key: SnapKey, pos: Vec2, length: Double, dir: Vec2, source: EdgeSource) {
        self.key = key
        self.pos = pos
        self.length = length
        self.dir = dir
        self.source = source
    }
}

public struct TraceStepInfo: Equatable {
    public let ringIndex: Int
    public let stepIndex: Int
    public let fromKey: SnapKey
    public let toKey: SnapKey
    public let from: Vec2
    public let to: Vec2
    public let incoming: Vec2
    public let candidates: [TraceStepCandidate]
    public let fromNeighbors: [TraceStepNeighbor]
    public let toNeighbors: [TraceStepNeighbor]

    public init(
        ringIndex: Int,
        stepIndex: Int,
        fromKey: SnapKey,
        toKey: SnapKey,
        from: Vec2,
        to: Vec2,
        incoming: Vec2,
        candidates: [TraceStepCandidate],
        fromNeighbors: [TraceStepNeighbor],
        toNeighbors: [TraceStepNeighbor]
    ) {
        self.ringIndex = ringIndex
        self.stepIndex = stepIndex
        self.fromKey = fromKey
        self.toKey = toKey
        self.from = from
        self.to = to
        self.incoming = incoming
        self.candidates = candidates
        self.fromNeighbors = fromNeighbors
        self.toNeighbors = toNeighbors
    }
}

public func traceLoops(
    segments: [Segment2],
    eps: Double,
    debugStep: ((TraceStepInfo) -> Void)? = nil
) -> [[Vec2]] {
    guard !segments.isEmpty else { return [] }

    let graph = buildSoupGraph(segments: segments, eps: eps)
    var adjacency = graph.adjacency
    var edges = graph.edges
    let pointForKey = graph.pointForKey
    let edgeSources = graph.edgeSources

    var rings: [[SnapKey]] = []
    var ringIndex = 0
    while let startEdge = edges.sorted(by: edgeLess).first {
        edges.remove(startEdge)
        let start = startEdge.a
        let next = startEdge.b
        var ring: [SnapKey] = [start, next]
        var prev = start
        var curr = next
        var stepIndex = 0

        if let debugStep {
            let candidates = adjacency[start] ?? []
            let info = makeTraceStepInfo(
                ringIndex: ringIndex,
                stepIndex: stepIndex,
                fromKey: start,
                toKey: next,
                candidates: candidates,
                chosen: next,
                incomingFrom: start,
                incomingTo: next,
                pointForKey: pointForKey,
                adjacency: adjacency,
                edgeSources: edgeSources
            )
            debugStep(info)
            stepIndex += 1
        }

        while curr != start {
            guard let neighbors = adjacency[curr] else { break }
            var candidates = neighbors.filter { edges.contains(EdgeKey(curr, $0)) }
            if candidates.count > 1 {
                let nonPrev = candidates.filter { $0 != prev }
                candidates = nonPrev.isEmpty ? candidates : nonPrev
            }
            guard let chosen = candidates.sorted(by: snapKeyLess).first else { break }
            if let debugStep {
                let info = makeTraceStepInfo(
                    ringIndex: ringIndex,
                    stepIndex: stepIndex,
                    fromKey: curr,
                    toKey: chosen,
                    candidates: candidates,
                    chosen: chosen,
                    incomingFrom: prev,
                    incomingTo: curr,
                    pointForKey: pointForKey,
                    adjacency: adjacency,
                    edgeSources: edgeSources
                )
                debugStep(info)
                stepIndex += 1
            }
            edges.remove(EdgeKey(curr, chosen))
            ring.append(chosen)
            prev = curr
            curr = chosen
        }
        if ring.first != ring.last {
            ring.append(ring.first!)
        }
        rings.append(ring)
        ringIndex += 1
    }

    let worldRings = rings.map { ringKeys in
        ringKeys.compactMap { pointForKey[$0] }
    }.map(dedupRing)
    return worldRings.filter { $0.count >= 4 }
}

public struct SoupNeighborEdge: Equatable {
    public let to: SnapKey
    public let toPos: Vec2
    public let len: Double
    public let source: EdgeSource

    public init(to: SnapKey, toPos: Vec2, len: Double, source: EdgeSource) {
        self.to = to
        self.toPos = toPos
        self.len = len
        self.source = source
    }
}

public struct SoupNodeAnomaly: Equatable {
    public let key: SnapKey
    public let pos: Vec2
    public let outCount: Int
    public let inCount: Int
    public let outNeighbors: [SoupNeighborEdge]
    public let inNeighbors: [SoupNeighborEdge]

    public init(
        key: SnapKey,
        pos: Vec2,
        outCount: Int,
        inCount: Int,
        outNeighbors: [SoupNeighborEdge],
        inNeighbors: [SoupNeighborEdge]
    ) {
        self.key = key
        self.pos = pos
        self.outCount = outCount
        self.inCount = inCount
        self.outNeighbors = outNeighbors
        self.inNeighbors = inNeighbors
    }
}

public struct SoupDegreeStats: Equatable {
    public let nodeCount: Int
    public let edgeCount: Int
    public let degreeHistogram: [Int: Int]
    public let anomalies: [SoupNodeAnomaly]

    public init(
        nodeCount: Int,
        edgeCount: Int,
        degreeHistogram: [Int: Int],
        anomalies: [SoupNodeAnomaly]
    ) {
        self.nodeCount = nodeCount
        self.edgeCount = edgeCount
        self.degreeHistogram = degreeHistogram
        self.anomalies = anomalies
    }
}

public func computeCapEndpointsDebug(
    leftRail: [Vec2],
    rightRail: [Vec2],
    capSegments: [Segment2],
    eps: Double
) -> CapEndpointsDebug? {
    guard let leftStart = leftRail.first, let leftEnd = leftRail.last else {
        return nil
    }
    guard let rightStart = rightRail.first, let rightEnd = rightRail.last else {
        return nil
    }

    let intendedStart = CapEndpointPair(
        left: leftStart,
        right: rightStart,
        leftKey: Epsilon.snapKey(leftStart, eps: eps),
        rightKey: Epsilon.snapKey(rightStart, eps: eps),
        distance: (leftStart - rightStart).length
    )
    let intendedEnd = CapEndpointPair(
        left: leftEnd,
        right: rightEnd,
        leftKey: Epsilon.snapKey(leftEnd, eps: eps),
        rightKey: Epsilon.snapKey(rightEnd, eps: eps),
        distance: (leftEnd - rightEnd).length
    )

    let startJoin = capSegments.first { seg in
        switch seg.source {
        case .capStartEdge(let role, _):
            return role == .joinLR
        case .capStart:
            return true
        default:
            return false
        }
    }
    let endJoin = capSegments.first { seg in
        switch seg.source {
        case .capEndEdge(let role, _):
            return role == .joinLR
        case .capEnd:
            return true
        default:
            return false
        }
    }

    let startDebug: CapJoinDebug?
    if let seg = startJoin {
        startDebug = CapJoinDebug(
            a: seg.a,
            b: seg.b,
            aKey: Epsilon.snapKey(seg.a, eps: eps),
            bKey: Epsilon.snapKey(seg.b, eps: eps),
            length: (seg.b - seg.a).length,
            source: seg.source
        )
    } else {
        startDebug = nil
    }

    let endDebug: CapJoinDebug?
    if let seg = endJoin {
        endDebug = CapJoinDebug(
            a: seg.a,
            b: seg.b,
            aKey: Epsilon.snapKey(seg.a, eps: eps),
            bKey: Epsilon.snapKey(seg.b, eps: eps),
            length: (seg.b - seg.a).length,
            source: seg.source
        )
    } else {
        endDebug = nil
    }

    return CapEndpointsDebug(
        eps: eps,
        intendedStart: intendedStart,
        intendedEnd: intendedEnd,
        emittedStartJoin: startDebug,
        emittedEndJoin: endDebug
    )
}

public func computeRailDebugSummary(
    rails: [RailSample],
    keyOf: (Vec2) -> SnapKey,
    prefixCount: Int
) -> RailDebugSummary {
    let clampedCount = max(1, min(prefixCount, rails.count))

    func makeDebug(_ index: Int, _ rail: RailSample) -> RailEndpointDebug {
        let leftKey = keyOf(rail.left)
        let rightKey = keyOf(rail.right)
        let distance = (rail.right - rail.left).length
        return RailEndpointDebug(
            index: index,
            left: rail.left,
            right: rail.right,
            leftKey: leftKey,
            rightKey: rightKey,
            distance: distance
        )
    }

    let start = makeDebug(0, rails[0])
    let end = makeDebug(rails.count - 1, rails[rails.count - 1])
    let prefix = (0..<clampedCount).map { makeDebug($0, rails[$0]) }

    return RailDebugSummary(count: rails.count, start: start, end: end, prefix: prefix)
}

public func computeRailFrameDiagnostics(
    frames: [RailSampleFrame],
    widthEps: Double,
    perpEps: Double,
    unitEps: Double
) -> RailFrameDiagnostics {
    let checks = frames.map { frame -> RailInvariantCheck in
        let delta = frame.right - frame.left
        let distLR = delta.length
        let expectedWidth = (frame.widthLeft > 0.0 || frame.widthRight > 0.0)
            ? (frame.widthLeft + frame.widthRight)
            : frame.widthTotal
        let widthErr = distLR - expectedWidth
        let dotTR = delta.dot(frame.tangent)
        let normalLen = frame.normal.length
        return RailInvariantCheck(
            index: frame.index,
            distLR: distLR,
            expectedWidth: expectedWidth,
            widthErr: widthErr,
            dotTR: dotTR,
            normalLen: normalLen
        )
    }
    return RailFrameDiagnostics(frames: frames, checks: checks)
}

public struct SegmentSpotlight: Equatable {
    public let label: String
    public let seg: Segment2
    public let aKey: SnapKey
    public let bKey: SnapKey
    public let len: Double

    public init(label: String, seg: Segment2, aKey: SnapKey, bKey: SnapKey, len: Double) {
        self.label = label
        self.seg = seg
        self.aKey = aKey
        self.bKey = bKey
        self.len = len
    }
}

public func spotlightCapSegments(
    segments: [Segment2],
    keyQuant: (Vec2) -> SnapKey,
    matchA: SnapKey?,
    matchB: SnapKey?,
    sources: (EdgeSource) -> Bool,
    topN: Int
) -> [SegmentSpotlight] {
    let filtered = segments.filter { sources($0.source) }
    let ranked = filtered.map { seg -> SegmentSpotlight in
        let aKey = keyQuant(seg.a)
        let bKey = keyQuant(seg.b)
        let len = (seg.b - seg.a).length
        return SegmentSpotlight(label: seg.source.description, seg: seg, aKey: aKey, bKey: bKey, len: len)
    }
    if let matchA, let matchB {
        return ranked.filter {
            ($0.aKey == matchA && $0.bKey == matchB) || ($0.aKey == matchB && $0.bKey == matchA)
        }
    }
    let sorted = ranked.sorted {
        if $0.len == $1.len {
            if $0.aKey == $1.aKey {
                if $0.bKey == $1.bKey {
                    return $0.label < $1.label
                }
                return snapKeyLess($0.bKey, $1.bKey)
            }
            return snapKeyLess($0.aKey, $1.aKey)
        }
        return $0.len > $1.len
    }
    return Array(sorted.prefix(max(0, topN)))
}

public func computeSoupDegreeStats(
    segments: [Segment2],
    eps: Double,
    limitAnomalies: Int = 200,
    includeDegrees: (Int) -> Bool = { $0 != 2 }
) -> SoupDegreeStats {
    let graph = buildSoupGraph(segments: segments, eps: eps)
    var histogram: [Int: Int] = [:]
    var anomalies: [SoupNodeAnomaly] = []
    for (key, list) in graph.adjacency {
        let degree = list.count
        histogram[degree, default: 0] += 1
        if includeDegrees(degree) && anomalies.count < limitAnomalies {
            let pos = graph.pointForKey[key] ?? Vec2(0, 0)
            let neighbors = list.sorted(by: snapKeyLess).map { neighbor in
                let toPos = graph.pointForKey[neighbor] ?? Vec2(0, 0)
                let len = (toPos - pos).length
                let source = graph.edgeSources[EdgeKey(key, neighbor)] ?? .unknown("missing")
                return SoupNeighborEdge(to: neighbor, toPos: toPos, len: len, source: source)
            }
            anomalies.append(
                SoupNodeAnomaly(
                    key: key,
                    pos: pos,
                    outCount: degree,
                    inCount: degree,
                    outNeighbors: neighbors,
                    inNeighbors: neighbors
                )
            )
        }
    }
    return SoupDegreeStats(
        nodeCount: graph.pointForKey.count,
        edgeCount: graph.edges.count,
        degreeHistogram: histogram,
        anomalies: anomalies
    )
}

private func makeTraceStepInfo(
    ringIndex: Int,
    stepIndex: Int,
    fromKey: SnapKey,
    toKey: SnapKey,
    candidates: [SnapKey],
    chosen: SnapKey,
    incomingFrom: SnapKey,
    incomingTo: SnapKey,
    pointForKey: [SnapKey: Vec2],
    adjacency: [SnapKey: [SnapKey]],
    edgeSources: [EdgeKey: EdgeSource]
) -> TraceStepInfo {
    let from = pointForKey[fromKey] ?? Vec2(0, 0)
    let to = pointForKey[toKey] ?? Vec2(0, 0)
    let incomingStart = pointForKey[incomingFrom] ?? from
    let incomingEnd = pointForKey[incomingTo] ?? from
    let incomingVec = incomingEnd - incomingStart
    let incomingDir = incomingVec.normalized()

    let sorted = candidates.sorted(by: snapKeyLess)
    let candidateInfos: [TraceStepCandidate] = sorted.map { candidate in
        let candidatePos = pointForKey[candidate] ?? Vec2(0, 0)
        let vector = candidatePos - from
        let length = vector.length
        let angle = angleBetween(incomingDir, vector.normalized())
        let source = edgeSources[EdgeKey(fromKey, candidate)] ?? .unknown("missing")
        return TraceStepCandidate(
            toKey: candidate,
            to: candidatePos,
            length: length,
            angle: angle,
            scoreKey: candidate,
            isChosen: candidate == chosen,
            source: source
        )
    }

    let fromNeighbors = buildNeighborList(
        key: fromKey,
        origin: from,
        pointForKey: pointForKey,
        adjacency: adjacency,
        edgeSources: edgeSources
    )
    let toPos = pointForKey[toKey] ?? Vec2(0, 0)
    let toNeighbors = buildNeighborList(
        key: toKey,
        origin: toPos,
        pointForKey: pointForKey,
        adjacency: adjacency,
        edgeSources: edgeSources
    )

    return TraceStepInfo(
        ringIndex: ringIndex,
        stepIndex: stepIndex,
        fromKey: fromKey,
        toKey: toKey,
        from: from,
        to: to,
        incoming: incomingVec,
        candidates: candidateInfos,
        fromNeighbors: fromNeighbors,
        toNeighbors: toNeighbors
    )
}

private func buildNeighborList(
    key: SnapKey,
    origin: Vec2,
    pointForKey: [SnapKey: Vec2],
    adjacency: [SnapKey: [SnapKey]],
    edgeSources: [EdgeKey: EdgeSource]
) -> [TraceStepNeighbor] {
    let neighbors = adjacency[key] ?? []
    return neighbors.sorted(by: snapKeyLess).map { neighbor in
        let pos = pointForKey[neighbor] ?? Vec2(0, 0)
        let vector = pos - origin
        let len = vector.length
        let dir = vector.normalized()
        let source = edgeSources[EdgeKey(key, neighbor)] ?? .unknown("missing")
        return TraceStepNeighbor(key: neighbor, pos: pos, length: len, dir: dir, source: source)
    }
}

private func angleBetween(_ a: Vec2, _ b: Vec2) -> Double {
    let aLen = a.length
    let bLen = b.length
    if aLen <= Epsilon.defaultValue || bLen <= Epsilon.defaultValue { return 0.0 }
    let cross = a.x * b.y - a.y * b.x
    let dot = a.x * b.x + a.y * b.y
    return atan2(cross, dot)
}

private struct SoupGraph {
    let pointForKey: [SnapKey: Vec2]
    let adjacency: [SnapKey: [SnapKey]]
    let edges: Set<EdgeKey>
    let edgeSources: [EdgeKey: EdgeSource]
}

private func buildSoupGraph(segments: [Segment2], eps: Double) -> SoupGraph {
    var pointForKey: [SnapKey: Vec2] = [:]
    var adjacency: [SnapKey: [SnapKey]] = [:]
    var edges: Set<EdgeKey> = []
    var edgeSources: [EdgeKey: EdgeSource] = [:]

    for seg in segments {
        let aKey = Epsilon.snapKey(seg.a, eps: eps)
        let bKey = Epsilon.snapKey(seg.b, eps: eps)
        pointForKey[aKey] = pointForKey[aKey] ?? seg.a
        pointForKey[bKey] = pointForKey[bKey] ?? seg.b
        adjacency[aKey, default: []].append(bKey)
        adjacency[bKey, default: []].append(aKey)
        let edge = EdgeKey(aKey, bKey)
        edges.insert(edge)
        if let existing = edgeSources[edge] {
            edgeSources[edge] = mergeEdgeSource(existing: existing, new: seg.source)
        } else {
            edgeSources[edge] = seg.source
        }
    }

    for (key, list) in adjacency {
        let sorted = list.sorted(by: snapKeyLess)
        var unique: [SnapKey] = []
        unique.reserveCapacity(sorted.count)
        var last: SnapKey? = nil
        for item in sorted {
            if let last, last == item { continue }
            unique.append(item)
            last = item
        }
        adjacency[key] = unique
    }

    return SoupGraph(
        pointForKey: pointForKey,
        adjacency: adjacency,
        edges: edges,
        edgeSources: edgeSources
    )
}

private func mergeEdgeSource(existing: EdgeSource, new: EdgeSource) -> EdgeSource {
    if existing.isUnknown && !new.isUnknown { return new }
    return existing
}

public func signedArea(_ ring: [Vec2]) -> Double {
    guard ring.count >= 3 else { return 0.0 }
    var area = 0.0
    for i in 0..<(ring.count - 1) {
        let a = ring[i]
        let b = ring[i + 1]
        area += (a.x * b.y - b.x * a.y)
    }
    return area * 0.5
}

private struct EdgeKey: Hashable {
    let a: SnapKey
    let b: SnapKey

    init(_ p0: SnapKey, _ p1: SnapKey) {
        if snapKeyLess(p0, p1) {
            a = p0
            b = p1
        } else {
            a = p1
            b = p0
        }
    }
}

private func snapKeyLess(_ a: SnapKey, _ b: SnapKey) -> Bool {
    if a.x != b.x { return a.x < b.x }
    return a.y < b.y
}

private func edgeLess(_ a: EdgeKey, _ b: EdgeKey) -> Bool {
    if snapKeyLess(a.a, b.a) { return true }
    if snapKeyLess(b.a, a.a) { return false }
    return snapKeyLess(a.b, b.b)
}

private func dedupRing(_ ring: [Vec2]) -> [Vec2] {
    guard !ring.isEmpty else { return [] }
    var result: [Vec2] = [ring[0]]
    for point in ring.dropFirst() where !Epsilon.approxEqual(point, result.last!) {
        result.append(point)
    }
    if let first = result.first, let last = result.last, !Epsilon.approxEqual(first, last) {
        result.append(first)
    }
    return result
}
