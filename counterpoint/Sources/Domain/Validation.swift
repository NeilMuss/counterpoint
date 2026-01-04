import Foundation

public protocol SpecValidating {
    func validate(_ spec: StrokeSpec) throws
}

public struct StrokeSpecValidationError: LocalizedError {
    public let messages: [String]

    public init(messages: [String]) {
        self.messages = messages
    }

    public var errorDescription: String? {
        messages.joined(separator: "\n")
    }
}

public struct StrokeSpecValidator: SpecValidating {
    public init() {}

    public func validate(_ spec: StrokeSpec) throws {
        var errors: [String] = []

        if spec.path.segments.isEmpty {
            errors.append("Path must contain at least one cubic segment.")
        }

        for (index, segment) in spec.path.segments.enumerated() {
            if !segment.p0.isFinite || !segment.p1.isFinite || !segment.p2.isFinite || !segment.p3.isFinite {
                errors.append("Path segment \(index) contains non-finite control points.")
            }
        }

        validate(track: spec.width, name: "width", mustBePositive: true, errors: &errors)
        validate(track: spec.height, name: "height", mustBePositive: true, errors: &errors)
        validate(track: spec.theta, name: "theta", mustBePositive: false, errors: &errors)
        if let offset = spec.offset {
            validate(track: offset, name: "offset", mustBePositive: false, errors: &errors)
        }
        if let alpha = spec.alpha {
            validate(track: alpha, name: "alpha", mustBePositive: false, errors: &errors)
        }

        if let debug = spec.debugReference {
            if debug.svgPathD.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append("DebugReference svgPathD must be non-empty.")
            }
            if let opacity = debug.opacity {
                if !opacity.isFinite || opacity < 0.0 || opacity > 1.0 {
                    errors.append("DebugReference opacity must be in [0,1].")
                }
            }
        }
        if let background = spec.backgroundGlyph {
            if background.svgPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append("BackgroundGlyph svgPath must be non-empty.")
            }
            if !background.strokeWidth.isFinite || background.strokeWidth < 0.0 {
                errors.append("BackgroundGlyph strokeWidth must be non-negative and finite.")
            }
            if !background.opacity.isFinite || background.opacity < 0.0 || background.opacity > 1.0 {
                errors.append("BackgroundGlyph opacity must be in [0,1].")
            }
            if !background.zoom.isFinite || background.zoom <= 0.0 {
                errors.append("BackgroundGlyph zoom must be positive and finite.")
            }
        }

        if case .miter(let limit) = spec.joinStyle {
            if !limit.isFinite || limit <= 0 {
                errors.append("JoinStyle miterLimit must be a positive finite value.")
            }
        }

        if spec.sampling.baseSpacing <= 0 || !spec.sampling.baseSpacing.isFinite {
            errors.append("Sampling baseSpacing must be a positive finite value.")
        }
        if let maxSpacing = spec.sampling.maxSpacing {
            if maxSpacing <= 0 || !maxSpacing.isFinite {
                errors.append("Sampling maxSpacing must be a positive finite value.")
            }
        }
        if spec.sampling.keyframeDensity < 1 {
            errors.append("Sampling keyframeDensity must be >= 1.")
        }
        if spec.sampling.flatnessTolerance <= 0 || !spec.sampling.flatnessTolerance.isFinite {
            errors.append("Sampling flatnessTolerance must be a positive finite value.")
        }
        if spec.sampling.rotationThresholdDegrees <= 0 || !spec.sampling.rotationThresholdDegrees.isFinite {
            errors.append("Sampling rotationThresholdDegrees must be a positive finite value.")
        }
        if spec.sampling.minimumSpacing <= 0 || !spec.sampling.minimumSpacing.isFinite {
            errors.append("Sampling minimumSpacing must be a positive finite value.")
        }
        if spec.sampling.maxSamples <= 1 {
            errors.append("Sampling maxSamples must be greater than 1.")
        }
        if let policy = spec.samplingPolicy {
            if policy.flattenTolerance <= 0 || !policy.flattenTolerance.isFinite {
                errors.append("SamplingPolicy flattenTolerance must be positive and finite.")
            }
            if policy.envelopeTolerance < 0 || !policy.envelopeTolerance.isFinite {
                errors.append("SamplingPolicy envelopeTolerance must be non-negative and finite.")
            }
            if policy.maxSamples <= 1 {
                errors.append("SamplingPolicy maxSamples must be greater than 1.")
            }
            if policy.maxRecursionDepth <= 0 {
                errors.append("SamplingPolicy maxRecursionDepth must be greater than 0.")
            }
            if policy.minParamStep <= 0 || !policy.minParamStep.isFinite {
                errors.append("SamplingPolicy minParamStep must be positive and finite.")
            }
        }
        switch spec.counterpointShape {
        case .rectangle:
            break
        case .ellipse(let segments):
            if segments < 8 {
                errors.append("CounterpointShape ellipse segments must be >= 8.")
            }
        }

        if !errors.isEmpty {
            throw StrokeSpecValidationError(messages: errors)
        }
    }

    private func validate(track: ParamTrack, name: String, mustBePositive: Bool, errors: inout [String]) {
        if track.keyframes.isEmpty {
            errors.append("ParamTrack '\(name)' must contain at least one keyframe.")
            return
        }
        for (index, keyframe) in track.keyframes.enumerated() {
            if !keyframe.t.isFinite || !keyframe.value.isFinite {
                errors.append("ParamTrack '\(name)' keyframe \(index) contains non-finite values.")
                continue
            }
            if keyframe.t < 0.0 || keyframe.t > 1.0 {
                errors.append("ParamTrack '\(name)' keyframe \(index) has t outside [0,1].")
            }
            if mustBePositive && keyframe.value <= 0.0 {
                errors.append("ParamTrack '\(name)' keyframe \(index) must be > 0.")
            }
            if let interpolation = keyframe.interpolationToNext {
                if !interpolation.alpha.isFinite || interpolation.alpha < -1.0 || interpolation.alpha > 1.0 {
                    errors.append("ParamTrack '\(name)' keyframe \(index) interpolation alpha must be in [-1,1].")
                }
            }
        }
    }
}

private extension Point {
    var isFinite: Bool {
        x.isFinite && y.isFinite
    }
}
