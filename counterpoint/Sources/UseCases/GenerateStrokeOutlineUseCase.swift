import Foundation
import Domain

public struct GenerateStrokeOutlineUseCase {
    private let sampler: PathSampling
    private let evaluator: ParamEvaluating
    private let unioner: PolygonUnioning

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
        let polyline = sampler.makePolyline(path: spec.path, tolerance: policy.flattenTolerance)
        guard let start = makeSample(at: 0.0, spec: spec, polyline: polyline, fallbackTangent: nil),
              let end = makeSample(at: 1.0, spec: spec, polyline: polyline, fallbackTangent: start.tangentAngle) else {
            return []
        }
        return adaptiveSamples(spec: spec, polyline: polyline, policy: policy, start: start, end: end)
    }

    private func makeSample(at t: Double, spec: StrokeSpec, polyline: PathPolyline, fallbackTangent: Double?) -> Sample? {
        let point = polyline.point(at: t)
        let tangentAngle = polyline.tangentAngle(at: t, fallbackAngle: fallbackTangent ?? 0.0)
        let width = evaluator.evaluate(spec.width, at: t)
        let height = evaluator.evaluate(spec.height, at: t)
        let theta = evaluator.evaluateAngle(spec.theta, at: t)
        let effectiveRotation: Double
        switch spec.angleMode {
        case .absolute:
            effectiveRotation = theta
        case .tangentRelative:
            effectiveRotation = theta + tangentAngle
        }
        return Sample(
            t: t,
            point: point,
            tangentAngle: tangentAngle,
            width: width,
            height: height,
            theta: theta,
            effectiveRotation: effectiveRotation
        )
    }

    private func adaptiveSamples(spec: StrokeSpec, polyline: PathPolyline, policy: SamplingPolicy, start: Sample, end: Sample) -> [Sample] {
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
            guard let sm = makeSample(at: midT, spec: spec, polyline: polyline, fallbackTangent: s0.tangentAngle) else {
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
