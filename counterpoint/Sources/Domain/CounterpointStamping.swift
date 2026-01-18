import Foundation

public struct CounterpointStamping {
    public init() {}

    public func ring(for sample: Sample, shape: CounterpointShape) -> Ring {
        switch shape {
        case .rectangle:
            return rectangleRing(for: sample)
        case .ellipse(let segments):
            return ellipseRing(for: sample, segments: max(8, segments))
        }
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
        return transform(local: local, sample: sample)
    }

    private func ellipseRing(for sample: Sample, segments: Int) -> Ring {
        let halfWidth = sample.width * 0.5
        let halfHeight = sample.height * 0.5
        var local: [Point] = []
        local.reserveCapacity(segments)
        for i in 0..<segments {
            let t = Double(i) / Double(segments)
            let angle = t * 2.0 * .pi
            local.append(Point(x: cos(angle) * halfWidth, y: sin(angle) * halfHeight))
        }
        return transform(local: local, sample: sample)
    }

    private func transform(local: [Point], sample: Sample) -> Ring {
        let rotated = local.map { GeometryMath.rotate(point: $0, by: sample.effectiveRotation) }
        let translated = rotated.map { $0 + sample.point }
        return closeRingIfNeeded(translated)
    }
}
