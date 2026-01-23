import Foundation

public enum SamplingInvariantViolation: Error, CustomStringConvertible {
    case missingEndpoints
    case nonMonotone
    case tooManySamples(max: Int, got: Int)

    public var description: String {
        switch self {
        case .missingEndpoints: return "Sampling invariant violated: missing endpoints t=0 and/or t=1."
        case .nonMonotone: return "Sampling invariant violated: ts must be strictly increasing."
        case .tooManySamples(let max, let got):
            return "Sampling invariant violated: ts count \(got) exceeds maxSamples \(max)."
        }
    }
}

public enum SamplingInvariants {
    public static func validate(ts: [Double], maxSamples: Int, tEps: Double) throws {
        guard let first = ts.first, let last = ts.last else { throw SamplingInvariantViolation.missingEndpoints }
        if abs(first - 0.0) > tEps || abs(last - 1.0) > tEps { throw SamplingInvariantViolation.missingEndpoints }

        for i in 1..<ts.count {
            if !(ts[i] > ts[i-1] + tEps) { throw SamplingInvariantViolation.nonMonotone }
        }

        if ts.count > maxSamples { throw SamplingInvariantViolation.tooManySamples(max: maxSamples, got: ts.count) }
    }
}
