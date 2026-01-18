public struct RailChainPoint: Equatable {
    public let point: Point
    public let localT: Double
    public let globalT: Double

    public init(point: Point, localT: Double, globalT: Double) {
        self.point = point
        self.localT = localT
        self.globalT = globalT
    }
}

public struct RailRun: Equatable {
    public let id: Int
    public let left: [RailChainPoint]
    public let right: [RailChainPoint]

    public init(id: Int, left: [RailChainPoint], right: [RailChainPoint]) {
        self.id = id
        self.left = left
        self.right = right
    }
}

public struct RailRunRange: Equatable {
    public let id: Int
    public let gtStart: Double
    public let gtEnd: Double

    public init(id: Int, gtStart: Double, gtEnd: Double) {
        self.id = id
        self.gtStart = gtStart
        self.gtEnd = gtEnd
    }
}

public struct RailChain: Equatable {
    public let runs: [RailRun]
    public let left: [RailChainPoint]
    public let right: [RailChainPoint]
    public let ranges: [RailRunRange]

    public init(runs: [RailRun], left: [RailChainPoint], right: [RailChainPoint], ranges: [RailRunRange]) {
        self.runs = runs
        self.left = left
        self.right = right
        self.ranges = ranges
    }
}
