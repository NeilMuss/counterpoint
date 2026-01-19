public struct BumpWindow: Codable, Equatable {
    public let chainId: Int?
    public let side: RailSide
    public let gt0: Double
    public let gt1: Double

    public init(chainId: Int? = nil, side: RailSide, gt0: Double, gt1: Double) {
        self.chainId = chainId
        self.side = side
        self.gt0 = gt0
        self.gt1 = gt1
    }
}

public struct BumpSmoothingPolicy: Codable, Equatable {
    public let iterations: Int
    public let strength: Double
    public let preserveEndpoints: Bool
    public let preserveGT: Bool

    public init(iterations: Int, strength: Double, preserveEndpoints: Bool = true, preserveGT: Bool = true) {
        self.iterations = iterations
        self.strength = strength
        self.preserveEndpoints = preserveEndpoints
        self.preserveGT = preserveGT
    }
}
