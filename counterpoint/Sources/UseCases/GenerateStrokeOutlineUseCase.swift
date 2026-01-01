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
        let rings = samples.map { rectangleRing(for: $0) }
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
        let polyline = sampler.makePolyline(path: spec.path, tolerance: spec.sampling.flatnessTolerance)
        let spacing = resolvedSpacing(spec: spec)
        let baseParameters = polyline.sampleParameters(spacing: spacing)
        let initial = baseParameters.compactMap { makeSample(at: $0, spec: spec, polyline: polyline, fallbackTangent: nil) }
        return refine(samples: initial, spec: spec, polyline: polyline)
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

    private func refine(samples: [Sample], spec: StrokeSpec, polyline: PathPolyline) -> [Sample] {
        guard samples.count > 1 else { return samples }
        var refined = samples
        let threshold = spec.sampling.rotationThresholdRadians
        let minSpacing = spec.sampling.minimumSpacing
        var index = 0
        var fallbackTangent = refined.first?.tangentAngle ?? 0.0

        while index < refined.count - 1 {
            let a = refined[index]
            let b = refined[index + 1]
            let delta = abs(AngleMath.angularDifference(b.effectiveRotation, a.effectiveRotation))
            let span = b.t - a.t
            if delta > threshold && span > minSpacing {
                let midT = (a.t + b.t) * 0.5
                if let midSample = makeSample(at: midT, spec: spec, polyline: polyline, fallbackTangent: fallbackTangent) {
                    refined.insert(midSample, at: index + 1)
                    fallbackTangent = midSample.tangentAngle
                    continue
                }
            }
            fallbackTangent = b.tangentAngle
            index += 1
        }

        return refined
    }

    private func rectangleRing(for sample: Sample) -> Ring {
        let halfWidth = sample.width * 0.5
        let halfHeight = sample.height * 0.5

        let local: [Point] = [
            Point(x: -halfWidth, y: -halfHeight),
            Point(x: halfWidth, y: -halfHeight),
            Point(x: halfWidth, y: halfHeight),
            Point(x: -halfWidth, y: halfHeight)
        ]

        let rotated = local.map { GeometryMath.rotate(point: $0, by: sample.effectiveRotation) }
        let translated = rotated.map { $0 + sample.point }
        var points = translated
        if let first = translated.first {
            points.append(first)
        }
        return points
    }

    private func resolvedSpacing(spec: StrokeSpec) -> Double {
        let minWidth = spec.width.minValue.map { abs($0) } ?? spec.sampling.baseSpacing
        let minHeight = spec.height.minValue.map { abs($0) } ?? spec.sampling.baseSpacing
        let minDimension = min(minWidth, minHeight)
        let cap = minDimension > 0 ? minDimension / 4.0 : spec.sampling.baseSpacing
        return max(spec.sampling.minimumSpacing, min(spec.sampling.baseSpacing, cap))
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
