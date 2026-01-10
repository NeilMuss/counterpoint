import Foundation
import Domain

public struct GenerateStrokeOutlineUseCase {
    public static var logSampleEvaluation = false
    private static var didLogSampleEvaluation = false

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
        let samples = generateSamples(for: spec)
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

    public func generateSamples(for spec: StrokeSpec) -> [Sample] {
        let policy = samplingPolicy(for: spec)
        let maxSpacing = spec.sampling.maxSpacing ?? spec.sampling.baseSpacing
        let polyline = sampler.makePolyline(path: spec.path, tolerance: policy.flattenTolerance)
        let translation = outputTranslation(for: spec, polyline: polyline)
        return generateSamples(
            for: spec,
            polyline: polyline,
            translation: translation,
            policy: policy,
            maxSpacing: maxSpacing
        )
    }

    public func generateConcatenatedSamples(for spec: StrokeSpec, paths: [BezierPath]) -> [Sample] {
        return generateConcatenatedSamplesWithJunctions(for: spec, paths: paths).samples
    }

    public func generateConcatenatedSamplesWithJunctions(for spec: StrokeSpec, paths: [BezierPath]) -> ConcatenatedSamples {
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
        }

        var seeds: [ConcatSeed] = []
        var junctionPairs: [(Int, Int)] = []
        var previousSegmentLastIndex: Int?
        for (index, path) in paths.enumerated() {
            let polyline = sampler.makePolyline(path: path, tolerance: policy.flattenTolerance)
            let localSamples = generateSamples(
                for: spec,
                polyline: polyline,
                translation: translation,
                policy: policy,
                maxSpacing: maxSpacing
            )
            if localSamples.isEmpty { continue }
            let trimmedSamples = (index == paths.count - 1) ? localSamples : Array(localSamples.dropLast())
            let firstIndexInSegment = seeds.count
            for sample in trimmedSamples {
                let basePoint = polyline.point(at: sample.uGeom)
                let tangentAngle = polyline.tangentAngle(at: sample.uGeom, fallbackAngle: sample.tangentAngle)
                seeds.append(ConcatSeed(
                    uGeom: sample.uGeom,
                    uGrid: sample.uGrid,
                    basePoint: basePoint,
                    tangentAngle: tangentAngle,
                    centerPoint: sample.point
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
            return ConcatenatedSamples(samples: [
                makeSampleFromBase(
                    uGeom: seed.uGeom,
                    uGrid: seed.uGrid,
                    progress: 0.0,
                    basePoint: seed.basePoint,
                    tangentAngle: seed.tangentAngle,
                    spec: spec,
                    translation: translation
                )
            ], junctionPairs: [])
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
                translation: translation
            )
            samples.append(sample)
        }
        return ConcatenatedSamples(samples: samples, junctionPairs: junctionPairs)
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
                    segmentIndex: nil
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
        let tangentAngle = polyline.tangentAngle(at: u, fallbackAngle: fallbackTangent ?? 0.0)
        return makeSampleFromBase(uGeom: u, uGrid: u, progress: progress, basePoint: basePoint, tangentAngle: tangentAngle, spec: spec, translation: translation)
    }

    private func makeSampleFromBase(uGeom: Double, uGrid: Double, progress: Double, basePoint: Point, tangentAngle: Double, spec: StrokeSpec, translation: Point) -> Sample {
        let alpha = spec.alpha.map { evaluator.evaluate($0, at: progress) } ?? 0.0
        let width = evaluator.evaluate(spec.width, at: progress)
        let height = evaluator.evaluate(spec.height, at: progress)
        let theta = evaluator.evaluateAngle(spec.theta, at: progress)
        let effectiveRotation: Double
        switch spec.angleMode {
        case .absolute:
            effectiveRotation = theta
        case .tangentRelative:
            effectiveRotation = theta + tangentAngle
        }
        let offsetValue = spec.offset.map { evaluator.evaluate($0, at: progress) } ?? 0.0
        let axis = Point(x: cos(effectiveRotation), y: sin(effectiveRotation))
        let center = basePoint + axis.leftNormal() * offsetValue + translation
        return Sample(
            uGeom: uGeom,
            uGrid: uGrid,
            t: progress,
            point: center,
            tangentAngle: tangentAngle,
            width: width,
            height: height,
            theta: theta,
            effectiveRotation: effectiveRotation,
            alpha: alpha
        )
    }

    private func adaptiveSamples(spec: StrokeSpec, polyline: PathPolyline, policy: SamplingPolicy, translation: Point, start: Sample, end: Sample) -> [Sample] {
        var samples: [Sample] = []
        samples.reserveCapacity(policy.maxSamples)
        let builder = BridgeBuilder()

        func recurse(t0: Double, t1: Double, s0: Sample, s1: Sample, depth: Int) {
            if samples.count >= policy.maxSamples - 1 {
                samples.append(s0)
                return
            }
            if depth >= policy.maxRecursionDepth || (t1 - t0) < policy.minParamStep {
                samples.append(s0)
                return
            }

            let midT = (t0 + t1) * 0.5
            guard let sm = makeSampleAtU(midT, progress: midT, spec: spec, polyline: polyline, translation: translation, fallbackTangent: s0.tangentAngle) else {
                samples.append(s0)
                return
            }

            let stamping = CounterpointStamping()
            let ringA = stamping.ring(for: s0, shape: spec.counterpointShape)
            let ringB = stamping.ring(for: s1, shape: spec.counterpointShape)
            let ringM = stamping.ring(for: sm, shape: spec.counterpointShape)
            let bridges = (try? builder.bridgeRings(from: ringA, to: ringB)) ?? []

            let deltaRotation = abs(AngleMath.angularDifference(s1.effectiveRotation, s0.effectiveRotation))
            if deltaRotation > spec.sampling.rotationThresholdRadians {
                recurse(t0: t0, t1: midT, s0: s0, s1: sm, depth: depth + 1)
                recurse(t0: midT, t1: t1, s0: sm, s1: s1, depth: depth + 1)
                return
            }

            let ok = ringWithinEnvelope(ringM, envelopes: [ringA, ringB] + bridges, tolerance: policy.envelopeTolerance)
            if ok {
                samples.append(s0)
            } else {
                recurse(t0: t0, t1: midT, s0: s0, s1: sm, depth: depth + 1)
                recurse(t0: midT, t1: t1, s0: sm, s1: s1, depth: depth + 1)
            }
        }

        recurse(t0: 0.0, t1: 1.0, s0: start, s1: end, depth: 0)
        samples.append(end)
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
                    translation: translation
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
                translation: translation
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
                        result.append(SampleSeed(
                            uGlobal: uGlobal,
                            uLocal: uLocal,
                            basePoint: basePoint,
                            tangentAngle: angle,
                            progressHint: progressHint,
                            segmentIndex: segmentIndex
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
            let tangent = segment.derivative(at: uData.u)
            let tangentAngle = tangent.normalized().map { atan2($0.y, $0.x) } ?? 0.0
            let uGlobal = (Double(uData.segmentIndex) + uData.u) / Double(segmentCount)
            return SampleSeed(
                uGlobal: uGlobal,
                uLocal: uData.u,
                basePoint: basePoint,
                tangentAngle: tangentAngle,
                progressHint: progress,
                segmentIndex: uData.segmentIndex
            )
        }

        let refined = refineByCurvature(seeds: seeds, spec: spec, flat: flat, cumulative: cumulative, totalLength: total)
        let spaced = enforceMaxSpacing(seeds: refined, maxSpacing: maxSpacing)
        let normalized = normalizeSeedOrder(seeds: spaced)
        let progressToPoint: (Double) -> (Double, Point, Double) = { progress in
            let uData = mapProgressToU(progress: progress, flat: flat, cumulative: cumulative, totalLength: total)
            let segment = spec.path.segments[uData.segmentIndex]
            let point = segment.point(at: uData.u)
            let tangent = segment.derivative(at: uData.u)
            let angle = tangent.normalized().map { atan2($0.y, $0.x) } ?? 0.0
            let uGeom = (Double(uData.segmentIndex) + uData.u) / Double(segmentCount)
            return (uGeom, point, angle)
        }
        return remapSeedsForProgress(seeds: normalized, spec: spec, polyline: polyline, translation: translation, progressToPoint: progressToPoint)
    }

    private func collectKeyframeTimes(spec: StrokeSpec) -> [Double] {
        var times: Set<Double> = [0.0, 1.0]
        let tracks: [ParamTrack?] = [spec.width, spec.height, spec.theta, spec.offset, spec.alpha]
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
                let tangent = segment.derivative(at: uData.u)
                let angle = tangent.normalized().map { atan2($0.y, $0.x) } ?? a.tangentAngle
                let segmentCount = max(1, spec.path.segments.count)
                let uGlobal = (Double(uData.segmentIndex) + uData.u) / Double(segmentCount)
                refined.append(SampleSeed(
                    uGlobal: uGlobal,
                    uLocal: uData.u,
                    basePoint: point,
                    tangentAngle: angle,
                    progressHint: midProgress,
                    segmentIndex: uData.segmentIndex
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

    private func capRings(for samples: [Sample], capStyle: CapStyle) -> [Ring] {
        guard samples.count >= 2 else { return [] }
        guard capStyle != .butt else { return [] }
        let builder = JoinCapBuilder()

        let start = samples[0]
        let next = samples[1]
        let end = samples[samples.count - 1]
        let prev = samples[samples.count - 2]

        let dirStart = (start.point - next.point).normalized() ?? Point(x: 0, y: 0)
        let dirEnd = (end.point - prev.point).normalized() ?? Point(x: 0, y: 0)

        let startRadius = max(start.width, start.height) * 0.5
        let endRadius = max(end.width, end.height) * 0.5

        var rings: [Ring] = []
        rings.append(contentsOf: builder.capRings(point: start.point, direction: dirStart, radius: startRadius, style: capStyle))
        rings.append(contentsOf: builder.capRings(point: end.point, direction: dirEnd, radius: endRadius, style: capStyle))
        return rings
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
