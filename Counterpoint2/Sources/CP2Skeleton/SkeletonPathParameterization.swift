import CP2Geometry

public struct SkeletonPathParameterization {
    public struct Mapping: Equatable {
        public let segmentIndex: Int
        public let localU: Double
    }

    private let path: SkeletonPath
    private let perSegment: [ArcLengthParameterization]
    private let segmentLengths: [Double]
    public let totalLength: Double

    public init(path: SkeletonPath, samplesPerSegment: Int) {
        self.path = path
        var params: [ArcLengthParameterization] = []
        var lengths: [Double] = []
        params.reserveCapacity(path.segments.count)
        lengths.reserveCapacity(path.segments.count)
        for segment in path.segments {
            let subPath = SkeletonPath(segment)
            let param = ArcLengthParameterization(path: subPath, samplesPerSegment: samplesPerSegment)
            params.append(param)
            lengths.append(param.totalLength)
        }
        perSegment = params
        segmentLengths = lengths
        totalLength = max(lengths.reduce(0, +), Epsilon.defaultValue)
    }

    public func map(globalT: Double) -> Mapping {
        if totalLength <= Epsilon.defaultValue {
            return Mapping(segmentIndex: 0, localU: 0.0)
        }
        let clamped = max(0.0, min(1.0, globalT))
        let target = clamped * totalLength
        var accumulated = 0.0
        for (index, length) in segmentLengths.enumerated() {
            let next = accumulated + length
            if target <= next || index == segmentLengths.count - 1 {
                let localS = max(0.0, min(length, target - accumulated))
                let u = perSegment[index].u(atDistance: localS)
                return Mapping(segmentIndex: index, localU: u)
            }
            accumulated = next
        }
        return Mapping(segmentIndex: 0, localU: 0.0)
    }

    public func position(globalT: Double) -> Vec2 {
        let mapped = map(globalT: globalT)
        let segment = path.segments[mapped.segmentIndex]
        return segment.evaluate(mapped.localU)
    }

    public func tangent(globalT: Double) -> Vec2 {
        let mapped = map(globalT: globalT)
        let segment = path.segments[mapped.segmentIndex]
        return segment.tangent(mapped.localU)
    }
}
