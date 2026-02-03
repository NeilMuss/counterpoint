import Foundation

public struct SamplingConfig: Sendable, Equatable {
    public var mode: Mode = .adaptive
    public var flatnessEps: Double = 0.25     // world units
    public var railEps: Double = 0.25         // world units
    public var paramEps: Double? = nil        // dimensionless (optional)
    public var attrEpsOffset: Double = 0.25   // world units
    public var attrEpsWidth: Double = 0.25    // world units
    public var attrEpsAngle: Double = 0.00436 // radians (default ~0.25deg)
    public var attrEpsAlpha: Double = 0.25    // dimensionless

    public var maxDepth: Int = 12
    public var maxSamples: Int = 512

    // de-dup/ordering stability
    public var tEps: Double = 1e-9

    public enum Mode: Sendable, Equatable {
        case fixed(count: Int)     // evenly spaced in global-t
        case adaptive              // recursive subdivision
    }

    public init() {}
}
