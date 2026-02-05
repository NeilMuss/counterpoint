import Foundation
import CP2Geometry

public struct ArtifactID: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

public enum StableSortPolicy: String, Codable, Sendable {
    case lexicographicXYThenIndex
    case byOriginalInsertionThenLexiTieBreak
}

public struct DeterminismPolicy: Codable, Equatable, Sendable {
    public let eps: Double
    public let stableSort: StableSortPolicy
    public init(eps: Double, stableSort: StableSortPolicy) {
        self.eps = eps
        self.stableSort = stableSort
    }
}

public protocol DebugPayload: Codable, Sendable {
    static var kind: String { get }
}

public struct DebugBundle: Codable, Equatable, Sendable {
    public var entries: [String: Data]

    public init(entries: [String: Data] = [:]) {
        self.entries = entries
    }

    public mutating func add<P: DebugPayload>(_ payload: P) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)
        entries[P.kind] = data
    }
}

public protocol InvariantCheckable {
    func validate() throws
}

public struct CP2InvariantError: Error, CustomStringConvertible {
    public let message: String
    public let context: String?
    public init(_ message: String, context: String? = nil) {
        self.message = message
        self.context = context
    }
    public var description: String {
        if let context {
            return "\(message) (\(context))"
        }
        return message
    }
}

public struct CP2Spec: Codable, Equatable, Sendable, InvariantCheckable {
    public let version: Int
    public let determinism: DeterminismPolicy
    public init(version: Int, determinism: DeterminismPolicy) {
        self.version = version
        self.determinism = determinism
    }
    public func validate() throws {
        if version <= 0 { throw CP2InvariantError("spec version must be > 0") }
        if determinism.eps <= 0 { throw CP2InvariantError("determinism.eps must be > 0") }
    }
}

public enum SkeletonSegment: Codable, Equatable, Sendable {
    case line(p0: Vec2, p1: Vec2)
    case cubic(p0: Vec2, p1: Vec2, p2: Vec2, p3: Vec2)

    public var start: Vec2 {
        switch self {
        case .line(let p0, _): return p0
        case .cubic(let p0, _, _, _): return p0
        }
    }

    public var end: Vec2 {
        switch self {
        case .line(_, let p1): return p1
        case .cubic(_, _, _, let p3): return p3
        }
    }
}

public struct SkeletonArtifact: Codable, Equatable, Sendable, InvariantCheckable {
    public let id: ArtifactID
    public let policy: DeterminismPolicy
    public let segments: [SkeletonSegment]
    public let totalLength: Double
    public let debug: DebugBundle?

    public init(id: ArtifactID, policy: DeterminismPolicy, segments: [SkeletonSegment], totalLength: Double, debug: DebugBundle? = nil) {
        self.id = id
        self.policy = policy
        self.segments = segments
        self.totalLength = totalLength
        self.debug = debug
    }

    public func validate() throws {
        if segments.isEmpty { throw CP2InvariantError("skeleton segments must be non-empty") }
        if totalLength <= 0 { throw CP2InvariantError("skeleton totalLength must be > 0") }
        if segments.count > 1 {
            for i in 0..<(segments.count - 1) {
                let a = segments[i].end
                let b = segments[i + 1].start
                if !Epsilon.approxEqual(a, b, eps: policy.eps) {
                    throw CP2InvariantError("skeleton continuity violated", context: "segment \(i) end != segment \(i + 1) start")
                }
            }
        }
    }
}

public struct SegmentArcMapping: Codable, Equatable, Sendable {
    public let globalTs: [Double]
    public let segmentIndices: [Int]
    public let localUs: [Double]
    public let arcLengths: [Double]

    public init(globalTs: [Double], segmentIndices: [Int], localUs: [Double], arcLengths: [Double]) {
        self.globalTs = globalTs
        self.segmentIndices = segmentIndices
        self.localUs = localUs
        self.arcLengths = arcLengths
    }
}

public struct ParameterizationArtifact: Codable, Equatable, Sendable, InvariantCheckable {
    public let id: ArtifactID
    public let policy: DeterminismPolicy
    public let skeletonId: ArtifactID
    public let arcSamples: Int
    public let mapping: SegmentArcMapping
    public let debug: DebugBundle?

    public init(id: ArtifactID, policy: DeterminismPolicy, skeletonId: ArtifactID, arcSamples: Int, mapping: SegmentArcMapping, debug: DebugBundle? = nil) {
        self.id = id
        self.policy = policy
        self.skeletonId = skeletonId
        self.arcSamples = arcSamples
        self.mapping = mapping
        self.debug = debug
    }

    public func validate() throws {
        if arcSamples < 2 { throw CP2InvariantError("arcSamples must be >= 2") }
        let count = mapping.globalTs.count
        if count == 0 || mapping.segmentIndices.count != count || mapping.localUs.count != count || mapping.arcLengths.count != count {
            throw CP2InvariantError("mapping arrays must have equal non-zero counts")
        }
        for i in 0..<(count - 1) {
            if mapping.globalTs[i + 1] + policy.eps < mapping.globalTs[i] {
                throw CP2InvariantError("globalTs must be monotone non-decreasing")
            }
        }
        if let first = mapping.globalTs.first, let last = mapping.globalTs.last {
            if abs(first - 0.0) > policy.eps || abs(last - 1.0) > policy.eps {
                throw CP2InvariantError("globalT endpoints must map to 0 and 1 within eps")
            }
        }
    }
}

public struct SampleAttributes: Codable, Equatable, Sendable {
    public let widthLeft: Double?
    public let widthRight: Double?
    public let theta: Double?
    public let offset: Double?
    public let alpha: Double?

    public init(widthLeft: Double? = nil, widthRight: Double? = nil, theta: Double? = nil, offset: Double? = nil, alpha: Double? = nil) {
        self.widthLeft = widthLeft
        self.widthRight = widthRight
        self.theta = theta
        self.offset = offset
        self.alpha = alpha
    }
}

public struct SamplePoint: Codable, Equatable, Sendable {
    public let globalT: Double
    public let pos: Vec2
    public let tan: Vec2?
    public let attrs: SampleAttributes

    public init(globalT: Double, pos: Vec2, tan: Vec2? = nil, attrs: SampleAttributes) {
        self.globalT = globalT
        self.pos = pos
        self.tan = tan
        self.attrs = attrs
    }
}

public struct SamplesArtifact: Codable, Equatable, Sendable, InvariantCheckable {
    public let id: ArtifactID
    public let policy: DeterminismPolicy
    public let skeletonId: ArtifactID
    public let samples: [SamplePoint]
    public let debug: DebugBundle?

    public init(id: ArtifactID, policy: DeterminismPolicy, skeletonId: ArtifactID, samples: [SamplePoint], debug: DebugBundle? = nil) {
        self.id = id
        self.policy = policy
        self.skeletonId = skeletonId
        self.samples = samples
        self.debug = debug
    }

    public func validate() throws {
        if samples.count < 2 { throw CP2InvariantError("samples must contain at least 2 points") }
        if abs(samples.first!.globalT - 0.0) > policy.eps {
            throw CP2InvariantError("samples must include t=0 within eps")
        }
        if abs(samples.last!.globalT - 1.0) > policy.eps {
            throw CP2InvariantError("samples must include t=1 within eps")
        }
        for i in 0..<(samples.count - 1) {
            if samples[i + 1].globalT <= samples[i].globalT + policy.eps {
                throw CP2InvariantError("samples must be strictly increasing in globalT")
            }
        }
        for i in 0..<(samples.count - 1) {
            if (samples[i + 1].pos - samples[i].pos).length <= policy.eps {
                throw CP2InvariantError("samples must not contain duplicate positions within eps")
            }
        }
    }
}

public struct RailsArtifact: Codable, Equatable, Sendable, InvariantCheckable {
    public let id: ArtifactID
    public let policy: DeterminismPolicy
    public let samplesId: ArtifactID
    public let sampleCount: Int
    public let left: [Vec2]
    public let right: [Vec2]
    public let debug: DebugBundle?

    public init(id: ArtifactID, policy: DeterminismPolicy, samplesId: ArtifactID, sampleCount: Int, left: [Vec2], right: [Vec2], debug: DebugBundle? = nil) {
        self.id = id
        self.policy = policy
        self.samplesId = samplesId
        self.sampleCount = sampleCount
        self.left = left
        self.right = right
        self.debug = debug
    }

    public func validate() throws {
        if left.count != right.count { throw CP2InvariantError("left/right rails must have equal counts") }
        if left.count != sampleCount { throw CP2InvariantError("rail count must match sampleCount") }
    }
}

public enum BoundaryChainKind: String, Codable, Sendable {
    case leftRail
    case rightRail
    case capStart
    case capEnd
    case join
    case fillet
    case other
}

public struct BoundaryChain: Codable, Equatable, Sendable {
    public let id: Int
    public let kind: BoundaryChainKind
    public let points: [Vec2]

    public init(id: Int, kind: BoundaryChainKind, points: [Vec2]) {
        self.id = id
        self.kind = kind
        self.points = points
    }
}

public struct BoundarySoupArtifact: Codable, Equatable, Sendable, InvariantCheckable {
    public let id: ArtifactID
    public let policy: DeterminismPolicy
    public let railsId: ArtifactID
    public let chains: [BoundaryChain]
    public let debug: DebugBundle?

    public init(id: ArtifactID, policy: DeterminismPolicy, railsId: ArtifactID, chains: [BoundaryChain], debug: DebugBundle? = nil) {
        self.id = id
        self.policy = policy
        self.railsId = railsId
        self.chains = chains
        self.debug = debug
    }

    public func validate() throws {
        for chain in chains {
            if chain.points.count < 2 {
                throw CP2InvariantError("boundary chain must have at least 2 points", context: "chain \(chain.id)")
            }
        }
    }
}

public enum RingWinding: String, Codable, Sendable {
    case cw
    case ccw
}

public struct Ring: Codable, Equatable, Sendable {
    public let points: [Vec2]
    public let winding: RingWinding
    public let area: Double

    public init(points: [Vec2], winding: RingWinding, area: Double) {
        self.points = points
        self.winding = winding
        self.area = area
    }
}

public struct RingsArtifact: Codable, Equatable, Sendable, InvariantCheckable {
    public let id: ArtifactID
    public let policy: DeterminismPolicy
    public let soupId: ArtifactID
    public let rings: [Ring]
    public let debug: DebugBundle?

    public init(id: ArtifactID, policy: DeterminismPolicy, soupId: ArtifactID, rings: [Ring], debug: DebugBundle? = nil) {
        self.id = id
        self.policy = policy
        self.soupId = soupId
        self.rings = rings
        self.debug = debug
    }

    public func validate() throws {
        for (index, ring) in rings.enumerated() {
            if ring.points.count < 4 {
                throw CP2InvariantError("ring must have >= 4 points including closure", context: "ring \(index)")
            }
            if !Epsilon.approxEqual(ring.points.first!, ring.points.last!, eps: policy.eps) {
                throw CP2InvariantError("ring must be closed within eps", context: "ring \(index)")
            }
            if abs(ring.area) <= policy.eps {
                throw CP2InvariantError("ring must have non-zero area", context: "ring \(index)")
            }
        }
    }
}

public struct SilhouetteArtifact: Codable, Equatable, Sendable, InvariantCheckable {
    public let id: ArtifactID
    public let policy: DeterminismPolicy
    public let sourceRingIds: [ArtifactID]
    public let finalRings: [Ring]
    public let debug: DebugBundle?

    public init(id: ArtifactID, policy: DeterminismPolicy, sourceRingIds: [ArtifactID], finalRings: [Ring], debug: DebugBundle? = nil) {
        self.id = id
        self.policy = policy
        self.sourceRingIds = sourceRingIds
        self.finalRings = finalRings
        self.debug = debug
    }

    public func validate() throws {
        for (index, ring) in finalRings.enumerated() {
            if ring.points.count < 4 {
                throw CP2InvariantError("silhouette ring must have >= 4 points including closure", context: "ring \(index)")
            }
            if !Epsilon.approxEqual(ring.points.first!, ring.points.last!, eps: policy.eps) {
                throw CP2InvariantError("silhouette ring must be closed within eps", context: "ring \(index)")
            }
            if abs(ring.area) <= policy.eps {
                throw CP2InvariantError("silhouette ring must have non-zero area", context: "ring \(index)")
            }
        }
    }
}
