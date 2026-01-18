public typealias Vec2 = Point

public enum RailSide: String, Codable, Equatable {
    case left
    case right
}

public struct RailSample2: Codable, Equatable {
    public let p: Vec2
    public let n: Vec2
    public let lt: Double
    public let sourceGT: Double?
    public let chainGT: Double?

    public init(p: Vec2, n: Vec2, lt: Double, sourceGT: Double? = nil, chainGT: Double? = nil) {
        self.p = p
        self.n = n
        self.lt = lt
        self.sourceGT = sourceGT
        self.chainGT = chainGT
    }
}

public struct RailRun2: Codable, Equatable {
    public let id: Int
    public let side: RailSide
    public let samples: [RailSample2]
    public let inkLength: Double
    public let sortKey: Double

    public init(id: Int, side: RailSide, samples: [RailSample2], inkLength: Double, sortKey: Double) {
        self.id = id
        self.side = side
        self.samples = samples
        self.inkLength = inkLength
        self.sortKey = sortKey
    }
}

public enum ChainEdgeKind: String, Codable, Equatable {
    case ink
    case connector
}

public struct ChainEdge2: Codable, Equatable {
    public let kind: ChainEdgeKind
    public let a: Vec2
    public let b: Vec2
    public let fromRun: Int?
    public let toRun: Int?
    public let length: Double
    public let contributesToMetric: Bool

    public init(
        kind: ChainEdgeKind,
        a: Vec2,
        b: Vec2,
        fromRun: Int? = nil,
        toRun: Int? = nil,
        length: Double,
        contributesToMetric: Bool
    ) {
        self.kind = kind
        self.a = a
        self.b = b
        self.fromRun = fromRun
        self.toRun = toRun
        self.length = length
        self.contributesToMetric = contributesToMetric
    }
}

public struct RailChain2: Codable, Equatable {
    public let side: RailSide
    public let runs: [RailRun2]
    public let edges: [ChainEdge2]
    public let metricLength: Double

    public init(side: RailSide, runs: [RailRun2], edges: [ChainEdge2], metricLength: Double) {
        self.side = side
        self.runs = runs
        self.edges = edges
        self.metricLength = metricLength
    }
}
