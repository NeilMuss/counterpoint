import Foundation
import Domain

public struct DirectSilhouetteResult: Equatable {
    public let outline: Ring
    public let outlineSelfIntersects: Bool
    public let leftRail: [Point]
    public let rightRail: [Point]
    public let leftRailSamples: [DirectSilhouetteTracer.RailSample]
    public let rightRailSamples: [DirectSilhouetteTracer.RailSample]
    public let leftRailSamplesPreRefine: [DirectSilhouetteTracer.RailSample]
    public let rightRailSamplesPreRefine: [DirectSilhouetteTracer.RailSample]
    public let leftRailRuns: [[Point]]
    public let rightRailRuns: [[Point]]
    public let endCap: [Point]
    public let startCap: [Point]
    public let junctionPatches: [Ring]
    public let junctionControlPoints: [Point]
    public let junctionDiagnostics: [DirectSilhouetteTracer.JunctionDiagnostic]
    public let junctionCorridors: [Ring]
    public let capPoints: [Point]
    public let railJoinSeams: [DirectSilhouetteTracer.RailJoinSeam]
    public let railConnectors: [DirectSilhouetteTracer.RailConnector]
    public let railRingMeta: [DirectSilhouetteTracer.RailPointMeta]
    public let railChain: RailChain?
}

public struct DirectSilhouetteOptions: Equatable {
    public var enableCornerRefine: Bool
    public var cornerRefineMaxDepth: Int
    public var cornerRefineMinStep: Double
    public var cornerRefineEpsilon: Double
    public var enableRailRefine: Bool
    public var railRefineMaxDepth: Int
    public var railRefineMinStep: Double

    public init(
        enableCornerRefine: Bool = true,
        cornerRefineMaxDepth: Int = 8,
        cornerRefineMinStep: Double = 1.0e-4,
        cornerRefineEpsilon: Double = 1.0e-9,
        enableRailRefine: Bool = true,
        railRefineMaxDepth: Int = 8,
        railRefineMinStep: Double = 1.0e-4
    ) {
        self.enableCornerRefine = enableCornerRefine
        self.cornerRefineMaxDepth = cornerRefineMaxDepth
        self.cornerRefineMinStep = cornerRefineMinStep
        self.cornerRefineEpsilon = cornerRefineEpsilon
        self.enableRailRefine = enableRailRefine
        self.railRefineMaxDepth = railRefineMaxDepth
        self.railRefineMinStep = railRefineMinStep
    }

    public static let `default` = DirectSilhouetteOptions()
}

public struct DirectSilhouetteTraceWindow: Equatable {
    public let tMin: Double
    public let tMax: Double
    public let label: String?

    public init(tMin: Double, tMax: Double, label: String? = nil) {
        self.tMin = min(tMin, tMax)
        self.tMax = max(tMin, tMax)
        self.label = label
    }

    public func contains(_ t: Double) -> Bool {
        t >= tMin && t <= tMax
    }

    public func intersects(_ a: Double, _ b: Double) -> Bool {
        max(min(a, b), tMin) <= min(max(a, b), tMax)
    }
}

public enum DirectSilhouetteTracer {
    public enum RailJumpSource: String {
        case raw
        case selected
    }
    public struct RailRefinementSummary: Equatable {
        public let insertedTotal: Int
        public let insertedChordOnly: Int
        public let insertedLengthOnly: Int
        public let insertedBoth: Int
        public let insertedTurnOnly: Int
        public let maxDepthHits: Int
        public let minStepHits: Int
        public let jumpSeamsSkipped: Int
    }
    public struct RailSample: Equatable {
        public let t: Double
        public let point: Point
        public let normal: Point
        public let debugSkeletonIndex: Int?
        public let debugSkeletonId: String?
        public let debugSegmentIndex: Int?
        public let debugSegmentKind: String?
        public let debugSegmentU: Double?
        public let debugRunId: Int?
        public let debugSupportCase: String?
        public let debugSupportLocal: Point?

        public init(
            t: Double,
            point: Point,
            normal: Point,
            debugSkeletonIndex: Int? = nil,
            debugSkeletonId: String? = nil,
            debugSegmentIndex: Int? = nil,
            debugSegmentKind: String? = nil,
            debugSegmentU: Double? = nil,
            debugRunId: Int? = nil,
            debugSupportCase: String? = nil,
            debugSupportLocal: Point? = nil
        ) {
            self.t = t
            self.point = point
            self.normal = normal
            self.debugSkeletonIndex = debugSkeletonIndex
            self.debugSkeletonId = debugSkeletonId
            self.debugSegmentIndex = debugSegmentIndex
            self.debugSegmentKind = debugSegmentKind
            self.debugSegmentU = debugSegmentU
            self.debugRunId = debugRunId
            self.debugSupportCase = debugSupportCase
            self.debugSupportLocal = debugSupportLocal
        }
    }

    public struct RailJoinSeam: Equatable {
        public let ringIndex: Int
        public let side: String
        public let dotForward: Double
        public let dotReversed: Double
        public let chosen: String

        public init(ringIndex: Int, side: String, dotForward: Double, dotReversed: Double, chosen: String) {
            self.ringIndex = ringIndex
            self.side = side
            self.dotForward = dotForward
            self.dotReversed = dotReversed
            self.chosen = chosen
        }
    }
    public struct RailConnector: Equatable {
        public let side: String
        public let railIndexStart: Int
        public let points: [Point]
        public let length: Double
        public let tStart: Double
        public let tEnd: Double

        public init(side: String, railIndexStart: Int, points: [Point], length: Double, tStart: Double, tEnd: Double) {
            self.side = side
            self.railIndexStart = railIndexStart
            self.points = points
            self.length = length
            self.tStart = tStart
            self.tEnd = tEnd
        }
    }
    public struct RailPointMeta: Equatable {
        public let side: String
        public let t: Double
        public let isConnector: Bool
        public let runId: Int?

        public init(side: String, t: Double, isConnector: Bool, runId: Int?) {
            self.side = side
            self.t = t
            self.isConnector = isConnector
            self.runId = runId
        }
    }

    public static func railRefinementSummaryForTest(
        samples: [Sample],
        tolerance: Double,
        maxSegmentLength: Double,
        maxTurnAngleDegrees: Double,
        maxDepth: Int,
        minParamStep: Double,
        sampleProvider: DirectSilhouetteSampleProvider
    ) -> RailRefinementSummary {
        let counts = RefinementCounts()
        _ = refineRailSamplesByChordError(
            samples: samples,
            tolerance: tolerance,
            maxSegmentLength: maxSegmentLength,
            maxTurnAngleDegrees: maxTurnAngleDegrees,
            maxDepth: maxDepth,
            minParamStep: minParamStep,
            sampleProvider: sampleProvider,
            refinementCounts: counts
        )
        let insertedTotal = counts.insertedChordOnly + counts.insertedLengthOnly + counts.insertedBoth
        return RailRefinementSummary(
            insertedTotal: insertedTotal,
            insertedChordOnly: counts.insertedChordOnly,
            insertedLengthOnly: counts.insertedLengthOnly,
            insertedBoth: counts.insertedBoth,
            insertedTurnOnly: counts.insertedTurnOnly,
            maxDepthHits: counts.maxDepthHits,
            minStepHits: counts.minStepHits,
            jumpSeamsSkipped: counts.jumpSeamsSkipped
        )
    }

    public static func maxRailSegmentLengthForTest(samples: [RailSample]) -> (length: Double, interval: (Double, Double)?) {
        maxRemainingRailSegmentLength(samples: samples)
    }

    public static func maxRailTurnAngleDegreesForTest(
        samples: [RailSample],
        sampleProvider: DirectSilhouetteSampleProvider
    ) -> (degrees: Double, interval: (Double, Double)?) {
        maxRemainingRailTurnDegrees(samples: samples, sampleProvider: sampleProvider)
    }

    public static func ringMaxTurnDegrees(
        ring: Ring,
        start: Int = 0,
        count: Int? = nil
    ) -> (degrees: Double, index: Int?) {
        maxRingTurnDegrees(ring: ring, start: start, count: count)
    }

    public typealias DirectSilhouetteParamProvider = (_ t: Double, _ tangentAngle: Double) -> (width: Double, widthLeft: Double, widthRight: Double, height: Double, theta: Double, effectiveRotation: Double, alpha: Double)
    public typealias DirectSilhouetteSampleProvider = (_ t: Double) -> Sample?
    public struct JunctionContext: Equatable {
        public let joinIndex: Int
        public let prev: Sample?
        public let a: Sample
        public let b: Sample
        public let next: Sample?

        public init(joinIndex: Int, prev: Sample?, a: Sample, b: Sample, next: Sample?) {
            self.joinIndex = joinIndex
            self.prev = prev
            self.a = a
            self.b = b
            self.next = next
        }
    }

    public struct JunctionDiagnostic: Equatable {
        public let joinIndex: Int
        public let tA: Double
        public let tB: Double
        public let usedBridge: Bool
        public let reason: String
        public let clipped: Bool
        public let clipReason: String
    }

    public static func trace(
        samples: [Sample],
        junctions: [JunctionContext] = [],
        capStyle: CapStylePair = CapStylePair(.butt),
        railTolerance: Double = 0.0,
        railChordTolerance: Double = 0.0,
        railMaxSegmentLength: Double = 0.0,
        railMaxTurnAngleDegrees: Double = 0.0,
        railSplitThreshold: Double = 20.0,
        railJumpsSource: RailJumpSource = .selected,
        options: DirectSilhouetteOptions = .default,
        paramsProvider: DirectSilhouetteParamProvider? = nil,
        sampleProvider: DirectSilhouetteSampleProvider? = nil,
        traceWindow: DirectSilhouetteTraceWindow? = nil,
        verbose: Bool = false,
        railsDebug: Bool = false,
        railsDebugStart: Int? = nil,
        epsilon: Double = 1.0e-9
    ) -> DirectSilhouetteResult {
        guard samples.count >= 2 else {
            return DirectSilhouetteResult(outline: [], outlineSelfIntersects: false, leftRail: [], rightRail: [], leftRailSamples: [], rightRailSamples: [], leftRailSamplesPreRefine: [], rightRailSamplesPreRefine: [], leftRailRuns: [], rightRailRuns: [], endCap: [], startCap: [], junctionPatches: [], junctionControlPoints: [], junctionDiagnostics: [], junctionCorridors: [], capPoints: [], railJoinSeams: [], railConnectors: [], railRingMeta: [], railChain: nil)
        }

        if let window = traceWindow {
            print("direct-trace window t=[\(format(window.tMin))..\((format(window.tMax)))] label=\(window.label ?? "none") samples=\(samples.count)")
        }

        let refinedSamples = refineSamples(
            samples: samples,
            options: options,
            railTolerance: railTolerance,
            paramsProvider: paramsProvider,
            sampleProvider: sampleProvider,
            traceWindow: traceWindow,
            epsilon: epsilon
        )

        let preRefineRails = buildRailSamplesForDebug(samples: refinedSamples, epsilon: epsilon)
        var railRefinementCounts: RefinementCounts? = nil
        let railMinStep = 0.0
        let splitThreshold = max(0.0, railSplitThreshold)
        let runs = splitRailRuns(samples: refinedSamples, threshold: splitThreshold, epsilon: epsilon)
        var refinedRuns: [[Sample]] = []
        refinedRuns.reserveCapacity(runs.count)
        if (railChordTolerance > 0.0 || railMaxSegmentLength > 0.0 || railMaxTurnAngleDegrees > 0.0), let sampleProvider {
            let refinementCounts = railsDebug ? RefinementCounts() : nil
            for run in runs {
                let refined = refineRailSamplesByChordError(
                    samples: run,
                    tolerance: railChordTolerance,
                    maxSegmentLength: railMaxSegmentLength,
                    maxTurnAngleDegrees: railMaxTurnAngleDegrees,
                    maxDepth: options.railRefineMaxDepth,
                    minParamStep: railMinStep,
                    sampleProvider: sampleProvider,
                    refinementCounts: refinementCounts
                )
                refinedRuns.append(refined)
            }
            railRefinementCounts = refinementCounts
        } else {
            refinedRuns = runs
        }
        let runRails = refinedRuns.map { railPointsForSamples($0, epsilon: epsilon) }
        let dominantRunIndex = selectDominantRunIndex(runs: refinedRuns, runRails: runRails, traceWindow: traceWindow)
        if railsDebug {
            let leftCounts = runRails.map { $0.left.count }
            let rightCounts = runRails.map { $0.right.count }
            let leftMaxSeg = runRails.map { maxSegmentLength(points: $0.left) }
            let rightMaxSeg = runRails.map { maxSegmentLength(points: $0.right) }
            print("railsRuns L runs=\(leftCounts.count) counts=\(leftCounts) maxSeg=\(leftMaxSeg) R runs=\(rightCounts.count) counts=\(rightCounts) maxSeg=\(rightMaxSeg)")
        }
        let selectedIndex = min(dominantRunIndex, max(0, refinedRuns.count - 1))
        let selectedBaseSamples = refinedRuns.isEmpty ? refinedSamples : refinedRuns[selectedIndex]

        let allBaseSamples: [Sample] = refinedRuns.isEmpty
            ? refinedSamples
            : refinedRuns.flatMap { $0 }

        func unwrapAngle(_ raw: Double, prev: Double?) -> Double {
            guard let prev else { return raw }
            let twoPi = 2.0 * Double.pi
            let candidates = [raw - twoPi, raw, raw + twoPi]
            var best = candidates[0]
            var bestDelta = abs(candidates[0] - prev)
            for candidate in candidates.dropFirst() {
                let delta = abs(candidate - prev)
                if delta < bestDelta {
                    bestDelta = delta
                    best = candidate
                }
            }
            return best
        }

        func unwrapSamples(_ base: [Sample]) -> [Sample] {
            var result: [Sample] = []
            result.reserveCapacity(base.count)
            var prevThetaUsed: Double? = nil
            for sample in base {
                let unwrapped = unwrapAngle(sample.effectiveRotation, prev: prevThetaUsed)
                prevThetaUsed = unwrapped
                var updated = sample
                updated.effectiveRotation = unwrapped
                result.append(updated)
            }
            return result
        }

        let railSamplesSelected = unwrapSamples(selectedBaseSamples)
        let railSamplesAll = unwrapSamples(allBaseSamples)

        var leftRail: [Point] = []
        var rightRail: [Point] = []
        var leftRailMeta: [RailPointMeta] = []
        var rightRailMeta: [RailPointMeta] = []
        var leftRailAllSamples: [RailSample] = []
        var rightRailAllSamples: [RailSample] = []
        var leftRailSamplesSelected: [RailSample] = []
        var rightRailSamplesSelected: [RailSample] = []
        var windowLeft: [Point] = []
        var windowRight: [Point] = []
        leftRail.reserveCapacity(railSamplesAll.count)
        rightRail.reserveCapacity(railSamplesAll.count)
        leftRailMeta.reserveCapacity(railSamplesAll.count)
        rightRailMeta.reserveCapacity(railSamplesAll.count)
        leftRailAllSamples.reserveCapacity(railSamplesAll.count)
        rightRailAllSamples.reserveCapacity(railSamplesAll.count)
        leftRailSamplesSelected.reserveCapacity(railSamplesSelected.count)
        rightRailSamplesSelected.reserveCapacity(railSamplesSelected.count)

        func appendConnectorIfNeeded(_ previous: Point?, next: Point, into points: inout [Point]) {
            guard let previous else { return }
            if (next - previous).length > epsilon {
                let mid = Point(x: 0.5 * (previous.x + next.x), y: 0.5 * (previous.y + next.y))
                points.append(mid)
            }
        }

        func railPoint(for sample: Sample, normal: Point, leftDistance: Double, rightDistance: Double) -> (Point, Point) {
            let leftPoint = sample.point + normal * leftDistance
            let rightPoint = sample.point - normal * rightDistance
            return (leftPoint, rightPoint)
        }

        struct RunInfo {
            let id: Int
            let samples: [Sample]
            let center: [Point]
            let left: [Point]
            let right: [Point]
            let startPoint: Point
            let endPoint: Point
            let startTangent: Point
            let endTangent: Point
        }

        func computeTangent(_ points: [Point], atStart: Bool) -> Point? {
            guard points.count >= 2 else { return nil }
            if atStart {
                return (points[1] - points[0]).normalized()
            }
            return (points[points.count - 1] - points[points.count - 2]).normalized()
        }

        let runInfos: [RunInfo] = refinedRuns.enumerated().compactMap { index, run in
            guard run.count >= 2 else { return nil }
            let center = run.map { $0.point }
            let rails = railPointsForSamples(run, epsilon: epsilon)
            guard let startTan = computeTangent(center, atStart: true),
                  let endTan = computeTangent(center, atStart: false) else {
                return nil
            }
            return RunInfo(
                id: index,
                samples: run,
                center: center,
                left: rails.left,
                right: rails.right,
                startPoint: center.first ?? Point(x: 0.0, y: 0.0),
                endPoint: center.last ?? Point(x: 0.0, y: 0.0),
                startTangent: startTan,
                endTangent: endTan
            )
        }

        let stitchMaxDistance = max(20.0, railSplitThreshold)

        func runDots(prevTangent: Point, run: RunInfo) -> (dotF: Double, dotR: Double) {
            let dotF = max(-1.0, min(1.0, prevTangent.dot(run.startTangent)))
            let incomingR = Point(x: -run.endTangent.x, y: -run.endTangent.y)
            let dotR = max(-1.0, min(1.0, prevTangent.dot(incomingR)))
            return (dotF, dotR)
        }

        struct RailJoinInfo {
            let side: String
            let railIndex: Int
            let dotForward: Double
            let dotReversed: Double
            let chosen: String
            let point: Point
        }
        var joinInfos: [RailJoinInfo] = []
        var connectors: [RailConnector] = []

        func buildConnectorPoints(from a: Point, to b: Point, maxLen: Double) -> [Point] {
            let distance = (b - a).length
            guard distance > maxLen, maxLen > 0.0 else { return [a, b] }
            let steps = Int(ceil(distance / maxLen))
            guard steps >= 2 else { return [a, b] }
            var points: [Point] = []
            points.reserveCapacity(steps + 1)
            for i in 0...steps {
                let t = Double(i) / Double(steps)
                points.append(Point(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
            }
            return points
        }

        func buildConnectorMeta(from tStart: Double, to tEnd: Double, count: Int, side: String, runId: Int?) -> [RailPointMeta] {
            guard count > 0 else { return [] }
            if count == 1 {
                return [RailPointMeta(side: side, t: tStart, isConnector: true, runId: runId)]
            }
            var metas: [RailPointMeta] = []
            metas.reserveCapacity(count)
            for i in 0..<count {
                let u = Double(i) / Double(count - 1)
                let t = tStart + (tEnd - tStart) * u
                metas.append(RailPointMeta(side: side, t: t, isConnector: true, runId: runId))
            }
            return metas
        }

        var prevNormalLeft: Point? = nil
        var prevNormalRight: Point? = nil
        var normalFlipCount = 0
        var normalFlipFirstIndex: Int? = nil
        var lastLeftPoint: Point? = nil
        var lastRightPoint: Point? = nil
        var firstSampleUsed: Sample? = nil
        var lastSampleUsed: Sample? = nil
        var centerline: [Point] = []
        var orderedRuns: [(run: RunInfo, reversed: Bool, dotF: Double, dotR: Double)] = []
        orderedRuns.reserveCapacity(runInfos.count)
        var prevTangent: Point? = nil
        var prevEndPoint: Point? = nil
        for run in runInfos {
            var reversed = false
            var dotF = 1.0
            var dotR = -1.0
            if let prevTangent {
                let dots = runDots(prevTangent: prevTangent, run: run)
                dotF = dots.dotF
                dotR = dots.dotR
                reversed = dotR > dotF
            }
            let startPoint = reversed ? run.endPoint : run.startPoint
            let endPoint = reversed ? run.startPoint : run.endPoint
            _ = prevEndPoint.map { (startPoint - $0).length }
            orderedRuns.append((run: run, reversed: reversed, dotF: dotF, dotR: dotR))
            prevEndPoint = endPoint
            prevTangent = reversed ? Point(x: -run.startTangent.x, y: -run.startTangent.y) : run.endTangent
        }

        func arcLength(_ points: [Point]) -> Double {
            guard points.count > 1 else { return 0.0 }
            var total = 0.0
            for i in 1..<points.count {
                total += (points[i] - points[i - 1]).length
            }
            return total
        }

        func localTValue(index: Int, count: Int) -> Double {
            guard count > 1 else { return 0.0 }
            return Double(index) / Double(count - 1)
        }

        let orderedCenters: [[Point]] = orderedRuns.map { entry in
            entry.reversed ? Array(entry.run.center.reversed()) : entry.run.center
        }
        let runLengths = orderedCenters.map { arcLength($0) }
        let totalRunLength = max(runLengths.reduce(0.0, +), epsilon)
        var railRuns: [RailRun] = []
        var railRunRanges: [RailRunRange] = []
        railRuns.reserveCapacity(orderedRuns.count)
        railRunRanges.reserveCapacity(orderedRuns.count)
        var chainLeft: [RailChainPoint] = []
        var chainRight: [RailChainPoint] = []
        var runOffset = 0.0
        for (index, entry) in orderedRuns.enumerated() {
            let run = entry.run
            let reversed = entry.reversed
            let orderedSamples = reversed ? Array(run.samples.reversed()) : run.samples
            let rails = railPointsForSamples(orderedSamples, epsilon: epsilon)
            let runLength = runLengths[index]
            let gtStart = runOffset / totalRunLength
            let gtEnd = (runOffset + runLength) / totalRunLength
            railRunRanges.append(RailRunRange(id: run.id, gtStart: gtStart, gtEnd: gtEnd))
            var leftPoints: [RailChainPoint] = []
            var rightPoints: [RailChainPoint] = []
            leftPoints.reserveCapacity(rails.left.count)
            rightPoints.reserveCapacity(rails.right.count)
            for i in 0..<rails.left.count {
                let localT = localTValue(index: i, count: rails.left.count)
                let globalT = (runOffset + localT * runLength) / totalRunLength
                leftPoints.append(RailChainPoint(point: rails.left[i], localT: localT, globalT: globalT))
            }
            for i in 0..<rails.right.count {
                let localT = localTValue(index: i, count: rails.right.count)
                let globalT = (runOffset + localT * runLength) / totalRunLength
                rightPoints.append(RailChainPoint(point: rails.right[i], localT: localT, globalT: globalT))
            }
            chainLeft.append(contentsOf: leftPoints)
            chainRight.append(contentsOf: rightPoints)
            railRuns.append(RailRun(id: run.id, left: leftPoints, right: rightPoints))
            runOffset += runLength
        }
        let railChain = RailChain(runs: railRuns, left: chainLeft, right: chainRight, ranges: railRunRanges)
        if railsDebug, !railChain.runs.isEmpty {
            print("railChain runs=\(railChain.runs.count)")
            for (index, run) in railChain.runs.enumerated() {
                let range = railChain.ranges[index]
                print("railChain run id=\(run.id) countL=\(run.left.count) countR=\(run.right.count) gt=[\(format(range.gtStart))..\(format(range.gtEnd))]")
            }
        }

        func appendRailSamples(_ samples: [Sample], runId: Int, prevNormal: inout Point?, prevPoint: inout Point?, points: inout [Point], railSamples: inout [RailSample], isLeft: Bool) {
            for sample in samples {
                let tangent = Point(x: cos(sample.tangentAngle), y: sin(sample.tangentAngle))
                var normal = tangent.leftNormal()
                if let prev = prevNormal, normal.dot(prev) < 0.0 {
                    normal = normal * -1.0
                    if normalFlipFirstIndex == nil { normalFlipFirstIndex = points.count }
                    normalFlipCount += 1
                }
                prevNormal = normal
                let railEpsilon = 1.0e-3
                let leftDistance = railSupportDistance(
                    direction: normal,
                    widthLeft: sample.widthLeft,
                    widthRight: sample.widthRight,
                    height: sample.height,
                    thetaWorld: sample.effectiveRotation,
                    railEpsilon: railEpsilon
                )
                let rightDistance = railSupportDistance(
                    direction: normal * -1.0,
                    widthLeft: sample.widthLeft,
                    widthRight: sample.widthRight,
                    height: sample.height,
                    thetaWorld: sample.effectiveRotation,
                    railEpsilon: railEpsilon
                )
                let (leftPoint, rightPoint) = railPoint(for: sample, normal: normal, leftDistance: leftDistance, rightDistance: rightDistance)
                let point = isLeft ? leftPoint : rightPoint
                points.append(point)
                railSamples.append(RailSample(
                    t: sample.t,
                    point: point,
                    normal: isLeft ? normal : normal * -1.0,
                    debugSkeletonIndex: sample.debugSkeletonIndex,
                    debugSkeletonId: sample.debugSkeletonId,
                    debugSegmentIndex: sample.debugSegmentIndex,
                    debugSegmentKind: sample.debugSegmentKind,
                    debugSegmentU: sample.debugSegmentU,
                    debugRunId: runId,
                    debugSupportCase: isLeft ? "L" : "R",
                    debugSupportLocal: nil
                ))
                if isLeft {
                    if firstSampleUsed == nil { firstSampleUsed = sample }
                    lastSampleUsed = sample
                }
                prevPoint = point
            }
        }

        let connectorMaxLen = railMaxSegmentLength > 0.0 ? railMaxSegmentLength : 1.0
        var previousRunId: Int? = nil
        for entry in orderedRuns {
            let run = entry.run
            let reversed = entry.reversed
            let orderedSamples = reversed ? Array(run.samples.reversed()) : run.samples
            let orderedLeft = reversed ? Array(run.left.reversed()) : run.left
            let orderedRight = reversed ? Array(run.right.reversed()) : run.right
            let leftFirstPoint = orderedLeft.first
            let rightFirstPoint = orderedRight.first
            if let leftFirstPoint, let lastLeftPoint, let rightFirstPoint, let lastRightPoint {
                let leftDist = (leftFirstPoint - lastLeftPoint).length
                let rightDist = (rightFirstPoint - lastRightPoint).length
                if max(leftDist, rightDist) > stitchMaxDistance, railsDebug {
                    print("railsStitchBreak side=LR prevRun=\(previousRunId ?? -1) noCandidateWithin=\(format(stitchMaxDistance))")
                    print("railsStitchBreak starting new RailRun id=\(run.id)")
                }
            }
            if let leftFirstPoint, let lastLeftPoint {
                let connector = buildConnectorPoints(from: lastLeftPoint, to: leftFirstPoint, maxLen: connectorMaxLen)
                if connector.count > 2 {
                    let startIndex = leftRail.count
                    leftRail.append(contentsOf: connector.dropFirst().dropLast())
                    let length = (leftFirstPoint - lastLeftPoint).length
                    let tStart = lastSampleUsed?.t ?? 0.0
                    let tEnd = orderedSamples.first?.t ?? tStart
                    connectors.append(RailConnector(side: "L", railIndexStart: startIndex, points: connector, length: length, tStart: tStart, tEnd: tEnd))
                }
                joinInfos.append(RailJoinInfo(
                    side: "L",
                    railIndex: leftRail.count,
                    dotForward: entry.dotF,
                    dotReversed: entry.dotR,
                    chosen: reversed ? "reversed" : "forward",
                    point: leftFirstPoint
                ))
            }
            if let rightFirstPoint, let lastRightPoint {
                let connector = buildConnectorPoints(from: lastRightPoint, to: rightFirstPoint, maxLen: connectorMaxLen)
                if connector.count > 2 {
                    let startIndex = rightRail.count
                    rightRail.append(contentsOf: connector.dropFirst().dropLast())
                    let length = (rightFirstPoint - lastRightPoint).length
                    let tStart = lastSampleUsed?.t ?? 0.0
                    let tEnd = orderedSamples.first?.t ?? tStart
                    connectors.append(RailConnector(side: "R", railIndexStart: startIndex, points: connector, length: length, tStart: tStart, tEnd: tEnd))
                }
                joinInfos.append(RailJoinInfo(
                    side: "R",
                    railIndex: rightRail.count,
                    dotForward: entry.dotF,
                    dotReversed: entry.dotR,
                    chosen: reversed ? "reversed" : "forward",
                    point: rightFirstPoint
                ))
            }
            appendRailSamples(orderedSamples, runId: run.id, prevNormal: &prevNormalLeft, prevPoint: &lastLeftPoint, points: &leftRail, railSamples: &leftRailAllSamples, isLeft: true)
            appendRailSamples(orderedSamples, runId: run.id, prevNormal: &prevNormalRight, prevPoint: &lastRightPoint, points: &rightRail, railSamples: &rightRailAllSamples, isLeft: false)
            let orderedCenter = reversed ? Array(run.center.reversed()) : run.center
            centerline.append(contentsOf: orderedCenter)
            previousRunId = run.id
        }

        var prevNormalSelected: Point? = nil
        for (index, sample) in railSamplesSelected.enumerated() {
            let updated = sample
            let tangent = Point(x: cos(updated.tangentAngle), y: sin(updated.tangentAngle))
            var normal = tangent.leftNormal()
            if let prev = prevNormalSelected, normal.dot(prev) < 0.0 {
                normal = normal * -1.0
            }
            prevNormalSelected = normal
            let railEpsilon = 1.0e-3
            let leftDistance = railSupportDistance(
                direction: normal,
                widthLeft: updated.widthLeft,
                widthRight: updated.widthRight,
                height: updated.height,
                thetaWorld: updated.effectiveRotation,
                railEpsilon: railEpsilon
            )
            let rightDistance = railSupportDistance(
                direction: normal * -1.0,
                widthLeft: updated.widthLeft,
                widthRight: updated.widthRight,
                height: updated.height,
                thetaWorld: updated.effectiveRotation,
                railEpsilon: railEpsilon
            )
            let leftPoint = updated.point + normal * leftDistance
            let rightPoint = updated.point - normal * rightDistance
            leftRailSamplesSelected.append(RailSample(
                t: updated.t,
                point: leftPoint,
                normal: normal,
                debugSkeletonIndex: updated.debugSkeletonIndex,
                debugSkeletonId: updated.debugSkeletonId,
                debugSegmentIndex: updated.debugSegmentIndex,
                debugSegmentKind: updated.debugSegmentKind,
                debugSegmentU: updated.debugSegmentU,
                debugRunId: nil,
                debugSupportCase: "L",
                debugSupportLocal: nil
            ))
            rightRailSamplesSelected.append(RailSample(
                t: updated.t,
                point: rightPoint,
                normal: normal * -1.0,
                debugSkeletonIndex: updated.debugSkeletonIndex,
                debugSkeletonId: updated.debugSkeletonId,
                debugSegmentIndex: updated.debugSegmentIndex,
                debugSegmentKind: updated.debugSegmentKind,
                debugSegmentU: updated.debugSegmentU,
                debugRunId: nil,
                debugSupportCase: "R",
                debugSupportLocal: nil
            ))
            if let window = traceWindow, window.contains(updated.t) {
                windowLeft.append(leftPoint)
                windowRight.append(rightPoint)
                print("direct-sample t=\(format(updated.t)) center=(\(format(updated.point.x)),\(format(updated.point.y))) width=\(format(updated.width)) height=\(format(updated.height)) theta=\(format(updated.theta)) effRot=\(format(updated.effectiveRotation))")
                print("direct-rail t=\(format(updated.t)) left=(\(format(leftPoint.x)),\(format(leftPoint.y))) right=(\(format(rightPoint.x)),\(format(rightPoint.y)))")
            }
            if let limit = railsDebugStart, index < limit {
                let rawTheta = updated.effectiveRotation
                let dotPrev = prevNormalSelected.map { normal.dot($0) } ?? 1.0
                let localN = railLocalDirection(direction: normal, thetaWorld: updated.effectiveRotation, railEpsilon: railEpsilon)
                print("rails-debug-start i=\(index) t=\(format(updated.t)) P=(\(format(updated.point.x)),\(format(updated.point.y))) T=(\(format(tangent.x)),\(format(tangent.y))) thetaRaw=\(format(rawTheta)) thetaUnwrapped=\(format(updated.effectiveRotation)) N=(\(format(normal.x)),\(format(normal.y))) dotPrev=\(format(dotPrev)) localN=(\(format(localN.x)),\(format(localN.y))) dL=\(format(leftDistance)) dR=\(format(rightDistance)) L=(\(format(leftPoint.x)),\(format(leftPoint.y))) R=(\(format(rightPoint.x)),\(format(rightPoint.y)))")
            }
        }

        if railsDebug {
            func skeletonKey(id: String?, index: Int?) -> String {
                if let id, !id.isEmpty { return id }
                if let index { return "index-\(index)" }
                return "nil"
            }
            func bbox(_ points: [Point]) -> (min: Point, max: Point)? {
                guard let first = points.first else { return nil }
                var minX = first.x
                var maxX = first.x
                var minY = first.y
                var maxY = first.y
                for point in points.dropFirst() {
                    minX = min(minX, point.x)
                    maxX = max(maxX, point.x)
                    minY = min(minY, point.y)
                    maxY = max(maxY, point.y)
                }
                return (Point(x: minX, y: minY), Point(x: maxX, y: maxY))
            }

            var centerByKey: [String: [Sample]] = [:]
            for sample in samples {
                let key = skeletonKey(id: sample.debugSkeletonId, index: sample.debugSkeletonIndex)
                centerByKey[key, default: []].append(sample)
            }
            var leftByKey: [String: [RailSample]] = [:]
            for sample in leftRailAllSamples {
                let key = skeletonKey(id: sample.debugSkeletonId, index: sample.debugSkeletonIndex)
                leftByKey[key, default: []].append(sample)
            }
            var rightByKey: [String: [RailSample]] = [:]
            for sample in rightRailAllSamples {
                let key = skeletonKey(id: sample.debugSkeletonId, index: sample.debugSkeletonIndex)
                rightByKey[key, default: []].append(sample)
            }

            let keys = Set(centerByKey.keys)
                .union(leftByKey.keys)
                .union(rightByKey.keys)
                .sorted()
            for key in keys {
                let center = centerByKey[key]?.count ?? 0
                let leftSamples = leftByKey[key] ?? []
                let rightSamples = rightByKey[key] ?? []
                let leftPoints = leftSamples.map { $0.point }
                let rightPoints = rightSamples.map { $0.point }
                let leftBBox = bbox(leftPoints)
                let rightBBox = bbox(rightPoints)
                let leftFirst = leftPoints.first
                let leftLast = leftPoints.last
                let rightFirst = rightPoints.first
                let rightLast = rightPoints.last
                let leftMaxX = leftBBox?.max.x
                let rightMaxX = rightBBox?.max.x
                let leftBBoxText = leftBBox.map { "(\(format($0.min.x)),\(format($0.min.y)))..(\(format($0.max.x)),\(format($0.max.y)))" } ?? "nil"
                let rightBBoxText = rightBBox.map { "(\(format($0.min.x)),\(format($0.min.y)))..(\(format($0.max.x)),\(format($0.max.y)))" } ?? "nil"
                let leftFirstText = leftFirst.map { "(\(format($0.x)),\(format($0.y)))" } ?? "nil"
                let leftLastText = leftLast.map { "(\(format($0.x)),\(format($0.y)))" } ?? "nil"
                let rightFirstText = rightFirst.map { "(\(format($0.x)),\(format($0.y)))" } ?? "nil"
                let rightLastText = rightLast.map { "(\(format($0.x)),\(format($0.y)))" } ?? "nil"
                let leftMaxXText = leftMaxX.map { format($0) } ?? "nil"
                let rightMaxXText = rightMaxX.map { format($0) } ?? "nil"
                print("railsInput skeleton=\(key) center=\(center) L=\(leftSamples.count) R=\(rightSamples.count) bboxL=\(leftBBoxText) bboxR=\(rightBBoxText) firstL=\(leftFirstText) lastL=\(leftLastText) firstR=\(rightFirstText) lastR=\(rightLastText)")
                print("railsInput skeleton=\(key) maxX_L=\(leftMaxXText) maxX_R=\(rightMaxXText)")
            }
        }

        if railsDebug {
            let sourceLabel = railJumpsSource == .raw ? "raw" : "selected"
            let leftSource = railJumpsSource == .raw ? preRefineRails.left : leftRailSamplesSelected
            let rightSource = railJumpsSource == .raw ? preRefineRails.right : rightRailSamplesSelected
            logRailJumps(label: "L \(sourceLabel)", samples: leftSource, maxItems: 5)
            logRailJumps(label: "R \(sourceLabel)", samples: rightSource, maxItems: 5)
        }

        if traceWindow != nil {
            print("direct-rail cleanup left pre=\(leftRail.count) right pre=\(rightRail.count)")
        }
        let leftDedup = removeConsecutiveDuplicates(leftRail, tol: epsilon)
        let rightDedup = removeConsecutiveDuplicates(rightRail, tol: epsilon)
        let leftAfter = removeTinyEdges(leftDedup, epsilon: epsilon)
        let rightAfter = removeTinyEdges(rightDedup, epsilon: epsilon)
        if traceWindow != nil {
            let leftDupRemoved = leftRail.count - leftDedup.count
            let rightDupRemoved = rightRail.count - rightDedup.count
            let leftTinyRemoved = leftDedup.count - leftAfter.count
            let rightTinyRemoved = rightDedup.count - rightAfter.count
            print("direct-rail postprocess removedDup left=\(leftDupRemoved) right=\(rightDupRemoved) removedTiny left=\(leftTinyRemoved) right=\(rightTinyRemoved)")
        }
        leftRail = leftAfter
        rightRail = rightAfter
        if railsDebug {
            let leftMax = maxSegmentLength(points: leftRail)
            let rightMax = maxSegmentLength(points: rightRail)
            let leftTurn = maxTurnDegrees(points: leftRail)
            let rightTurn = maxTurnDegrees(points: rightRail)
            let leftChord = maxChordDeviation(points: leftRail)
            let rightChord = maxChordDeviation(points: rightRail)
            let leftWorst = maxSegmentDetail(points: leftRail)
            let rightWorst = maxSegmentDetail(points: rightRail)
            print("railsFinal side=L pts=\(leftRail.count) maxSeg=\(format(leftMax)) maxChord=\(format(leftChord)) maxTurnDeg=\(format(leftTurn))")
            print("railsFinal side=R pts=\(rightRail.count) maxSeg=\(format(rightMax)) maxChord=\(format(rightChord)) maxTurnDeg=\(format(rightTurn))")
            if let leftWorst {
                print("railsFinalWorst side=L idx=\(leftWorst.index) len=\(format(leftWorst.length)) A=(\(format(leftWorst.a.x)),\(format(leftWorst.a.y))) B=(\(format(leftWorst.b.x)),\(format(leftWorst.b.y)))")
            }
            if let rightWorst {
                print("railsFinalWorst side=R idx=\(rightWorst.index) len=\(format(rightWorst.length)) A=(\(format(rightWorst.a.x)),\(format(rightWorst.a.y))) B=(\(format(rightWorst.b.x)),\(format(rightWorst.b.y)))")
            }
            if !connectors.isEmpty {
                let totalLen = connectors.reduce(0.0) { $0 + $1.length }
                let maxLen = connectors.map { $0.length }.max() ?? 0.0
                print("railsConnectors count=\(connectors.count) totalLen=\(format(totalLen)) maxLen=\(format(maxLen))")
            }
        }
        if railsDebug {
            print("railsGeom built L=\(leftRail.count) R=\(rightRail.count)")
            print("railsRefine usedSamples L=\(leftRailAllSamples.count) R=\(rightRailAllSamples.count)")
            if let counts = railRefinementCounts {
                let insertedTotal = counts.insertedChordOnly + counts.insertedLengthOnly + counts.insertedBoth
                let leftDiagSamples = cleanedRailSamples(leftRailAllSamples, epsilon: epsilon)
                let rightDiagSamples = cleanedRailSamples(rightRailAllSamples, epsilon: epsilon)
                let leftMax = maxRemainingRailSegmentLength(samples: leftDiagSamples)
                let rightMax = maxRemainingRailSegmentLength(samples: rightDiagSamples)
                let leftIntervalText = leftMax.interval == nil ? "none" : "\(formatT(leftMax.interval!.0))..\((formatT(leftMax.interval!.1)))"
                let rightIntervalText = rightMax.interval == nil ? "none" : "\(formatT(rightMax.interval!.0))..\((formatT(rightMax.interval!.1)))"
                print("railsRefine insertedTotal=\(insertedTotal) chordOnly=\(counts.insertedChordOnly) lengthOnly=\(counts.insertedLengthOnly) both=\(counts.insertedBoth) chordTol=\(railChordTolerance) maxLen=\(railMaxSegmentLength) maxTurnDeg=\(railMaxTurnAngleDegrees) maxDepth=\(options.railRefineMaxDepth) minStep=\(railMinStep)")
                print("railsRefine maxSegRemainingL=\(format(leftMax.length)) t=[\(leftIntervalText)] maxSegRemainingR=\(format(rightMax.length)) t=[\(rightIntervalText)] capHits maxDepth=\(counts.maxDepthHits) minStep=\(counts.minStepHits) jumpSeams=\(counts.jumpSeamsSkipped)")
                if counts.insertedTurnOnly > 0 {
                    print("railsRefine turnOnly=\(counts.insertedTurnOnly)")
                }
            }
            let leftDiagSamples = cleanedRailSamples(leftRailAllSamples, epsilon: epsilon)
            let rightDiagSamples = cleanedRailSamples(rightRailAllSamples, epsilon: epsilon)
            let leftDiag = maxRemainingRailDiagnostics(samples: leftDiagSamples, side: .left, sampleProvider: sampleProvider, traceWindow: traceWindow)
            let rightDiag = maxRemainingRailDiagnostics(samples: rightDiagSamples, side: .right, sampleProvider: sampleProvider, traceWindow: traceWindow)
            let leftChordInterval = leftDiag.maxChord.interval == nil ? "none" : "\(formatT(leftDiag.maxChord.interval!.0))..\((formatT(leftDiag.maxChord.interval!.1)))"
            let rightChordInterval = rightDiag.maxChord.interval == nil ? "none" : "\(formatT(rightDiag.maxChord.interval!.0))..\((formatT(rightDiag.maxChord.interval!.1)))"
            let leftTurnInterval = leftDiag.maxTurn.interval == nil ? "none" : "\(formatT(leftDiag.maxTurn.interval!.0))..\((formatT(leftDiag.maxTurn.interval!.1)))"
            let rightTurnInterval = rightDiag.maxTurn.interval == nil ? "none" : "\(formatT(rightDiag.maxTurn.interval!.0))..\((formatT(rightDiag.maxTurn.interval!.1)))"
            print("railsRefine maxChordRemainingL=\(format(leftDiag.maxChord.value)) t=[\(leftChordInterval)] maxChordRemainingR=\(format(rightDiag.maxChord.value)) t=[\(rightChordInterval)]")
            if railMaxTurnAngleDegrees > 0.0 {
                print("railsRefine maxTurnRemainingL=\(format(leftDiag.maxTurn.value)) t=[\(leftTurnInterval)] maxTurnRemainingR=\(format(rightDiag.maxTurn.value)) t=[\(rightTurnInterval)]")
            }
            if let window = traceWindow {
                let leftWindow = maxRemainingRailDiagnostics(samples: leftDiagSamples, side: .left, sampleProvider: sampleProvider, traceWindow: window)
                let rightWindow = maxRemainingRailDiagnostics(samples: rightDiagSamples, side: .right, sampleProvider: sampleProvider, traceWindow: window)
                let leftSegInterval = leftWindow.maxSegment.interval == nil ? "none" : "\(formatT(leftWindow.maxSegment.interval!.0))..\((formatT(leftWindow.maxSegment.interval!.1)))"
                let rightSegInterval = rightWindow.maxSegment.interval == nil ? "none" : "\(formatT(rightWindow.maxSegment.interval!.0))..\((formatT(rightWindow.maxSegment.interval!.1)))"
                let leftChordWindowInterval = leftWindow.maxChord.interval == nil ? "none" : "\(formatT(leftWindow.maxChord.interval!.0))..\((formatT(leftWindow.maxChord.interval!.1)))"
                let rightChordWindowInterval = rightWindow.maxChord.interval == nil ? "none" : "\(formatT(rightWindow.maxChord.interval!.0))..\((formatT(rightWindow.maxChord.interval!.1)))"
                let leftTurnWindowInterval = leftWindow.maxTurn.interval == nil ? "none" : "\(formatT(leftWindow.maxTurn.interval!.0))..\((formatT(leftWindow.maxTurn.interval!.1)))"
                let rightTurnWindowInterval = rightWindow.maxTurn.interval == nil ? "none" : "\(formatT(rightWindow.maxTurn.interval!.0))..\((formatT(rightWindow.maxTurn.interval!.1)))"
                print("railsRefine window t=[\(formatT(window.tMin))..\(formatT(window.tMax))] maxSegRemainingL=\(format(leftWindow.maxSegment.value)) t=[\(leftSegInterval)] maxSegRemainingR=\(format(rightWindow.maxSegment.value)) t=[\(rightSegInterval)]")
                print("railsRefine window maxChordRemainingL=\(format(leftWindow.maxChord.value)) t=[\(leftChordWindowInterval)] maxChordRemainingR=\(format(rightWindow.maxChord.value)) t=[\(rightChordWindowInterval)]")
                if railMaxTurnAngleDegrees > 0.0 {
                    print("railsRefine window maxTurnRemainingL=\(format(leftWindow.maxTurn.value)) t=[\(leftTurnWindowInterval)] maxTurnRemainingR=\(format(rightWindow.maxTurn.value)) t=[\(rightTurnWindowInterval)]")
                }
            }
        }
        if traceWindow != nil {
            print("direct-rail cleanup left post=\(leftRail.count) right post=\(rightRail.count)")
            if !windowLeft.isEmpty || !windowRight.isEmpty {
                let leftMissing = missingPointCount(points: windowLeft, within: leftRail, epsilon: epsilon)
                let rightMissing = missingPointCount(points: windowRight, within: rightRail, epsilon: epsilon)
                print("direct-rail windowMissing left=\(leftMissing) right=\(rightMissing)")
            }
        }

        let leftStart = leftRail.first!
        let leftEnd = leftRail.last!
        let rightStartRaw = rightRail.first!
        let rightEndRaw = rightRail.last!
        let dStartStart = (leftStart - rightStartRaw).length
        let dStartEnd = (leftStart - rightEndRaw).length
        let dEndStart = (leftEnd - rightStartRaw).length
        let dEndEnd = (leftEnd - rightEndRaw).length

        let startSample = firstSampleUsed ?? railSamplesAll.first!
        let endSample = lastSampleUsed ?? railSamplesAll.last!
        var capPatches: [Ring] = []
        if case .circle = capStyle.end {
            let radius = max(0.0, (endSample.widthLeft + endSample.widthRight) * 0.5)
            if radius > 0.0 {
                capPatches.append(fullDisk(center: endSample.point, radius: radius, segments: 48))
            }
        }
        if case .circle = capStyle.start {
            let radius = max(0.0, (startSample.widthLeft + startSample.widthRight) * 0.5)
            if radius > 0.0 {
                capPatches.append(fullDisk(center: startSample.point, radius: radius, segments: 48))
            }
        }

        func closestCornerIndex(_ point: Point, corners: [Point]) -> Int {
            var bestIndex = 0
            var bestDist = (corners[0] - point).length
            for (index, corner) in corners.enumerated().dropFirst() {
                let dist = (corner - point).length
                if dist < bestDist {
                    bestDist = dist
                    bestIndex = index
                }
            }
            return bestIndex
        }

        func capPath(sample: Sample, startPoint: Point, endPoint: Point, isStart: Bool) -> [Point] {
            let corners = rectangleCornersWorld(
                center: sample.point,
                widthLeft: sample.widthLeft,
                widthRight: sample.widthRight,
                height: sample.height,
                thetaWorld: sample.effectiveRotation
            )

            let halfH = sample.height * 0.5
            let xMin = -sample.widthLeft
            let xMax = sample.widthRight
            let yMin = -halfH
            let yMax = halfH

            func toLocal(_ point: Point) -> Point {
                let delta = point - sample.point
                return GeometryMath.rotate(point: delta, by: -sample.effectiveRotation)
            }

            func edgeIndex(for local: Point) -> Int {
                let dxRight = abs(local.x - xMax)
                let dxLeft = abs(local.x - xMin)
                let dyTop = abs(local.y - yMax)
                let dyBottom = abs(local.y - yMin)
                var best = 0
                var bestDist = dyBottom
                if dxRight < bestDist { bestDist = dxRight; best = 1 }
                if dyTop < bestDist { bestDist = dyTop; best = 2 }
                if dxLeft < bestDist { bestDist = dxLeft; best = 3 }
                return best
            }

            let localStart = toLocal(startPoint)
            let localEnd = toLocal(endPoint)
            let startEdge = edgeIndex(for: localStart)
            let endEdge = edgeIndex(for: localEnd)

            let ccwCornerEnd = [1, 2, 3, 0] // bottom->c1, right->c2, top->c3, left->c0
            let cwCornerEnd = [0, 1, 2, 3]  // bottom->c0, right->c1, top->c2, left->c3

            func cornerPath(step: Int, cornerMap: [Int]) -> [Int] {
                guard startEdge != endEdge else { return [] }
                var indices: [Int] = []
                var edge = startEdge
                while edge != endEdge {
                    let cornerIdx = cornerMap[edge]
                    indices.append(cornerIdx)
                    edge = (edge + step + 4) % 4
                }
                return indices
            }

            let ccw = cornerPath(step: 1, cornerMap: ccwCornerEnd)
            let cw = cornerPath(step: -1, cornerMap: cwCornerEnd)
            let tangent = Point(x: cos(sample.tangentAngle), y: sin(sample.tangentAngle))
            let outDir = isStart ? tangent * -1.0 : tangent

            func score(_ indices: [Int]) -> Double {
                guard !indices.isEmpty else { return 0.0 }
                var total = 0.0
                for idx in indices {
                    total += (corners[idx] - sample.point).dot(outDir)
                }
                return total
            }

            let scoreCCW = score(ccw)
            let scoreCW = score(cw)
            let useCCW = scoreCCW > scoreCW || (abs(scoreCCW - scoreCW) <= epsilon)
            let chosen = useCCW ? ccw : cw

            if verbose {
                let label = isStart ? "start" : "end"
                let cornerList = chosen.map { "(\(format(corners[$0].x)),\(format(corners[$0].y)))" }.joined(separator: ", ")
                let dirLabel = useCCW ? "CCW" : "CW"
                print("cap \(label): startEdge=\(startEdge) endEdge=\(endEdge) path=\(dirLabel) corners=[\(cornerList)]")
            }

            return chosen.map { corners[$0] }
        }

        func buildCaps(rightStart: Point, rightEnd: Point) -> (endCap: [Point], startCap: [Point], capPoints: [Point]) {
            func orientCap(_ points: [Point], start: Point, end: Point) -> [Point] {
                guard points.count > 1 else { return points }
                let firstDist = (points[0] - start).length
                let lastDist = (points[points.count - 1] - start).length
                if lastDist < firstDist {
                    return Array(points.reversed())
                }
                return points
            }

            let endCapRaw = capPath(sample: endSample, startPoint: leftRail.last!, endPoint: rightEnd, isStart: false)
            let startCapRaw = capPath(sample: startSample, startPoint: rightStart, endPoint: leftRail.first!, isStart: true)
            let endCap = orientCap(endCapRaw, start: leftRail.last!, end: rightEnd)
            let startCap = orientCap(startCapRaw, start: rightStart, end: leftRail.first!)
            return (endCap: endCap, startCap: startCap, capPoints: [])
        }

        func pointsEqualWithin(_ a: Point, _ b: Point, epsilon: Double) -> Bool {
            let dx = a.x - b.x
            let dy = a.y - b.y
            return (dx * dx + dy * dy) <= (epsilon * epsilon)
        }

        func appendOutline(_ points: [Point], to outline: inout [Point]) {
            guard !points.isEmpty else { return }
            if let last = outline.last, pointsEqualWithin(last, points[0], epsilon: epsilon) {
                outline.append(contentsOf: points.dropFirst())
            } else {
                outline.append(contentsOf: points)
            }
        }

        let caps = buildCaps(rightStart: rightStartRaw, rightEnd: rightEndRaw)
        let rightRailForRing = Array(rightRail.reversed())
        let L0 = leftRail.first!
        let Ln = leftRail.last!
        let R0 = rightRail.first!
        let Rn = rightRail.last!

        var outline: [Point] = []
        outline.reserveCapacity(leftRail.count + rightRail.count + caps.endCap.count + caps.startCap.count)
        appendOutline(leftRail, to: &outline)
        appendOutline(caps.endCap, to: &outline)
        appendOutline(rightRailForRing, to: &outline)
        appendOutline(caps.startCap, to: &outline)

        if traceWindow != nil {
            print("direct-outline pre-clean count=\(outline.count) capPoints=\(caps.capPoints.count)")
        }
        let outlineDedup = removeConsecutiveDuplicates(outline, tol: epsilon)
        let outlineAfter = removeTinyEdges(outlineDedup, epsilon: epsilon)
        if traceWindow != nil {
            let removedDup = outline.count - outlineDedup.count
            let removedTiny = outlineDedup.count - outlineAfter.count
            print("direct-outline postprocess removedDup=\(removedDup) removedTiny=\(removedTiny)")
            print("direct-postprocess note=removeConsecutiveDuplicates+removeTinyEdges")
            print("direct-outline post-clean count=\(outlineAfter.count)")
            if !windowLeft.isEmpty || !windowRight.isEmpty {
                for (index, point) in windowLeft.enumerated() {
                    let present = containsPoint(outlineAfter, point, epsilon: epsilon)
                    print("direct-outline window-left idx=\(index) present=\(present) point=(\(format(point.x)),\(format(point.y)))")
                }
                for (index, point) in windowRight.enumerated() {
                    let present = containsPoint(outlineAfter, point, epsilon: epsilon)
                    print("direct-outline window-right idx=\(index) present=\(present) point=(\(format(point.x)),\(format(point.y)))")
                }
            }
        }
        func rotateRing(_ ring: Ring, startIndex: Int) -> Ring {
            guard ring.count > 1 else { return ring }
            var body = ring
            if let last = body.last, let first = body.first, pointsEqualWithin(last, first, epsilon: epsilon) {
                body.removeLast()
            }
            guard !body.isEmpty else { return ring }
            let clamped = max(0, min(startIndex, body.count - 1))
            let rotated = Array(body[clamped...] + body[..<clamped])
            return closeRingIfNeeded(rotated, tol: epsilon)
        }

        func rotateRingToLeftRail(_ ring: Ring) -> Ring {
            guard leftRail.count > 1 else { return ring }
            var body = ring
            if let last = body.last, let first = body.first, pointsEqualWithin(last, first, epsilon: epsilon) {
                body.removeLast()
            }
            guard !body.isEmpty else { return ring }
            let n = body.count
            let l0 = leftRail[0]
            let l1 = leftRail[1]

            var matchIndex: Int? = nil
            var reverseNeeded = false
            for i in 0..<n {
                guard pointsEqualWithin(body[i], l0, epsilon: epsilon) else { continue }
                let next = body[(i + 1) % n]
                let prev = body[(i - 1 + n) % n]
                if pointsEqualWithin(next, l1, epsilon: epsilon) {
                    matchIndex = i
                    reverseNeeded = false
                    break
                }
                if pointsEqualWithin(prev, l1, epsilon: epsilon) {
                    matchIndex = i
                    reverseNeeded = true
                    break
                }
            }
            var candidate = ring
            if reverseNeeded {
                candidate = Array(candidate.reversed())
                candidate = closeRingIfNeeded(removeConsecutiveDuplicates(candidate, tol: epsilon), tol: epsilon)
            }
            if let index = matchIndex {
                return rotateRing(candidate, startIndex: index)
            }

            var bestIndex = 0
            var bestDist = (body[0] - l0).length
            for i in 1..<n {
                let dist = (body[i] - l0).length
                if dist < bestDist {
                    bestDist = dist
                    bestIndex = i
                }
            }
            return rotateRing(candidate, startIndex: bestIndex)
        }

        var outlineResult = closeRingIfNeeded(outlineAfter, tol: epsilon)
        let area = signedArea(outlineResult)
        if area < 0.0 {
            outlineResult = Array(outlineResult.reversed())
            outlineResult = closeRingIfNeeded(removeConsecutiveDuplicates(outlineResult, tol: epsilon), tol: epsilon)
        }
        outlineResult = rotateRingToLeftRail(outlineResult)
        if railsDebug, let ringBounds = boundingBox(outlineResult) {
            print("ringAssemble pts=\(outlineResult.count) bbox=(\(format(ringBounds.min.x)),\(format(ringBounds.min.y)))..(\(format(ringBounds.max.x)),\(format(ringBounds.max.y)))")
        }
        let sanitizeEps: Double = {
            guard let bounds = boundingBox(outlineResult) else { return 1.0e-6 }
            let maxDim = max(abs(bounds.max.x - bounds.min.x), abs(bounds.max.y - bounds.min.y))
            return max(1.0e-6 * maxDim, 1.0e-6)
        }()
        let hairpinSpanTol = max(10.0 * sanitizeEps, 0.01)
        let sanitizeInputCount = outlineResult.count
        let sanitizeStats: RingSanitizeStats
        let sanitized = sanitizeRingWithStats(
            outlineResult,
            eps: sanitizeEps,
            hairpinAngleDeg: 179.0,
            hairpinSpanTol: hairpinSpanTol
        )
        outlineResult = sanitized.ring
        sanitizeStats = sanitized.stats

        func ringPointsForIndexing(_ ring: [Point]) -> [Point] {
            guard ring.count > 1 else { return ring }
            let delta = ring[0] - ring[ring.count - 1]
            if delta.dot(delta) <= 1.0e-12 {
                return Array(ring.dropLast())
            }
            return ring
        }

        let ringPoints = ringPointsForIndexing(outlineResult)
        func nearestRingIndex(for point: Point, in ring: [Point]) -> Int? {
            guard !ring.isEmpty else { return nil }
            var bestIndex = 0
            var bestDist = (ring[0] - point).length
            for (index, candidate) in ring.enumerated().dropFirst() {
                let dist = (candidate - point).length
                if dist < bestDist {
                    bestDist = dist
                    bestIndex = index
                }
            }
            return bestIndex
        }
        var railJoinSeams: [RailJoinSeam] = []
        railJoinSeams.reserveCapacity(joinInfos.count)
        if !ringPoints.isEmpty {
            for info in joinInfos {
                let ringIndex: Int
                if let nearest = nearestRingIndex(for: info.point, in: ringPoints) {
                    ringIndex = nearest
                } else {
                    continue
                }
                railJoinSeams.append(RailJoinSeam(
                    ringIndex: ringIndex,
                    side: info.side,
                    dotForward: info.dotForward,
                    dotReversed: info.dotReversed,
                    chosen: info.chosen
                ))
            }
        }

        if railsDebug {
            let removed = sanitizeStats.droppedHairpinIndices.map(String.init).joined(separator: ",")
            let removedNote = removed.isEmpty ? "" : " removed=\(removed)"
            print("ringSanitize in=\(sanitizeInputCount) out=\(outlineResult.count) droppedDup=\(sanitizeStats.droppedDuplicates) droppedHairpin=\(sanitizeStats.droppedHairpins)\(removedNote)")
            if !ringPoints.isEmpty {
                func ringGTForPoints(_ points: [Point]) -> [Double]? {
                    guard points.count >= 2 else { return nil }
                    var cumulative: [Double] = Array(repeating: 0.0, count: points.count)
                    var total = 0.0
                    for i in 1..<points.count {
                        total += (points[i] - points[i - 1]).length
                        cumulative[i] = total
                    }
                    guard total > 0.0 else { return nil }
                    return cumulative.map { $0 / total }
                }
                var minX = ringPoints[0].x
                var maxX = ringPoints[0].x
                var minY = ringPoints[0].y
                var maxY = ringPoints[0].y
                var minXIndex = 0
                var maxXIndex = 0
                var minYIndex = 0
                var maxYIndex = 0
                for (index, point) in ringPoints.enumerated() {
                    if point.x < minX { minX = point.x; minXIndex = index }
                    if point.x > maxX { maxX = point.x; maxXIndex = index }
                    if point.y < minY { minY = point.y; minYIndex = index }
                    if point.y > maxY { maxY = point.y; maxYIndex = index }
                }
                print("ringExtrema minX idx=\(minXIndex) point=(\(format(minX)),\(format(ringPoints[minXIndex].y)))")
                print("ringExtrema maxX idx=\(maxXIndex) point=(\(format(maxX)),\(format(ringPoints[maxXIndex].y)))")
                print("ringExtrema minY idx=\(minYIndex) point=(\(format(ringPoints[minYIndex].x)),\(format(minY)))")
                print("ringExtrema maxY idx=\(maxYIndex) point=(\(format(ringPoints[maxYIndex].x)),\(format(maxY)))")
                if let ringGT = ringGTForPoints(ringPoints) {
                    print("ringExtremaGT minX idx=\(minXIndex) gt=\(format(ringGT[minXIndex]))")
                    print("ringExtremaGT maxX idx=\(maxXIndex) gt=\(format(ringGT[maxXIndex]))")
                    print("ringExtremaGT minY idx=\(minYIndex) gt=\(format(ringGT[minYIndex]))")
                    print("ringExtremaGT maxY idx=\(maxYIndex) gt=\(format(ringGT[maxYIndex]))")
                }
            }
            let firstSlice = Array(outlineResult.prefix(8))
            let lastSlice = Array(outlineResult.suffix(8))
            let leftSlice = Array(leftRail.prefix(8))
            let startCapList = caps.startCap.map { "(\(format($0.x)),\(format($0.y)))" }.joined(separator: ", ")
            let endCapList = caps.endCap.map { "(\(format($0.x)),\(format($0.y)))" }.joined(separator: ", ")
            print("rails-debug L0=(\(format(L0.x)),\(format(L0.y))) Ln=(\(format(Ln.x)),\(format(Ln.y))) R0=(\(format(R0.x)),\(format(R0.y))) Rn=(\(format(Rn.x)),\(format(Rn.y)))")
            print("rails-debug cap-end=[\(endCapList)] cap-start=[\(startCapList)]")
            print("rails-debug ring-first \(firstSlice)")
            print("rails-debug ring-last \(lastSlice)")
            print("rails-debug left-first \(leftSlice)")
            if outlineResult.count > 1, leftRail.count > 1 {
                let d0 = (outlineResult[0] - leftRail[0]).length
                var nearestIndex = 0
                var nearestDist = (outlineResult[1] - leftRail[0]).length
                for i in 1..<min(leftRail.count, 8) {
                    let dist = (outlineResult[1] - leftRail[i]).length
                    if dist < nearestDist {
                        nearestDist = dist
                        nearestIndex = i
                    }
                }
                if d0 >= 1.0e-6 || nearestDist >= 1.0e-6 {
                    print("rails-debug ringStartMismatch d0=\(format(d0)) ring1-nearestLeft=\(format(nearestDist)) nearestLeftIndex=\(nearestIndex)")
                }
            }
        }

        let intersection = firstSelfIntersection(outlineResult, epsilon: epsilon)
        let outlineSelfIntersects = intersection != nil
        if verbose {
            print("direct-outline endpoints L0=(\(format(L0.x)),\(format(L0.y))) L1=(\(format(Ln.x)),\(format(Ln.y))) R0=(\(format(R0.x)),\(format(R0.y))) R1=(\(format(Rn.x)),\(format(Rn.y)))")
            print(String(format: "direct-outline dist SS=%.6f SE=%.6f ES=%.6f EE=%.6f", dStartStart, dStartEnd, dEndStart, dEndEnd))
            print("direct-outline rails-normal-flips count=\(normalFlipCount) firstIndex=\(normalFlipFirstIndex ?? -1)")
            let ringArea = signedArea(outlineResult)
            print(String(format: "direct-outline counts left=%d right=%d ring=%d area=%.6f", leftRail.count, rightRail.count, outlineResult.count, ringArea))
            if let hit = intersection {
                let s1 = hit.s1
                let s2 = hit.s2
                let n = outlineResult.count
                let prevI = (hit.i - 1 + n) % n
                let nextI = (hit.i + 1) % n
                let prevJ = (hit.j - 1 + n) % n
                let nextJ = (hit.j + 1) % n
                print("rails-self-intersection i=\(hit.i) j=\(hit.j) ringCount=\(n) area=\(format(ringArea)) prevI=\(prevI) nextI=\(nextI) prevJ=\(prevJ) nextJ=\(nextJ)")
                print("segI A=(\(format(s1.a.x)),\(format(s1.a.y))) B=(\(format(s1.b.x)),\(format(s1.b.y)))")
                print("segJ C=(\(format(s2.a.x)),\(format(s2.a.y))) D=(\(format(s2.b.x)),\(format(s2.b.y)))")
                let localStart = max(0, hit.i - 2)
                let localEnd = min(n - 1, hit.i + 2)
                print("ring[0..5] \(Array(outlineResult.prefix(min(6, n))))")
                print("ring[i-2..i+2] \(Array(outlineResult[localStart...localEnd]))")
            }
        }

        let endCap = caps.endCap
        let startCap = caps.startCap
        let capPoints = caps.capPoints

        var patches: [Ring] = []
        var junctionControlPoints: [Point] = []
        var junctionDiagnostics: [JunctionDiagnostic] = []
        var junctionCorridors: [Ring] = []
        patches.reserveCapacity(junctions.count + capPatches.count)
        if !capPatches.isEmpty {
            patches.append(contentsOf: capPatches)
        }
        junctionDiagnostics.reserveCapacity(junctions.count)
        for junction in junctions {
            guard let patch = junctionPatch(from: junction, epsilon: epsilon, verbose: verbose) else { continue }
            var finalRing = patch.ring
            var diagnostic = patch.diagnostic
            var corridorRing: Ring? = nil
            if let corridor = buildJunctionCorridor(
                samples: refinedSamples,
                leftRail: leftRail,
                rightRail: rightRail,
                context: junction,
                window: 8,
                epsilon: epsilon
            ) {
                corridorRing = corridor
                junctionCorridors.append(corridor)
            }
            if let corridor = corridorRing {
                let clip = clipJunctionPatch(
                    ring: finalRing,
                    corridor: corridor,
                    context: junction,
                    epsilon: epsilon,
                    verbose: verbose
                )
                if let clipped = clip.ring {
                    finalRing = clipped
                }
                if verbose {
                    print("junction-clip joinIndex=\(junction.joinIndex) applied=\(clip.applied) reason=\(clip.reason)")
                }
                diagnostic = JunctionDiagnostic(
                    joinIndex: diagnostic.joinIndex,
                    tA: diagnostic.tA,
                    tB: diagnostic.tB,
                    usedBridge: diagnostic.usedBridge,
                    reason: diagnostic.reason,
                    clipped: clip.applied,
                    clipReason: clip.reason
                )
            } else {
                diagnostic = JunctionDiagnostic(
                    joinIndex: diagnostic.joinIndex,
                    tA: diagnostic.tA,
                    tB: diagnostic.tB,
                    usedBridge: diagnostic.usedBridge,
                    reason: diagnostic.reason,
                    clipped: false,
                    clipReason: "noCorridor"
                )
            }
            patches.append(finalRing)
            junctionControlPoints.append(contentsOf: patch.controlPoints)
            junctionDiagnostics.append(diagnostic)
        }
        let cleanedCaps = removeTinyEdges(removeConsecutiveDuplicates(capPoints, tol: epsilon), epsilon: epsilon)
        let leftRailRuns = railRuns.map { $0.left.map { $0.point } }
        let rightRailRuns = railRuns.map { $0.right.map { $0.point } }
        return DirectSilhouetteResult(
            outline: outlineResult,
            outlineSelfIntersects: outlineSelfIntersects,
            leftRail: leftRail,
            rightRail: rightRail,
            leftRailSamples: leftRailAllSamples,
            rightRailSamples: rightRailAllSamples,
            leftRailSamplesPreRefine: preRefineRails.left,
            rightRailSamplesPreRefine: preRefineRails.right,
            leftRailRuns: leftRailRuns,
            rightRailRuns: rightRailRuns,
            endCap: endCap,
            startCap: startCap,
            junctionPatches: patches,
            junctionControlPoints: junctionControlPoints,
            junctionDiagnostics: junctionDiagnostics,
            junctionCorridors: junctionCorridors,
            capPoints: cleanedCaps,
            railJoinSeams: railJoinSeams,
            railConnectors: connectors,
            railRingMeta: [],
            railChain: railChain
        )
    }

    private struct RailSupportResult {
        let offset: Point
        let localDir: Point
        let caseLabel: String
    }

    private static func maxSegmentLength(points: [Point]) -> Double {
        guard points.count > 1 else { return 0.0 }
        var maxLen = 0.0
        for i in 1..<points.count {
            let len = (points[i] - points[i - 1]).length
            if len > maxLen { maxLen = len }
        }
        return maxLen
    }

    private static func maxTurnDegrees(points: [Point]) -> Double {
        guard points.count > 2 else { return 0.0 }
        var maxDeg = 0.0
        for i in 2..<points.count {
            let a = points[i - 2]
            let b = points[i - 1]
            let c = points[i]
            let v1 = (b - a).normalized()
            let v2 = (c - b).normalized()
            guard let v1, let v2 else { continue }
            let dot = max(-1.0, min(1.0, v1.dot(v2)))
            let deg = acos(dot) * 180.0 / Double.pi
            if deg > maxDeg { maxDeg = deg }
        }
        return maxDeg
    }

    private static func maxChordDeviation(points: [Point]) -> Double {
        guard points.count > 2 else { return 0.0 }
        var maxDev = 0.0
        for i in 2..<points.count {
            let a = points[i - 2]
            let b = points[i - 1]
            let c = points[i]
            let ac = c - a
            let ab = b - a
            let acLen2 = ac.dot(ac)
            if acLen2 <= 1.0e-12 { continue }
            let t = max(0.0, min(1.0, ab.dot(ac) / acLen2))
            let proj = Point(x: a.x + ac.x * t, y: a.y + ac.y * t)
            let dev = (b - proj).length
            if dev > maxDev { maxDev = dev }
        }
        return maxDev
    }

    private static func maxSegmentDetail(points: [Point]) -> (index: Int, length: Double, a: Point, b: Point)? {
        guard points.count > 1 else { return nil }
        var maxLen = 0.0
        var maxIndex = 0
        for i in 1..<points.count {
            let len = (points[i] - points[i - 1]).length
            if len > maxLen {
                maxLen = len
                maxIndex = i - 1
            }
        }
        return (maxIndex, maxLen, points[maxIndex], points[maxIndex + 1])
    }

    private static func railSupportOffset(
        direction: Point,
        widthLeft: Double,
        widthRight: Double,
        height: Double,
        thetaWorld: Double,
        epsilon: Double,
        railEpsilon: Double
    ) -> RailSupportResult {
        let local = railLocalDirection(direction: direction, thetaWorld: thetaWorld, railEpsilon: railEpsilon)
        let halfH = height * 0.5
        let localPoint: Point
        let caseLabel: String
        if abs(local.y) <= railEpsilon {
            let x = local.x >= 0.0 ? widthRight : -widthLeft
            localPoint = Point(x: x, y: 0.0)
            caseLabel = local.x >= 0.0 ? "rightMid" : "leftMid"
        } else if abs(local.x) <= railEpsilon {
            let y = local.y >= 0.0 ? halfH : -halfH
            localPoint = Point(x: 0.0, y: y)
            caseLabel = local.y >= 0.0 ? "topMid" : "bottomMid"
        } else {
            let x = local.x >= 0.0 ? widthRight : -widthLeft
            let y = local.y >= 0.0 ? halfH : -halfH
            localPoint = Point(x: x, y: y)
            if local.x >= 0.0 {
                caseLabel = local.y >= 0.0 ? "topRight" : "bottomRight"
            } else {
                caseLabel = local.y >= 0.0 ? "topLeft" : "bottomLeft"
            }
        }
        let offset = GeometryMath.rotate(point: localPoint, by: thetaWorld)
        return RailSupportResult(offset: offset, localDir: local, caseLabel: caseLabel)
    }

    private static func railSupportOffsetContinuous(
        direction: Point,
        widthLeft: Double,
        widthRight: Double,
        height: Double,
        thetaWorld: Double,
        center: Point,
        prevPoint: Point,
        prevCase: String?,
        tangent: Point,
        targetSide: Double?,
        epsilon: Double,
        railEpsilon: Double,
        switchMargin: Double
    ) -> RailSupportResult {
        _ = epsilon
        let local = railLocalDirection(direction: direction, thetaWorld: thetaWorld, railEpsilon: railEpsilon)
        let halfH = height * 0.5
        let candidates: [(String, Point)] = [
            ("topRight", Point(x: widthRight, y: halfH)),
            ("bottomRight", Point(x: widthRight, y: -halfH)),
            ("topLeft", Point(x: -widthLeft, y: halfH)),
            ("bottomLeft", Point(x: -widthLeft, y: -halfH)),
            ("rightMid", Point(x: widthRight, y: 0.0)),
            ("leftMid", Point(x: -widthLeft, y: 0.0)),
            ("topMid", Point(x: 0.0, y: halfH)),
            ("bottomMid", Point(x: 0.0, y: -halfH))
        ]
        let filteredCandidates: [(String, Point)]
        if let targetSide, targetSide != 0.0 {
            let matches = candidates.filter { candidate in
                let offset = GeometryMath.rotate(point: candidate.1, by: thetaWorld)
                let side = railSideSign(tangent: tangent, vector: offset, epsilon: railEpsilon)
                return side == targetSide
            }
            filteredCandidates = matches.isEmpty ? candidates : matches
        } else {
            filteredCandidates = candidates
        }
        var bestLabel = filteredCandidates[0].0
        var bestOffset = GeometryMath.rotate(point: filteredCandidates[0].1, by: thetaWorld)
        var bestDist = (center + bestOffset - prevPoint).length
        for candidate in filteredCandidates.dropFirst() {
            let offset = GeometryMath.rotate(point: candidate.1, by: thetaWorld)
            let dist = (center + offset - prevPoint).length
            if dist < bestDist {
                bestDist = dist
                bestLabel = candidate.0
                bestOffset = offset
            }
        }
        if let prevCase, let prev = candidates.first(where: { $0.0 == prevCase }) {
            let prevOffset = GeometryMath.rotate(point: prev.1, by: thetaWorld)
            let prevSide = railSideSign(tangent: tangent, vector: prevOffset, epsilon: railEpsilon)
            let sideMatches = targetSide == nil || targetSide == 0.0 || prevSide == targetSide
            if sideMatches {
                let prevDist = (center + prevOffset - prevPoint).length
                if bestLabel != prevCase, (bestDist + switchMargin) >= prevDist {
                    return RailSupportResult(offset: prevOffset, localDir: local, caseLabel: prevCase)
                }
            }
        }
        return RailSupportResult(offset: bestOffset, localDir: local, caseLabel: bestLabel)
    }

    private static func railSideSign(tangent: Point, vector: Point, epsilon: Double) -> Double {
        let cross = tangent.x * vector.y - tangent.y * vector.x
        return signWithZero(cross, epsilon: epsilon)
    }

    private static func railLocalDirection(direction: Point, thetaWorld: Double, railEpsilon: Double) -> Point {
        var local = GeometryMath.rotate(point: direction, by: -thetaWorld)
        if abs(local.x) < railEpsilon { local.x = 0.0 }
        if abs(local.y) < railEpsilon { local.y = 0.0 }
        let slopeEps = 0.01
        let ax = abs(local.x)
        let ay = abs(local.y)
        if ay <= ax * slopeEps { local.y = 0.0 }
        if ax <= ay * slopeEps { local.x = 0.0 }
        return local
    }

    private static func railSupportDistance(
        direction: Point,
        widthLeft: Double,
        widthRight: Double,
        height: Double,
        thetaWorld: Double,
        railEpsilon: Double
    ) -> Double {
        let local = railLocalDirection(direction: direction, thetaWorld: thetaWorld, railEpsilon: railEpsilon)
        let len = local.length
        let unit = len > 1.0e-9 ? local * (1.0 / len) : local
        let halfH = height * 0.5
        let xScale = unit.x >= 0.0 ? widthRight : widthLeft
        return abs(unit.x) * xScale + abs(unit.y) * halfH
    }

    public static func supportOffset(direction: Point, widthLeft: Double, widthRight: Double, height: Double, thetaWorld: Double, epsilon: Double = 1.0e-9) -> Point {
        let local = GeometryMath.rotate(point: direction, by: -thetaWorld)
        let halfH = height * 0.5
        let sx = signWithZero(local.x, epsilon: epsilon)
        let sy = signWithZero(local.y, epsilon: epsilon)
        let cornerX = sx >= 0 ? widthRight : -widthLeft
        let localCorner = Point(x: cornerX, y: sy * halfH)
        return GeometryMath.rotate(point: localCorner, by: thetaWorld)
    }

    public static func leftRailPoint(sample: Sample, epsilon: Double = 1.0e-9) -> Point {
        railPointInternal(sample: sample, side: .left, epsilon: epsilon)
    }

    public static func rightRailPoint(sample: Sample, epsilon: Double = 1.0e-9) -> Point {
        railPointInternal(sample: sample, side: .right, epsilon: epsilon)
    }

    private static func rectangleCornersWorld(center: Point, widthLeft: Double, widthRight: Double, height: Double, thetaWorld: Double) -> [Point] {
        let halfH = height * 0.5
        let local = [
            Point(x: -widthLeft, y: -halfH),
            Point(x: widthRight, y: -halfH),
            Point(x: widthRight, y: halfH),
            Point(x: -widthLeft, y: halfH)
        ]
        return local.map { center + GeometryMath.rotate(point: $0, by: thetaWorld) }
    }

    private static func endCapPoints(corners: [Point], center: Point, faceDir: Point, from: Point, to: Point, epsilon: Double) -> [Point] {
        guard !corners.isEmpty else { return [] }
        let maxDot = corners.map { ($0 - center).dot(faceDir) }.max() ?? 0.0
        var candidates: [Point] = []
        for corner in corners {
            if abs((corner - center).dot(faceDir) - maxDot) <= epsilon {
                candidates.append(corner)
            }
        }
        if candidates.count < 2 {
            let sorted = corners.sorted { ($0 - center).dot(faceDir) > ($1 - center).dot(faceDir) }
            candidates = Array(sorted.prefix(2))
        }
        if candidates.count > 2 {
            candidates = Array(candidates.prefix(2))
        }
        guard candidates.count == 2 else { return candidates }
        let first = candidates[0]
        let second = candidates[1]
        let distFirst = (first - from).length
        let distSecond = (second - from).length
        if abs(distFirst - distSecond) <= epsilon {
            let ordered = [first, second].sorted { (a, b) in
                if a.x != b.x { return a.x < b.x }
                return a.y < b.y
            }
            return ordered
        }
        return distFirst <= distSecond ? [first, second] : [second, first]
    }

    private static func signWithZero(_ value: Double, epsilon: Double) -> Double {
        if abs(value) <= epsilon { return 0.0 }
        return value < 0 ? -1.0 : 1.0
    }

    private enum RailSide {
        case left
        case right
    }

    private final class RefinementCounts {
        var insertedChordOnly = 0
        var insertedLengthOnly = 0
        var insertedBoth = 0
        var insertedTurnOnly = 0
        var maxDepthHits = 0
        var minStepHits = 0
        var jumpSeamsSkipped = 0
    }

    private static func refineRailSamplesByChordError(
        samples: [Sample],
        tolerance: Double,
        maxSegmentLength: Double,
        maxTurnAngleDegrees: Double,
        maxDepth: Int,
        minParamStep: Double,
        sampleProvider: DirectSilhouetteSampleProvider,
        refinementCounts: RefinementCounts?
    ) -> [Sample] {
        guard samples.count >= 2 else { return samples }
        var refined: [Sample] = []
        refined.reserveCapacity(samples.count)
        refined.append(samples[0])
        for index in 0..<(samples.count - 1) {
            let a = samples[index]
            let b = samples[index + 1]
            let segment = refineRailPair(
                a,
                b,
                depth: 0,
                tolerance: tolerance,
                maxSegmentLength: maxSegmentLength,
                maxTurnAngleDegrees: maxTurnAngleDegrees,
                maxDepth: maxDepth,
                minParamStep: minParamStep,
                sampleProvider: sampleProvider,
                refinementCounts: refinementCounts
            )
            if segment.count > 1 {
                refined.append(contentsOf: segment.dropFirst())
            }
        }
        return refined
    }

    private static func refineRailPair(
        _ a: Sample,
        _ b: Sample,
        depth: Int,
        tolerance: Double,
        maxSegmentLength: Double,
        maxTurnAngleDegrees: Double,
        maxDepth: Int,
        minParamStep: Double,
        sampleProvider: DirectSilhouetteSampleProvider,
        refinementCounts: RefinementCounts?
    ) -> [Sample] {
        if depth >= maxDepth {
            refinementCounts?.maxDepthHits += 1
            return [a, b]
        }
        if abs(b.t - a.t) <= minParamStep {
            refinementCounts?.minStepHits += 1
            return [a, b]
        }
        let tm = 0.5 * (a.t + b.t)
        guard let mid = sampleProvider(tm) else {
            return [a, b]
        }
        let leftA = leftRailPoint(sample: a)
        let leftB = leftRailPoint(sample: b)
        let leftM = leftRailPoint(sample: mid)
        let rightA = rightRailPoint(sample: a)
        let rightB = rightRailPoint(sample: b)
        let rightM = rightRailPoint(sample: mid)
        let leftError = distancePointToSegment(point: leftM, a: leftA, b: leftB)
        let rightError = distancePointToSegment(point: rightM, a: rightA, b: rightB)
        let error = max(leftError, rightError)
        let leftLength = (leftB - leftA).length
        let rightLength = (rightB - rightA).length
        let maxLength = max(leftLength, rightLength)
        let turnAngle = abs(angleDeltaRadians(a.tangentAngle, b.tangentAngle))
        let turnAngleDegrees = turnAngle * 180.0 / Double.pi
        let chordFail = tolerance > 0.0 && error > tolerance
        let lengthFail = maxSegmentLength > 0.0 && maxLength > maxSegmentLength
        let turnFail = maxTurnAngleDegrees > 0.0 && turnAngleDegrees > maxTurnAngleDegrees
        let jumpThreshold = 20.0
        if maxLength > jumpThreshold {
            refinementCounts?.jumpSeamsSkipped += 1
            return [a, b]
        }
        if !chordFail && !lengthFail && !turnFail {
            return [a, b]
        }
        if chordFail && lengthFail {
            refinementCounts?.insertedBoth += 1
        } else if chordFail {
            refinementCounts?.insertedChordOnly += 1
        } else if lengthFail {
            refinementCounts?.insertedLengthOnly += 1
        } else if turnFail {
            refinementCounts?.insertedTurnOnly += 1
        }
        let left = refineRailPair(a, mid, depth: depth + 1, tolerance: tolerance, maxSegmentLength: maxSegmentLength, maxTurnAngleDegrees: maxTurnAngleDegrees, maxDepth: maxDepth, minParamStep: minParamStep, sampleProvider: sampleProvider, refinementCounts: refinementCounts)
        let right = refineRailPair(mid, b, depth: depth + 1, tolerance: tolerance, maxSegmentLength: maxSegmentLength, maxTurnAngleDegrees: maxTurnAngleDegrees, maxDepth: maxDepth, minParamStep: minParamStep, sampleProvider: sampleProvider, refinementCounts: refinementCounts)
        if left.isEmpty { return right }
        if right.isEmpty { return left }
        return Array(left.dropLast()) + right
    }

    private static func distancePointToSegment(point: Point, a: Point, b: Point) -> Double {
        let ab = b - a
        let ap = point - a
        let denom = ab.dot(ab)
        if denom <= 1.0e-12 {
            return ap.length
        }
        let t = max(0.0, min(1.0, ap.dot(ab) / denom))
        let proj = a + ab * t
        return (point - proj).length
    }

    private static func maxRemainingRailSegmentLength(samples: [RailSample]) -> (length: Double, interval: (Double, Double)?) {
        guard samples.count >= 2 else { return (0.0, nil) }
        var maxLength = 0.0
        var maxInterval: (Double, Double)? = nil
        for i in 0..<(samples.count - 1) {
            let a = samples[i]
            let b = samples[i + 1]
            let length = (b.point - a.point).length
            if length > maxLength {
                maxLength = length
                maxInterval = (a.t, b.t)
            }
        }
        return (maxLength, maxInterval)
    }

    private struct RailMetricMax {
        var value: Double
        var interval: (Double, Double)?
    }

    private struct RailDiagnostics {
        let maxSegment: RailMetricMax
        let maxChord: RailMetricMax
        let maxTurn: RailMetricMax
    }

    private static func maxRemainingRailDiagnostics(
        samples: [RailSample],
        side: RailSide,
        sampleProvider: DirectSilhouetteSampleProvider?,
        traceWindow: DirectSilhouetteTraceWindow?
    ) -> RailDiagnostics {
        guard samples.count >= 2 else {
            return RailDiagnostics(
                maxSegment: RailMetricMax(value: 0.0, interval: nil),
                maxChord: RailMetricMax(value: 0.0, interval: nil),
                maxTurn: RailMetricMax(value: 0.0, interval: nil)
            )
        }
        var maxSeg = RailMetricMax(value: 0.0, interval: nil)
        var maxChord = RailMetricMax(value: 0.0, interval: nil)
        var maxTurn = RailMetricMax(value: 0.0, interval: nil)

        for i in 0..<(samples.count - 1) {
            let a = samples[i]
            let b = samples[i + 1]
            if let window = traceWindow, !window.intersects(a.t, b.t) {
                continue
            }
            let segLength = (b.point - a.point).length
            if segLength > maxSeg.value {
                maxSeg.value = segLength
                maxSeg.interval = (a.t, b.t)
            }
            guard let sampleProvider else { continue }
            guard let mid = sampleProvider(0.5 * (a.t + b.t)) else { continue }
            let midPoint = (side == .left) ? leftRailPoint(sample: mid) : rightRailPoint(sample: mid)
            let chordError = distancePointToSegment(point: midPoint, a: a.point, b: b.point)
            if chordError > maxChord.value {
                maxChord.value = chordError
                maxChord.interval = (a.t, b.t)
            }
            guard let sa = sampleProvider(a.t), let sb = sampleProvider(b.t) else { continue }
            let delta = abs(angleDeltaRadians(sa.tangentAngle, sb.tangentAngle)) * 180.0 / Double.pi
            if delta > maxTurn.value {
                maxTurn.value = delta
                maxTurn.interval = (a.t, b.t)
            }
        }
        return RailDiagnostics(maxSegment: maxSeg, maxChord: maxChord, maxTurn: maxTurn)
    }

    private static func maxRemainingRailTurnDegrees(samples: [RailSample], sampleProvider: DirectSilhouetteSampleProvider) -> (degrees: Double, interval: (Double, Double)?) {
        guard samples.count >= 2 else { return (0.0, nil) }
        var maxDegrees = 0.0
        var maxInterval: (Double, Double)? = nil
        for i in 0..<(samples.count - 1) {
            let a = samples[i]
            let b = samples[i + 1]
            guard let sa = sampleProvider(a.t), let sb = sampleProvider(b.t) else { continue }
            let delta = abs(angleDeltaRadians(sa.tangentAngle, sb.tangentAngle)) * 180.0 / Double.pi
            if delta > maxDegrees {
                maxDegrees = delta
                maxInterval = (a.t, b.t)
            }
        }
        return (maxDegrees, maxInterval)
    }

    private static func angleDeltaRadians(_ a: Double, _ b: Double) -> Double {
        var delta = b - a
        let twoPi = 2.0 * Double.pi
        while delta > Double.pi { delta -= twoPi }
        while delta < -Double.pi { delta += twoPi }
        return delta
    }

    private static func maxRingTurnDegrees(
        ring: Ring,
        start: Int,
        count: Int?
    ) -> (degrees: Double, index: Int?) {
        guard ring.count >= 3 else { return (0.0, nil) }
        var points = ring
        if let first = points.first,
           let last = points.last,
           (first - last).length <= 1.0e-9 {
            points.removeLast()
        }
        guard points.count >= 3 else { return (0.0, nil) }
        let clampedStart = max(0, min(start, points.count - 1))
        let requestedCount = count ?? (points.count - clampedStart)
        let clampedCount = max(0, min(requestedCount, points.count - clampedStart))
        guard clampedCount >= 3 else { return (0.0, nil) }
        let end = clampedStart + clampedCount - 1
        var bestDegrees = 0.0
        var bestIndex: Int? = nil
        for i in (clampedStart + 1)..<end {
            let a = points[i - 1]
            let b = points[i]
            let c = points[i + 1]
            let v1 = b - a
            let v2 = c - b
            let len1 = v1.length
            let len2 = v2.length
            if len1 <= 1.0e-12 || len2 <= 1.0e-12 { continue }
            let dot = max(-1.0, min(1.0, (v1.x * v2.x + v1.y * v2.y) / (len1 * len2)))
            let angle = acos(dot)
            let degrees = angle * 180.0 / Double.pi
            if degrees > bestDegrees {
                bestDegrees = degrees
                bestIndex = i
            }
        }
        return (bestDegrees, bestIndex)
    }

    private static func formatT(_ value: Double) -> String {
        String(format: "%.9f", value)
    }

    private static func refineSamples(
        samples: [Sample],
        options: DirectSilhouetteOptions,
        railTolerance: Double,
        paramsProvider: DirectSilhouetteParamProvider?,
        sampleProvider: DirectSilhouetteSampleProvider?,
        traceWindow: DirectSilhouetteTraceWindow?,
        epsilon: Double
    ) -> [Sample] {
        guard samples.count >= 2 else { return samples }
        var refined: [Sample] = []
        refined.reserveCapacity(samples.count)
        refined.append(samples[0])
        for index in 0..<(samples.count - 1) {
            let a = samples[index]
            let b = samples[index + 1]
            let segment = refinePair(
                a,
                b,
                depth: 0,
                options: options,
                railTolerance: railTolerance,
                paramsProvider: paramsProvider,
                sampleProvider: sampleProvider,
                traceWindow: traceWindow,
                epsilon: epsilon
            )
            if segment.count > 1 {
                refined.append(contentsOf: segment.dropFirst())
            }
        }
        return refined
    }

    private static func refinePair(
        _ a: Sample,
        _ b: Sample,
        depth: Int,
        options: DirectSilhouetteOptions,
        railTolerance: Double,
        paramsProvider: DirectSilhouetteParamProvider?,
        sampleProvider: DirectSilhouetteSampleProvider?,
        traceWindow: DirectSilhouetteTraceWindow?,
        epsilon: Double
    ) -> [Sample] {
        let maxDepth = max(options.cornerRefineMaxDepth, options.railRefineMaxDepth)
        if depth >= maxDepth {
            if let window = traceWindow, window.intersects(a.t, b.t) {
                print("direct-refine depthCap t=[\(format(a.t))..\((format(b.t)))] depth=\(depth)")
            }
            return [a, b]
        }
        let minStep = min(options.cornerRefineMinStep, options.railRefineMinStep)
        if abs(b.t - a.t) <= minStep {
            if let window = traceWindow, window.intersects(a.t, b.t) {
                print("direct-refine minStep t=[\(format(a.t))..\((format(b.t)))] step=\(format(abs(b.t - a.t)))")
            }
            return [a, b]
        }
        if !needsRailSplit(a, b, options: options, railTolerance: railTolerance, paramsProvider: paramsProvider, sampleProvider: sampleProvider, traceWindow: traceWindow, epsilon: epsilon) {
            return [a, b]
        }
        let mid = interpolateSample(a, b, paramsProvider: paramsProvider, sampleProvider: sampleProvider)
        let left = refinePair(a, mid, depth: depth + 1, options: options, railTolerance: railTolerance, paramsProvider: paramsProvider, sampleProvider: sampleProvider, traceWindow: traceWindow, epsilon: epsilon)
        let right = refinePair(mid, b, depth: depth + 1, options: options, railTolerance: railTolerance, paramsProvider: paramsProvider, sampleProvider: sampleProvider, traceWindow: traceWindow, epsilon: epsilon)
        if left.isEmpty { return right }
        if right.isEmpty { return left }
        return Array(left.dropLast()) + right
    }

    private static func needsRailSplit(
        _ a: Sample,
        _ b: Sample,
        options: DirectSilhouetteOptions,
        railTolerance: Double,
        paramsProvider: DirectSilhouetteParamProvider?,
        sampleProvider: DirectSilhouetteSampleProvider?,
        traceWindow: DirectSilhouetteTraceWindow?,
        epsilon: Double
    ) -> Bool {
        let inWindow = traceWindow?.intersects(a.t, b.t) ?? false
        if options.enableCornerRefine, cornerSwitchesBetween(a, b, epsilon: options.cornerRefineEpsilon) {
            if inWindow {
                print("direct-refine cornerSwitch t=[\(format(a.t))..\((format(b.t)))]")
            }
            return true
        }
        var deviation: Double = 0.0
        if options.enableRailRefine, railTolerance > 0 {
            deviation = railDeviation(a: a, b: b, paramsProvider: paramsProvider, sampleProvider: sampleProvider, traceWindow: traceWindow, epsilon: epsilon)
            if inWindow {
                print("direct-refine railDeviation t=[\(format(a.t))..\((format(b.t)))] dev=\(format(deviation)) tol=\(format(railTolerance))")
            }
            if deviation > railTolerance {
                return true
            }
        }
        if inWindow {
            let reason: String
            if !options.enableCornerRefine && !(options.enableRailRefine && railTolerance > 0) {
                reason = "disabled"
            } else if options.enableRailRefine && railTolerance > 0 {
                reason = "withinTolerance"
            } else {
                reason = "noCornerSwitch"
            }
            print("direct-refine keep t=[\(format(a.t))..\((format(b.t)))] reason=\(reason) dev=\(format(deviation))")
        }
        return false
    }

    private static func cornerSwitchesBetween(_ a: Sample, _ b: Sample, epsilon: Double) -> Bool {
        let leftA = cornerKey(for: a, side: .left, epsilon: epsilon)
        let leftB = cornerKey(for: b, side: .left, epsilon: epsilon)
        if leftA != leftB { return true }
        let rightA = cornerKey(for: a, side: .right, epsilon: epsilon)
        let rightB = cornerKey(for: b, side: .right, epsilon: epsilon)
        return rightA != rightB
    }

    private static func cornerKey(for sample: Sample, side: RailSide, epsilon: Double) -> (Int, Int) {
        let tangent = Point(x: cos(sample.tangentAngle), y: sin(sample.tangentAngle))
        var normal = tangent.leftNormal()
        if side == .right {
            normal = normal * -1.0
        }
        let local = GeometryMath.rotate(point: normal, by: -sample.effectiveRotation)
        let sx = signIntWithZero(local.x, epsilon: epsilon)
        let sy = signIntWithZero(local.y, epsilon: epsilon)
        return (sx, sy)
    }

    private static func signIntWithZero(_ value: Double, epsilon: Double) -> Int {
        if abs(value) <= epsilon { return 0 }
        return value < 0 ? -1 : 1
    }

    internal static func interpolatedSample(_ a: Sample, _ b: Sample, fraction: Double, sampleProvider: DirectSilhouetteSampleProvider? = nil) -> Sample {
        interpolateSample(a, b, fraction: fraction, sampleProvider: sampleProvider)
    }

    internal static func railDeviationForTest(
        a: Sample,
        b: Sample,
        paramsProvider: DirectSilhouetteParamProvider?,
        sampleProvider: DirectSilhouetteSampleProvider? = nil,
        epsilon: Double
    ) -> Double {
        railDeviation(a: a, b: b, paramsProvider: paramsProvider, sampleProvider: sampleProvider, traceWindow: nil, epsilon: epsilon)
    }

    private static func interpolateSample(
        _ a: Sample,
        _ b: Sample,
        fraction: Double = 0.5,
        paramsProvider: DirectSilhouetteParamProvider? = nil,
        sampleProvider: DirectSilhouetteSampleProvider? = nil
    ) -> Sample {
        let t = ScalarMath.clamp01(fraction)
        if let provider = sampleProvider {
            let sampleT = ScalarMath.lerp(a.t, b.t, t)
            if let provided = provider(sampleT) {
                return provided
            }
        }
        let point = Point(
            x: ScalarMath.lerp(a.point.x, b.point.x, t),
            y: ScalarMath.lerp(a.point.y, b.point.y, t)
        )
        let tangentA = Point(x: cos(a.tangentAngle), y: sin(a.tangentAngle))
        let tangentB = Point(x: cos(b.tangentAngle), y: sin(b.tangentAngle))
        let tangent = (tangentA + tangentB).normalized() ?? tangentA
        let tangentAngle = atan2(tangent.y, tangent.x)
        let theta = a.theta + AngleMath.shortestDelta(from: a.theta, to: b.theta) * t
        let effectiveRotation = a.effectiveRotation + AngleMath.shortestDelta(from: a.effectiveRotation, to: b.effectiveRotation) * t
        var width = ScalarMath.lerp(a.width, b.width, t)
        var widthLeft = ScalarMath.lerp(a.widthLeft, b.widthLeft, t)
        var widthRight = ScalarMath.lerp(a.widthRight, b.widthRight, t)
        var height = ScalarMath.lerp(a.height, b.height, t)
        var alpha = ScalarMath.lerp(a.alpha, b.alpha, t)
        var resolvedTheta = theta
        var resolvedRotation = effectiveRotation
        if let provider = paramsProvider {
            let params = provider(ScalarMath.lerp(a.t, b.t, t), tangentAngle)
            width = params.width
            widthLeft = params.widthLeft
            widthRight = params.widthRight
            height = params.height
            alpha = params.alpha
            resolvedTheta = params.theta
            resolvedRotation = params.effectiveRotation
        }
        return Sample(
            uGeom: ScalarMath.lerp(a.uGeom, b.uGeom, t),
            uGrid: ScalarMath.lerp(a.uGrid, b.uGrid, t),
            t: ScalarMath.lerp(a.t, b.t, t),
            point: point,
            tangentAngle: tangentAngle,
            width: width,
            widthLeft: widthLeft,
            widthRight: widthRight,
            height: height,
            theta: resolvedTheta,
            effectiveRotation: resolvedRotation,
            alpha: alpha
        )
    }

    private static func railDeviation(
        a: Sample,
        b: Sample,
        paramsProvider: DirectSilhouetteParamProvider?,
        sampleProvider: DirectSilhouetteSampleProvider?,
        traceWindow: DirectSilhouetteTraceWindow?,
        epsilon: Double
    ) -> Double {
        let tm = 0.5 * (a.t + b.t)
        let mid = interpolateSample(a, b, paramsProvider: paramsProvider, sampleProvider: sampleProvider)
        let left0 = railPointInternal(sample: a, side: .left, epsilon: epsilon)
        let left1 = railPointInternal(sample: b, side: .left, epsilon: epsilon)
        let leftMid = railPointInternal(sample: mid, side: .left, epsilon: epsilon)
        let leftLinear = Point(
            x: ScalarMath.lerp(left0.x, left1.x, 0.5),
            y: ScalarMath.lerp(left0.y, left1.y, 0.5)
        )
        let right0 = railPointInternal(sample: a, side: .right, epsilon: epsilon)
        let right1 = railPointInternal(sample: b, side: .right, epsilon: epsilon)
        let rightMid = railPointInternal(sample: mid, side: .right, epsilon: epsilon)
        let rightLinear = Point(
            x: ScalarMath.lerp(right0.x, right1.x, 0.5),
            y: ScalarMath.lerp(right0.y, right1.y, 0.5)
        )
        let leftError = (leftMid - leftLinear).length
        let rightError = (rightMid - rightLinear).length
        if let window = traceWindow, window.intersects(a.t, b.t) {
            print("[DEV] t0=\(format(a.t)) t1=\(format(b.t)) tm=\(format(tm))")
            print("      L0=(\(format(left0.x)),\(format(left0.y))) Lm=(\(format(leftMid.x)),\(format(leftMid.y))) L1=(\(format(left1.x)),\(format(left1.y))) Llin=(\(format(leftLinear.x)),\(format(leftLinear.y))) devL=\(format(leftError))")
            print("      R0=(\(format(right0.x)),\(format(right0.y))) Rm=(\(format(rightMid.x)),\(format(rightMid.y))) R1=(\(format(right1.x)),\(format(right1.y))) Rlin=(\(format(rightLinear.x)),\(format(rightLinear.y))) devR=\(format(rightError))")
        }
        return max(leftError, rightError)
    }

    private static func railPointInternal(sample: Sample, side: RailSide, epsilon: Double) -> Point {
        let tangent = Point(x: cos(sample.tangentAngle), y: sin(sample.tangentAngle))
        var normal = tangent.leftNormal()
        if side == .right {
            normal = normal * -1.0
        }
        let railEpsilon = 1.0e-3
        let distance = railSupportDistance(
            direction: normal,
            widthLeft: sample.widthLeft,
            widthRight: sample.widthRight,
            height: sample.height,
            thetaWorld: sample.effectiveRotation,
            railEpsilon: railEpsilon
        )
        _ = epsilon
        return sample.point + normal * distance
    }

    private static func railPointsForSamples(_ samples: [Sample], epsilon: Double) -> (left: [Point], right: [Point]) {
        guard !samples.isEmpty else { return ([], []) }
        var left: [Point] = []
        var right: [Point] = []
        left.reserveCapacity(samples.count)
        right.reserveCapacity(samples.count)
        var prevNormal: Point? = nil
        let railEpsilon = 1.0e-3
        for sample in samples {
            let tangent = Point(x: cos(sample.tangentAngle), y: sin(sample.tangentAngle))
            var normal = tangent.leftNormal()
            if let prev = prevNormal, normal.dot(prev) < 0.0 {
                normal = normal * -1.0
            }
            prevNormal = normal
            let leftDistance = railSupportDistance(
                direction: normal,
                widthLeft: sample.widthLeft,
                widthRight: sample.widthRight,
                height: sample.height,
                thetaWorld: sample.effectiveRotation,
                railEpsilon: railEpsilon
            )
            let rightDistance = railSupportDistance(
                direction: normal * -1.0,
                widthLeft: sample.widthLeft,
                widthRight: sample.widthRight,
                height: sample.height,
                thetaWorld: sample.effectiveRotation,
                railEpsilon: railEpsilon
            )
            left.append(sample.point + normal * leftDistance)
            right.append(sample.point - normal * rightDistance)
        }
        _ = epsilon
        return (left, right)
    }

    private static func splitRailRuns(samples: [Sample], threshold: Double, epsilon: Double) -> [[Sample]] {
        guard !samples.isEmpty else { return [] }
        if threshold <= 0.0 { return [samples] }
        var runs: [[Sample]] = []
        var current: [Sample] = [samples[0]]
        var prevNormal: Point? = nil
        var prevLeft: Point? = nil
        var prevRight: Point? = nil
        let railEpsilon = 1.0e-3
        for sample in samples.dropFirst() {
            let tangent = Point(x: cos(sample.tangentAngle), y: sin(sample.tangentAngle))
            var normal = tangent.leftNormal()
            if let prev = prevNormal, normal.dot(prev) < 0.0 {
                normal = normal * -1.0
            }
            let leftDistance = railSupportDistance(
                direction: normal,
                widthLeft: sample.widthLeft,
                widthRight: sample.widthRight,
                height: sample.height,
                thetaWorld: sample.effectiveRotation,
                railEpsilon: railEpsilon
            )
            let rightDistance = railSupportDistance(
                direction: normal * -1.0,
                widthLeft: sample.widthLeft,
                widthRight: sample.widthRight,
                height: sample.height,
                thetaWorld: sample.effectiveRotation,
                railEpsilon: railEpsilon
            )
            let leftPoint = sample.point + normal * leftDistance
            let rightPoint = sample.point - normal * rightDistance
            let shouldSplit: Bool
            if let prevLeft, let prevRight {
                let leftSeg = (leftPoint - prevLeft).length
                let rightSeg = (rightPoint - prevRight).length
                shouldSplit = max(leftSeg, rightSeg) > threshold
            } else {
                shouldSplit = false
            }
            if shouldSplit {
                runs.append(current)
                current = [sample]
                prevNormal = nil
                prevLeft = nil
                prevRight = nil
            } else {
                current.append(sample)
                prevNormal = normal
                prevLeft = leftPoint
                prevRight = rightPoint
            }
        }
        if !current.isEmpty {
            runs.append(current)
        }
        _ = epsilon
        return runs
    }

    private static func selectDominantRunIndex(
        runs: [[Sample]],
        runRails: [(left: [Point], right: [Point])],
        traceWindow: DirectSilhouetteTraceWindow?
    ) -> Int {
        guard !runs.isEmpty else { return 0 }
        var bestIndex = 0
        var bestLength = -Double.greatestFiniteMagnitude
        var bestCount = -1
        for (index, run) in runs.enumerated() {
            guard run.count >= 2, runRails.indices.contains(index) else { continue }
            let left = runRails[index].left
            let segmentCount = min(run.count - 1, max(0, left.count - 1))
            if segmentCount <= 0 { continue }
            var length = 0.0
            for i in 0..<segmentCount {
                let a = run[i]
                let b = run[i + 1]
                if let window = traceWindow, !window.intersects(a.t, b.t) {
                    continue
                }
                length += (left[i + 1] - left[i]).length
            }
            if length > bestLength || (abs(length - bestLength) <= 1.0e-9 && run.count > bestCount) {
                bestLength = length
                bestIndex = index
                bestCount = run.count
            }
        }
        return bestIndex
    }

    private static func removeTinyEdges(_ points: [Point], epsilon: Double) -> [Point] {
        guard !points.isEmpty else { return points }
        var result: [Point] = []
        result.reserveCapacity(points.count)
        var last = points[0]
        result.append(last)
        for point in points.dropFirst() {
            if (point - last).length > epsilon {
                result.append(point)
                last = point
            }
        }
        return result
    }

    private static func cleanedRailSamples(_ samples: [RailSample], epsilon: Double) -> [RailSample] {
        guard !samples.isEmpty else { return samples }
        var result: [RailSample] = []
        result.reserveCapacity(samples.count)
        var last = samples[0]
        result.append(last)
        for sample in samples.dropFirst() {
            if (sample.point - last.point).length > epsilon {
                result.append(sample)
                last = sample
            }
        }
        guard result.count > 1 else { return result }
        var trimmed: [RailSample] = []
        trimmed.reserveCapacity(result.count)
        var prev = result[0]
        trimmed.append(prev)
        for sample in result.dropFirst() {
            if (sample.point - prev.point).length > epsilon {
                trimmed.append(sample)
                prev = sample
            }
        }
        return trimmed
    }

    private struct RailJump: Comparable {
        let index: Int
        let length: Double
        let tA: Double
        let tB: Double
        let a: Point
        let b: Point

        static func < (lhs: RailJump, rhs: RailJump) -> Bool {
            lhs.length < rhs.length
        }
    }

    private static func buildRailSamplesForDebug(samples: [Sample], epsilon: Double) -> (left: [RailSample], right: [RailSample]) {
        guard samples.count >= 2 else { return ([], []) }
        var left: [RailSample] = []
        var right: [RailSample] = []
        left.reserveCapacity(samples.count)
        right.reserveCapacity(samples.count)
        var prevNormal: Point? = nil
        let railEpsilon = 1.0e-3
        for sample in samples {
            let tangent = Point(x: cos(sample.tangentAngle), y: sin(sample.tangentAngle))
            var normal = tangent.leftNormal()
            if let prev = prevNormal, normal.dot(prev) < 0.0 {
                normal = normal * -1.0
            }
            prevNormal = normal
            let leftDistance = railSupportDistance(
                direction: normal,
                widthLeft: sample.widthLeft,
                widthRight: sample.widthRight,
                height: sample.height,
                thetaWorld: sample.effectiveRotation,
                railEpsilon: railEpsilon
            )
            let rightDistance = railSupportDistance(
                direction: normal * -1.0,
                widthLeft: sample.widthLeft,
                widthRight: sample.widthRight,
                height: sample.height,
                thetaWorld: sample.effectiveRotation,
                railEpsilon: railEpsilon
            )
            let leftPoint = sample.point + normal * leftDistance
            let rightPoint = sample.point - normal * rightDistance
            left.append(RailSample(
                t: sample.t,
                point: leftPoint,
                normal: normal,
                debugSkeletonIndex: sample.debugSkeletonIndex,
                debugSkeletonId: sample.debugSkeletonId,
                debugSegmentIndex: sample.debugSegmentIndex,
                debugSegmentKind: sample.debugSegmentKind,
                debugSegmentU: sample.debugSegmentU,
                debugRunId: nil,
                debugSupportCase: "L",
                debugSupportLocal: nil
            ))
            right.append(RailSample(
                t: sample.t,
                point: rightPoint,
                normal: normal * -1.0,
                debugSkeletonIndex: sample.debugSkeletonIndex,
                debugSkeletonId: sample.debugSkeletonId,
                debugSegmentIndex: sample.debugSegmentIndex,
                debugSegmentKind: sample.debugSegmentKind,
                debugSegmentU: sample.debugSegmentU,
                debugRunId: nil,
                debugSupportCase: "R",
                debugSupportLocal: nil
            ))
        }
        return (left, right)
    }

    private static func logRailJumps(label: String, samples: [RailSample], maxItems: Int) {
        guard samples.count >= 2 else {
            print("railsJump \(label) none")
            return
        }
        func debugValue(_ value: Int?) -> String { value.map(String.init) ?? "nil" }
        func debugValue(_ value: Double?) -> String { value.map { formatT($0) } ?? "nil" }
        func debugValue(_ value: String?) -> String { value ?? "nil" }
        func debugPoint(_ point: Point?) -> String {
            guard let point else { return "nil" }
            return "(\(format(point.x)),\(format(point.y)))"
        }
        func railSampleLine(_ sample: RailSample, prevCase: String?) -> String {
            "t=\(formatT(sample.t)) skeletonId=\(debugValue(sample.debugSkeletonId)) skeletonIndex=\(debugValue(sample.debugSkeletonIndex)) segmentIndex=\(debugValue(sample.debugSegmentIndex)) segmentKind=\(debugValue(sample.debugSegmentKind)) u=\(debugValue(sample.debugSegmentU)) prevSupport=\(debugValue(prevCase)) support=\(debugValue(sample.debugSupportCase)) local=\(debugPoint(sample.debugSupportLocal)) world=(\(format(sample.point.x)),\(format(sample.point.y)))"
        }
        var jumps: [RailJump] = []
        jumps.reserveCapacity(samples.count - 1)
        for i in 0..<(samples.count - 1) {
            let a = samples[i]
            let b = samples[i + 1]
            let length = (b.point - a.point).length
            jumps.append(RailJump(index: i, length: length, tA: a.t, tB: b.t, a: a.point, b: b.point))
        }
        let top = jumps.sorted(by: >).prefix(maxItems)
        if top.isEmpty {
            print("railsJump \(label) none")
            return
        }
        print("railsJump \(label) top=\(top.count)")
        for jump in top {
            let a = samples[jump.index]
            let b = samples[jump.index + 1]
            let prevCaseA = jump.index > 0 ? samples[jump.index - 1].debugSupportCase : nil
            let prevCaseB = samples[jump.index].debugSupportCase
            print("railsJump \(label) i=\(jump.index) segLen=\(format(jump.length))")
            print("railsJump \(label) A \(railSampleLine(a, prevCase: prevCaseA))")
            print("railsJump \(label) B \(railSampleLine(b, prevCase: prevCaseB))")
        }
        if let worst = top.first {
            let a = samples[worst.index]
            let b = samples[worst.index + 1]
            print("railsJump \(label) worst normalA=(\(format(a.normal.x)),\(format(a.normal.y))) localA=\(debugPoint(a.debugSupportLocal)) caseA=\(debugValue(a.debugSupportCase)) normalB=(\(format(b.normal.x)),\(format(b.normal.y))) localB=\(debugPoint(b.debugSupportLocal)) caseB=\(debugValue(b.debugSupportCase))")
        }
    }

    private static func containsPoint(_ points: [Point], _ target: Point, epsilon: Double) -> Bool {
        for point in points {
            if (point - target).length <= epsilon {
                return true
            }
        }
        return false
    }

    private static func missingPointCount(points: [Point], within target: [Point], epsilon: Double) -> Int {
        var missing = 0
        for point in points {
            if !containsPoint(target, point, epsilon: epsilon) {
                missing += 1
            }
        }
        return missing
    }

    private static func roundCapArc(center: Point, from: Point, to: Point, faceDir: Point, tolerance: Double, maxDepth: Int, epsilon: Double) -> [Point] {
        let startVec = from - center
        let endVec = to - center
        let startRadius = startVec.length
        let endRadius = endVec.length
        let radius = max(startRadius, endRadius)
        if radius <= epsilon { return [] }
        let startAngle = atan2(startVec.y, startVec.x)
        let endAngle = atan2(endVec.y, endVec.x)
        let face = faceDir.normalized() ?? faceDir
        let ccwDelta = normalizedAngle(endAngle - startAngle)
        let cwDelta = ccwDelta - (2.0 * .pi)
        let ccwMid = startAngle + ccwDelta * 0.5
        let cwMid = startAngle + cwDelta * 0.5
        let ccwDot = Point(x: cos(ccwMid), y: sin(ccwMid)).dot(face)
        let cwDot = Point(x: cos(cwMid), y: sin(cwMid)).dot(face)
        let useDelta = (cwDot > ccwDot + epsilon) ? cwDelta : ccwDelta
        let endAngleAdjusted = startAngle + useDelta

        var points: [Point] = []
        points.reserveCapacity(16)
        points.append(from)
        func recurse(_ a: Double, _ b: Double, depth: Int) {
            let pa = Point(x: center.x + cos(a) * radius, y: center.y + sin(a) * radius)
            let pb = Point(x: center.x + cos(b) * radius, y: center.y + sin(b) * radius)
            let mid = 0.5 * (a + b)
            let pm = Point(x: center.x + cos(mid) * radius, y: center.y + sin(mid) * radius)
            let chordMid = Point(
                x: ScalarMath.lerp(pa.x, pb.x, 0.5),
                y: ScalarMath.lerp(pa.y, pb.y, 0.5)
            )
            let error = (pm - chordMid).length
            if error <= tolerance || depth >= maxDepth {
                points.append(pb)
                return
            }
            recurse(a, mid, depth: depth + 1)
            recurse(mid, b, depth: depth + 1)
        }
        recurse(startAngle, endAngleAdjusted, depth: 0)
        return points
    }

    private static func normalizedAngle(_ value: Double) -> Double {
        var result = value
        let twoPi = 2.0 * .pi
        while result < 0 { result += twoPi }
        while result >= twoPi { result -= twoPi }
        return result
    }

    private static func trimArcPoints(_ points: [Point]) -> [Point] {
        if points.count <= 2 { return [] }
        return Array(points.dropFirst().dropLast())
    }

    private static func fullDisk(center: Point, radius: Double, segments: Int) -> Ring {
        let steps = max(12, segments)
        var points: [Point] = []
        points.reserveCapacity(steps + 1)
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let a = t * (.pi * 2.0)
            let p = Point(x: center.x + cos(a) * radius, y: center.y + sin(a) * radius)
            points.append(p)
        }
        return closeRingIfNeeded(points)
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.6f", value)
    }

    private struct JunctionPatchResult {
        let ring: Ring
        let controlPoints: [Point]
        let diagnostic: JunctionDiagnostic
    }

    private struct JunctionClipResult {
        let ring: Ring?
        let applied: Bool
        let reason: String
    }

    private enum JunctionInvalidReason: String {
        case containsNaN
        case degenerate
        case areaTooSmall
        case selfIntersect
        case railsCross
        case orientationFlip
        case unknown
    }

    private static func junctionPatch(from context: JunctionContext, epsilon: Double, verbose: Bool) -> JunctionPatchResult? {
        let leftA = leftRailPoint(sample: context.a, epsilon: epsilon)
        let rightA = rightRailPoint(sample: context.a, epsilon: epsilon)
        let leftB = leftRailPoint(sample: context.b, epsilon: epsilon)
        let rightB = rightRailPoint(sample: context.b, epsilon: epsilon)

        let leftPrev = context.prev.map { leftRailPoint(sample: $0, epsilon: epsilon) }
        let rightPrev = context.prev.map { rightRailPoint(sample: $0, epsilon: epsilon) }
        let leftNext = context.next.map { leftRailPoint(sample: $0, epsilon: epsilon) }
        let rightNext = context.next.map { rightRailPoint(sample: $0, epsilon: epsilon) }

        let fallbackA = Point(x: cos(context.a.tangentAngle), y: sin(context.a.tangentAngle))
        let fallbackB = Point(x: cos(context.b.tangentAngle), y: sin(context.b.tangentAngle))

        let dLeftA = railTangent(prev: leftPrev, current: leftA, next: leftB, fallback: fallbackA, epsilon: epsilon)
        let dLeftB = railTangent(prev: leftA, current: leftB, next: leftNext, fallback: fallbackB, epsilon: epsilon)
        let dRightA = railTangent(prev: rightPrev, current: rightA, next: rightB, fallback: fallbackA, epsilon: epsilon)
        let dRightB = railTangent(prev: rightA, current: rightB, next: rightNext, fallback: fallbackB, epsilon: epsilon)

        let avgWidth = max(epsilon, 0.5 * (context.a.width + context.b.width))
        let minHandle = max(0.25, avgWidth * 0.02)
        let maxHandle = max(minHandle, avgWidth * 0.6)
        let baseHandle = clamp(avgWidth * 0.25, min: minHandle, max: maxHandle)
        let span = min((leftB - leftA).length, (rightB - rightA).length)
        let spanLimit = max(minHandle, span * 0.35)
        let handleBase = min(baseHandle, spanLimit)
        let handleCandidates = [handleBase, handleBase * 0.5, handleBase * 0.25, handleBase * 0.125].filter { $0 >= minHandle * 0.1 }

        let hasNeighbors = context.prev != nil && context.next != nil
        let fallbackReason = hasNeighbors ? "invalidPatch" : "missingNeighbors"
        var lastReason: JunctionInvalidReason = .unknown
        var lastHandle = handleBase

        if verbose {
            print("junction joinIndex=\(context.joinIndex) tA=\(format(context.a.t)) tB=\(format(context.b.t)) handleBase=\(format(handleBase)) span=\(format(span)) minHandle=\(format(minHandle))")
            print("junction-left L_A=(\(format(leftA.x)),\(format(leftA.y))) L_B=(\(format(leftB.x)),\(format(leftB.y))) dL_A=(\(format(dLeftA.x)),\(format(dLeftA.y))) dL_B=(\(format(dLeftB.x)),\(format(dLeftB.y)))")
            print("junction-right R_A=(\(format(rightA.x)),\(format(rightA.y))) R_B=(\(format(rightB.x)),\(format(rightB.y))) dR_A=(\(format(dRightA.x)),\(format(dRightA.y))) dR_B=(\(format(dRightB.x)),\(format(dRightB.y)))")
        }

        for handle in handleCandidates {
            lastHandle = handle
            let leftC1 = leftA + dLeftA * handle
            let leftC2 = leftB - dLeftB * handle
            let rightC1 = rightB + (dRightB * -1.0) * handle
            let rightC2 = rightA - (dRightA * -1.0) * handle

            let leftCurve = sampleCubic(p0: leftA, p1: leftC1, p2: leftC2, p3: leftB, segments: 12)
            let rightCurve = sampleCubic(p0: rightB, p1: rightC1, p2: rightC2, p3: rightA, segments: 12)

            var ring = leftCurve + rightCurve
            ring = removeTinyEdges(removeConsecutiveDuplicates(ring, tol: epsilon), epsilon: epsilon)
            ring = closeRingIfNeeded(ring, tol: epsilon)
            let reason = validateBridgePatch(
                ring: ring,
                leftCurve: leftCurve,
                rightCurve: rightCurve,
                epsilon: epsilon
            )
            if reason == nil {
                let controls = [leftC1, leftC2, rightC1, rightC2]
                let diagnostic = JunctionDiagnostic(
                    joinIndex: context.joinIndex,
                    tA: context.a.t,
                    tB: context.b.t,
                    usedBridge: true,
                    reason: "ok",
                    clipped: false,
                    clipReason: "none"
                )
                if verbose {
                    print("junction joinIndex=\(context.joinIndex) tA=\(format(context.a.t)) tB=\(format(context.b.t)) used=bridge reason=ok")
                    print("junction-left L_A=(\(format(leftA.x)),\(format(leftA.y))) L_B=(\(format(leftB.x)),\(format(leftB.y))) dL_A=(\(format(dLeftA.x)),\(format(dLeftA.y))) dL_B=(\(format(dLeftB.x)),\(format(dLeftB.y))) C1=(\(format(leftC1.x)),\(format(leftC1.y))) C2=(\(format(leftC2.x)),\(format(leftC2.y)))")
                    print("junction-right R_A=(\(format(rightA.x)),\(format(rightA.y))) R_B=(\(format(rightB.x)),\(format(rightB.y))) dR_A=(\(format(dRightA.x)),\(format(dRightA.y))) dR_B=(\(format(dRightB.x)),\(format(dRightB.y))) C1=(\(format(rightC2.x)),\(format(rightC2.y))) C2=(\(format(rightC1.x)),\(format(rightC1.y)))")
                }
                return JunctionPatchResult(ring: ring, controlPoints: controls, diagnostic: diagnostic)
            } else {
                lastReason = reason ?? .unknown
                if verbose {
                    print("junction-handle handle=\(format(handle)) invalid=\(lastReason.rawValue)")
                }
            }
        }

        let chordLeft = (leftB - leftA).normalized(epsilon: epsilon)
        let chordRight = (rightB - rightA).normalized(epsilon: epsilon)
        if let chordLeft, let chordRight {
            let chordHandle = max(minHandle, min(handleBase, span * 0.35))
            let leftC1 = leftA + chordLeft * chordHandle
            let leftC2 = leftB - chordLeft * chordHandle
            let rightC1 = rightB + (chordRight * -1.0) * chordHandle
            let rightC2 = rightA - (chordRight * -1.0) * chordHandle

            let leftCurve = sampleCubic(p0: leftA, p1: leftC1, p2: leftC2, p3: leftB, segments: 12)
            let rightCurve = sampleCubic(p0: rightB, p1: rightC1, p2: rightC2, p3: rightA, segments: 12)
            var ring = leftCurve + rightCurve
            ring = removeTinyEdges(removeConsecutiveDuplicates(ring, tol: epsilon), epsilon: epsilon)
            ring = closeRingIfNeeded(ring, tol: epsilon)
            let reason = validateBridgePatch(
                ring: ring,
                leftCurve: leftCurve,
                rightCurve: rightCurve,
                epsilon: epsilon
            )
            if reason == nil {
                let controls = [leftC1, leftC2, rightC1, rightC2]
                let diagnostic = JunctionDiagnostic(
                    joinIndex: context.joinIndex,
                    tA: context.a.t,
                    tB: context.b.t,
                    usedBridge: true,
                    reason: "okChord",
                    clipped: false,
                    clipReason: "none"
                )
                if verbose {
                    print("junction joinIndex=\(context.joinIndex) tA=\(format(context.a.t)) tB=\(format(context.b.t)) used=bridge reason=okChord")
                }
                return JunctionPatchResult(ring: ring, controlPoints: controls, diagnostic: diagnostic)
            } else {
                lastReason = reason ?? .unknown
                if verbose {
                    print("junction-chord invalid=\(lastReason.rawValue) handle=\(format(chordHandle))")
                }
            }
        }

        let quad = closeRingIfNeeded([leftA, leftB, rightB, rightA], tol: epsilon)
        if quad.count >= 4, abs(signedArea(quad)) > epsilon, !ringSelfIntersects(quad, epsilon: epsilon) {
            let diagnostic = JunctionDiagnostic(
                joinIndex: context.joinIndex,
                tA: context.a.t,
                tB: context.b.t,
                usedBridge: true,
                reason: "quad",
                clipped: false,
                clipReason: "none"
            )
            if verbose {
                print("junction joinIndex=\(context.joinIndex) tA=\(format(context.a.t)) tB=\(format(context.b.t)) used=bridge reason=quad")
            }
            return JunctionPatchResult(ring: quad, controlPoints: [], diagnostic: diagnostic)
        }

        let reason = hasNeighbors ? fallbackReason : "missingNeighbors"
        if verbose {
            print("junction joinIndex=\(context.joinIndex) tA=\(format(context.a.t)) tB=\(format(context.b.t)) used=hull reason=\(reason)")
            print("junction-invalid reason=\(lastReason.rawValue) handle=\(format(lastHandle))")
        }
        return convexHullPatch(from: context, epsilon: epsilon, reason: reason, verbose: verbose)
    }

    private static func validateBridgePatch(
        ring: Ring,
        leftCurve: [Point],
        rightCurve: [Point],
        epsilon: Double
    ) -> JunctionInvalidReason? {
        if ring.contains(where: { !$0.x.isFinite || !$0.y.isFinite }) { return .containsNaN }
        if ring.count < 4 { return .degenerate }
        let area = abs(signedArea(ring))
        if area <= epsilon { return .areaTooSmall }
        if ringSelfIntersects(ring, epsilon: epsilon) { return .selfIntersect }
        if railsCross(leftCurve: leftCurve, rightCurve: rightCurve, epsilon: epsilon) { return .railsCross }
        return nil
    }

    private static func railsCross(leftCurve: [Point], rightCurve: [Point], epsilon: Double) -> Bool {
        guard leftCurve.count >= 2, rightCurve.count >= 2 else { return false }
        let leftSegments = segmentsFromPolyline(leftCurve)
        let rightSegments = segmentsFromPolyline(rightCurve)
        for ls in leftSegments {
            for rs in rightSegments {
                switch intersect(ls, rs, tol: epsilon) {
                case .proper, .collinearOverlap:
                    return true
                case .endpoint, .none:
                    continue
                }
            }
        }
        return false
    }

    private static func segmentsFromPolyline(_ points: [Point]) -> [Segment] {
        guard points.count >= 2 else { return [] }
        var segments: [Segment] = []
        segments.reserveCapacity(points.count - 1)
        for i in 0..<(points.count - 1) {
            let a = points[i]
            let b = points[i + 1]
            if a != b {
                segments.append(Segment(a: a, b: b))
            }
        }
        return segments
    }

    private static func convexHullPatch(from context: JunctionContext, epsilon: Double, reason: String, verbose: Bool) -> JunctionPatchResult? {
        let cornersA = rectangleCornersWorld(
            center: context.a.point,
            widthLeft: context.a.widthLeft,
            widthRight: context.a.widthRight,
            height: context.a.height,
            thetaWorld: context.a.effectiveRotation
        )
        let cornersB = rectangleCornersWorld(
            center: context.b.point,
            widthLeft: context.b.widthLeft,
            widthRight: context.b.widthRight,
            height: context.b.height,
            thetaWorld: context.b.effectiveRotation
        )
        let hull = convexHull(points: cornersA + cornersB, epsilon: epsilon)
        guard hull.count >= 3 else { return nil }
        let area = signedArea(hull)
        if abs(area) <= epsilon { return nil }
        let cleaned = removeTinyEdges(removeConsecutiveDuplicates(hull, tol: epsilon), epsilon: epsilon)
        let closed = closeRingIfNeeded(cleaned, tol: epsilon)
        if closed.count < 4 { return nil }
        let diagnostic = JunctionDiagnostic(
            joinIndex: context.joinIndex,
            tA: context.a.t,
            tB: context.b.t,
            usedBridge: false,
            reason: reason,
            clipped: false,
            clipReason: "none"
        )
        if verbose {
            print("junction-hull joinIndex=\(context.joinIndex) area=\(format(abs(area))) points=\(closed.count)")
        }
        return JunctionPatchResult(ring: closed, controlPoints: [], diagnostic: diagnostic)
    }

    private static func buildJunctionCorridor(
        samples: [Sample],
        leftRail: [Point],
        rightRail: [Point],
        context: JunctionContext,
        window: Int,
        epsilon: Double
    ) -> Ring? {
        guard samples.count == leftRail.count, samples.count == rightRail.count, samples.count > 1 else { return nil }
        guard let indexA = nearestSampleIndex(samples, target: context.a),
              let indexB = nearestSampleIndex(samples, target: context.b) else { return nil }
        let minIndex = max(0, min(indexA, indexB) - window)
        let maxIndex = min(samples.count - 1, max(indexA, indexB) + window)
        guard maxIndex > minIndex else { return nil }
        let leftSlice = Array(leftRail[minIndex...maxIndex])
        let rightSlice = Array(rightRail[minIndex...maxIndex].reversed())
        var corridor = leftSlice + rightSlice
        corridor = removeTinyEdges(removeConsecutiveDuplicates(corridor, tol: epsilon), epsilon: epsilon)
        corridor = closeRingIfNeeded(corridor, tol: epsilon)
        if corridor.count < 4 { return nil }
        if abs(signedArea(corridor)) <= epsilon { return nil }
        return corridor
    }

    private static func nearestSampleIndex(_ samples: [Sample], target: Sample) -> Int? {
        guard !samples.isEmpty else { return nil }
        var bestIndex = 0
        var bestDelta = abs(samples[0].t - target.t)
        for i in 1..<samples.count {
            let delta = abs(samples[i].t - target.t)
            if delta < bestDelta {
                bestDelta = delta
                bestIndex = i
            }
        }
        return bestIndex
    }

    private static func clipJunctionPatch(
        ring: Ring,
        corridor: Ring,
        context: JunctionContext,
        epsilon: Double,
        verbose: Bool
    ) -> JunctionClipResult {
        guard let patchBounds = boundingBox(ring), let corridorBounds = boundingBox(corridor) else {
            return JunctionClipResult(ring: nil, applied: false, reason: "invalidBounds")
        }
        let minX = min(patchBounds.min.x, corridorBounds.min.x)
        let minY = min(patchBounds.min.y, corridorBounds.min.y)
        let maxX = max(patchBounds.max.x, corridorBounds.max.x)
        let maxY = max(patchBounds.max.y, corridorBounds.max.y)
        let width = maxX - minX
        let height = maxY - minY
        guard width.isFinite, height.isFinite, width > 0.0, height > 0.0 else {
            return JunctionClipResult(ring: nil, applied: false, reason: "invalidBounds")
        }
        let minDim = min(width, height)
        let pixelSize = max(epsilon, minDim / 64.0)
        let padding = pixelSize * 2.0
        let bounds = Rasterizer.RasterBounds(
            minX: minX - padding,
            minY: minY - padding,
            maxX: maxX + padding,
            maxY: maxY + padding
        )
        let patchGrid = Rasterizer.rasterizeFixed(polygons: [Polygon(outer: ring, holes: [])], bounds: bounds, pixelSize: pixelSize)
        let corridorGrid = Rasterizer.rasterizeFixed(polygons: [Polygon(outer: corridor, holes: [])], bounds: bounds, pixelSize: pixelSize)
        var intersectGrid = patchGrid.grid
        for i in 0..<intersectGrid.data.count {
            intersectGrid.data[i] = (patchGrid.grid.data[i] != 0 && corridorGrid.grid.data[i] != 0) ? 1 : 0
        }
        let contours = ContourTracer.trace(grid: intersectGrid, origin: patchGrid.origin, pixelSize: patchGrid.pixelSize)
        guard let clipped = largestRing(contours) else {
            let quad = closeRingIfNeeded([leftRailPoint(sample: context.a, epsilon: epsilon),
                                          leftRailPoint(sample: context.b, epsilon: epsilon),
                                          rightRailPoint(sample: context.b, epsilon: epsilon),
                                          rightRailPoint(sample: context.a, epsilon: epsilon)], tol: epsilon)
            if verbose {
                print("junction-clip result=empty fallback=quad joinIndex=\(context.joinIndex)")
            }
            return JunctionClipResult(ring: quad, applied: false, reason: "emptyIntersection")
        }
        if verbose {
            print("junction-clip applied joinIndex=\(context.joinIndex) pixelSize=\(format(pixelSize))")
        }
        return JunctionClipResult(ring: clipped, applied: true, reason: "ok")
    }

    private static func largestRing(_ rings: [Ring]) -> Ring? {
        guard !rings.isEmpty else { return nil }
        var best = rings[0]
        var bestArea = abs(signedArea(best))
        for ring in rings.dropFirst() {
            let area = abs(signedArea(ring))
            if area > bestArea {
                best = ring
                bestArea = area
            }
        }
        return best
    }

    private static func railTangent(prev: Point?, current: Point, next: Point?, fallback: Point, epsilon: Double) -> Point {
        if let prev {
            if let dir = (current - prev).normalized(epsilon: epsilon) { return dir }
        }
        if let next {
            if let dir = (next - current).normalized(epsilon: epsilon) { return dir }
        }
        return fallback.normalized(epsilon: epsilon) ?? Point(x: 1.0, y: 0.0)
    }

    private static func clamp(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
        if value < minValue { return minValue }
        if value > maxValue { return maxValue }
        return value
    }

    private static func sampleCubic(p0: Point, p1: Point, p2: Point, p3: Point, segments: Int) -> [Point] {
        let steps = max(2, segments)
        var points: [Point] = []
        points.reserveCapacity(steps + 1)
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let mt = 1.0 - t
            let mt2 = mt * mt
            let t2 = t * t
            let a = mt2 * mt
            let b = 3.0 * mt2 * t
            let c = 3.0 * mt * t2
            let d = t2 * t
            let point = Point(
                x: p0.x * a + p1.x * b + p2.x * c + p3.x * d,
                y: p0.y * a + p1.y * b + p2.y * c + p3.y * d
            )
            points.append(point)
        }
        return points
    }

    private static func convexHull(points: [Point], epsilon: Double) -> [Point] {
        guard points.count > 1 else { return points }
        let sorted = points.sorted { a, b in
            if a.x != b.x { return a.x < b.x }
            return a.y < b.y
        }
        var unique: [Point] = []
        unique.reserveCapacity(sorted.count)
        for point in sorted {
            if let last = unique.last, (point - last).length <= epsilon {
                continue
            }
            unique.append(point)
        }
        guard unique.count >= 2 else { return unique }

        func cross(_ o: Point, _ a: Point, _ b: Point) -> Double {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }

        var lower: [Point] = []
        for p in unique {
            while lower.count >= 2, cross(lower[lower.count - 2], lower[lower.count - 1], p) <= epsilon {
                lower.removeLast()
            }
            lower.append(p)
        }
        var upper: [Point] = []
        for p in unique.reversed() {
            while upper.count >= 2, cross(upper[upper.count - 2], upper[upper.count - 1], p) <= epsilon {
                upper.removeLast()
            }
            upper.append(p)
        }
        lower.removeLast()
        upper.removeLast()
        var hull = lower + upper
        if hull.count < 3 { return hull }
        if signedArea(hull) < 0 {
            hull.reverse()
        }
        var startIndex = 0
        for i in 1..<hull.count {
            let a = hull[i]
            let b = hull[startIndex]
            if a.x < b.x || (a.x == b.x && a.y < b.y) {
                startIndex = i
            }
        }
        if startIndex > 0 {
            hull = Array(hull[startIndex...] + hull[..<startIndex])
        }
        return hull
    }

    private static func ringSelfIntersects(_ ring: Ring, epsilon: Double) -> Bool {
        let segmentsList = segments(from: ring, ensureClosed: true)
        guard segmentsList.count >= 4 else { return false }
        for i in 0..<segmentsList.count {
            let s1 = segmentsList[i]
            for j in (i + 1)..<segmentsList.count {
                if abs(i - j) <= 1 { continue }
                if i == 0 && j == segmentsList.count - 1 { continue }
                let s2 = segmentsList[j]
                switch intersect(s1, s2, tol: epsilon) {
                case .none:
                    continue
                case .endpoint:
                    continue
                case .proper, .collinearOverlap:
                    return true
                }
            }
        }
        return false
    }

    private static func firstSelfIntersection(_ ring: Ring, epsilon: Double) -> (i: Int, j: Int, s1: Segment, s2: Segment)? {
        let segmentsList = segments(from: ring, ensureClosed: true)
        guard segmentsList.count >= 4 else { return nil }
        for i in 0..<segmentsList.count {
            let s1 = segmentsList[i]
            for j in (i + 1)..<segmentsList.count {
                if abs(i - j) <= 1 { continue }
                if i == 0 && j == segmentsList.count - 1 { continue }
                let s2 = segmentsList[j]
                switch intersect(s1, s2, tol: epsilon) {
                case .none, .endpoint:
                    continue
                case .proper, .collinearOverlap:
                    return (i: i, j: j, s1: s1, s2: s2)
                }
            }
        }
        return nil
    }
}
