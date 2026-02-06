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
    case midSegment
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
    case penStrip(loop: Int)
    case penCap
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
        case .penStrip(let loop): return "penStrip(\(loop))"
        case .penCap: return "penCap"
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
    public let crossAxis: Vec2
    public let effectiveAngle: Double
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
        crossAxis: Vec2,
        effectiveAngle: Double,
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
        self.crossAxis = crossAxis
        self.effectiveAngle = effectiveAngle
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
    public let alignment: Double
    public let normalLen: Double

    public init(
        index: Int,
        distLR: Double,
        expectedWidth: Double,
        widthErr: Double,
        alignment: Double,
        normalLen: Double
    ) {
        self.index = index
        self.distLR = distLR
        self.expectedWidth = expectedWidth
        self.widthErr = widthErr
        self.alignment = alignment
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

public struct RailCornerDebug: Equatable, Sendable {
    public let index: Int
    public let center: Vec2
    public let tangent: Vec2
    public let normal: Vec2
    public let u: Vec2
    public let v: Vec2
    public let uRot: Vec2
    public let vRot: Vec2
    public let effectiveAngle: Double
    public let widthLeft: Double
    public let widthRight: Double
    public let widthTotal: Double
    public let corners: [Vec2]
    public let left: Vec2
    public let right: Vec2

    public init(
        index: Int,
        center: Vec2,
        tangent: Vec2,
        normal: Vec2,
        u: Vec2,
        v: Vec2,
        uRot: Vec2,
        vRot: Vec2,
        effectiveAngle: Double,
        widthLeft: Double,
        widthRight: Double,
        widthTotal: Double,
        corners: [Vec2],
        left: Vec2,
        right: Vec2
    ) {
        self.index = index
        self.center = center
        self.tangent = tangent
        self.normal = normal
        self.u = u
        self.v = v
        self.uRot = uRot
        self.vRot = vRot
        self.effectiveAngle = effectiveAngle
        self.widthLeft = widthLeft
        self.widthRight = widthRight
        self.widthTotal = widthTotal
        self.corners = corners
        self.left = left
        self.right = right
    }
}

public struct RailPoints: Sendable, Equatable {
    public let left: Vec2
    public let right: Vec2

    public init(left: Vec2, right: Vec2) {
        self.left = left
        self.right = right
    }
}

public func railPointsFromCrossAxis(
    center: Vec2,
    crossAxis: Vec2,
    widthLeft: Double,
    widthRight: Double
) -> RailPoints {
    let axisLen = crossAxis.length
    if axisLen <= 1.0e-12 {
        return RailPoints(left: center, right: center)
    }
    let axis = crossAxis * (1.0 / axisLen)
    let left = center + axis * widthLeft
    let right = center - axis * widthRight
    return RailPoints(left: left, right: right)
}

public struct RailDeltaDecomp: Equatable, Sendable {
    public let delta: Vec2
    public let dotT: Double
    public let dotN: Double
    public let len: Double
    public let widthErr: Double

    public init(delta: Vec2, dotT: Double, dotN: Double, len: Double, widthErr: Double) {
        self.delta = delta
        self.dotT = dotT
        self.dotN = dotN
        self.len = len
        self.widthErr = widthErr
    }
}

public struct SweepStyle: Equatable, Codable {
    public let width: Double
    public let widthLeft: Double
    public let widthRight: Double
    public let height: Double
    public let angle: Double
    public let offset: Double
    public let angleIsRelative: Bool

    public init(
        width: Double,
        widthLeft: Double,
        widthRight: Double,
        height: Double,
        angle: Double,
        offset: Double,
        angleIsRelative: Bool
    ) {
        self.width = width
        self.widthLeft = widthLeft
        self.widthRight = widthRight
        self.height = height
        self.angle = angle
        self.offset = offset
        self.angleIsRelative = angleIsRelative
    }
}

public enum PenShape: String, Codable, Sendable {
    case railsOnly
    case rectCorners
    case auto
}

public struct CapBuildResult: Equatable, Sendable {
    public let segments: [Segment2]
    public let startLeftTrim: Vec2?
    public let endLeftTrim: Vec2?
    public let startRightTrim: Vec2?
    public let endRightTrim: Vec2?
}

public func buildCaps(
    leftRail: [Vec2],
    rightRail: [Vec2],
    capNamespace: String = "stroke",
    capLocalIndex: Int = 0,
    widthStart: Double,
    widthEnd: Double,
    startCap: CapStyle,
    endCap: CapStyle,
    capFilletArcSegments: Int = 8,
    capRoundArcSegments: Int = 64,
    debugFillet: ((CapFilletDebug) -> Void)? = nil,
    debugCapBoundary: ((CapBoundaryDebug) -> Void)? = nil
) -> CapBuildResult {
    guard let leftStart = leftRail.first, let leftEnd = leftRail.last else {
        return CapBuildResult(segments: [], startLeftTrim: nil, endLeftTrim: nil, startRightTrim: nil, endRightTrim: nil)
    }
    guard let rightStart = rightRail.first, let rightEnd = rightRail.last else {
        return CapBuildResult(segments: [], startLeftTrim: nil, endLeftTrim: nil, startRightTrim: nil, endRightTrim: nil)
    }

    let startDistance = (leftStart - rightStart).length
    let endDistance = (leftEnd - rightEnd).length
    let startAltDistance = (leftStart - rightEnd).length
    let endAltDistance = (leftEnd - rightStart).length
    let sumDirect = startDistance + endDistance
    let sumSwap = startAltDistance + endAltDistance
    let useReversedRight = sumSwap + Epsilon.defaultValue < sumDirect

    let rightForStart = useReversedRight ? rightEnd : rightStart
    let rightForEnd = useReversedRight ? rightStart : rightEnd
    func shouldEmitCapJoin(kind: String, left: Vec2, right: Vec2, widthScale: Double) -> Bool {
        let len = (left - right).length
        let limit = widthScale * 3.0
        if len <= limit { return true }
        let detail = "stroke=\(capNamespace) cap=\(kind) idx=\(capLocalIndex)"
        print(String(format: "capJoinInvariant FAIL %@ len=%.6f width=%.6f limit=%.6f L=(%.6f,%.6f) R=(%.6f,%.6f) reversedRight=%@", detail, len, widthScale, limit, left.x, left.y, right.x, right.y, useReversedRight.description))
        #if DEBUG
        assertionFailure("capJoinInvariant violated: \(detail)")
        #endif
        return false
    }

    var caps: [Segment2] = []
    var startLeftTrim: Vec2? = nil
    var endLeftTrim: Vec2? = nil
    var startRightTrim: Vec2? = nil
    var endRightTrim: Vec2? = nil
    let startDetail = "stroke=\(capNamespace) cap=start idx=\(capLocalIndex)"
    let endDetail = "stroke=\(capNamespace) cap=end idx=\(capLocalIndex)"
    let roundSegments = max(8, min(512, capRoundArcSegments))
    func failureReason(_ error: FilletError) -> String {
        switch error {
        case .degenerateAngle: return "degenerateAngle"
        case .radiusTooLarge: return "radiusTooLarge"
        case .cornerNotFound: return "cornerNotFound"
        case .cornerOverlap: return "cornerOverlap"
        case .noCorner: return "noCorner"
        }
    }

    func emitFillet(_ info: CapFilletDebug) {
        debugFillet?(info)
        let thetaDeg = info.theta * 180.0 / Double.pi
        var parts: [String] = []
        parts.append("CAP_FILLET")
        parts.append("stroke=\(capNamespace)")
        parts.append("endpoint=\(info.kind)")
        parts.append("side=\(info.side)")
        parts.append(String(format: "r=%.6f", info.radius))
        parts.append("idx=\(info.cornerIndex)")
        parts.append(String(format: "B=(%.6f,%.6f)", info.corner.x, info.corner.y))
        parts.append(String(format: "thetaDeg=%.6f", thetaDeg))
        parts.append(String(format: "d=%.6f", info.d))
        parts.append(String(format: "lenIn=%.6f", info.lenIn))
        parts.append(String(format: "lenOut=%.6f", info.lenOut))
        parts.append("insertedPoints=\(info.insertedPoints)")
        parts.append("result=\(info.success ? "ok" : "fail")")
        if let reason = info.failureReason {
            parts.append("reason=\(reason)")
        }
        if info.success {
            parts.append(String(format: "P=(%.6f,%.6f)", info.p.x, info.p.y))
            parts.append(String(format: "Q=(%.6f,%.6f)", info.q.x, info.q.y))
            parts.append("arcSegments=\(info.arcSegments)")
        }
        print(parts.joined(separator: " "))
    }

    func nearestCornerIndex(_ polyline: [Vec2], target: Vec2) -> (index: Int, distance: Double) {
        var bestIndex: Int = 0
        var bestDist = Double.greatestFiniteMagnitude
        for (index, point) in polyline.enumerated() {
            let dist = (point - target).length
            if dist < bestDist {
                bestDist = dist
                bestIndex = index
            }
        }
        return (bestIndex, bestDist)
    }

    func polygonSignedArea(_ polygon: [Vec2]) -> Double {
        guard polygon.count >= 3 else { return 0.0 }
        var sum = 0.0
        for i in 0..<polygon.count {
            let a = polygon[i]
            let b = polygon[(i + 1) % polygon.count]
            sum += (a.x * b.y - b.x * a.y)
        }
        return 0.5 * sum
    }

    func averagePoint(_ points: [Vec2]) -> Vec2? {
        guard !points.isEmpty else { return nil }
        var sum = Vec2(0, 0)
        for point in points { sum = sum + point }
        return sum * (1.0 / Double(points.count))
    }

    func normalizeAngle(_ angle: Double) -> Double {
        var a = angle
        while a < 0 { a += Double.pi * 2.0 }
        while a >= Double.pi * 2.0 { a -= Double.pi * 2.0 }
        return a
    }

    func angleBetweenCCW(start: Double, end: Double, mid: Double) -> Bool {
        let a0 = normalizeAngle(start)
        let a1 = normalizeAngle(end)
        let am = normalizeAngle(mid)
        let deltaEnd = normalizeAngle(a1 - a0)
        let deltaMid = normalizeAngle(am - a0)
        return deltaMid <= deltaEnd
    }

    func roundCapArcPoints(left: Vec2, right: Vec2, outward: Vec2, segments: Int) -> [Vec2]? {
        let span = (right - left)
        let distance = span.length
        let radius = 0.5 * distance
        if radius <= Epsilon.defaultValue { return nil }
        let center = (left + right) * 0.5
        let outLen = outward.length
        if outLen <= Epsilon.defaultValue { return nil }
        let out = outward * (1.0 / outLen)
        let a0 = atan2(left.y - center.y, left.x - center.x)
        let a1 = atan2(right.y - center.y, right.x - center.x)
        let am = atan2(out.y, out.x)
        let useCCW = angleBetweenCCW(start: a0, end: a1, mid: am)
        let steps = max(2, segments + 1)
        var points: [Vec2] = []
        points.reserveCapacity(steps)
        let deltaCCW = normalizeAngle(a1 - a0)
        let delta = useCCW ? deltaCCW : -normalizeAngle(a0 - a1)
        for i in 0..<steps {
            let t = Double(i) / Double(steps - 1)
            let angle = a0 + delta * t
            points.append(Vec2(center.x + cos(angle) * radius, center.y + sin(angle) * radius))
        }
        if points.count >= 2 {
            points[0] = left
            points[points.count - 1] = right
        }
        return points
    }

    func railTangent(atStart: Bool) -> Vec2? {
        guard leftRail.count > 1, rightRail.count > 1 else { return nil }
        let leftDir = atStart ? (leftRail[1] - leftRail[0]) : (leftRail[leftRail.count - 1] - leftRail[leftRail.count - 2])
        let rightDir: Vec2
        if atStart {
            rightDir = useReversedRight
                ? (rightRail[rightRail.count - 2] - rightRail[rightRail.count - 1])
                : (rightRail[1] - rightRail[0])
        } else {
            rightDir = useReversedRight
                ? (rightRail[1] - rightRail[0])
                : (rightRail[rightRail.count - 1] - rightRail[rightRail.count - 2])
        }
        let dir = leftDir + rightDir
        let dirLen = dir.length
        if dirLen > Epsilon.defaultValue { return dir * (1.0 / dirLen) }
        let leftLen = leftDir.length
        if leftLen > Epsilon.defaultValue { return leftDir * (1.0 / leftLen) }
        let rightLen = rightDir.length
        if rightLen > Epsilon.defaultValue { return rightDir * (1.0 / rightLen) }
        return nil
    }

    func pointInPolygon(_ point: Vec2, polygon: [Vec2]) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let pi = polygon[i]
            let pj = polygon[j]
            let intersects = ((pi.y > point.y) != (pj.y > point.y)) &&
                (point.x < (pj.x - pi.x) * (point.y - pi.y) / ((pj.y - pi.y) + 1.0e-12) + pi.x)
            if intersects { inside.toggle() }
            j = i
        }
        return inside
    }

    func filletOutward(a: Vec2, b: Vec2, c: Vec2, radius: Double, polygon: [Vec2]) -> (result: FilletResult, usedA: Vec2, usedB: Vec2, usedC: Vec2, flipped: Bool) {
        _ = polygonSignedArea(polygon)
        let first = filletCornerSigned(a: a, b: b, c: c, radius: radius, sign: 1.0)
        guard case .success(let splice) = first else {
            return (first, a, b, c, false)
        }
        let mid = splice.arcMidpoint
        if !pointInPolygon(mid, polygon: polygon) {
            let flipped = filletCornerSigned(a: a, b: b, c: c, radius: radius, sign: -1.0)
            return (flipped, a, b, c, true)
        }
        return (first, a, b, c, false)
    }

    func cornerInfos(for points: [Vec2]) -> [CapBoundaryCornerInfo] {
        guard points.count >= 3 else { return [] }
        var infos: [CapBoundaryCornerInfo] = []
        infos.reserveCapacity(points.count)
        for i in 0..<points.count {
            if i == 0 || i == points.count - 1 {
                infos.append(CapBoundaryCornerInfo(index: i, point: points[i], lenIn: 0.0, lenOut: 0.0, theta: 0.0))
                continue
            }
            let a = points[i - 1]
            let b = points[i]
            let c = points[i + 1]
            let u = (b - a)
            let v = (c - b)
            let lenIn = u.length
            let lenOut = v.length
            let uN = u.normalized()
            let vN = v.normalized()
            let cross = uN.x * vN.y - uN.y * vN.x
            let dot = max(-1.0, min(1.0, uN.dot(vN)))
            let angle = atan2(cross, dot)
            infos.append(CapBoundaryCornerInfo(index: i, point: b, lenIn: lenIn, lenOut: lenOut, theta: angle))
        }
        return infos
    }

    func chooseCornerPair(from infos: [CapBoundaryCornerInfo], minAngle: Double) -> (top: CapBoundaryCornerInfo?, bottom: CapBoundaryCornerInfo?, chosen: [CapBoundaryCornerInfo]) {
        let candidates = infos.filter { $0.index > 0 && $0.index < infos.count - 1 }
        let sorted = candidates.sorted { abs($0.theta) > abs($1.theta) }
        let chosen = sorted.prefix(2).filter { abs($0.theta) >= minAngle }
        if chosen.count < 2 { return (nil, nil, Array(chosen)) }
        let first = chosen[chosen.startIndex]
        let second = chosen[chosen.index(after: chosen.startIndex)]
        if first.point.y >= second.point.y {
            return (first, second, [first, second])
        }
        return (second, first, [second, first])
    }

    // Start cap fillets (plan-first on base polyline)
    var startHadFillet = false
    var startMidLeftQ: Vec2? = nil
    var startMidRightP: Vec2? = nil
    var startFailureReason: String? = nil
    var startFallbackReason: String? = nil
    var startFallbackPoint: Vec2? = nil
    var startFallbackCorner: Vec2? = nil
    if case .round = startCap, leftRail.count > 1, rightRail.count > 1 {
        let startPolyline = baseCapPolyline(
            leftRail: leftRail,
            rightRail: rightRail,
            atStart: true,
            minApproach: 0.0
        )
        let tangent = railTangent(atStart: true)
        let outward = tangent.map { Vec2(-$0.x, -$0.y) } ?? Vec2(0, 0)
        let arcPoints = roundCapArcPoints(
            left: leftStart,
            right: rightForStart,
            outward: outward,
            segments: roundSegments
        )
        if let arcPoints {
            let chainPoints = arcPoints
            caps.append(contentsOf: segmentsFromPoints(chainPoints, source: .capStartEdge(role: .joinLR, detail: "\(startDetail) round")))
            startLeftTrim = leftStart
            startRightTrim = rightForStart
            if debugCapBoundary != nil {
                print(String(format: "CAP_KIND endpoint=start kind=round corner=none r=%.6f", 0.5 * (rightForStart - leftStart).length))
                print("CAP_CHAIN_RAW points=\(chainPoints.count) edges=\(max(0, chainPoints.count - 1))")
                print("CAP_CHAIN_SIMPLIFIED points=\(chainPoints.count) edges=\(max(0, chainPoints.count - 1))")
                print("CAP_CHAIN_CONNECTED ok=\(chainPoints.count >= 2)")
                debugCapBoundary?(CapBoundaryDebug(
                    endpoint: "start",
                    original: chainPoints,
                    simplified: chainPoints,
                    corners: cornerInfos(for: chainPoints),
                    chosenIndices: [],
                    chosenThetas: [],
                    trimPoints: [leftStart, rightForStart],
                    arcPoints: arcPoints,
                    fallbackReason: nil,
                    fallbackPoint: nil,
                    fallbackCorner: nil
                ))
            }
        } else {
            if shouldEmitCapJoin(kind: "start", left: leftStart, right: rightForStart, widthScale: widthStart) {
                caps.append(Segment2(leftStart, rightForStart, source: .capStartEdge(role: .joinLR, detail: startDetail)))
            }
            print("CAP_ROUND_FALLBACK endpoint=start reason=degenerate")
            if debugCapBoundary != nil {
                print("CAP_KIND endpoint=start kind=round corner=none r=0.000000")
                print("CAP_CHAIN_RAW points=\(startPolyline.count) edges=\(max(0, startPolyline.count - 1))")
                print("CAP_CHAIN_SIMPLIFIED points=\(startPolyline.count) edges=\(max(0, startPolyline.count - 1))")
                print("CAP_CHAIN_CONNECTED ok=\(startPolyline.count >= 2)")
                debugCapBoundary?(CapBoundaryDebug(
                    endpoint: "start",
                    original: startPolyline,
                    simplified: startPolyline,
                    corners: cornerInfos(for: startPolyline),
                    chosenIndices: [],
                    chosenThetas: [],
                    trimPoints: [leftStart, rightForStart],
                    arcPoints: [],
                    fallbackReason: "roundFallback",
                    fallbackPoint: averagePoint(startPolyline),
                    fallbackCorner: nil
                ))
            }
        }
    } else if case .ball = startCap, leftRail.count > 1, rightRail.count > 1 {
        if shouldEmitCapJoin(kind: "start", left: leftStart, right: rightForStart, widthScale: widthStart) {
            caps.append(Segment2(leftStart, rightForStart, source: .capStartEdge(role: .joinLR, detail: startDetail)))
        }
        if debugCapBoundary != nil {
            print("CAP_KIND endpoint=start kind=ball corner=none r=0.000000")
            print("CAP_CHAIN_RAW points=2 edges=1")
            print("CAP_CHAIN_SIMPLIFIED points=2 edges=1")
            print("CAP_CHAIN_CONNECTED ok=true")
        }
    } else if case .fillet(let radius, let corner) = startCap, leftRail.count > 1, rightRail.count > 1 {
        let minApproach = max(5.0, radius * 2.0)
        let startPolyline = baseCapPolyline(
            leftRail: leftRail,
            rightRail: rightRail,
            atStart: true,
            minApproach: minApproach
        )
        let simplify = simplifyOpenPolylineForCorners(startPolyline, epsLen: 1.0e-4, epsAngleRad: 1.0e-6)
        let simplified = simplify.points
        let infos = cornerInfos(for: simplified)
        let minCornerAngle = 10.0 * Double.pi / 180.0
        let selection = chooseCornerPair(from: infos, minAngle: minCornerAngle)
        if debugCapBoundary != nil {
            print(String(format: "CAP_KIND endpoint=start kind=fillet corner=%@ r=%.6f", corner.rawValue, radius))
            print("CAP_CHAIN_RAW points=\(startPolyline.count) edges=\(max(0, startPolyline.count - 1))")
            print("CAP_CHAIN_SIMPLIFIED points=\(simplified.count) edges=\(max(0, simplified.count - 1))")
            print("CAP_CHAIN_CONNECTED ok=\(simplified.count >= 2)")
            print("CAP_BOUNDARY_RAW endpoint=start n=\(startPolyline.count)")
            for (index, point) in startPolyline.enumerated() {
                print(String(format: "  i=%d P=(%.6f,%.6f)", index, point.x, point.y))
            }
            print("CAP_BOUNDARY_SIMPLIFIED endpoint=start n=\(simplified.count) removed=\(simplify.removedCount)")
            for (index, point) in simplified.enumerated() {
                print(String(format: "  i=%d P=(%.6f,%.6f)", index, point.x, point.y))
            }
            print("CAP_BOUNDARY endpoint=start n=\(simplified.count) removed=\(simplify.removedCount)")
            for info in infos {
                let thetaDeg = info.theta * 180.0 / Double.pi
                print(String(format: "  i=%d P=(%.6f,%.6f) lenIn=%.6f lenOut=%.6f thetaDeg=%.6f", info.index, info.point.x, info.point.y, info.lenIn, info.lenOut, thetaDeg))
            }
            let chosen = selection.chosen.map { String($0.index) }.joined(separator: ",")
            let thetas = selection.chosen.map { String(format: "%.3f", $0.theta * 180.0 / Double.pi) }.joined(separator: ",")
            print("CAP_BOUNDARY_CORNERS endpoint=start chosen=[\(chosen)] theta=[\(thetas)]")
        }
        var leftCorner = selection.top
        var rightCorner = selection.bottom
        let usePoints = simplified
        let polygon = simplified
        if simplified.count < 3 {
            startFailureReason = "invalidChain"
            leftCorner = nil
            rightCorner = nil
        }
        var startArcPoints: [Vec2] = []
        var startTrimPoints: [Vec2] = []
        func emitNoCorner(_ side: String, _ cornerPoint: Vec2) {
            startFailureReason = "noCorner"
            emitFillet(CapFilletDebug(
                kind: "start",
                side: side,
                radius: radius,
                cornerIndex: -1,
                a: cornerPoint,
                b: cornerPoint,
                c: cornerPoint,
                theta: 0,
                d: 0,
                lenIn: 0,
                lenOut: 0,
                arcMidpoint: cornerPoint,
                corner: cornerPoint,
                p: cornerPoint,
                q: cornerPoint,
                bridge: nil,
                success: false,
                failureReason: failureReason(.noCorner),
                arcSegments: 0,
                insertedPoints: 0
            ))
        }
        func applyFillet(side: String, cornerInfo: CapBoundaryCornerInfo, detail: String, setTrim: (FilletSplice) -> Void) {
            let index = cornerInfo.index
            guard index > 0, index < usePoints.count - 1 else {
                emitNoCorner(side, cornerInfo.point)
                return
            }
            let filletPlan = filletOutward(
                a: usePoints[index - 1],
                b: usePoints[index],
                c: usePoints[index + 1],
                radius: radius,
                polygon: polygon
            )
            let fillet = filletPlan.result
            switch fillet {
            case .success(let splice):
                startHadFillet = true
                setTrim(splice)
                let lenIn = (filletPlan.usedB - filletPlan.usedA).length
                let lenOut = (filletPlan.usedC - filletPlan.usedB).length
                let sampled = sampleCubicSegments(
                    splice.bridge,
                    segments: capFilletArcSegments,
                    source: .capStartEdge(role: .joinLR, detail: detail)
                )
                var points = sampled.points
                if points.count >= 2 {
                    points[0] = splice.p
                    points[points.count - 1] = splice.q
                }
                let insertedPoints = points.count
                startArcPoints.append(contentsOf: points)
                startTrimPoints.append(splice.p)
                startTrimPoints.append(splice.q)
                if capNamespace == "fillet", insertedPoints >= 2 {
                    let head = points.prefix(3).map { String(format: "(%.3f,%.3f)", $0.x, $0.y) }.joined(separator: ", ")
                    let tail = points.suffix(3).map { String(format: "(%.3f,%.3f)", $0.x, $0.y) }.joined(separator: ", ")
                    print("CAP_FILLET_POINTS endpoint=start side=\(side) count=\(insertedPoints) head=[\(head)] tail=[\(tail)]")
                    let pKey = Epsilon.snapKey(splice.p, eps: Epsilon.defaultValue)
                    let qKey = Epsilon.snapKey(splice.q, eps: Epsilon.defaultValue)
                    let p0Key = Epsilon.snapKey(points[0], eps: Epsilon.defaultValue)
                    let qNKey = Epsilon.snapKey(points[points.count - 1], eps: Epsilon.defaultValue)
                    print("capFilletKeys endpoint=start side=\(side) Pkey=(\(pKey.x),\(pKey.y)) arc0key=(\(p0Key.x),\(p0Key.y)) Qkey=(\(qKey.x),\(qKey.y)) arcLastKey=(\(qNKey.x),\(qNKey.y))")
                }
                emitFillet(CapFilletDebug(
                    kind: "start",
                    side: side,
                    radius: radius,
                    cornerIndex: index,
                    a: filletPlan.usedA,
                    b: filletPlan.usedB,
                    c: filletPlan.usedC,
                    theta: splice.theta,
                    d: splice.d,
                    lenIn: lenIn,
                    lenOut: lenOut,
                    arcMidpoint: splice.arcMidpoint,
                    corner: splice.b,
                    p: splice.p,
                    q: splice.q,
                    bridge: splice.bridge,
                    success: true,
                    failureReason: nil,
                    arcSegments: capFilletArcSegments,
                    insertedPoints: insertedPoints
                ))
                caps.append(contentsOf: segmentsFromPoints(points, source: .capStartEdge(role: .joinLR, detail: detail)))
            case .failure(let reason):
                startFailureReason = failureReason(reason)
                let lenIn = (filletPlan.usedB - filletPlan.usedA).length
                let lenOut = (filletPlan.usedC - filletPlan.usedB).length
                emitFillet(CapFilletDebug(
                    kind: "start",
                    side: side,
                    radius: radius,
                    cornerIndex: index,
                    a: filletPlan.usedA,
                    b: filletPlan.usedB,
                    c: filletPlan.usedC,
                    theta: 0,
                    d: 0,
                    lenIn: lenIn,
                    lenOut: lenOut,
                    arcMidpoint: usePoints[index],
                    corner: usePoints[index],
                    p: usePoints[index],
                    q: usePoints[index],
                    bridge: nil,
                    success: false,
                    failureReason: failureReason(reason),
                    arcSegments: 0,
                    insertedPoints: 0
                ))
            }
        }
        if (corner == .left || corner == .both) {
            if let cornerInfo = leftCorner {
                applyFillet(side: "left", cornerInfo: cornerInfo, detail: "\(startDetail) fillet-left") {
                    startLeftTrim = $0.p
                    startMidLeftQ = $0.q
                }
            } else {
                emitNoCorner("left", leftStart)
            }
        }
        if (corner == .right || corner == .both) {
            if let cornerInfo = rightCorner {
                applyFillet(side: "right", cornerInfo: cornerInfo, detail: "\(startDetail) fillet-right") {
                    startRightTrim = $0.q
                    startMidRightP = $0.p
                }
            } else {
                emitNoCorner("right", rightForStart)
            }
        }
        func fallbackStart(_ reason: String) {
            if shouldEmitCapJoin(kind: "start", left: leftStart, right: rightForStart, widthScale: widthStart) {
                caps.append(Segment2(leftStart, rightForStart, source: .capStartEdge(role: .joinLR, detail: startDetail)))
            }
            startFallbackReason = reason
            startFallbackPoint = averagePoint(simplified) ?? averagePoint(startPolyline)
            if corner == .left || corner == .both {
                startFallbackCorner = leftCorner?.point ?? rightCorner?.point
            } else {
                startFallbackCorner = rightCorner?.point ?? leftCorner?.point
            }
            if debugCapBoundary != nil {
                print("CAP_BOUNDARY_INVALID endpoint=start reason=\(reason) points=\(simplified.count) edges=0")
            }
            print("CAP_FILLET_FALLBACK endpoint=start fallback=butt reason=\(reason)")
        }
        if !startHadFillet {
            fallbackStart(startFailureReason ?? "noCorner")
        } else if corner == .both {
            if let midLeft = startMidLeftQ, let midRight = startMidRightP {
                caps.append(Segment2(midLeft, midRight, source: .capStartEdge(role: .midSegment, detail: "\(startDetail) fillet-both")))
            } else {
                fallbackStart("invalidChain")
                startHadFillet = false
            }
        } else if corner == .left {
            if let midLeft = startMidLeftQ {
                caps.append(Segment2(midLeft, rightForStart, source: .capStartEdge(role: .midSegment, detail: "\(startDetail) fillet-left")))
            } else {
                fallbackStart("invalidChain")
                startHadFillet = false
            }
        } else if corner == .right {
            if let midRight = startMidRightP {
                caps.append(Segment2(leftStart, midRight, source: .capStartEdge(role: .midSegment, detail: "\(startDetail) fillet-right")))
            } else {
                fallbackStart("invalidChain")
                startHadFillet = false
            }
        }
        if let debugCapBoundary {
            debugCapBoundary(CapBoundaryDebug(
                endpoint: "start",
                original: startPolyline,
                simplified: simplified,
                corners: infos,
                chosenIndices: selection.chosen.map { $0.index },
                chosenThetas: selection.chosen.map { $0.theta },
                trimPoints: startTrimPoints,
                arcPoints: startArcPoints,
                fallbackReason: startFallbackReason,
                fallbackPoint: startFallbackPoint,
                fallbackCorner: startFallbackCorner
            ))
        }
    } else if shouldEmitCapJoin(kind: "start", left: leftStart, right: rightForStart, widthScale: widthStart) {
        caps.append(Segment2(leftStart, rightForStart, source: .capStartEdge(role: .joinLR, detail: startDetail)))
        if debugCapBoundary != nil {
            print("CAP_KIND endpoint=start kind=butt corner=none r=0.000000")
            print("CAP_CHAIN_RAW points=2 edges=1")
            print("CAP_CHAIN_SIMPLIFIED points=2 edges=1")
            print("CAP_CHAIN_CONNECTED ok=true")
            debugCapBoundary?(CapBoundaryDebug(
                endpoint: "start",
                original: [leftStart, rightForStart],
                simplified: [leftStart, rightForStart],
                corners: cornerInfos(for: [leftStart, rightForStart]),
                chosenIndices: [],
                chosenThetas: [],
                trimPoints: [leftStart, rightForStart],
                arcPoints: [],
                fallbackReason: nil,
                fallbackPoint: nil,
                fallbackCorner: nil
            ))
        }
    }

    // End cap fillets (plan-first on base polyline)
    var endHadFillet = false
    var endMidLeftQ: Vec2? = nil
    var endMidRightP: Vec2? = nil
    var endFailureReason: String? = nil
    var endFallbackReason: String? = nil
    var endFallbackPoint: Vec2? = nil
    var endFallbackCorner: Vec2? = nil
    if case .round = endCap, leftRail.count > 1, rightRail.count > 1 {
        let endPolyline = baseCapPolyline(
            leftRail: leftRail,
            rightRail: rightRail,
            atStart: false,
            minApproach: 0.0
        )
        let tangent = railTangent(atStart: false)
        let outward = tangent ?? Vec2(0, 0)
        let arcPoints = roundCapArcPoints(
            left: leftEnd,
            right: rightForEnd,
            outward: outward,
            segments: roundSegments
        )
        if let arcPoints {
            let chainPoints = arcPoints
            caps.append(contentsOf: segmentsFromPoints(chainPoints, source: .capEndEdge(role: .joinLR, detail: "\(endDetail) round")))
            endLeftTrim = leftEnd
            endRightTrim = rightForEnd
            if debugCapBoundary != nil {
                print(String(format: "CAP_KIND endpoint=end kind=round corner=none r=%.6f", 0.5 * (rightForEnd - leftEnd).length))
                print("CAP_CHAIN_RAW points=\(chainPoints.count) edges=\(max(0, chainPoints.count - 1))")
                print("CAP_CHAIN_SIMPLIFIED points=\(chainPoints.count) edges=\(max(0, chainPoints.count - 1))")
                print("CAP_CHAIN_CONNECTED ok=\(chainPoints.count >= 2)")
                debugCapBoundary?(CapBoundaryDebug(
                    endpoint: "end",
                    original: chainPoints,
                    simplified: chainPoints,
                    corners: cornerInfos(for: chainPoints),
                    chosenIndices: [],
                    chosenThetas: [],
                    trimPoints: [leftEnd, rightForEnd],
                    arcPoints: arcPoints,
                    fallbackReason: nil,
                    fallbackPoint: nil,
                    fallbackCorner: nil
                ))
            }
        } else {
            if shouldEmitCapJoin(kind: "end", left: leftEnd, right: rightForEnd, widthScale: widthEnd) {
                caps.append(Segment2(rightForEnd, leftEnd, source: .capEndEdge(role: .joinLR, detail: endDetail)))
            }
            print("CAP_ROUND_FALLBACK endpoint=end reason=degenerate")
            if debugCapBoundary != nil {
                print("CAP_KIND endpoint=end kind=round corner=none r=0.000000")
                print("CAP_CHAIN_RAW points=\(endPolyline.count) edges=\(max(0, endPolyline.count - 1))")
                print("CAP_CHAIN_SIMPLIFIED points=\(endPolyline.count) edges=\(max(0, endPolyline.count - 1))")
                print("CAP_CHAIN_CONNECTED ok=\(endPolyline.count >= 2)")
                debugCapBoundary?(CapBoundaryDebug(
                    endpoint: "end",
                    original: endPolyline,
                    simplified: endPolyline,
                    corners: cornerInfos(for: endPolyline),
                    chosenIndices: [],
                    chosenThetas: [],
                    trimPoints: [leftEnd, rightForEnd],
                    arcPoints: [],
                    fallbackReason: "roundFallback",
                    fallbackPoint: averagePoint(endPolyline),
                    fallbackCorner: nil
                ))
            }
        }
    } else if case .ball = endCap, leftRail.count > 1, rightRail.count > 1 {
        if shouldEmitCapJoin(kind: "end", left: leftEnd, right: rightForEnd, widthScale: widthEnd) {
            caps.append(Segment2(rightForEnd, leftEnd, source: .capEndEdge(role: .joinLR, detail: endDetail)))
        }
        if debugCapBoundary != nil {
            print("CAP_KIND endpoint=end kind=ball corner=none r=0.000000")
            print("CAP_CHAIN_RAW points=2 edges=1")
            print("CAP_CHAIN_SIMPLIFIED points=2 edges=1")
            print("CAP_CHAIN_CONNECTED ok=true")
        }
    } else if case .fillet(let radius, let corner) = endCap, leftRail.count > 1, rightRail.count > 1 {
        let minApproach = max(5.0, radius * 2.0)
        let endPolyline = baseCapPolyline(
            leftRail: leftRail,
            rightRail: rightRail,
            atStart: false,
            minApproach: minApproach
        )
        let simplify = simplifyOpenPolylineForCorners(endPolyline, epsLen: 1.0e-4, epsAngleRad: 1.0e-6)
        let simplified = simplify.points
        let infos = cornerInfos(for: simplified)
        let minCornerAngle = 10.0 * Double.pi / 180.0
        let selection = chooseCornerPair(from: infos, minAngle: minCornerAngle)
        if debugCapBoundary != nil {
            print(String(format: "CAP_KIND endpoint=end kind=fillet corner=%@ r=%.6f", corner.rawValue, radius))
            print("CAP_CHAIN_RAW points=\(endPolyline.count) edges=\(max(0, endPolyline.count - 1))")
            print("CAP_CHAIN_SIMPLIFIED points=\(simplified.count) edges=\(max(0, simplified.count - 1))")
            print("CAP_CHAIN_CONNECTED ok=\(simplified.count >= 2)")
            print("CAP_BOUNDARY_RAW endpoint=end n=\(endPolyline.count)")
            for (index, point) in endPolyline.enumerated() {
                print(String(format: "  i=%d P=(%.6f,%.6f)", index, point.x, point.y))
            }
            print("CAP_BOUNDARY_SIMPLIFIED endpoint=end n=\(simplified.count) removed=\(simplify.removedCount)")
            for (index, point) in simplified.enumerated() {
                print(String(format: "  i=%d P=(%.6f,%.6f)", index, point.x, point.y))
            }
            print("CAP_BOUNDARY endpoint=end n=\(simplified.count) removed=\(simplify.removedCount)")
            for info in infos {
                let thetaDeg = info.theta * 180.0 / Double.pi
                print(String(format: "  i=%d P=(%.6f,%.6f) lenIn=%.6f lenOut=%.6f thetaDeg=%.6f", info.index, info.point.x, info.point.y, info.lenIn, info.lenOut, thetaDeg))
            }
            let chosen = selection.chosen.map { String($0.index) }.joined(separator: ",")
            let thetas = selection.chosen.map { String(format: "%.3f", $0.theta * 180.0 / Double.pi) }.joined(separator: ",")
            print("CAP_BOUNDARY_CORNERS endpoint=end chosen=[\(chosen)] theta=[\(thetas)]")
        }
        var leftCorner = selection.top
        var rightCorner = selection.bottom
        let usePoints = simplified
        let polygon = simplified
        if simplified.count < 3 {
            endFailureReason = "invalidChain"
            leftCorner = nil
            rightCorner = nil
        }
        var endArcPoints: [Vec2] = []
        var endTrimPoints: [Vec2] = []
        func emitNoCorner(_ side: String, _ cornerPoint: Vec2) {
            endFailureReason = "noCorner"
            emitFillet(CapFilletDebug(
                kind: "end",
                side: side,
                radius: radius,
                cornerIndex: -1,
                a: cornerPoint,
                b: cornerPoint,
                c: cornerPoint,
                theta: 0,
                d: 0,
                lenIn: 0,
                lenOut: 0,
                arcMidpoint: cornerPoint,
                corner: cornerPoint,
                p: cornerPoint,
                q: cornerPoint,
                bridge: nil,
                success: false,
                failureReason: failureReason(.noCorner),
                arcSegments: 0,
                insertedPoints: 0
            ))
        }
        func applyFillet(side: String, cornerInfo: CapBoundaryCornerInfo, detail: String, setTrim: (FilletSplice) -> Void) {
            let index = cornerInfo.index
            guard index > 0, index < usePoints.count - 1 else {
                emitNoCorner(side, cornerInfo.point)
                return
            }
            let filletPlan = filletOutward(
                a: usePoints[index - 1],
                b: usePoints[index],
                c: usePoints[index + 1],
                radius: radius,
                polygon: polygon
            )
            let fillet = filletPlan.result
            switch fillet {
            case .success(let splice):
                endHadFillet = true
                setTrim(splice)
                let lenIn = (filletPlan.usedB - filletPlan.usedA).length
                let lenOut = (filletPlan.usedC - filletPlan.usedB).length
                let sampled = sampleCubicSegments(
                    splice.bridge,
                    segments: capFilletArcSegments,
                    source: .capEndEdge(role: .joinLR, detail: detail)
                )
                var points = sampled.points
                if points.count >= 2 {
                    points[0] = splice.p
                    points[points.count - 1] = splice.q
                }
                let insertedPoints = points.count
                endArcPoints.append(contentsOf: points)
                endTrimPoints.append(splice.p)
                endTrimPoints.append(splice.q)
                if capNamespace == "fillet", insertedPoints >= 2 {
                    let head = points.prefix(3).map { String(format: "(%.3f,%.3f)", $0.x, $0.y) }.joined(separator: ", ")
                    let tail = points.suffix(3).map { String(format: "(%.3f,%.3f)", $0.x, $0.y) }.joined(separator: ", ")
                    print("CAP_FILLET_POINTS endpoint=end side=\(side) count=\(insertedPoints) head=[\(head)] tail=[\(tail)]")
                    let pKey = Epsilon.snapKey(splice.p, eps: Epsilon.defaultValue)
                    let qKey = Epsilon.snapKey(splice.q, eps: Epsilon.defaultValue)
                    let p0Key = Epsilon.snapKey(points[0], eps: Epsilon.defaultValue)
                    let qNKey = Epsilon.snapKey(points[points.count - 1], eps: Epsilon.defaultValue)
                    print("capFilletKeys endpoint=end side=\(side) Pkey=(\(pKey.x),\(pKey.y)) arc0key=(\(p0Key.x),\(p0Key.y)) Qkey=(\(qKey.x),\(qKey.y)) arcLastKey=(\(qNKey.x),\(qNKey.y))")
                }
                emitFillet(CapFilletDebug(
                    kind: "end",
                    side: side,
                    radius: radius,
                    cornerIndex: index,
                    a: filletPlan.usedA,
                    b: filletPlan.usedB,
                    c: filletPlan.usedC,
                    theta: splice.theta,
                    d: splice.d,
                    lenIn: lenIn,
                    lenOut: lenOut,
                    arcMidpoint: splice.arcMidpoint,
                    corner: splice.b,
                    p: splice.p,
                    q: splice.q,
                    bridge: splice.bridge,
                    success: true,
                    failureReason: nil,
                    arcSegments: capFilletArcSegments,
                    insertedPoints: insertedPoints
                ))
                caps.append(contentsOf: segmentsFromPoints(points, source: .capEndEdge(role: .joinLR, detail: detail)))
            case .failure(let reason):
                endFailureReason = failureReason(reason)
                let lenIn = (filletPlan.usedB - filletPlan.usedA).length
                let lenOut = (filletPlan.usedC - filletPlan.usedB).length
                emitFillet(CapFilletDebug(
                    kind: "end",
                    side: side,
                    radius: radius,
                    cornerIndex: index,
                    a: filletPlan.usedA,
                    b: filletPlan.usedB,
                    c: filletPlan.usedC,
                    theta: 0,
                    d: 0,
                    lenIn: lenIn,
                    lenOut: lenOut,
                    arcMidpoint: usePoints[index],
                    corner: usePoints[index],
                    p: usePoints[index],
                    q: usePoints[index],
                    bridge: nil,
                    success: false,
                    failureReason: failureReason(reason),
                    arcSegments: 0,
                    insertedPoints: 0
                ))
            }
        }
        if (corner == .left || corner == .both) {
            if let cornerInfo = leftCorner {
                applyFillet(side: "left", cornerInfo: cornerInfo, detail: "\(endDetail) fillet-left") {
                    endLeftTrim = $0.p
                    endMidLeftQ = $0.q
                }
            } else {
                emitNoCorner("left", leftEnd)
            }
        }
        if (corner == .right || corner == .both) {
            if let cornerInfo = rightCorner {
                applyFillet(side: "right", cornerInfo: cornerInfo, detail: "\(endDetail) fillet-right") {
                    endRightTrim = $0.q
                    endMidRightP = $0.p
                }
            } else {
                emitNoCorner("right", rightForEnd)
            }
        }
        func fallbackEnd(_ reason: String) {
            if shouldEmitCapJoin(kind: "end", left: leftEnd, right: rightForEnd, widthScale: widthEnd) {
                caps.append(Segment2(rightForEnd, leftEnd, source: .capEndEdge(role: .joinLR, detail: endDetail)))
            }
            endFallbackReason = reason
            endFallbackPoint = averagePoint(simplified) ?? averagePoint(endPolyline)
            if corner == .left || corner == .both {
                endFallbackCorner = leftCorner?.point ?? rightCorner?.point
            } else {
                endFallbackCorner = rightCorner?.point ?? leftCorner?.point
            }
            if debugCapBoundary != nil {
                print("CAP_BOUNDARY_INVALID endpoint=end reason=\(reason) points=\(simplified.count) edges=0")
            }
            print("CAP_FILLET_FALLBACK endpoint=end fallback=butt reason=\(reason)")
        }
        if !endHadFillet {
            fallbackEnd(endFailureReason ?? "noCorner")
        } else if corner == .both {
            if let midLeft = endMidLeftQ, let midRight = endMidRightP {
                caps.append(Segment2(midLeft, midRight, source: .capEndEdge(role: .midSegment, detail: "\(endDetail) fillet-both")))
            } else {
                fallbackEnd("invalidChain")
                endHadFillet = false
            }
        } else if corner == .left {
            if let midLeft = endMidLeftQ {
                caps.append(Segment2(midLeft, rightForEnd, source: .capEndEdge(role: .midSegment, detail: "\(endDetail) fillet-left")))
            } else {
                fallbackEnd("invalidChain")
                endHadFillet = false
            }
        } else if corner == .right {
            if let midRight = endMidRightP {
                caps.append(Segment2(leftEnd, midRight, source: .capEndEdge(role: .midSegment, detail: "\(endDetail) fillet-right")))
            } else {
                fallbackEnd("invalidChain")
                endHadFillet = false
            }
        }
        if let debugCapBoundary {
            debugCapBoundary(CapBoundaryDebug(
                endpoint: "end",
                original: endPolyline,
                simplified: simplified,
                corners: infos,
                chosenIndices: selection.chosen.map { $0.index },
                chosenThetas: selection.chosen.map { $0.theta },
                trimPoints: endTrimPoints,
                arcPoints: endArcPoints,
                fallbackReason: endFallbackReason,
                fallbackPoint: endFallbackPoint,
                fallbackCorner: endFallbackCorner
            ))
        }
    } else if shouldEmitCapJoin(kind: "end", left: leftEnd, right: rightForEnd, widthScale: widthEnd) {
        caps.append(Segment2(rightForEnd, leftEnd, source: .capEndEdge(role: .joinLR, detail: endDetail)))
        if debugCapBoundary != nil {
            print("CAP_KIND endpoint=end kind=butt corner=none r=0.000000")
            print("CAP_CHAIN_RAW points=2 edges=1")
            print("CAP_CHAIN_SIMPLIFIED points=2 edges=1")
            print("CAP_CHAIN_CONNECTED ok=true")
            debugCapBoundary?(CapBoundaryDebug(
                endpoint: "end",
                original: [leftEnd, rightForEnd],
                simplified: [leftEnd, rightForEnd],
                corners: cornerInfos(for: [leftEnd, rightForEnd]),
                chosenIndices: [],
                chosenThetas: [],
                trimPoints: [leftEnd, rightForEnd],
                arcPoints: [],
                fallbackReason: nil,
                fallbackPoint: nil,
                fallbackCorner: nil
            ))
        }
    }
    return CapBuildResult(
        segments: caps,
        startLeftTrim: startLeftTrim,
        endLeftTrim: endLeftTrim,
        startRightTrim: startRightTrim,
        endRightTrim: endRightTrim
    )
}

public func baseCapPolyline(
    leftRail: [Vec2],
    rightRail: [Vec2],
    atStart: Bool,
    minApproach: Double = 0.0
) -> [Vec2] {
    guard leftRail.count >= 2, rightRail.count >= 2 else { return [] }
    let leftStart = leftRail.first!
    let leftEnd = leftRail.last!
    let rightStart = rightRail.first!
    let rightEnd = rightRail.last!

    let startDistance = (leftStart - rightStart).length
    let endDistance = (leftEnd - rightEnd).length
    let startAltDistance = (leftStart - rightEnd).length
    let endAltDistance = (leftEnd - rightStart).length
    let sumDirect = startDistance + endDistance
    let sumSwap = startAltDistance + endAltDistance
    let useReversedRight = sumSwap + Epsilon.defaultValue < sumDirect

    let rightOrdered = useReversedRight ? Array(rightRail.reversed()) : rightRail

    func approachPoint(rail: [Vec2], atStart: Bool) -> Vec2 {
        if rail.count < 2 { return rail.first ?? Vec2(0, 0) }
        if minApproach <= 0.0 {
            return atStart ? rail[1] : rail[rail.count - 2]
        }
        if atStart {
            let origin = rail[0]
            for index in 1..<rail.count {
                if (rail[index] - origin).length >= minApproach {
                    return rail[index]
                }
            }
            return rail[rail.count - 1]
        } else {
            let origin = rail[rail.count - 1]
            for index in stride(from: rail.count - 2, through: 0, by: -1) {
                if (rail[index] - origin).length >= minApproach {
                    return rail[index]
                }
            }
            return rail[0]
        }
    }

    if atStart {
        let leftApproach = approachPoint(rail: leftRail, atStart: true)
        let rightApproach = approachPoint(rail: rightOrdered, atStart: true)
        return [leftApproach, leftStart, rightOrdered[0], rightApproach]
    }
    let leftApproach = approachPoint(rail: leftRail, atStart: false)
    let rightApproach = approachPoint(rail: rightOrdered, atStart: false)
    return [leftApproach, leftEnd, rightOrdered[rightOrdered.count - 1], rightApproach]
}

public struct FilletSplice: Equatable, Sendable {
    public let a: Vec2
    public let b: Vec2
    public let c: Vec2
    public let p: Vec2
    public let q: Vec2
    public let theta: Double
    public let d: Double
    public let bridge: CubicBezier2
    public let arcMidpoint: Vec2
}

public enum FilletError: Error, Equatable {
    case degenerateAngle
    case radiusTooLarge
    case cornerNotFound
    case cornerOverlap
    case noCorner
}

public enum FilletResult: Equatable {
    case success(FilletSplice)
    case failure(FilletError)
}

public func filletCorner(a: Vec2, b: Vec2, c: Vec2, radius: Double) -> FilletResult {
    filletCornerSigned(a: a, b: b, c: c, radius: radius, sign: 1.0)
}

private func filletCornerSigned(a: Vec2, b: Vec2, c: Vec2, radius: Double, sign: Double) -> FilletResult {
    let u = (b - a).normalized()
    let v = (c - b).normalized()
    let dot = max(-1.0, min(1.0, (u * -1.0).dot(v)))
    let theta = acos(dot)
    let epsAngle = 1.0e-3
    if theta <= epsAngle || abs(theta - Double.pi) <= epsAngle {
        return .failure(.degenerateAngle)
    }
    let d = radius * tan(theta * 0.5)
    let lenA = (b - a).length
    let lenC = (c - b).length
    if d > lenA || d > lenC {
        return .failure(.radiusTooLarge)
    }
    let p = b - u * d
    let q = b + v * d

    let inDir = (u * -1.0).normalized()
    let outDir = v.normalized()
    let bis = (inDir + outDir).normalized()
    if bis.length <= 1.0e-6 {
        return .failure(.degenerateAngle)
    }
    let h = radius / max(1.0e-12, sin(theta * 0.5))
    let center = b + bis * h * sign
    let r0 = (p - center).normalized()
    let r1 = (q - center).normalized()
    let rawPhi = atan2(r0.x * r1.y - r0.y * r1.x, r0.x * r1.x + r0.y * r1.y)
    let ccwTangent = Vec2(-r0.y, r0.x)
    let cwTangent = Vec2(r0.y, -r0.x)
    var wantsCCW = ccwTangent.dot(inDir) >= cwTangent.dot(inDir)
    let endCCW = Vec2(-r1.y, r1.x)
    let endCW = Vec2(r1.y, -r1.x)
    if wantsCCW {
        if endCCW.dot(outDir) < endCW.dot(outDir) { wantsCCW = false }
    } else {
        if endCW.dot(outDir) < endCCW.dot(outDir) { wantsCCW = true }
    }
    var phi = rawPhi
    if wantsCCW {
        if phi < 0 { phi += 2.0 * Double.pi }
    } else {
        if phi > 0 { phi -= 2.0 * Double.pi }
    }
    let k = (4.0 / 3.0) * tan(abs(phi) / 4.0)
    let t0 = wantsCCW ? ccwTangent : cwTangent
    let t1 = wantsCCW ? endCCW : endCW
    let b0 = p
    let b1 = p + t0 * (k * radius)
    let b2 = q - t1 * (k * radius)
    let b3 = q
    let bridge = CubicBezier2(p0: b0, p1: b1, p2: b2, p3: b3)
    let startAngle = atan2(r0.y, r0.x)
    let midAngle = startAngle + phi * 0.5
    let arcMidpoint = center + Vec2(cos(midAngle), sin(midAngle)) * radius
    return .success(FilletSplice(a: a, b: b, c: c, p: p, q: q, theta: theta, d: d, bridge: bridge, arcMidpoint: arcMidpoint))
}

public struct CapFilletDebug: Equatable, Sendable {
    public let kind: String
    public let side: String
    public let radius: Double
    public let cornerIndex: Int
    public let a: Vec2
    public let b: Vec2
    public let c: Vec2
    public let theta: Double
    public let d: Double
    public let lenIn: Double
    public let lenOut: Double
    public let arcMidpoint: Vec2
    public let corner: Vec2
    public let p: Vec2
    public let q: Vec2
    public let bridge: CubicBezier2?
    public let success: Bool
    public let failureReason: String?
    public let arcSegments: Int
    public let insertedPoints: Int
}

public struct CapBoundaryCornerInfo: Equatable, Sendable {
    public let index: Int
    public let point: Vec2
    public let lenIn: Double
    public let lenOut: Double
    public let theta: Double
}

public struct CapBoundaryDebug: Equatable, Sendable {
    public let endpoint: String
    public let original: [Vec2]
    public let simplified: [Vec2]
    public let corners: [CapBoundaryCornerInfo]
    public let chosenIndices: [Int]
    public let chosenThetas: [Double]
    public let trimPoints: [Vec2]
    public let arcPoints: [Vec2]
    public let fallbackReason: String?
    public let fallbackPoint: Vec2?
    public let fallbackCorner: Vec2?
}

public struct CapPlaneDebug: Equatable, Sendable {
    public let endpoint: String
    public let side: String
    public let origin: Vec2
    public let normal: Vec2
    public let overhangs: [Vec2]
    public let removedCount: Int
    public let clippedCount: Int
    public let maxOverhangBefore: Double
    public let maxOverhangAfter: Double
}

private func sampleCubicSegments(_ cubic: CubicBezier2, segments: Int, source: EdgeSource) -> (segments: [Segment2], points: [Vec2]) {
    let count = max(2, segments + 1)
    var points: [Vec2] = []
    points.reserveCapacity(count)
    for i in 0..<count {
        let t = Double(i) / Double(count - 1)
        points.append(cubic.evaluate(t))
    }
    var segmentsOut: [Segment2] = []
    for i in 0..<(points.count - 1) {
        segmentsOut.append(Segment2(points[i], points[i + 1], source: source))
    }
    return (segmentsOut, points)
}

private func segmentsFromPoints(_ points: [Vec2], source: EdgeSource) -> [Segment2] {
    guard points.count >= 2 else { return [] }
    var segmentsOut: [Segment2] = []
    segmentsOut.reserveCapacity(points.count - 1)
    for i in 0..<(points.count - 1) {
        segmentsOut.append(Segment2(points[i], points[i + 1], source: source))
    }
    return segmentsOut
}

private struct RailTrimResult {
    let points: [Vec2]
    let removedCount: Int
    let clippedCount: Int
    let maxOverhangBefore: Double
    let maxOverhangAfter: Double
    let overhangs: [Vec2]
    let valid: Bool
}

private func trimRailToCapPlane(
    rail: [Vec2],
    origin: Vec2,
    normal: Vec2,
    atStart: Bool,
    eps: Double
) -> RailTrimResult {
    guard rail.count >= 2 else {
        return RailTrimResult(points: rail, removedCount: 0, clippedCount: 0, maxOverhangBefore: 0.0, maxOverhangAfter: 0.0, overhangs: [], valid: false)
    }
    func overhang(_ p: Vec2) -> Double {
        let v = p - origin
        return v.x * normal.x + v.y * normal.y
    }
    func endpointWindow(_ points: [Vec2], atStart: Bool) -> ArraySlice<Vec2> {
        let window = min(5, points.count)
        if atStart {
            return points.prefix(window)
        }
        return points.suffix(window)
    }
    func maxOverhang(in points: ArraySlice<Vec2>) -> Double {
        var maxValue = -Double.greatestFiniteMagnitude
        for point in points {
            let d = overhang(point)
            if d > maxValue { maxValue = d }
        }
        return maxValue.isFinite ? maxValue : 0.0
    }
    let maxBefore = maxOverhang(in: endpointWindow(rail, atStart: atStart))
    var overhangs: [Vec2] = []
    for point in rail {
        let d = overhang(point)
        if d > eps {
            overhangs.append(point)
        }
    }

    var trimmed = rail
    let removedCount = 0
    var clippedCount = 0
    let valid = rail.count >= 2
    let window = min(5, rail.count)
    if atStart {
        for i in 0..<window {
            let d = overhang(trimmed[i])
            if d > eps {
                trimmed[i] = trimmed[i] - normal * d
                clippedCount += 1
            }
        }
    } else {
        if window > 0 {
            for offset in 0..<window {
                let i = trimmed.count - 1 - offset
                let d = overhang(trimmed[i])
                if d > eps {
                    trimmed[i] = trimmed[i] - normal * d
                    clippedCount += 1
                }
            }
        }
    }

    let maxAfter = maxOverhang(in: endpointWindow(trimmed, atStart: atStart))

    return RailTrimResult(
        points: trimmed,
        removedCount: removedCount,
        clippedCount: clippedCount,
        maxOverhangBefore: maxBefore.isFinite ? maxBefore : 0.0,
        maxOverhangAfter: maxAfter,
        overhangs: overhangs,
        valid: valid
    )
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
    attrEpsOffset: Double = 0.25,
    attrEpsWidth: Double = 0.25,
    attrEpsAngle: Double = 0.00436,
    attrEpsAlpha: Double = 0.25,
    maxDepth: Int = 12,
    maxSamples: Int = 512,
    warpGT: @escaping (Double) -> Double = { $0 },
    styleAtGT: @escaping (Double) -> SweepStyle,
    alphaAtGT: ((Double) -> Double)? = nil,
    keyframeTs: [Double] = [],
    debugSampling: ((SamplingResult) -> Void)? = nil,
    debugCapEndpoints: ((CapEndpointsDebug) -> Void)? = nil,
    debugRailSummary: ((RailDebugSummary) -> Void)? = nil,
    debugRailFrames: (([RailSampleFrame]) -> Void)? = nil,
    debugRailCornerIndex: Int? = nil,
    debugRailCorner: ((RailCornerDebug) -> Void)? = nil,
    debugPenStamps: ((PenStampsDebug) -> Void)? = nil,
    debugCapFillet: ((CapFilletDebug) -> Void)? = nil,
    debugCapBoundary: ((CapBoundaryDebug) -> Void)? = nil,
    debugCapPlane: ((CapPlaneDebug) -> Void)? = nil,
    capNamespace: String = "stroke",
    capLocalIndex: Int = 0,
    startCap: CapStyle = .butt,
    endCap: CapStyle = .butt,
    capFilletArcSegments: Int = 8,
    capRoundArcSegments: Int = 64,
    penShape: PenShape = .auto
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
    cfg.attrEpsOffset = attrEpsOffset
    cfg.attrEpsWidth = attrEpsWidth
    cfg.attrEpsAngle = attrEpsAngle
    cfg.attrEpsAlpha = attrEpsAlpha
    cfg.paramEps = max(attrEpsOffset, max(attrEpsWidth, max(attrEpsAngle, attrEpsAlpha)))
    cfg.maxDepth = maxDepth
    cfg.maxSamples = maxSamples

    let sampler = GlobalTSampler()
    let paramsAt: (@Sendable (Double) -> GlobalTSampler.StrokeParamsSample?) = { gt in
        let t = warpGT(gt)
        let style = styleAtGT(t)
        let alpha = alphaAtGT?(t) ?? 0.0
        return GlobalTSampler.StrokeParamsSample(
            widthLeft: style.widthLeft,
            widthRight: style.widthRight,
            theta: style.angle,
            offset: style.offset,
            alpha: alpha
        )
    }

    // IMPORTANT:
    // - When adaptiveSampling is false, we pass railProbe=nil to avoid doing
    //   any extra work or generating trace noise.
    let paramsAtOpt: (@Sendable (Double) -> GlobalTSampler.StrokeParamsSample?)? =
        adaptiveSampling ? paramsAt : (nil as (@Sendable (Double) -> GlobalTSampler.StrokeParamsSample?)?)
    let sampling = sampler.sampleGlobalT(
        config: cfg,
        positionAt: positionAtGT,
        railProbe: adaptiveSampling ? probe : nil,
        paramsAt: paramsAtOpt
    )

    // Step 3.5: expose sampling trace to the caller (e.g., cp2-cli debug SVG)
    var samplingOutput = sampling

    // Preserve the older behavior: even in adaptive mode, ensure a minimum uniform density.
    var samples: [Double] = adaptiveSampling
        ? mergeWithUniformSamples(sampling.ts, minCount: max(2, sampleCount))
        : sampling.ts
    let injected = injectKeyframeSamplesWithCount(samples, keyframes: keyframeTs, eps: cfg.tEps)
    samples = injected.samples
    if injected.insertedCount > 0 {
        var stats = samplingOutput.stats
        stats.keyframeHits = injected.insertedCount
        samplingOutput = SamplingResult(ts: samplingOutput.ts, trace: samplingOutput.trace, stats: stats)
    }
    if samples != samplingOutput.ts {
        samplingOutput = SamplingResult(ts: samples, trace: samplingOutput.trace, stats: samplingOutput.stats)
    }
    debugSampling?(samplingOutput)

    let count = max(2, samples.count)

    let resolvedPenShape: PenShape = {
        switch penShape {
        case .auto:
            let base = styleAtGT(warpGT(0.0))
            return base.angleIsRelative ? .railsOnly : .rectCorners
        default:
            return penShape
        }
    }()
    let useRectCorners = resolvedPenShape == .rectCorners

    var left: [Vec2] = []
    var right: [Vec2] = []
    left.reserveCapacity(count)
    right.reserveCapacity(count)

    var corner0: [Vec2] = []
    var corner1: [Vec2] = []
    var corner2: [Vec2] = []
    var corner3: [Vec2] = []
    if useRectCorners {
        corner0.reserveCapacity(count)
        corner1.reserveCapacity(count)
        corner2.reserveCapacity(count)
        corner3.reserveCapacity(count)
    }

    let wantsFrames = debugRailFrames != nil || debugRailSummary != nil || useRectCorners
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
            if useRectCorners {
                let style = styleAtGT(warpGT(gt))
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
                corner0.append(corners.c0)
                corner1.append(corners.c1)
                corner2.append(corners.c2)
                corner3.append(corners.c3)
            }
            if let debugRailCorner, let target = debugRailCornerIndex, target == index {
                let cornerDebug = computeRailCornerDebug(
                    index: index,
                    center: frame.center,
                    tangent: frame.tangent,
                    normal: frame.normal,
                    widthLeft: frame.widthLeft,
                    widthRight: frame.widthRight,
                    height: styleAtGT(warpGT(gt)).height,
                    effectiveAngle: frame.effectiveAngle,
                    computeCorners: { center, u, v, width, height, angle in
                        rectangleCorners(
                            center: center,
                            tangent: u,
                            normal: v,
                            width: width,
                            height: height,
                            effectiveAngle: angle
                        )
                    },
                    left: frame.left,
                    right: frame.right
                )
                debugRailCorner(cornerDebug)
            }
        } else {
            let rail = probe.rails(atGlobalT: gt)
            left.append(rail.left)
            right.append(rail.right)
            if let debugRailCorner, let target = debugRailCornerIndex, target == index {
                let (railSample, frame) = computeRailSampleFrame(
                    param: param,
                    warpGT: warpGT,
                    styleAtGT: styleAtGT,
                    gt: gt,
                    index: index
                )
                _ = railSample
                let cornerDebug = computeRailCornerDebug(
                    index: index,
                    center: frame.center,
                    tangent: frame.tangent,
                    normal: frame.normal,
                    widthLeft: frame.widthLeft,
                    widthRight: frame.widthRight,
                    height: styleAtGT(warpGT(gt)).height,
                    effectiveAngle: frame.effectiveAngle,
                    computeCorners: { center, u, v, width, height, angle in
                        rectangleCorners(
                            center: center,
                            tangent: u,
                            normal: v,
                            width: width,
                            height: height,
                            effectiveAngle: angle
                        )
                    },
                    left: frame.left,
                    right: frame.right
                )
                debugRailCorner(cornerDebug)
            }
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
    if let debugPenStamps, useRectCorners, corner0.count == count, corner1.count == count, corner2.count == count, corner3.count == count {
        var samplesOut: [PenStampSample] = []
        samplesOut.reserveCapacity(count)
        for i in 0..<count {
            let corners = [corner0[i], corner1[i], corner2[i], corner3[i]]
            let gt = i < samples.count ? samples[i] : Double(i) / Double(max(1, count - 1))
            samplesOut.append(PenStampSample(index: i, gt: gt, corners: corners))
        }
        debugPenStamps(PenStampsDebug(samples: samplesOut))
    }

    // ---- Trim rails to cap plane to avoid overhang at butt caps ----
    let eps = Epsilon.defaultValue
    let startGT = samples.first ?? 0.0
    let endGT = samples.last ?? 1.0
    let startFrame = railSampleFrameAtGlobalT(
        param: param,
        warpGT: warpGT,
        styleAtGT: styleAtGT,
        gt: startGT,
        index: 0
    )
    let endFrame = railSampleFrameAtGlobalT(
        param: param,
        warpGT: warpGT,
        styleAtGT: styleAtGT,
        gt: endGT,
        index: max(0, count - 1)
    )
    func normalize(_ v: Vec2) -> Vec2 {
        let len = v.length
        if len <= eps { return Vec2(0, 0) }
        return v * (1.0 / len)
    }
    let startNormal = normalize(startFrame.tangent) * -1.0
    let endNormal = normalize(endFrame.tangent)
    let isClosed = {
        guard let first = path.segments.first, let last = path.segments.last else { return false }
        return Epsilon.approxEqual(first.p0, last.p3)
    }()
    if debugCapBoundary != nil {
        print(String(format: "CAP_PLANE endpoint=start origin=(%.6f,%.6f) n=(%.6f,%.6f)", startFrame.center.x, startFrame.center.y, startNormal.x, startNormal.y))
        print(String(format: "CAP_PLANE endpoint=end origin=(%.6f,%.6f) n=(%.6f,%.6f)", endFrame.center.x, endFrame.center.y, endNormal.x, endNormal.y))
    }

    func applyTrim(
        rail: [Vec2],
        endpoint: String,
        side: String,
        origin: Vec2,
        normal: Vec2,
        atStart: Bool
    ) -> [Vec2] {
        let result = trimRailToCapPlane(rail: rail, origin: origin, normal: normal, atStart: atStart, eps: eps)
        if debugCapBoundary != nil {
            print(String(format: "CAP_RAIL_TRIM endpoint=%@ side=%@ removed=%d clipped=%d maxOverhangBefore=%.6f maxOverhangAfter=%.6f valid=%@", endpoint, side, result.removedCount, result.clippedCount, result.maxOverhangBefore, result.maxOverhangAfter, result.valid.description))
        }
        debugCapPlane?(CapPlaneDebug(
            endpoint: endpoint,
            side: side,
            origin: origin,
            normal: normal,
            overhangs: result.overhangs,
            removedCount: result.removedCount,
            clippedCount: result.clippedCount,
            maxOverhangBefore: result.maxOverhangBefore,
            maxOverhangAfter: result.maxOverhangAfter
        ))
        return result.valid ? result.points : rail
    }

    if !isClosed {
        left = applyTrim(rail: left, endpoint: "start", side: "left", origin: startFrame.center, normal: startNormal, atStart: true)
        right = applyTrim(rail: right, endpoint: "start", side: "right", origin: startFrame.center, normal: startNormal, atStart: true)
        left = applyTrim(rail: left, endpoint: "end", side: "left", origin: endFrame.center, normal: endNormal, atStart: false)
        right = applyTrim(rail: right, endpoint: "end", side: "right", origin: endFrame.center, normal: endNormal, atStart: false)
    }

    if useRectCorners && !corner0.isEmpty && corner0.count == count {
        return buildPenSoupSegmentsRectCorners(
            corner0: corner0,
            corner1: corner1,
            corner2: corner2,
            corner3: corner3,
            eps: eps
        ).segments
    }

    // MARK: EDGE CREATION SITES
    // - boundarySoupGeneral: left forward (railLeft), right backward (railRight), caps (capStart/capEnd)
    // - traceLoops: consumes segments; no creation
    //
    // ---- Stitch boundary soup segments (left forward, right backward, caps) ----
    var segments: [Segment2] = []
    segments.reserveCapacity(count * 2 + 2)
    func widthScale(_ style: SweepStyle) -> Double {
        let sum = style.widthLeft + style.widthRight
        let maxSide = max(style.widthLeft, style.widthRight)
        return max(sum, 2.0 * maxSide)
    }
    let startStyle = styleAtGT(warpGT(0.0))
    let endStyle = styleAtGT(warpGT(1.0))
    let caps = buildCaps(
        leftRail: left,
        rightRail: right,
        capNamespace: capNamespace,
        capLocalIndex: capLocalIndex,
        widthStart: widthScale(startStyle),
        widthEnd: widthScale(endStyle),
        startCap: startCap,
        endCap: endCap,
        capFilletArcSegments: capFilletArcSegments,
        capRoundArcSegments: capRoundArcSegments,
        debugFillet: debugCapFillet,
        debugCapBoundary: debugCapBoundary
    )
    let startDistance = (left.first! - right.first!).length
    let endDistance = (left.last! - right.last!).length
    let startAltDistance = (left.first! - right.last!).length
    let endAltDistance = (left.last! - right.first!).length
    let sumDirect = startDistance + endDistance
    let sumSwap = startAltDistance + endAltDistance
    let useReversedRight = sumSwap + Epsilon.defaultValue < sumDirect
    var rightAdjusted = right
    if let startRightTrim = caps.startRightTrim {
        let index = useReversedRight ? rightAdjusted.count - 1 : 0
        rightAdjusted[index] = startRightTrim
    }
    if let endRightTrim = caps.endRightTrim {
        let index = useReversedRight ? 0 : rightAdjusted.count - 1
        rightAdjusted[index] = endRightTrim
    }
    let leftCount = left.count
    let rightCount = rightAdjusted.count
    for i in stride(from: rightCount - 1, to: 0, by: -1) {
        segments.append(Segment2(rightAdjusted[i], rightAdjusted[i - 1], source: .railRight))
    }
    let startLeft = caps.startLeftTrim ?? left[0]
    let endLeft = caps.endLeftTrim ?? left[leftCount - 1]
    if leftCount == 2 {
        segments.append(Segment2(startLeft, endLeft, source: .railLeft))
    } else if leftCount > 2 {
        segments.append(Segment2(startLeft, left[1], source: .railLeft))
        for i in 1..<(leftCount - 1) {
            segments.append(Segment2(left[i], left[i + 1], source: .railLeft))
        }
        segments.append(Segment2(left[leftCount - 2], endLeft, source: .railLeft))
    }
    segments.append(contentsOf: caps.segments)
    if let debugCapEndpoints, let capInfo = computeCapEndpointsDebug(
        leftRail: left,
        rightRail: rightAdjusted,
        capSegments: caps.segments,
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
    attrEpsOffset: Double = 0.25,
    attrEpsWidth: Double = 0.25,
    attrEpsAngle: Double = 0.00436,
    attrEpsAlpha: Double = 0.25,
    maxDepth: Int = 12,
    maxSamples: Int = 512,
    keyframeTs: [Double] = [],
    debugSampling: ((SamplingResult) -> Void)? = nil,
    debugCapEndpoints: ((CapEndpointsDebug) -> Void)? = nil,
    debugRailSummary: ((RailDebugSummary) -> Void)? = nil,
    debugRailFrames: (([RailSampleFrame]) -> Void)? = nil,
    debugRailCornerIndex: Int? = nil,
    debugRailCorner: ((RailCornerDebug) -> Void)? = nil,
    debugPenStamps: ((PenStampsDebug) -> Void)? = nil,
    debugCapFillet: ((CapFilletDebug) -> Void)? = nil,
    debugCapBoundary: ((CapBoundaryDebug) -> Void)? = nil,
    debugCapPlane: ((CapPlaneDebug) -> Void)? = nil,
    capNamespace: String = "stroke",
    capLocalIndex: Int = 0,
    startCap: CapStyle = .butt,
    endCap: CapStyle = .butt,
    capFilletArcSegments: Int = 8,
    capRoundArcSegments: Int = 64,
    penShape: PenShape = .auto
) -> [Segment2] {
    boundarySoupGeneral(
        path: path,
        sampleCount: sampleCount,
        arcSamplesPerSegment: arcSamplesPerSegment,
        adaptiveSampling: adaptiveSampling,
        flatnessEps: flatnessEps,
        railEps: railEps,
        attrEpsOffset: attrEpsOffset,
        attrEpsWidth: attrEpsWidth,
        attrEpsAngle: attrEpsAngle,
        attrEpsAlpha: attrEpsAlpha,
        maxDepth: maxDepth,
        maxSamples: maxSamples,
        styleAtGT: { _ in
            SweepStyle(
                width: width,
                widthLeft: width * 0.5,
                widthRight: width * 0.5,
                height: height,
                angle: effectiveAngle,
                offset: 0.0,
                angleIsRelative: true
            )
        },
        alphaAtGT: nil,
        keyframeTs: keyframeTs,
        debugSampling: debugSampling,
        debugCapEndpoints: debugCapEndpoints,
        debugRailSummary: debugRailSummary,
        debugRailFrames: debugRailFrames,
        debugRailCornerIndex: debugRailCornerIndex,
        debugRailCorner: debugRailCorner,
        debugPenStamps: debugPenStamps,
        debugCapFillet: debugCapFillet,
        debugCapBoundary: debugCapBoundary,
        debugCapPlane: debugCapPlane,
        capNamespace: capNamespace,
        capLocalIndex: capLocalIndex,
        startCap: startCap,
        endCap: endCap,
        capFilletArcSegments: capFilletArcSegments,
        capRoundArcSegments: capRoundArcSegments,
        penShape: penShape
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
    attrEpsOffset: Double = 0.25,
    attrEpsWidth: Double = 0.25,
    attrEpsAngle: Double = 0.00436,
    attrEpsAlpha: Double = 0.25,
    maxDepth: Int = 12,
    maxSamples: Int = 512,
    widthAtT: @escaping (Double) -> Double,
    keyframeTs: [Double] = [],
    debugSampling: ((SamplingResult) -> Void)? = nil,
    debugCapEndpoints: ((CapEndpointsDebug) -> Void)? = nil,
    debugRailSummary: ((RailDebugSummary) -> Void)? = nil,
    debugRailFrames: (([RailSampleFrame]) -> Void)? = nil,
    debugRailCornerIndex: Int? = nil,
    debugRailCorner: ((RailCornerDebug) -> Void)? = nil,
    debugPenStamps: ((PenStampsDebug) -> Void)? = nil,
    debugCapFillet: ((CapFilletDebug) -> Void)? = nil,
    debugCapBoundary: ((CapBoundaryDebug) -> Void)? = nil,
    debugCapPlane: ((CapPlaneDebug) -> Void)? = nil,
    capNamespace: String = "stroke",
    capLocalIndex: Int = 0,
    startCap: CapStyle = .butt,
    endCap: CapStyle = .butt,
    capFilletArcSegments: Int = 8,
    capRoundArcSegments: Int = 64,
    penShape: PenShape = .auto
) -> [Segment2] {
    boundarySoupGeneral(
        path: path,
        sampleCount: sampleCount,
        arcSamplesPerSegment: arcSamplesPerSegment,
        adaptiveSampling: adaptiveSampling,
        flatnessEps: flatnessEps,
        railEps: railEps,
        attrEpsOffset: attrEpsOffset,
        attrEpsWidth: attrEpsWidth,
        attrEpsAngle: attrEpsAngle,
        attrEpsAlpha: attrEpsAlpha,
        maxDepth: maxDepth,
        maxSamples: maxSamples,
        styleAtGT: { t in
            let total = widthAtT(t)
            return SweepStyle(
                width: total,
                widthLeft: total * 0.5,
                widthRight: total * 0.5,
                height: height,
                angle: effectiveAngle,
                offset: 0.0,
                angleIsRelative: true
            )
        },
        alphaAtGT: nil,
        keyframeTs: keyframeTs,
        debugSampling: debugSampling,
        debugCapEndpoints: debugCapEndpoints,
        debugRailSummary: debugRailSummary,
        debugRailFrames: debugRailFrames,
        debugRailCornerIndex: debugRailCornerIndex,
        debugRailCorner: debugRailCorner,
        debugPenStamps: debugPenStamps,
        debugCapFillet: debugCapFillet,
        debugCapBoundary: debugCapBoundary,
        debugCapPlane: debugCapPlane,
        capNamespace: capNamespace,
        capLocalIndex: capLocalIndex,
        startCap: startCap,
        endCap: endCap,
        capFilletArcSegments: capFilletArcSegments,
        capRoundArcSegments: capRoundArcSegments,
        penShape: penShape
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
    attrEpsOffset: Double = 0.25,
    attrEpsWidth: Double = 0.25,
    attrEpsAngle: Double = 0.00436,
    attrEpsAlpha: Double = 0.25,
    maxDepth: Int = 12,
    maxSamples: Int = 512,
    widthAtT: @escaping (Double) -> Double,
    widthLeftAtT: ((Double) -> Double)? = nil,
    widthRightAtT: ((Double) -> Double)? = nil,
    angleAtT: @escaping (Double) -> Double,
    debugSampling: ((SamplingResult) -> Void)? = nil,
    debugCapEndpoints: ((CapEndpointsDebug) -> Void)? = nil,
    debugRailSummary: ((RailDebugSummary) -> Void)? = nil,
    debugRailFrames: (([RailSampleFrame]) -> Void)? = nil,
    debugRailCornerIndex: Int? = nil,
    debugRailCorner: ((RailCornerDebug) -> Void)? = nil,
    debugPenStamps: ((PenStampsDebug) -> Void)? = nil,
    debugCapFillet: ((CapFilletDebug) -> Void)? = nil,
    debugCapBoundary: ((CapBoundaryDebug) -> Void)? = nil,
    debugCapPlane: ((CapPlaneDebug) -> Void)? = nil,
    capNamespace: String = "stroke",
    capLocalIndex: Int = 0,
    startCap: CapStyle = .butt,
    endCap: CapStyle = .butt,
    capFilletArcSegments: Int = 8,
    capRoundArcSegments: Int = 64,
    penShape: PenShape = .auto
) -> [Segment2] {
    boundarySoupGeneral(
        path: path,
        sampleCount: sampleCount,
        arcSamplesPerSegment: arcSamplesPerSegment,
        adaptiveSampling: adaptiveSampling,
        flatnessEps: flatnessEps,
        railEps: railEps,
        attrEpsOffset: attrEpsOffset,
        attrEpsWidth: attrEpsWidth,
        attrEpsAngle: attrEpsAngle,
        attrEpsAlpha: attrEpsAlpha,
        maxDepth: maxDepth,
        maxSamples: maxSamples,
        styleAtGT: { t in
            let total = widthAtT(t)
            let wL = widthLeftAtT?(t) ?? total * 0.5
            let wR = widthRightAtT?(t) ?? total * 0.5
            return SweepStyle(
                width: total,
                widthLeft: wL,
                widthRight: wR,
                height: height,
                angle: angleAtT(t),
                offset: 0.0,
                angleIsRelative: true
            )
        },
        alphaAtGT: nil,
        debugSampling: debugSampling,
        debugCapEndpoints: debugCapEndpoints,
        debugRailSummary: debugRailSummary,
        debugRailFrames: debugRailFrames,
        debugRailCornerIndex: debugRailCornerIndex,
        debugRailCorner: debugRailCorner,
        debugPenStamps: debugPenStamps,
        debugCapFillet: debugCapFillet,
        debugCapBoundary: debugCapBoundary,
        debugCapPlane: debugCapPlane,
        capNamespace: capNamespace,
        capLocalIndex: capLocalIndex,
        startCap: startCap,
        endCap: endCap,
        capFilletArcSegments: capFilletArcSegments,
        capRoundArcSegments: capRoundArcSegments,
        penShape: penShape
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
    attrEpsOffset: Double = 0.25,
    attrEpsWidth: Double = 0.25,
    attrEpsAngle: Double = 0.00436,
    attrEpsAlpha: Double = 0.25,
    maxDepth: Int = 12,
    maxSamples: Int = 512,
    widthAtT: @escaping (Double) -> Double,
    widthLeftAtT: ((Double) -> Double)? = nil,
    widthRightAtT: ((Double) -> Double)? = nil,
    angleAtT: @escaping (Double) -> Double,
    offsetAtT: @escaping (Double) -> Double = { _ in 0.0 },
    alphaAtT: @escaping (Double) -> Double,
    alphaStart: Double,
    angleIsRelative: Bool = true,
    keyframeTs: [Double] = [],
    debugSampling: ((SamplingResult) -> Void)? = nil,
    debugCapEndpoints: ((CapEndpointsDebug) -> Void)? = nil,
    debugRailSummary: ((RailDebugSummary) -> Void)? = nil,
    debugRailFrames: (([RailSampleFrame]) -> Void)? = nil,
    debugRailCornerIndex: Int? = nil,
    debugRailCorner: ((RailCornerDebug) -> Void)? = nil,
    debugPenStamps: ((PenStampsDebug) -> Void)? = nil,
    debugCapFillet: ((CapFilletDebug) -> Void)? = nil,
    debugCapBoundary: ((CapBoundaryDebug) -> Void)? = nil,
    debugCapPlane: ((CapPlaneDebug) -> Void)? = nil,
    capNamespace: String = "stroke",
    capLocalIndex: Int = 0,
    startCap: CapStyle = .butt,
    endCap: CapStyle = .butt,
    capFilletArcSegments: Int = 8,
    capRoundArcSegments: Int = 64,
    penShape: PenShape = .auto
) -> [Segment2] {
    boundarySoupGeneral(
        path: path,
        sampleCount: sampleCount,
        arcSamplesPerSegment: arcSamplesPerSegment,
        adaptiveSampling: adaptiveSampling,
        flatnessEps: flatnessEps,
        railEps: railEps,
        attrEpsOffset: attrEpsOffset,
        attrEpsWidth: attrEpsWidth,
        attrEpsAngle: attrEpsAngle,
        attrEpsAlpha: attrEpsAlpha,
        maxDepth: maxDepth,
        maxSamples: maxSamples,
        warpGT: { gt in gt },
        styleAtGT: { t in
            let total = widthAtT(t)
            let wL = widthLeftAtT?(t) ?? total * 0.5
            let wR = widthRightAtT?(t) ?? total * 0.5
            return SweepStyle(
                width: total,
                widthLeft: wL,
                widthRight: wR,
                height: height,
                angle: angleAtT(t),
                offset: offsetAtT(t),
                angleIsRelative: angleIsRelative
            )
        },
        alphaAtGT: alphaAtT,
        keyframeTs: keyframeTs,
        debugSampling: debugSampling,
        debugCapEndpoints: debugCapEndpoints,
        debugRailSummary: debugRailSummary,
        debugRailFrames: debugRailFrames,
        debugRailCornerIndex: debugRailCornerIndex,
        debugRailCorner: debugRailCorner,
        debugPenStamps: debugPenStamps,
        debugCapFillet: debugCapFillet,
        debugCapBoundary: debugCapBoundary,
        debugCapPlane: debugCapPlane,
        capNamespace: capNamespace,
        capLocalIndex: capLocalIndex,
        startCap: startCap,
        endCap: endCap,
        capFilletArcSegments: capFilletArcSegments,
        capRoundArcSegments: capRoundArcSegments,
        penShape: penShape
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

    let halfWidth = 0.5 * style.width
    let effectiveAngle: Double
    let vRot: Vec2
    if style.angleIsRelative {
        effectiveAngle = style.angle
        let c = cos(effectiveAngle)
        let s = sin(effectiveAngle)
        vRot = tangent * s + normal * c
    } else {
        let c = cos(style.angle)
        let s = sin(style.angle)
        vRot = Vec2(s, c)
        let relSin = vRot.dot(tangent)
        let relCos = vRot.dot(normal)
        effectiveAngle = atan2(relSin, relCos)
    }
    let center = point + vRot * style.offset
    let railPoints = railPointsFromCrossAxis(
        center: center,
        crossAxis: vRot,
        widthLeft: style.widthLeft > 0.0 ? style.widthLeft : halfWidth,
        widthRight: style.widthRight > 0.0 ? style.widthRight : halfWidth
    )
    let sample = RailSample(left: railPoints.left, right: railPoints.right)
    let frame = RailSampleFrame(
        index: index,
        center: center,
        tangent: tangent,
        normal: normal,
        crossAxis: vRot,
        effectiveAngle: effectiveAngle,
        widthLeft: halfWidth,
        widthRight: halfWidth,
        widthTotal: style.width,
        left: railPoints.left,
        right: railPoints.right
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

public struct PenCornerSet: Equatable, Sendable {
    public let c0: Vec2
    public let c1: Vec2
    public let c2: Vec2
    public let c3: Vec2
}

public struct PenStampSample: Equatable, Sendable {
    public let index: Int
    public let gt: Double
    public let corners: [Vec2]

    public init(index: Int, gt: Double, corners: [Vec2]) {
        self.index = index
        self.gt = gt
        self.corners = corners
    }
}

public struct PenStampsDebug: Equatable, Sendable {
    public let samples: [PenStampSample]

    public init(samples: [PenStampSample]) {
        self.samples = samples
    }
}

public func penCorners(
    center: Vec2,
    crossAxis: Vec2,
    widthLeft: Double,
    widthRight: Double,
    height: Double
) -> PenCornerSet {
    let axisLen = crossAxis.length
    let u = axisLen > 1.0e-12 ? crossAxis * (1.0 / axisLen) : Vec2(1.0, 0.0)
    let alongAxis = Vec2(-u.y, u.x)
    let h = height
    let c0 = center + u * widthRight + alongAxis * h
    let c1 = center + u * widthRight - alongAxis * h
    let c2 = center - u * widthLeft - alongAxis * h
    let c3 = center - u * widthLeft + alongAxis * h
    return PenCornerSet(c0: c0, c1: c1, c2: c2, c3: c3)
}

func buildPenEdgeStripLoops(
    corner0: [Vec2],
    corner1: [Vec2],
    corner2: [Vec2],
    corner3: [Vec2],
    eps: Double
) -> [[Vec2]] {
    guard !corner0.isEmpty else { return [] }
    let count = corner0.count
    guard corner1.count == count, corner2.count == count, corner3.count == count else { return [] }
    let corners = [corner0, corner1, corner2, corner3]
    var loops: [[Vec2]] = []
    loops.reserveCapacity(4)
    for k in 0..<4 {
        let a = corners[k]
        let b = corners[(k + 1) % 4]
        var loop: [Vec2] = []
        loop.reserveCapacity(a.count + b.count + 1)
        loop.append(contentsOf: a)
        loop.append(contentsOf: b.reversed())
        if let first = a.first {
            if loop.isEmpty || !Epsilon.approxEqual(loop.last ?? first, first, eps: eps) {
                loop.append(first)
            }
        }
        loops.append(loop)
    }
    return loops
}

func buildPenSoupSegmentsRectCorners(
    corner0: [Vec2],
    corner1: [Vec2],
    corner2: [Vec2],
    corner3: [Vec2],
    eps: Double
) -> (segments: [Segment2], laneSegments: Int, perimeterSegments: Int) {
    guard !corner0.isEmpty else { return ([], 0, 0) }
    let count = corner0.count
    guard corner1.count == count, corner2.count == count, corner3.count == count else {
        return ([], 0, 0)
    }
    let loops = buildPenEdgeStripLoops(
        corner0: corner0,
        corner1: corner1,
        corner2: corner2,
        corner3: corner3,
        eps: eps
    )
    var segments: [Segment2] = []
    segments.reserveCapacity(loops.reduce(0) { $0 + max(0, $1.count - 1) } + count * 4)

    var laneSegments = 0
    for (index, loop) in loops.enumerated() {
        guard loop.count >= 2 else { continue }
        let source = EdgeSource.penStrip(loop: index)
        for i in 0..<(loop.count - 1) {
            segments.append(Segment2(loop[i], loop[i + 1], source: source))
            laneSegments += 1
        }
    }

    func edgeKey(_ a: Vec2, _ b: Vec2) -> String {
        let ka = Epsilon.snapKey(a, eps: eps)
        let kb = Epsilon.snapKey(b, eps: eps)
        if ka.x < kb.x || (ka.x == kb.x && ka.y < kb.y) {
            return "\(ka.x),\(ka.y)->\(kb.x),\(kb.y)"
        }
        return "\(kb.x),\(kb.y)->\(ka.x),\(ka.y)"
    }
    func appendPerimeterEdge(_ a: Vec2, _ b: Vec2, seen: inout Set<String>) -> Bool {
        if (a - b).length <= eps { return false }
        let key = edgeKey(a, b)
        if seen.contains(key) { return false }
        seen.insert(key)
        segments.append(Segment2(a, b, source: .penCap))
        return true
    }

    let edgePairs = [(0, 1), (1, 2), (2, 3), (3, 0)]
    var perimeterSegments = 0
    for k in 0..<count {
        let c0 = corner0[k]
        let c1 = corner1[k]
        let c2 = corner2[k]
        let c3 = corner3[k]
        let corners = [c0, c1, c2, c3]
        var seen: Set<String> = []
        for pair in edgePairs {
            let a = corners[pair.0]
            let b = corners[pair.1]
            if appendPerimeterEdge(a, b, seen: &seen) {
                perimeterSegments += 1
            }
        }
    }
    return (segments, laneSegments, perimeterSegments)
}

private func splitSegmentsAtIntersections(_ segments: [Segment2], eps: Double) -> [Segment2] {
    guard segments.count >= 2 else { return segments }
    let count = segments.count
    var splitTs: [[Double]] = Array(repeating: [0.0, 1.0], count: count)
    func cross(_ a: Vec2, _ b: Vec2) -> Double { a.x * b.y - a.y * b.x }
    func addT(_ t: Double, to index: Int) {
        if t > eps && t < 1.0 - eps {
            splitTs[index].append(t)
        }
    }
    for i in 0..<count {
        let segA = segments[i]
        let a0 = segA.a
        let a1 = segA.b
        let r = a1 - a0
        if r.length <= eps { continue }
        for j in (i + 1)..<count {
            let segB = segments[j]
            let b0 = segB.a
            let b1 = segB.b
            if Epsilon.approxEqual(a0, b0, eps: eps) || Epsilon.approxEqual(a0, b1, eps: eps) || Epsilon.approxEqual(a1, b0, eps: eps) || Epsilon.approxEqual(a1, b1, eps: eps) {
                continue
            }
            let s = b1 - b0
            if s.length <= eps { continue }
            let denom = cross(r, s)
            if abs(denom) <= eps { continue }
            let t = cross(b0 - a0, s) / denom
            let u = cross(b0 - a0, r) / denom
            if t >= eps && t <= 1.0 - eps && u >= eps && u <= 1.0 - eps {
                addT(t, to: i)
                addT(u, to: j)
            }
        }
    }
    var output: [Segment2] = []
    output.reserveCapacity(segments.count)
    for (index, seg) in segments.enumerated() {
        var ts = splitTs[index]
        ts.sort()
        var lastT: Double? = nil
        var unique: [Double] = []
        unique.reserveCapacity(ts.count)
        for t in ts {
            if let last = lastT, abs(t - last) <= eps { continue }
            unique.append(t)
            lastT = t
        }
        for k in 0..<(unique.count - 1) {
            let t0 = unique[k]
            let t1 = unique[k + 1]
            if t1 - t0 <= eps { continue }
            let p0 = seg.a + (seg.b - seg.a) * t0
            let p1 = seg.a + (seg.b - seg.a) * t1
            if (p1 - p0).length <= eps { continue }
            output.append(Segment2(p0, p1, source: seg.source))
        }
    }
    return output
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

func injectKeyframeSamples(_ samples: [Double], keyframes: [Double], eps: Double) -> [Double] {
    guard !keyframes.isEmpty else { return samples }
    let clampedKeys = keyframes.map { max(0.0, min(1.0, $0)) }
    let combined = (samples + clampedKeys).sorted()
    var result: [Double] = []
    result.reserveCapacity(combined.count)
    var last: Double? = nil
    for t in combined {
        if let previous = last, abs(t - previous) <= eps {
            continue
        }
        result.append(t)
        last = t
    }
    return result
}

func injectKeyframeSamplesWithCount(_ samples: [Double], keyframes: [Double], eps: Double) -> (samples: [Double], insertedCount: Int) {
    guard !keyframes.isEmpty else { return (samples, 0) }
    var inserted = 0
    for key in keyframes {
        let clamped = max(0.0, min(1.0, key))
        let exists = samples.contains { abs($0 - clamped) <= eps }
        if !exists { inserted += 1 }
    }
    let merged = injectKeyframeSamples(samples, keyframes: keyframes, eps: eps)
    return (merged, inserted)
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

private func ringSelfIntersectionCount(_ ring: [Vec2], eps: Double) -> Int {
    guard ring.count >= 4 else { return 0 }
    func cross(_ u: Vec2, _ v: Vec2) -> Double { u.x * v.y - u.y * v.x }
    var count = 0
    let edgeCount = ring.count - 1
    for i in 0..<edgeCount {
        let a = ring[i]
        let b = ring[i + 1]
        if i + 2 >= edgeCount { continue }
        for j in (i + 2)..<edgeCount {
            if i == 0 && j == ring.count - 2 { continue }
            let c = ring[j]
            let d = ring[j + 1]
            if Epsilon.approxEqual(a, c, eps: eps) || Epsilon.approxEqual(a, d, eps: eps) ||
                Epsilon.approxEqual(b, c, eps: eps) || Epsilon.approxEqual(b, d, eps: eps) {
                continue
            }
            let r = b - a
            let s = d - c
            let denom = cross(r, s)
            if abs(denom) <= eps { continue }
            let t = cross(c - a, s) / denom
            let u = cross(c - a, r) / denom
            if t >= -eps && t <= 1.0 + eps && u >= -eps && u <= 1.0 + eps {
                count += 1
            }
        }
    }
    return count
}

public func traceLoops(
    segments: [Segment2],
    eps: Double,
    debugStep: ((TraceStepInfo) -> Void)? = nil
) -> [[Vec2]] {
    guard !segments.isEmpty else { return [] }

    let graph = buildSoupGraph(segments: segments, eps: eps)
    let adjacency = graph.adjacency
    var edges = graph.edges
    let pointForKey = graph.pointForKey
    let edgeSources = graph.edgeSources

    func ringTieKey(_ ring: [SnapKey]) -> UInt64 {
        var hash: UInt64 = 1469598103934665603
        for key in ring {
            hash ^= UInt64(bitPattern: Int64(key.x))
            hash = hash &* 1099511628211
            hash ^= UInt64(bitPattern: Int64(key.y))
            hash = hash &* 1099511628211
        }
        return hash
    }

    struct ChoiceKey: Hashable {
        let curr: SnapKey
        let prev: SnapKey
    }

    func traceRing(
        start: SnapKey,
        next: SnapKey,
        ringIndex: Int,
        edgesIn: Set<EdgeKey>,
        forcedChoices: [ChoiceKey: SnapKey],
        debugStep: ((TraceStepInfo) -> Void)?
    ) -> (ring: [SnapKey], used: Set<EdgeKey>, firstAmbiguous: (from: SnapKey, prev: SnapKey, to: SnapKey, candidates: [SnapKey])?) {
        var ring: [SnapKey] = [start, next]
        var prev = start
        var curr = next
        var stepIndex = 0
        var ringSegments: [(SnapKey, SnapKey)] = [(start, next)]
        var usedEdges: Set<EdgeKey> = [EdgeKey(start, next)]
        var edgesLocal = edgesIn
        edgesLocal.remove(EdgeKey(start, next))
        var firstAmbiguous: (from: SnapKey, prev: SnapKey, to: SnapKey, candidates: [SnapKey])? = nil

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
            let candidates = neighbors.filter { edgesLocal.contains(EdgeKey(curr, $0)) }
            let currPos = pointForKey[curr] ?? Vec2(0, 0)
            let prevPos = pointForKey[prev] ?? Vec2(0, 0)
            let incoming = (currPos - prevPos).normalized()
            func signedAngle(_ candidate: SnapKey) -> Double {
                let nextPos = pointForKey[candidate] ?? Vec2(0, 0)
                let outgoing = (nextPos - currPos).normalized()
                let cross = incoming.x * outgoing.y - incoming.y * outgoing.x
                let dot = incoming.x * outgoing.x + incoming.y * outgoing.y
                return atan2(cross, dot)
            }
            func segmentIntersectsExisting(_ aKey: SnapKey, _ bKey: SnapKey) -> Bool {
                let a = pointForKey[aKey] ?? Vec2(0, 0)
                let b = pointForKey[bKey] ?? Vec2(0, 0)
                func cross(_ u: Vec2, _ v: Vec2) -> Double { u.x * v.y - u.y * v.x }
                for (sKey, tKey) in ringSegments {
                    if sKey == aKey || sKey == bKey || tKey == aKey || tKey == bKey { continue }
                    let c = pointForKey[sKey] ?? Vec2(0, 0)
                    let d = pointForKey[tKey] ?? Vec2(0, 0)
                    let r = b - a
                    let s = d - c
                    let denom = cross(r, s)
                    if abs(denom) <= eps { continue }
                    let t = cross(c - a, s) / denom
                    let u = cross(c - a, r) / denom
                    if t >= -eps && t <= 1.0 + eps && u >= -eps && u <= 1.0 + eps {
                        return true
                    }
                }
                return false
            }
            let ordered = candidates.sorted {
                let angleA = abs(signedAngle($0))
                let angleB = abs(signedAngle($1))
                if abs(angleA - angleB) > 1.0e-9 {
                    return angleA < angleB
                }
                return snapKeyLess($0, $1)
            }
            if firstAmbiguous == nil && ordered.count > 1 {
                firstAmbiguous = (from: curr, prev: prev, to: curr, candidates: ordered)
            }
            var chosen: SnapKey? = nil
            if let forced = forcedChoices[ChoiceKey(curr: curr, prev: prev)] {
                if ordered.contains(forced) {
                    chosen = forced
                }
            }
            if chosen == nil {
                let hasNonPrev = ordered.contains { $0 != prev }
                for candidate in ordered {
                    if candidate == prev && hasNonPrev { continue }
                    if !segmentIntersectsExisting(curr, candidate) {
                        chosen = candidate
                        break
                    }
                }
            }
            if chosen == nil {
                chosen = ordered.first
                if debugStep != nil, let chosenKey = chosen {
                    let currPos = pointForKey[curr] ?? Vec2(0, 0)
                    let nextPos = pointForKey[chosenKey] ?? Vec2(0, 0)
                    print(String(format: "TRACE_FORCED_INTERSECTION ring=%d step=%d curr=(%.6f,%.6f) next=(%.6f,%.6f)", ringIndex, stepIndex, currPos.x, currPos.y, nextPos.x, nextPos.y))
                }
            }
            guard let chosen else { break }
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
            edgesLocal.remove(EdgeKey(curr, chosen))
            usedEdges.insert(EdgeKey(curr, chosen))
            ring.append(chosen)
            ringSegments.append((curr, chosen))
            prev = curr
            curr = chosen
        }
        if ring.first != ring.last {
            ring.append(ring.first!)
        }
        return (ring, usedEdges, firstAmbiguous)
    }

    var rings: [[SnapKey]] = []
    var ringIndex = 0
    let maxBranches = 3
    let maxDepth = 2

    func branchCandidates(from candidates: [SnapKey]) -> [SnapKey] {
        if candidates.count <= maxBranches { return candidates }
        if maxBranches <= 1 { return [candidates[0]] }
        if maxBranches == 2 { return [candidates[0], candidates.last!] }
        return [candidates[0], candidates[1], candidates.last!]
    }

    func scoreRing(_ ringKeys: [SnapKey]) -> (intersections: Int, area: Double, tie: UInt64) {
        let ringPoints = ringKeys.compactMap { pointForKey[$0] }
        let intersections = ringSelfIntersectionCount(ringPoints, eps: eps)
        let area = abs(signedArea(ringPoints))
        let tie = ringTieKey(ringKeys)
        return (intersections, area, tie)
    }

    func betterScore(_ a: (intersections: Int, area: Double, tie: UInt64), _ b: (intersections: Int, area: Double, tie: UInt64)) -> Bool {
        if a.intersections != b.intersections { return a.intersections < b.intersections }
        if abs(a.area - b.area) > 1.0e-9 { return a.area > b.area }
        return a.tie < b.tie
    }

    func explore(
        start: SnapKey,
        next: SnapKey,
        ringIndex: Int,
        edgesIn: Set<EdgeKey>,
        forcedChoices: [ChoiceKey: SnapKey],
        depth: Int
    ) -> (ring: [SnapKey], used: Set<EdgeKey>, score: (intersections: Int, area: Double, tie: UInt64)) {
        let attempt = traceRing(
            start: start,
            next: next,
            ringIndex: ringIndex,
            edgesIn: edgesIn,
            forcedChoices: forcedChoices,
            debugStep: debugStep
        )
        let ringKeys = attempt.ring
        let score = scoreRing(ringKeys)
        if depth <= 0 || attempt.firstAmbiguous == nil {
            return (ringKeys, attempt.used, score)
        }
        guard let ambiguous = attempt.firstAmbiguous else {
            return (ringKeys, attempt.used, score)
        }
        var best = (ringKeys, attempt.used, score)
        let candidates = branchCandidates(from: ambiguous.candidates)
        for candidate in candidates {
            var nextForced = forcedChoices
            nextForced[ChoiceKey(curr: ambiguous.from, prev: ambiguous.prev)] = candidate
            let branch = explore(
                start: start,
                next: next,
                ringIndex: ringIndex,
                edgesIn: edgesIn,
                forcedChoices: nextForced,
                depth: depth - 1
            )
            if betterScore(branch.score, best.2) {
                best = branch
            }
        }
        return best
    }

    let maxStartEdges = 3
    while let _ = edges.sorted(by: edgeLess).first {
        let startEdges = Array(edges.sorted(by: edgeLess).prefix(maxStartEdges))
        var bestRing: ([SnapKey], Set<EdgeKey>, (intersections: Int, area: Double, tie: UInt64))? = nil
        for startEdge in startEdges {
            let start = startEdge.a
            let next = startEdge.b
            let candidate = explore(
                start: start,
                next: next,
                ringIndex: ringIndex,
                edgesIn: edges,
                forcedChoices: [:],
                depth: maxDepth
            )
            if let best = bestRing {
                if betterScore(candidate.score, best.2) {
                    bestRing = (candidate.ring, candidate.used, candidate.score)
                }
            } else {
                bestRing = (candidate.ring, candidate.used, candidate.score)
            }
        }
        if let bestRing {
            rings.append(bestRing.0)
            edges.subtract(bestRing.1)
        } else {
            break
        }
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

public struct SoupNeighborhoodEdge: Equatable, Sendable {
    public let toKey: SnapKey
    public let toPos: Vec2
    public let len: Double
    public let dir: Vec2
    public let source: EdgeSource
    public let segmentIndex: Int?

    public init(toKey: SnapKey, toPos: Vec2, len: Double, dir: Vec2, source: EdgeSource, segmentIndex: Int?) {
        self.toKey = toKey
        self.toPos = toPos
        self.len = len
        self.dir = dir
        self.source = source
        self.segmentIndex = segmentIndex
    }
}

public struct SoupNeighborhoodNode: Equatable, Sendable {
    public let key: SnapKey
    public let pos: Vec2
    public let degree: Int
    public let edges: [SoupNeighborhoodEdge]

    public init(key: SnapKey, pos: Vec2, degree: Int, edges: [SoupNeighborhoodEdge]) {
        self.key = key
        self.pos = pos
        self.degree = degree
        self.edges = edges
    }
}

public struct SoupKeyCollision: Equatable, Sendable {
    public let key: SnapKey
    public let positions: [Vec2]

    public init(key: SnapKey, positions: [Vec2]) {
        self.key = key
        self.positions = positions
    }
}

public struct SoupNeighborhoodReport: Equatable, Sendable {
    public let center: Vec2
    public let radius: Double
    public let nodes: [SoupNeighborhoodNode]
    public let collisions: [SoupKeyCollision]

    public init(center: Vec2, radius: Double, nodes: [SoupNeighborhoodNode], collisions: [SoupKeyCollision]) {
        self.center = center
        self.radius = radius
        self.nodes = nodes
        self.collisions = collisions
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
        let axisLen = frame.crossAxis.length
        let deltaDir = distLR > 1.0e-12 ? (delta * (1.0 / distLR)) : Vec2(0.0, 0.0)
        let expectedDir = axisLen > 1.0e-12 ? (frame.crossAxis * (-1.0 / axisLen)) : Vec2(0.0, 0.0)
        let alignment = 1.0 - abs(deltaDir.dot(expectedDir))
        let normalLen = frame.normal.length
        return RailInvariantCheck(
            index: frame.index,
            distLR: distLR,
            expectedWidth: expectedWidth,
            widthErr: widthErr,
            alignment: alignment,
            normalLen: normalLen
        )
    }
    return RailFrameDiagnostics(frames: frames, checks: checks)
}

public func decomposeDelta(
    left: Vec2,
    right: Vec2,
    tangent: Vec2,
    normal: Vec2,
    expectedWidth: Double
) -> RailDeltaDecomp {
    let delta = right - left
    let dotT = delta.dot(tangent)
    let dotN = delta.dot(normal)
    let len = delta.length
    let widthErr = len - expectedWidth
    return RailDeltaDecomp(delta: delta, dotT: dotT, dotN: dotN, len: len, widthErr: widthErr)
}

public func computeRailCornerDebug(
    index: Int,
    center: Vec2,
    tangent: Vec2,
    normal: Vec2,
    widthLeft: Double,
    widthRight: Double,
    height: Double,
    effectiveAngle: Double,
    computeCorners: (Vec2, Vec2, Vec2, Double, Double, Double) -> [Vec2],
    left: Vec2,
    right: Vec2
) -> RailCornerDebug {
    let u = tangent
    let v = normal
    let c = cos(effectiveAngle)
    let s = sin(effectiveAngle)
    let uRot = u * c - v * s
    let vRot = u * s + v * c
    let widthTotal = widthLeft + widthRight
    let corners = computeCorners(center, u, v, widthTotal, height, effectiveAngle)
    return RailCornerDebug(
        index: index,
        center: center,
        tangent: tangent,
        normal: normal,
        u: u,
        v: v,
        uRot: uRot,
        vRot: vRot,
        effectiveAngle: effectiveAngle,
        widthLeft: widthLeft,
        widthRight: widthRight,
        widthTotal: widthTotal,
        corners: corners,
        left: left,
        right: right
    )
}

public func railSampleFrameAtGlobalT(
    param: SkeletonPathParameterization,
    warpGT: @escaping (Double) -> Double,
    styleAtGT: @escaping (Double) -> SweepStyle,
    gt: Double,
    index: Int
) -> RailSampleFrame {
    return computeRailSampleFrame(
        param: param,
        warpGT: warpGT,
        styleAtGT: styleAtGT,
        gt: gt,
        index: index
    ).frame
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

public func computeSoupNeighborhood(
    segments: [Segment2],
    eps: Double,
    center: Vec2,
    radius: Double
) -> SoupNeighborhoodReport {
    var pointForKey: [SnapKey: Vec2] = [:]
    var adjacency: [SnapKey: [SnapKey]] = [:]
    var edgeSources: [EdgeKey: EdgeSource] = [:]
    var keyPositions: [SnapKey: [Vec2]] = [:]

    func addPosition(_ key: SnapKey, _ pos: Vec2) {
        var list = keyPositions[key] ?? []
        let exists = list.contains(where: { Epsilon.approxEqual($0, pos, eps: Epsilon.defaultValue) })
        if !exists {
            list.append(pos)
        }
        keyPositions[key] = list
    }

    for seg in segments {
        let aKey = Epsilon.snapKey(seg.a, eps: eps)
        let bKey = Epsilon.snapKey(seg.b, eps: eps)
        pointForKey[aKey] = pointForKey[aKey] ?? seg.a
        pointForKey[bKey] = pointForKey[bKey] ?? seg.b
        addPosition(aKey, seg.a)
        addPosition(bKey, seg.b)
        adjacency[aKey, default: []].append(bKey)
        adjacency[bKey, default: []].append(aKey)
        let edge = EdgeKey(aKey, bKey)
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

    let collisions = keyPositions.compactMap { key, positions -> SoupKeyCollision? in
        guard positions.count > 1 else { return nil }
        return SoupKeyCollision(key: key, positions: positions)
    }.sorted { snapKeyLess($0.key, $1.key) }

    var nodes: [SoupNeighborhoodNode] = []
    for (key, pos) in pointForKey {
        if (pos - center).length > radius { continue }
        let neighbors = adjacency[key] ?? []
        let degree = neighbors.count
        let edges = neighbors.sorted(by: snapKeyLess).map { neighbor -> SoupNeighborhoodEdge in
            let toPos = pointForKey[neighbor] ?? Vec2(0, 0)
            let delta = toPos - pos
            let len = delta.length
            let dir = len > Epsilon.defaultValue ? delta * (1.0 / len) : Vec2(0, 0)
            let source = edgeSources[EdgeKey(key, neighbor)] ?? .unknown("missing")
            return SoupNeighborhoodEdge(
                toKey: neighbor,
                toPos: toPos,
                len: len,
                dir: dir,
                source: source,
                segmentIndex: nil
            )
        }
        nodes.append(SoupNeighborhoodNode(key: key, pos: pos, degree: degree, edges: edges))
    }
    nodes.sort { snapKeyLess($0.key, $1.key) }

    return SoupNeighborhoodReport(
        center: center,
        radius: radius,
        nodes: nodes,
        collisions: collisions
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

public func soupConnectivity(
    segments: [Segment2],
    eps: Double,
    from: Vec2,
    targets: [Vec2]
) -> Bool {
    guard !segments.isEmpty, !targets.isEmpty else { return false }
    let graph = buildSoupGraph(segments: segments, eps: eps)
    let fromKey = Epsilon.snapKey(from, eps: eps)
    let targetKeys = Set(targets.map { Epsilon.snapKey($0, eps: eps) })
    if targetKeys.contains(fromKey) { return true }
    var queue: [SnapKey] = [fromKey]
    var visited: Set<SnapKey> = [fromKey]
    while let current = queue.first {
        queue.removeFirst()
        let neighbors = graph.adjacency[current] ?? []
        for neighbor in neighbors {
            if visited.contains(neighbor) { continue }
            if targetKeys.contains(neighbor) { return true }
            visited.insert(neighbor)
            queue.append(neighbor)
        }
    }
    return false
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
