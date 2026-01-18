import Domain

public struct RailChainBumpMetric: Equatable {
    public let side: RailSide
    public let chainGT: Double
    public let position: Vec2
    public let curvatureMagnitude: Double

    public init(side: RailSide, chainGT: Double, position: Vec2, curvatureMagnitude: Double) {
        self.side = side
        self.chainGT = chainGT
        self.position = position
        self.curvatureMagnitude = curvatureMagnitude
    }
}

public func measureRailChainBumpMetric(
    _ window: RailChain2Window,
    side: RailSide
) -> RailChainBumpMetric? {
    guard let bump = detectRailChainBump(window, side: side) else { return nil }
    return RailChainBumpMetric(
        side: bump.side,
        chainGT: bump.chainGT,
        position: bump.position,
        curvatureMagnitude: bump.curvatureMagnitude
    )
}
