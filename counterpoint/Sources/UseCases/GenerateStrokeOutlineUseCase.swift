import Foundation
import Domain

public struct GenerateStrokeOutlineUseCase {
    public static var logSampleEvaluation = false
    private static var didLogSampleEvaluation = false
    public static var logLaneOffsetSamples = false
    public static var logStamping = false
    public static var logAdaptiveSampling = false
    public static var logRailsDebug = false
    public static var logRailsDebugStart: Int? = nil
    public static var lastRailsDebugSamples: (left: [DirectSilhouetteTracer.RailSample], right: [DirectSilhouetteTracer.RailSample])? = nil
    public static var lastRailsDebugSamplesPreRefine: (left: [DirectSilhouetteTracer.RailSample], right: [DirectSilhouetteTracer.RailSample])? = nil
    public static var lastRailsDebugRuns: (left: [[Point]], right: [[Point]])? = nil
    public static var lastRailsDebugRing: Ring? = nil
    private static var didLogStamping = false

    private let sampler: PathSampling
    private let evaluator: ParamEvaluating
    private let unioner: PolygonUnioning

    private struct SampleSeed {
        let uGlobal: Double
        let uLocal: Double
        let basePoint: Point
        let tangentAngle: Double
        let progressHint: Double
        let segmentIndex: Int?
        let segmentU: Double?
        let segmentKind: String?
        let skeletonIndex: Int?
        let skeletonId: String?
    }

    public struct ConcatenatedSamples {
        public let samples: [Sample]
        public let junctionPairs: [(Int, Int)]
    }

    public init(sampler: PathSampling, evaluator: ParamEvaluating, unioner: PolygonUnioning) {
        self.sampler = sampler
        self.evaluator = evaluator
        self.unioner = unioner
    }

    public func generateOutline(for spec: StrokeSpec, includeBridges: Bool = true) throws -> PolygonSet {
        GenerateStrokeOutlineUseCase.lastRailsDebugSamples = nil
        GenerateStrokeOutlineUseCase.lastRailsDebugSamplesPreRefine = nil
        GenerateStrokeOutlineUseCase.lastRailsDebugRuns = nil
        GenerateStrokeOutlineUseCase.lastRailsDebugRing = nil
        let samples = generateSamples(for: spec)
        if GenerateStrokeOutlineUseCase.logStamping, !GenerateStrokeOutlineUseCase.didLogStamping, !samples.isEmpty {
            GenerateStrokeOutlineUseCase.didLogStamping = true
            logStampSample(samples.first!, label: "first", spec: spec)
            if samples.count > 1 {
                logStampSample(samples[samples.count - 1], label: "last", spec: spec)
            }
        }
        if (spec.output?.outlineMethod ?? .union) == .rails, spec.counterpointShape == .rectangle {
            return railOutline(samples: samples, spec: spec)
        }
        let stamping = CounterpointStamping()
        let rings = samples.map { stamping.ring(for: $0, shape: spec.counterpointShape) }
        let capRings = capRings(for: samples, capStyle: spec.capStyle)
        let joinRings = joinRings(for: samples, joinStyle: spec.joinStyle)
        let allRings: [Ring]
        if includeBridges {
            let bridges = try bridgeRings(between: rings)
            allRings = rings + bridges + capRings + joinRings
        } else {
            allRings = rings + capRings + joinRings
        }
        return try unioner.union(subjectRings: allRings)
    }

    private func railOutline(samples: [Sample], spec: StrokeSpec) -> PolygonSet {
        let policy = samplingPolicy(for: spec)
        let polyline = sampler.makePolyline(path: spec.path, tolerance: policy.flattenTolerance)
        let translation = outputTranslation(for: spec, polyline: polyline)
        let flat = flattenPathWithU(path: spec.path, tolerance: policy.flattenTolerance)
        let cumulative = cumulativeLengths(for: flat)
        let totalLength = cumulative.last ?? 0.0
        let segmentCount = max(1, spec.path.segments.count)
        let sampleProvider: DirectSilhouetteTracer.DirectSilhouetteSampleProvider = { progress in
            guard !spec.path.segments.isEmpty, !flat.isEmpty else { return nil }
            let clamped = ScalarMath.clamp01(progress)
            let uData = mapProgressToU(progress: clamped, flat: flat, cumulative: cumulative, totalLength: totalLength)
            let segment = spec.path.segments[uData.segmentIndex]
            let basePoint = segment.point(at: uData.u)
            let tangentAngle = segment.safeTangentAngle(at: uData.u)
            let uGeom = (Double(uData.segmentIndex) + uData.u) / Double(segmentCount)
            return makeSampleFromBase(
                uGeom: uGeom,
                uGrid: uData.u,
                progress: clamped,
                basePoint: basePoint,
                tangentAngle: tangentAngle,
                spec: spec,
                translation: translation
            )
        }
        let direct = DirectSilhouetteTracer.trace(
            samples: samples,
            capStyle: spec.capStyle,
            railTolerance: policy.railTolerance,
            railChordTolerance: policy.railChordTolerance,
            railMaxSegmentLength: policy.railMaxSegmentLength,
            railMaxTurnAngleDegrees: policy.railMaxTurnAngleDegrees,
            railSplitThreshold: 20.0,
            railJumpsSource: .selected,
            options: DirectSilhouetteOptions(railRefineMaxDepth: policy.maxRecursionDepth, railRefineMinStep: policy.minParamStep),
            sampleProvider: sampleProvider,
            verbose: GenerateStrokeOutlineUseCase.logStamping,
            railsDebug: GenerateStrokeOutlineUseCase.logRailsDebug,
            railsDebugStart: GenerateStrokeOutlineUseCase.logRailsDebugStart
        )
        GenerateStrokeOutlineUseCase.lastRailsDebugSamples = (direct.leftRailSamples, direct.rightRailSamples)
        GenerateStrokeOutlineUseCase.lastRailsDebugSamplesPreRefine = (direct.leftRailSamplesPreRefine, direct.rightRailSamplesPreRefine)
        GenerateStrokeOutlineUseCase.lastRailsDebugRuns = (direct.leftRailRuns, direct.rightRailRuns)
        GenerateStrokeOutlineUseCase.lastRailsDebugRing = direct.outline
        if direct.outlineSelfIntersects {
            if GenerateStrokeOutlineUseCase.logStamping {
                FileHandle.standardError.write(Data("rails-fallback reason=self-intersection\n".utf8))
            }
            let stamping = CounterpointStamping()
            let rings = samples.map { stamping.ring(for: $0, shape: spec.counterpointShape) }
            let capRings = capRings(for: samples, capStyle: spec.capStyle)
            let joinRings = joinRings(for: samples, joinStyle: spec.joinStyle)
            let bridges = (try? bridgeRings(between: rings)) ?? []
            let allRings = rings + bridges + capRings + joinRings
            if let fallback = try? unioner.union(subjectRings: allRings) {
                return fallback
            }
        }
        var polygons: PolygonSet = []
        if !direct.outline.isEmpty {
            polygons.append(Polygon(outer: direct.outline))
        }
        for patch in direct.junctionPatches {
            polygons.append(Polygon(outer: patch))
        }
        return polygons
    }

    public func generateSamples(for spec: StrokeSpec) -> [Sample] {
        let policy = samplingPolicy(for: spec)
        let maxSpacing = spec.sampling.maxSpacing ?? spec.sampling.baseSpacing
        let polyline = sampler.makePolyline(path: spec.path, tolerance: policy.flattenTolerance)
        let translation = outputTranslation(for: spec, polyline: polyline)
        let samples = generateSamples(
            for: spec,
            polyline: polyline,
            translation: translation,
            policy: policy,
            maxSpacing: maxSpacing
        )
        return applyLaneOffsetContinuity(samples: samples, spec: spec)
    }

    public func generateConcatenatedSamples(for spec: StrokeSpec, paths: [BezierPath]) -> [Sample] {
        return generateConcatenatedSamplesWithJunctions(for: spec, paths: paths).samples
    }

    public func generateConcatenatedSamplesWithJunctions(
        for spec: StrokeSpec,
        paths: [BezierPath],
        debugSkeletonIds: [String]? = nil
    ) -> ConcatenatedSamples {
        guard !paths.isEmpty else { return ConcatenatedSamples(samples: [], junctionPairs: []) }
        let policy = samplingPolicy(for: spec)
        let maxSpacing = spec.sampling.maxSpacing ?? spec.sampling.baseSpacing
        let translationPolyline = sampler.makePolyline(path: paths[0], tolerance: policy.flattenTolerance)
        let translation = outputTranslation(for: spec, polyline: translationPolyline)

        struct ConcatSeed {
            let uGeom: Double
            let uGrid: Double
            let basePoint: Point
            let tangentAngle: Double
            let centerPoint: Point
            let debugSkeletonIndex: Int?
            let debugSkeletonId: String?
            let debugSegmentIndex: Int?
            let debugSegmentU: Double?
            let debugSegmentKind: String?
        }

        let includeDebug = GenerateStrokeOutlineUseCase.logRailsDebug
        var seeds: [ConcatSeed] = []
        var junctionPairs: [(Int, Int)] = []
        var previousSegmentLastIndex: Int?
        for (index, path) in paths.enumerated() {
            let polyline = sampler.makePolyline(path: path, tolerance: policy.flattenTolerance)
            let pathDomain = includeDebug ? PathDomain(path: path, samplesPerSegment: 24) : nil
            let localSamples = generateSamples(
                for: spec,
                polyline: polyline,
                translation: translation,
                policy: policy,
                maxSpacing: maxSpacing
            )
            let adjustedSamples = applyLaneOffsetContinuity(samples: localSamples, spec: spec)
            if adjustedSamples.isEmpty { continue }
            let trimmedSamples = (index == paths.count - 1) ? adjustedSamples : Array(adjustedSamples.dropLast())
            let firstIndexInSegment = seeds.count
            let skeletonId = includeDebug ? (debugSkeletonIds?.indices.contains(index) == true ? debugSkeletonIds?[index] : nil) : nil
            for sample in trimmedSamples {
                let basePoint = polyline.point(at: sample.uGeom)
                let tangentAngle = polyline.tangentAngle(at: sample.uGeom, fallbackAngle: sample.tangentAngle)
                let debugSegment: PathDomain.Sample?
                if let pathDomain {
                    debugSegment = pathDomain.evalAtS(sample.uGeom, path: path)
                } else {
                    debugSegment = nil
                }
                let debugSegmentIndex = debugSegment?.segmentIndex
                let debugSegmentU = debugSegment?.t
                seeds.append(ConcatSeed(
                    uGeom: sample.uGeom,
                    uGrid: sample.uGrid,
                    basePoint: basePoint,
                    tangentAngle: tangentAngle,
                    centerPoint: sample.point,
                    debugSkeletonIndex: includeDebug ? index : nil,
                    debugSkeletonId: skeletonId,
                    debugSegmentIndex: debugSegmentIndex,
                    debugSegmentU: debugSegmentU,
                    debugSegmentKind: debugSegmentIndex == nil ? nil : "cubic"
                ))
            }
            if !trimmedSamples.isEmpty {
                let lastIndexInSegment = seeds.count - 1
                if let previous = previousSegmentLastIndex {
                    junctionPairs.append((previous, firstIndexInSegment))
                }
                previousSegmentLastIndex = lastIndexInSegment
            }
        }

        guard !seeds.isEmpty else { return ConcatenatedSamples(samples: [], junctionPairs: []) }
        if seeds.count == 1 {
            let seed = seeds[0]
            let samples = applyLaneOffsetContinuity(samples: [
                makeSampleFromBase(
                    uGeom: seed.uGeom,
                    uGrid: seed.uGrid,
                    progress: 0.0,
                    basePoint: seed.basePoint,
                    tangentAngle: seed.tangentAngle,
                    spec: spec,
                    translation: translation,
                    debugSkeletonIndex: seed.debugSkeletonIndex,
                    debugSkeletonId: seed.debugSkeletonId,
                    debugSegmentIndex: seed.debugSegmentIndex,
                    debugSegmentKind: seed.debugSegmentKind,
                    debugSegmentU: seed.debugSegmentU
                )
            ], spec: spec)
            return ConcatenatedSamples(samples: samples, junctionPairs: [])
        }

        var cumulative: [Double] = []
        cumulative.reserveCapacity(seeds.count)
        cumulative.append(0.0)
        var total = 0.0
        for index in 1..<seeds.count {
            total += (seeds[index].centerPoint - seeds[index - 1].centerPoint).length
            cumulative.append(total)
        }
        let denom = max(1.0e-9, total)
        var samples: [Sample] = []
        samples.reserveCapacity(seeds.count)
        for (index, seed) in seeds.enumerated() {
            let progress = cumulative[index] / denom
            let sample = makeSampleFromBase(
                uGeom: seed.uGeom,
                uGrid: seed.uGrid,
                progress: progress,
                basePoint: seed.basePoint,
                tangentAngle: seed.tangentAngle,
                spec: spec,
                translation: translation,
                debugSkeletonIndex: seed.debugSkeletonIndex,
                debugSkeletonId: seed.debugSkeletonId,
                debugSegmentIndex: seed.debugSegmentIndex,
                debugSegmentKind: seed.debugSegmentKind,
                debugSegmentU: seed.debugSegmentU
            )
            samples.append(sample)
        }
        let adjusted = applyLaneOffsetContinuity(samples: samples, spec: spec)
        return ConcatenatedSamples(samples: adjusted, junctionPairs: junctionPairs)
    }

    private func generateSamples(
        for spec: StrokeSpec,
        polyline: PathPolyline,
        translation: Point,
        policy: SamplingPolicy,
        maxSpacing: Double
    ) -> [Sample] {
        switch spec.sampling.mode {
        case .adaptive:
            guard let start = makeSampleAtU(0.0, progress: 0.0, spec: spec, polyline: polyline, translation: translation, fallbackTangent: nil),
                  let end = makeSampleAtU(1.0, progress: 1.0, spec: spec, polyline: polyline, translation: translation, fallbackTangent: start.tangentAngle) else {
                return []
            }
            let samples = adaptiveSamples(spec: spec, polyline: polyline, policy: policy, translation: translation, start: start, end: end)
            let seeds = samples.map { sample -> SampleSeed in
                let basePoint = polyline.point(at: sample.uGeom)
                let tangentAngle = polyline.tangentAngle(at: sample.uGeom, fallbackAngle: sample.tangentAngle)
                return SampleSeed(
                    uGlobal: sample.uGeom,
                    uLocal: sample.uGrid,
                    basePoint: basePoint,
                    tangentAngle: tangentAngle,
                    progressHint: sample.t,
                    segmentIndex: nil,
                    segmentU: nil,
                    segmentKind: nil,
                    skeletonIndex: nil,
                    skeletonId: nil
                )
            }
            let spacedSeeds = enforceMaxSpacing(seeds: seeds, maxSpacing: maxSpacing)
            return remapSeedsForProgress(seeds: spacedSeeds, spec: spec, polyline: polyline, translation: translation)
        case .keyframeGrid:
            return keyframeGridSamples(spec: spec, polyline: polyline, translation: translation, maxSpacing: maxSpacing)
        }
    }

    private func makeSampleAtU(_ u: Double, progress: Double, spec: StrokeSpec, polyline: PathPolyline, translation: Point, fallbackTangent: Double?) -> Sample? {
        if GenerateStrokeOutlineUseCase.logSampleEvaluation, !GenerateStrokeOutlineUseCase.didLogSampleEvaluation {
            GenerateStrokeOutlineUseCase.didLogSampleEvaluation = true
            FileHandle.standardError.write(Data("GenerateStrokeOutlineUseCase.makeSample invoked\n".utf8))
        }
        let basePoint = polyline.point(at: u)
        let tangentAngle: Double
        if u <= 0.0, let first = spec.path.segments.first {
            tangentAngle = first.safeTangentAngle(at: 0.0)
        } else if u >= 1.0, let last = spec.path.segments.last {
            tangentAngle = last.safeTangentAngle(at: 1.0)
        } else {
            tangentAngle = polyline.tangentAngle(at: u, fallbackAngle: fallbackTangent ?? 0.0)
        }
        return makeSampleFromBase(uGeom: u, uGrid: u, progress: progress, basePoint: basePoint, tangentAngle: tangentAngle, spec: spec, translation: translation)
    }

    private func logStampSample(_ sample: Sample, label: String, spec: StrokeSpec) {
        let phaseDeg = spec.tangentPhaseDegrees.map { String(format: "%.6f", $0) } ?? "nil"
        let phaseRad = (spec.tangentPhaseDegrees ?? 0.0) * .pi / 180.0
        let line = String(
            format: "stamp-%@ t=%.6f uGeom=%.6f uLocal=%.6f P=(%.3f,%.3f) tangent=%.6f theta=%.6f thetaUsed=%.6f phaseDeg=%@ phaseRad=%.6f angleMode=%@",
            label,
            sample.t,
            sample.uGeom,
            sample.uGrid,
            sample.point.x,
            sample.point.y,
            sample.tangentAngle,
            sample.theta,
            sample.effectiveRotation,
            phaseDeg,
            phaseRad,
            String(describing: spec.angleMode)
        )
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }

    private func makeSampleFromBase(
        uGeom: Double,
        uGrid: Double,
        progress: Double,
        basePoint: Point,
        tangentAngle: Double,
        spec: StrokeSpec,
        translation: Point,
        debugSkeletonIndex: Int? = nil,
        debugSkeletonId: String? = nil,
        debugSegmentIndex: Int? = nil,
        debugSegmentKind: String? = nil,
        debugSegmentU: Double? = nil
    ) -> Sample {
        let alpha = spec.alpha.map { evaluator.evaluate($0, at: progress) } ?? 0.0
        let width = evaluator.evaluate(spec.width, at: progress)
        let widthLeft = spec.widthLeft.map { evaluator.evaluate($0, at: progress) } ?? (width * 0.5)
        let widthRight = spec.widthRight.map { evaluator.evaluate($0, at: progress) } ?? (width * 0.5)
        let height = evaluator.evaluate(spec.height, at: progress)
        let theta = AngleMath.wrapPi(evaluator.evaluateAngle(spec.theta, at: progress))
        let tangentPhase = (spec.tangentPhaseDegrees ?? 0.0) * .pi / 180.0
        let effectiveRotation: Double
        switch spec.angleMode {
        case .absolute:
            effectiveRotation = theta
        case .tangentRelative:
            effectiveRotation = AngleMath.wrapPi(theta + tangentAngle + tangentPhase)
        }
        let offsetValue = spec.offset.map { evaluator.evaluate($0, at: progress) } ?? 0.0
        let tangent = Point(x: cos(tangentAngle), y: sin(tangentAngle))
        let laneNormal = Point(x: tangent.y, y: -tangent.x)
        let center = basePoint + laneNormal * offsetValue + translation
        return Sample(
            uGeom: uGeom,
            uGrid: uGrid,
            t: progress,
            point: center,
            tangentAngle: tangentAngle,
            width: width,
            widthLeft: widthLeft,
            widthRight: widthRight,
            height: height,
            theta: theta,
            effectiveRotation: effectiveRotation,
            alpha: alpha,
            debugSkeletonIndex: debugSkeletonIndex,
            debugSkeletonId: debugSkeletonId,
            debugSegmentIndex: debugSegmentIndex,
            debugSegmentKind: debugSegmentKind,
            debugSegmentU: debugSegmentU
        )
    }

    private func applyLaneOffsetContinuity(samples: [Sample], spec: StrokeSpec) -> [Sample] {
        guard let offset = spec.offset, !samples.isEmpty else { return samples }
        var adjusted = samples
        var prevNormal: Point? = nil
        var remainingLogs = GenerateStrokeOutlineUseCase.logLaneOffsetSamples ? min(3, adjusted.count) : 0
        for index in adjusted.indices {
            let sample = adjusted[index]
            let tangent = Point(x: cos(sample.tangentAngle), y: sin(sample.tangentAngle))
            var normal = Point(x: tangent.y, y: -tangent.x)
            let offsetValue = evaluator.evaluate(offset, at: sample.t)
            var point = sample.point
            if let prev = prevNormal, normal.dot(prev) < 0.0 {
                point = point - normal * (2.0 * offsetValue)
                adjusted[index].point = point
                normal = normal * -1.0
            }
            if remainingLogs > 0 {
                let basePoint = point - normal * offsetValue
                let shiftedPoint = point
                print(String(format: "lane-offset t=%.6f P=(%.3f,%.3f) T=(%.3f,%.3f) N=(%.3f,%.3f) d=%.3f P'=(%.3f,%.3f)",
                             sample.t,
                             basePoint.x, basePoint.y,
                             tangent.x, tangent.y,
                             normal.x, normal.y,
                             offsetValue,
                             shiftedPoint.x, shiftedPoint.y))
                remainingLogs -= 1
            }
            prevNormal = normal
        }
        return adjusted
    }

    private func adaptiveSamples(spec: StrokeSpec, polyline: PathPolyline, policy: SamplingPolicy, translation: Point, start: Sample, end: Sample) -> [Sample] {
        var samples: [Sample] = []
        samples.reserveCapacity(policy.maxSamples)
        let builder = BridgeBuilder()
        let logEnabled = GenerateStrokeOutlineUseCase.logAdaptiveSampling
        var refinementCount = 0
        let logLimit = 200
        var sawTailInterval = false
        var totalIntervalsVisited = 0
        var splitsByRateLimit = 0
        var splitsByMidpointFail = 0
        var splitsByProbeFail: [Double: Int] = [0.25: 0, 0.5: 0, 0.75: 0]
        var accepts = 0
        var topThetaOffenders: [(t0: Double, t1: Double, depth: Int, delta: Double, wLeft: Double, wRight: Double)] = []
        var topWidthOffenders: [(t0: Double, t1: Double, depth: Int, delta: Double, wLeft: Double, wRight: Double)] = []

        func recordOffenders(t0: Double, t1: Double, depth: Int, deltaTheta: Double, deltaWLeft: Double, deltaWRight: Double) {
            let thetaDeg = abs(deltaTheta) * 180.0 / .pi
            let widthDelta = max(abs(deltaWLeft), abs(deltaWRight))
            topThetaOffenders.append((t0, t1, depth, thetaDeg, deltaWLeft, deltaWRight))
            topThetaOffenders.sort { $0.delta > $1.delta }
            if topThetaOffenders.count > 10 { topThetaOffenders.removeLast(topThetaOffenders.count - 10) }
            topWidthOffenders.append((t0, t1, depth, widthDelta, deltaWLeft, deltaWRight))
            topWidthOffenders.sort { $0.delta > $1.delta }
            if topWidthOffenders.count > 10 { topWidthOffenders.removeLast(topWidthOffenders.count - 10) }
        }

        func shouldLogInterval(t0: Double, t1: Double) -> Bool {
            guard logEnabled else { return false }
            if t0 >= 0.7 || t1 >= 0.7 { return true }
            return refinementCount < logLimit
        }

        func logInterval(_ message: String) {
            guard logEnabled else { return }
            FileHandle.standardError.write(Data((message + "\n").utf8))
        }

        func recurse(t0: Double, t1: Double, s0: Sample, s1: Sample, depth: Int) {
            totalIntervalsVisited += 1
            if logEnabled, (t0 >= 0.7 || t1 >= 0.7) {
                sawTailInterval = true
            }
            if samples.count >= policy.maxSamples - 1 {
                samples.append(s0)
                return
            }
            let atLimit = depth >= policy.maxRecursionDepth || (t1 - t0) < policy.minParamStep

            let midT = (t0 + t1) * 0.5
            guard let sm = makeSampleAtU(midT, progress: midT, spec: spec, polyline: polyline, translation: translation, fallbackTangent: s0.tangentAngle) else {
                samples.append(s0)
                return
            }

            let deltaThetaUsed = abs(AngleMath.angularDifference(s1.effectiveRotation, s0.effectiveRotation))
            let deltaWLeft = abs(s1.widthLeft - s0.widthLeft)
            let deltaWRight = abs(s1.widthRight - s0.widthRight)
            let widthDelta = max(deltaWLeft, deltaWRight)
            let maxWidth = max(s0.widthLeft, s0.widthRight, s1.widthLeft, s1.widthRight)
            let widthThreshold = max(policy.widthChangeMin, policy.widthChangeFactor * maxWidth)
            let turnDelta = abs(AngleMath.angularDifference(s1.tangentAngle, s0.tangentAngle))
            let turnDeg = turnDelta * 180.0 / .pi
            let allowRateLimit = turnDeg >= policy.turnThresholdDegrees
            let challenging = allowRateLimit && (deltaThetaUsed > policy.rotationThresholdRadians || widthDelta > widthThreshold)
            recordOffenders(t0: t0, t1: t1, depth: depth, deltaTheta: deltaThetaUsed, deltaWLeft: deltaWLeft, deltaWRight: deltaWRight)

            let stamping = CounterpointStamping()
            let ringA = stamping.ring(for: s0, shape: spec.counterpointShape)
            let ringB = stamping.ring(for: s1, shape: spec.counterpointShape)
            let bridges = (try? builder.bridgeRings(from: ringA, to: ringB)) ?? []

            let probeUs: [Double] = challenging ? [0.25, 0.5, 0.75] : [0.5]
            let envelope = [ringA, ringB] + bridges
            for u in probeUs {
                let probeT = t0 + (t1 - t0) * u
                let probeSample: Sample
                if u == 0.5 {
                    probeSample = sm
                } else if let candidate = makeSampleAtU(probeT, progress: probeT, spec: spec, polyline: polyline, translation: translation, fallbackTangent: s0.tangentAngle) {
                    probeSample = candidate
                } else {
                    recurse(t0: t0, t1: midT, s0: s0, s1: sm, depth: depth + 1)
                    recurse(t0: midT, t1: t1, s0: sm, s1: s1, depth: depth + 1)
                    return
                }
                let ringP = stamping.ring(for: probeSample, shape: spec.counterpointShape)
                let ok = ringWithinEnvelope(ringP, envelopes: envelope, tolerance: policy.envelopeTolerance)
                if !ok {
                    splitsByProbeFail[u, default: 0] += 1
                    if u == 0.5 {
                        splitsByMidpointFail += 1
                    }
                    refinementCount += 1
                    if shouldLogInterval(t0: t0, t1: t1) {
                        let thetaDeg = deltaThetaUsed * 180.0 / .pi
                        logInterval(String(
                            format: "adaptive-probe u=%.2f t=%.4f P=(%.3f,%.3f) tan=%.5f thetaUsed=%.5f wL=%.3f wR=%.3f h=%.3f",
                            u,
                            probeSample.t,
                            probeSample.point.x,
                            probeSample.point.y,
                            probeSample.tangentAngle,
                            probeSample.effectiveRotation,
                            probeSample.widthLeft,
                            probeSample.widthRight,
                            probeSample.height
                        ))
                        logInterval(String(
                            format: "adaptive-split reason=probeFail u=%.2f t=[%.4f..%.4f] depth=%d dThetaDeg=%.3f dWLeft=%.3f dWRight=%.3f challenging=%d",
                            u,
                            t0,
                            t1,
                            depth,
                            thetaDeg,
                            deltaWLeft,
                            deltaWRight,
                            challenging ? 1 : 0
                        ))
                    }
                    if atLimit {
                        samples.append(s0)
                        samples.append(sm)
                        return
                    }
                    recurse(t0: t0, t1: midT, s0: s0, s1: sm, depth: depth + 1)
                    recurse(t0: midT, t1: t1, s0: sm, s1: s1, depth: depth + 1)
                    return
                }
            }

            if challenging {
                splitsByRateLimit += 1
                refinementCount += 1
                if shouldLogInterval(t0: t0, t1: t1) {
                    let thetaDeg = deltaThetaUsed * 180.0 / .pi
                    logInterval(String(
                        format: "adaptive-split reason=rateLimit t=[%.4f..%.4f] depth=%d dThetaDeg=%.3f dWLeft=%.3f dWRight=%.3f",
                        t0,
                        t1,
                        depth,
                        thetaDeg,
                        deltaWLeft,
                        deltaWRight
                    ))
                }
                if !atLimit {
                    recurse(t0: t0, t1: midT, s0: s0, s1: sm, depth: depth + 1)
                    recurse(t0: midT, t1: t1, s0: sm, s1: s1, depth: depth + 1)
                } else {
                    samples.append(s0)
                }
                return
            }

            accepts += 1
            samples.append(s0)
        }

        recurse(t0: 0.0, t1: 1.0, s0: start, s1: end, depth: 0)
        samples.append(end)
        if logEnabled && (refinementCount < logLimit || sawTailInterval) {
            let probe025 = splitsByProbeFail[0.25, default: 0]
            let probe050 = splitsByProbeFail[0.5, default: 0]
            let probe075 = splitsByProbeFail[0.75, default: 0]
            let summary = String(
                format: "adaptive-summary intervals=%d accepts=%d rateLimit=%d midpointFail=%d probeFail[0.25]=%d probeFail[0.5]=%d probeFail[0.75]=%d",
                totalIntervalsVisited,
                accepts,
                splitsByRateLimit,
                splitsByMidpointFail,
                probe025,
                probe050,
                probe075
            )
            FileHandle.standardError.write(Data((summary + "\n").utf8))
            for (index, offender) in topThetaOffenders.enumerated() {
                let line = String(
                    format: "adaptive-top-theta[%d] t=[%.4f..%.4f] depth=%d dThetaDeg=%.3f dWLeft=%.3f dWRight=%.3f",
                    index,
                    offender.t0,
                    offender.t1,
                    offender.depth,
                    offender.delta,
                    offender.wLeft,
                    offender.wRight
                )
                FileHandle.standardError.write(Data((line + "\n").utf8))
            }
            for (index, offender) in topWidthOffenders.enumerated() {
                let line = String(
                    format: "adaptive-top-width[%d] t=[%.4f..%.4f] depth=%d dWidth=%.3f dWLeft=%.3f dWRight=%.3f",
                    index,
                    offender.t0,
                    offender.t1,
                    offender.depth,
                    offender.delta,
                    offender.wLeft,
                    offender.wRight
                )
                FileHandle.standardError.write(Data((line + "\n").utf8))
            }
        }
        return samples
    }

    private func remapSeedsForProgress(
        seeds: [SampleSeed],
        spec: StrokeSpec,
        polyline: PathPolyline,
        translation: Point,
        progressToPoint: ((Double) -> (Double, Point, Double))? = nil
    ) -> [Sample] {
        guard seeds.count > 1 else {
            return seeds.map { seed in
                makeSampleFromBase(
                    uGeom: seed.uGlobal,
                    uGrid: seed.uLocal,
                    progress: 0.0,
                    basePoint: seed.basePoint,
                    tangentAngle: seed.tangentAngle,
                    spec: spec,
                    translation: translation,
                    debugSkeletonIndex: seed.skeletonIndex,
                    debugSkeletonId: seed.skeletonId,
                    debugSegmentIndex: seed.segmentIndex,
                    debugSegmentKind: seed.segmentKind,
                    debugSegmentU: seed.segmentU
                )
            }
        }
        var lengths: [Double] = [0.0]
        lengths.reserveCapacity(seeds.count)
        var total = 0.0
        for i in 1..<seeds.count {
            total += (seeds[i].basePoint - seeds[i - 1].basePoint).length
            lengths.append(total)
        }
        let denom = total > 0.0 ? total : 1.0
        return seeds.enumerated().map { index, seed in
            let progress = lengths[index] / denom
            let basePoint: Point
            let tangentAngle: Double
            let uGeom: Double
            if let progressToPoint {
                let resolved = progressToPoint(progress)
                uGeom = resolved.0
                basePoint = resolved.1
                tangentAngle = resolved.2
            } else {
                uGeom = seed.uGlobal
                basePoint = seed.basePoint
                tangentAngle = seed.tangentAngle
            }
            return makeSampleFromBase(
                uGeom: uGeom,
                uGrid: seed.uLocal,
                progress: progress,
                basePoint: basePoint,
                tangentAngle: tangentAngle,
                spec: spec,
                translation: translation,
                debugSkeletonIndex: seed.skeletonIndex,
                debugSkeletonId: seed.skeletonId,
                debugSegmentIndex: seed.segmentIndex,
                debugSegmentKind: seed.segmentKind,
                debugSegmentU: seed.segmentU
            )
        }
    }

    private func enforceMaxSpacing(seeds: [SampleSeed], maxSpacing: Double) -> [SampleSeed] {
        guard seeds.count > 1, maxSpacing > 0 else { return seeds }
        var result: [SampleSeed] = []
        result.reserveCapacity(seeds.count)
        for i in 0..<(seeds.count - 1) {
            let a = seeds[i]
            let b = seeds[i + 1]
            result.append(a)
            let distance = (b.basePoint - a.basePoint).length
            if distance > maxSpacing {
                let inserts = Int(floor(distance / maxSpacing))
                if inserts > 0 {
                    let angle = atan2(b.basePoint.y - a.basePoint.y, b.basePoint.x - a.basePoint.x)
                    for k in 1...inserts {
                        let t = Double(k) / Double(inserts + 1)
                        let uGlobal = ScalarMath.lerp(a.uGlobal, b.uGlobal, t)
                        let uLocal = ScalarMath.lerp(a.uLocal, b.uLocal, t)
                        let basePoint = lerpPoint(a.basePoint, b.basePoint, t)
                        let progressHint = ScalarMath.lerp(a.progressHint, b.progressHint, t)
                        let segmentIndex = a.segmentIndex == b.segmentIndex ? a.segmentIndex : nil
                        let segmentU = a.segmentU == b.segmentU ? a.segmentU : nil
                        let segmentKind = a.segmentKind == b.segmentKind ? a.segmentKind : nil
                        let skeletonIndex = a.skeletonIndex == b.skeletonIndex ? a.skeletonIndex : nil
                        let skeletonId = a.skeletonId == b.skeletonId ? a.skeletonId : nil
                        result.append(SampleSeed(
                            uGlobal: uGlobal,
                            uLocal: uLocal,
                            basePoint: basePoint,
                            tangentAngle: angle,
                            progressHint: progressHint,
                            segmentIndex: segmentIndex,
                            segmentU: segmentU,
                            segmentKind: segmentKind,
                            skeletonIndex: skeletonIndex,
                            skeletonId: skeletonId
                        ))
                    }
                }
            }
        }
        if let last = seeds.last {
            result.append(last)
        }
        return result
    }

    private func lerpPoint(_ a: Point, _ b: Point, _ t: Double) -> Point {
        Point(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    private func dedupeSorted(_ values: [Double], epsilon: Double) -> [Double] {
        guard !values.isEmpty else { return [] }
        let sorted = values.sorted()
        var result: [Double] = [sorted[0]]
        for value in sorted.dropFirst() {
            if abs(value - result.last!) > epsilon {
                result.append(value)
            }
        }
        if result.first != 0.0 {
            result.insert(0.0, at: 0)
        }
        if result.last != 1.0 {
            result.append(1.0)
        }
        return result
    }

    private struct FlattenedPoint {
        let point: Point
        let segmentIndex: Int
        let u: Double
    }

    private func keyframeGridSamples(spec: StrokeSpec, polyline: PathPolyline, translation: Point, maxSpacing: Double) -> [Sample] {
        let flat = flattenPathWithU(path: spec.path, tolerance: spec.sampling.flatnessTolerance)
        guard flat.count > 1 else {
            return remapSeedsForProgress(seeds: [], spec: spec, polyline: polyline, translation: translation)
        }

        let cumulative = cumulativeLengths(for: flat)
        let totalLength = cumulative.last ?? 0.0
        let total = totalLength > 0.0 ? totalLength : 1.0
        let keyframes = collectKeyframeTimes(spec: spec)
        let keyframeDensity = max(1, spec.sampling.keyframeDensity)

        var tValues: [Double] = []
        for index in 0..<(keyframes.count - 1) {
            let t0 = keyframes[index]
            let t1 = keyframes[index + 1]
            let intervalT = max(0.0, t1 - t0)
            let intervalLength = intervalT * total
            let intervalHasParamChange = hasParamChange(spec: spec, t0: t0, t1: t1)
            let intervalNeedsCoverage = maxSpacing > 0.0 && intervalLength > maxSpacing
            let n: Int
            if intervalHasParamChange || intervalNeedsCoverage {
                let spacingCount = maxSpacing > 0.0 ? Int(ceil(intervalLength / maxSpacing)) : 1
                n = max(1, max(spacingCount, keyframeDensity))
            } else {
                n = 1
            }
            tValues.append(t0)
            if n > 1 {
                for i in 1..<n {
                    let t = t0 + intervalT * (Double(i) / Double(n))
                    tValues.append(t)
                }
            }
            tValues.append(t1)
        }
        tValues = dedupeSorted(tValues, epsilon: 1.0e-9)

        let segmentCount = max(1, spec.path.segments.count)
        let seeds = tValues.map { progress in
            let uData = mapProgressToU(progress: progress, flat: flat, cumulative: cumulative, totalLength: total)
            let segment = spec.path.segments[uData.segmentIndex]
            let basePoint = segment.point(at: uData.u)
            let tangentAngle = segment.safeTangentAngle(at: uData.u)
            let uGlobal = (Double(uData.segmentIndex) + uData.u) / Double(segmentCount)
            return SampleSeed(
                uGlobal: uGlobal,
                uLocal: uData.u,
                basePoint: basePoint,
                tangentAngle: tangentAngle,
                progressHint: progress,
                segmentIndex: uData.segmentIndex,
                segmentU: uData.u,
                segmentKind: "cubic",
                skeletonIndex: nil,
                skeletonId: nil
            )
        }

        let refined = refineByCurvature(seeds: seeds, spec: spec, flat: flat, cumulative: cumulative, totalLength: total)
        let spaced = enforceMaxSpacing(seeds: refined, maxSpacing: maxSpacing)
        let normalized = normalizeSeedOrder(seeds: spaced)
        let progressToPoint: (Double) -> (Double, Point, Double) = { progress in
            let uData = mapProgressToU(progress: progress, flat: flat, cumulative: cumulative, totalLength: total)
            let segment = spec.path.segments[uData.segmentIndex]
            let point = segment.point(at: uData.u)
            let angle = segment.safeTangentAngle(at: uData.u)
            let uGeom = (Double(uData.segmentIndex) + uData.u) / Double(segmentCount)
            return (uGeom, point, angle)
        }
        return remapSeedsForProgress(seeds: normalized, spec: spec, polyline: polyline, translation: translation, progressToPoint: progressToPoint)
    }

    private func collectKeyframeTimes(spec: StrokeSpec) -> [Double] {
        var times: Set<Double> = [0.0, 1.0]
        let tracks: [ParamTrack?] = [spec.width, spec.widthLeft, spec.widthRight, spec.height, spec.theta, spec.offset, spec.alpha]
        for track in tracks.compactMap({ $0 }) {
            for key in track.keyframes {
                times.insert(ScalarMath.clamp01(key.t))
            }
        }
        return times.sorted()
    }

    private func flattenPathWithU(path: BezierPath, tolerance: Double) -> [FlattenedPoint] {
        var points: [FlattenedPoint] = []
        for (segmentIndex, segment) in path.segments.enumerated() {
            let segmentPoints = flattenSegmentWithU(segment: segment, segmentIndex: segmentIndex, tolerance: tolerance)
            if points.isEmpty {
                points.append(contentsOf: segmentPoints)
            } else {
                points.append(contentsOf: segmentPoints.dropFirst())
            }
        }
        return points
    }

    private func flattenSegmentWithU(segment: CubicBezier, segmentIndex: Int, tolerance: Double) -> [FlattenedPoint] {
        var result: [FlattenedPoint] = []
        func subdivide(_ cubic: CubicBezier, u0: Double, u1: Double) {
            if cubic.flatness() <= tolerance {
                if result.isEmpty {
                    result.append(FlattenedPoint(point: cubic.p0, segmentIndex: segmentIndex, u: u0))
                }
                result.append(FlattenedPoint(point: cubic.p3, segmentIndex: segmentIndex, u: u1))
            } else {
                let parts = cubic.subdivided()
                let mid = (u0 + u1) * 0.5
                subdivide(parts.left, u0: u0, u1: mid)
                subdivide(parts.right, u0: mid, u1: u1)
            }
        }
        subdivide(segment, u0: 0.0, u1: 1.0)
        return result
    }

    private func cumulativeLengths(for points: [FlattenedPoint]) -> [Double] {
        var result: [Double] = []
        result.reserveCapacity(points.count)
        var total = 0.0
        result.append(0.0)
        for i in 1..<points.count {
            total += (points[i].point - points[i - 1].point).length
            result.append(total)
        }
        return result
    }

    private struct UMapResult {
        let segmentIndex: Int
        let u: Double
    }

    private func mapProgressToU(progress: Double, flat: [FlattenedPoint], cumulative: [Double], totalLength: Double) -> UMapResult {
        let target = ScalarMath.clamp01(progress) * totalLength
        var index = 0
        while index + 1 < cumulative.count && cumulative[index + 1] < target {
            index += 1
        }
        var next = min(index + 1, flat.count - 1)
        while next < flat.count - 1 && cumulative[next] == cumulative[index] {
            next += 1
        }
        let start = cumulative[index]
        let end = cumulative[next]
        let span = max(1.0e-9, end - start)
        let alpha = (target - start) / span
        let u = ScalarMath.lerp(flat[index].u, flat[next].u, alpha)
        let segmentIndex = flat[next].segmentIndex
        return UMapResult(segmentIndex: segmentIndex, u: u)
    }

    private func refineByCurvature(seeds: [SampleSeed], spec: StrokeSpec, flat: [FlattenedPoint], cumulative: [Double], totalLength: Double) -> [SampleSeed] {
        guard seeds.count > 1 else { return seeds }
        let threshold = spec.sampling.rotationThresholdDegrees
        var refined: [SampleSeed] = []
        refined.reserveCapacity(seeds.count)
        for i in 0..<(seeds.count - 1) {
            let a = seeds[i]
            let b = seeds[i + 1]
            refined.append(a)
            let delta = abs(AngleMath.angularDifference(a.tangentAngle, b.tangentAngle)) * 180.0 / .pi
            if delta > threshold {
                let midProgress = (a.progressHint + b.progressHint) * 0.5
                let uData = mapProgressToU(progress: midProgress, flat: flat, cumulative: cumulative, totalLength: totalLength)
                let segment = spec.path.segments[uData.segmentIndex]
                let point = segment.point(at: uData.u)
                let angle = segment.safeTangentAngle(at: uData.u)
                let segmentCount = max(1, spec.path.segments.count)
                let uGlobal = (Double(uData.segmentIndex) + uData.u) / Double(segmentCount)
                refined.append(SampleSeed(
                    uGlobal: uGlobal,
                    uLocal: uData.u,
                    basePoint: point,
                    tangentAngle: angle,
                    progressHint: midProgress,
                    segmentIndex: uData.segmentIndex,
                    segmentU: uData.u,
                    segmentKind: "cubic",
                    skeletonIndex: nil,
                    skeletonId: nil
                ))
            }
        }
        if let last = seeds.last {
            refined.append(last)
        }
        return refined
    }

    private func normalizeSeedOrder(seeds: [SampleSeed]) -> [SampleSeed] {
        guard !seeds.isEmpty else { return [] }
        let sorted = seeds.sorted { lhs, rhs in
            switch (lhs.segmentIndex, rhs.segmentIndex) {
            case let (l?, r?) where l != r:
                return l < r
            case let (l?, r?) where l == r:
                return lhs.uLocal < rhs.uLocal
            default:
                return lhs.uGlobal < rhs.uGlobal
            }
        }
        return dedupeSeeds(sorted, epsilon: 1.0e-9)
    }

    private func dedupeSeeds(_ seeds: [SampleSeed], epsilon: Double) -> [SampleSeed] {
        guard let first = seeds.first else { return [] }
        var result: [SampleSeed] = [first]
        for seed in seeds.dropFirst() {
            let last = result[result.count - 1]
            let du = abs(seed.uGlobal - last.uGlobal)
            let dp = (seed.basePoint - last.basePoint).length
            if du > epsilon || dp > epsilon {
                result.append(seed)
            }
        }
        return result
    }

    private func hasParamChange(spec: StrokeSpec, t0: Double, t1: Double) -> Bool {
        let eps = 1.0e-6
        let widthDelta = abs(evaluator.evaluate(spec.width, at: t1) - evaluator.evaluate(spec.width, at: t0))
        if widthDelta > eps { return true }
        if let widthLeft = spec.widthLeft {
            let delta = abs(evaluator.evaluate(widthLeft, at: t1) - evaluator.evaluate(widthLeft, at: t0))
            if delta > eps { return true }
        }
        if let widthRight = spec.widthRight {
            let delta = abs(evaluator.evaluate(widthRight, at: t1) - evaluator.evaluate(widthRight, at: t0))
            if delta > eps { return true }
        }
        let heightDelta = abs(evaluator.evaluate(spec.height, at: t1) - evaluator.evaluate(spec.height, at: t0))
        if heightDelta > eps { return true }
        let thetaDelta = abs(AngleMath.angularDifference(
            evaluator.evaluateAngle(spec.theta, at: t0),
            evaluator.evaluateAngle(spec.theta, at: t1)
        ))
        if thetaDelta > eps { return true }
        if let offset = spec.offset {
            let delta = abs(evaluator.evaluate(offset, at: t1) - evaluator.evaluate(offset, at: t0))
            if delta > eps { return true }
        }
        if let alpha = spec.alpha {
            let delta = abs(evaluator.evaluate(alpha, at: t1) - evaluator.evaluate(alpha, at: t0))
            if delta > eps { return true }
        }
        return false
    }

    private func outputTranslation(for spec: StrokeSpec, polyline: PathPolyline) -> Point {
        let mode = spec.output?.coordinateMode ?? .normalized
        guard mode == .normalized, let origin = polyline.points.first else { return Point(x: 0, y: 0) }
        return Point(x: -origin.x, y: -origin.y)
    }

    private func samplingPolicy(for spec: StrokeSpec) -> SamplingPolicy {
        spec.samplingPolicy ?? SamplingPolicy.fromSamplingSpec(spec.sampling)
    }

    private func bridgeRings(between rings: [Ring]) throws -> [Ring] {
        guard rings.count > 1 else { return [] }
        let builder = BridgeBuilder()
        var bridges: [Ring] = []
        bridges.reserveCapacity(rings.count * 2)
        for index in 0..<(rings.count - 1) {
            let segmentBridges = try builder.bridgeRings(from: rings[index], to: rings[index + 1])
            bridges.append(contentsOf: segmentBridges)
        }
        return bridges
    }

    private func ringWithinEnvelope(_ ring: Ring, envelopes: [Ring], tolerance: Double) -> Bool {
        let closed = closeRingIfNeeded(ring)
        guard closed.count >= 4 else { return true }
        for point in closed.dropLast() {
            var covered = false
            for envelope in envelopes {
                if pointInsideOrNearRing(point, ring: envelope, tolerance: tolerance) {
                    covered = true
                    break
                }
            }
            if !covered { return false }
        }
        return true
    }

    private func capRings(for samples: [Sample], capStyle: CapStylePair) -> [Ring] {
        guard samples.count >= 2 else { return [] }
        let builder = JoinCapBuilder()

        let start = samples[0]
        let next = samples[1]
        let end = samples[samples.count - 1]
        let prev = samples[samples.count - 2]

        let dirStart = (start.point - next.point).normalized() ?? Point(x: 0, y: 0)
        let dirEnd = (end.point - prev.point).normalized() ?? Point(x: 0, y: 0)

        let startRadius = capRadius(for: start, style: capStyle.start)
        let endRadius = capRadius(for: end, style: capStyle.end)

        var rings: [Ring] = []
        if capStyle.start != .butt {
            rings.append(contentsOf: builder.capRings(point: start.point, direction: dirStart, radius: startRadius, style: capStyle.start))
        }
        if capStyle.end != .butt {
            rings.append(contentsOf: builder.capRings(point: end.point, direction: dirEnd, radius: endRadius, style: capStyle.end))
        }
        return rings
    }

    private func capRadius(for sample: Sample, style: CapStyle) -> Double {
        switch style {
        case .circle:
            return max(0.0, (sample.widthLeft + sample.widthRight) * 0.5)
        case .butt, .square, .round:
            return max(sample.width, sample.height) * 0.5
        }
    }

    private func joinRings(for samples: [Sample], joinStyle: JoinStyle) -> [Ring] {
        guard samples.count >= 3 else { return [] }
        guard case .bevel = joinStyle else {
            let builder = JoinCapBuilder()
            var rings: [Ring] = []
            for i in 1..<(samples.count - 1) {
                let prev = samples[i - 1]
                let current = samples[i]
                let next = samples[i + 1]
                guard let dirIn = (current.point - prev.point).normalized(),
                      let dirOut = (next.point - current.point).normalized() else {
                    continue
                }
                let radius = max(current.width, current.height) * 0.5
                let joinRings = builder.joinRings(point: current.point, dirIn: dirIn, dirOut: dirOut, radius: radius, style: joinStyle)
                rings.append(contentsOf: joinRings)
            }
            return rings
        }
        return []
    }
}
