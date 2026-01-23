import CP2Geometry

/// Holds the varying parameters for a sweep operation.
///
/// Note: CP2Skeleton stays independent of JSON/spec keyframe types.
/// The CLI/spec layer evaluates keyframes into closures and passes them in here.
public struct SweepParameters {
    public let widthAtT: (Double) -> Double
    public let offsetAtT: (Double) -> Double

    public init(
        widthAtT: @escaping (Double) -> Double,
        offsetAtT: @escaping (Double) -> Double
    ) {
        self.widthAtT = widthAtT
        self.offsetAtT = offsetAtT
    }

    /// Returns width at parameter `t`.
    public func width(at t: Double) -> Double { widthAtT(t) }

    /// Returns offset at parameter `t`.
    public func offset(at t: Double) -> Double { offsetAtT(t) }
}



/// Represents a fully computed sample point on the skeleton path, including its local frame and rail points.
public struct SweepSample {
    public let t: Double          // Global parameter on the skeleton path [0, 1]
    public let position: Vec2     // Position on the skeleton path
    public var tangent: Vec2      // Tangent of the skeleton path
    public var normal: Vec2       // Normal of the skeleton path (perp to tangent)
    
    public var railLeft: Vec2     // The computed left rail point
    public var railRight: Vec2    // The computed right rail point
    
    // Width and offset at this sample
    public let width: Double
    public let offset: Double

    public init(
        t: Double,
        position: Vec2,
        tangent: Vec2,
        normal: Vec2,
        railLeft: Vec2,
        railRight: Vec2,
        width: Double,
        offset: Double
    ) {
        self.t = t
        self.position = position
        self.tangent = tangent
        self.normal = normal
        self.railLeft = railLeft
        self.railRight = railRight
        self.width = width
        self.offset = offset
    }
}
