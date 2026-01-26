import Foundation

struct SpecParamProvider: StrokeParamProvider {
    let params: StrokeParams

    func makeParamFuncs(options: CLIOptions, exampleName: String?, sweepWidth: Double) -> StrokeParamFuncs {
        let alphaStartGT = options.alphaStartGT
        let angleMode = params.angleMode ?? .relative
        let alphaEndValue = options.alphaEnd ?? 0.0
        let paramKeyframeTs = collectKeyframeTs()

        let widthTrack = params.width.map { ParamTrack.fromKeyframedScalar($0, mode: .hermiteMonotone) }
        let widthLeftTrack = params.widthLeft.map { ParamTrack.fromKeyframedScalar($0, mode: .hermiteMonotone) }
        let widthRightTrack = params.widthRight.map { ParamTrack.fromKeyframedScalar($0, mode: .hermiteMonotone) }
        let thetaTrack = params.theta.map { ParamTrack.fromKeyframedScalar($0, mode: .linear) }
        let offsetTrack = params.offset.map { ParamTrack.fromKeyframedScalar($0, mode: .linear) }
        let alphaTrack = params.alpha.map { ParamTrack.fromKeyframedScalar($0, mode: .linear) }

        let widthLegacyAtT: (Double) -> Double = { t in
            if let widthTrack { return widthTrack.value(at: t) }
            return sweepWidth
        }

        let widthLeftAtT: (Double) -> Double = { t in
            if let widthLeftTrack {
                return widthLeftTrack.value(at: t)
            }
            if params.widthRight != nil {
                if params.width != nil {
                    return widthLegacyAtT(t) * 0.5
                }
                return widthRightTrack?.value(at: t) ?? (sweepWidth * 0.5)
            }
            if params.width != nil {
                return widthLegacyAtT(t) * 0.5
            }
            return sweepWidth * 0.5
        }

        let widthLeftSegmentAlphaAtT: (Double) -> Double = { t in
            if let widthLeftTrack {
                return widthLeftTrack.segmentAlpha(at: t)
            }
            if params.widthRight != nil {
                if params.width != nil {
                    return widthTrack?.segmentAlpha(at: t) ?? 0.0
                }
                return widthRightTrack?.segmentAlpha(at: t) ?? 0.0
            }
            if params.width != nil {
                return widthTrack?.segmentAlpha(at: t) ?? 0.0
            }
            return 0.0
        }

        let widthRightAtT: (Double) -> Double = { t in
            if let widthRightTrack {
                return widthRightTrack.value(at: t)
            }
            if params.widthLeft != nil {
                if params.width != nil {
                    return widthLegacyAtT(t) * 0.5
                }
                return widthLeftTrack?.value(at: t) ?? (sweepWidth * 0.5)
            }
            if params.width != nil {
                return widthLegacyAtT(t) * 0.5
            }
            return sweepWidth * 0.5
        }

        let widthRightSegmentAlphaAtT: (Double) -> Double = { t in
            if let widthRightTrack {
                return widthRightTrack.segmentAlpha(at: t)
            }
            if params.widthLeft != nil {
                if params.width != nil {
                    return widthTrack?.segmentAlpha(at: t) ?? 0.0
                }
                return widthLeftTrack?.segmentAlpha(at: t) ?? 0.0
            }
            if params.width != nil {
                return widthTrack?.segmentAlpha(at: t) ?? 0.0
            }
            return 0.0
        }

        let widthAtT: (Double) -> Double = { t in
            widthLeftAtT(t) + widthRightAtT(t)
        }
        let thetaAtT: (Double) -> Double = { t in
            if let thetaTrack { return thetaTrack.value(at: t) * Double.pi / 180.0 }
            return 0.0
        }
        let offsetAtT: (Double) -> Double = { t in
            if let offsetTrack { return offsetTrack.value(at: t) }
            return 0.0
        }
        let alphaAtT: (Double) -> Double = { t in
            if let alphaTrack { return alphaTrack.value(at: t) }
            if t < alphaStartGT { return 0.0 }
            let phase = (t - alphaStartGT) / max(1.0e-12, 1.0 - alphaStartGT)
            return alphaEndValue * max(0.0, min(1.0, phase))
        }

        let usesVariableWidthAngleAlpha = params.width != nil || params.widthLeft != nil || params.widthRight != nil || params.theta != nil || params.offset != nil || params.alpha != nil

        return StrokeParamFuncs(
            alphaStartGT: alphaStartGT,
            alphaEndValue: alphaEndValue,
            widthAtT: widthAtT,
            widthLeftAtT: widthLeftAtT,
            widthRightAtT: widthRightAtT,
            widthLeftSegmentAlphaAtT: widthLeftSegmentAlphaAtT,
            widthRightSegmentAlphaAtT: widthRightSegmentAlphaAtT,
            thetaAtT: thetaAtT,
            offsetAtT: offsetAtT,
            alphaAtT: alphaAtT,
            usesVariableWidthAngleAlpha: usesVariableWidthAngleAlpha,
            angleMode: angleMode,
            paramKeyframeTs: paramKeyframeTs
        )
    }

    private func collectKeyframeTs() -> [Double] {
        var ts: [Double] = []
        if let width = params.width { ts.append(contentsOf: width.keyframes.map { $0.t }) }
        if let widthLeft = params.widthLeft { ts.append(contentsOf: widthLeft.keyframes.map { $0.t }) }
        if let widthRight = params.widthRight { ts.append(contentsOf: widthRight.keyframes.map { $0.t }) }
        if let offset = params.offset { ts.append(contentsOf: offset.keyframes.map { $0.t }) }
        if let theta = params.theta { ts.append(contentsOf: theta.keyframes.map { $0.t }) }
        ts.append(contentsOf: [0.0, 1.0])
        let sorted = ts.sorted()
        var result: [Double] = []
        result.reserveCapacity(sorted.count)
        var last: Double? = nil
        for t in sorted {
            let clamped = max(0.0, min(1.0, t))
            if let previous = last, abs(clamped - previous) <= 1.0e-9 {
                continue
            }
            result.append(clamped)
            last = clamped
        }
        return result
    }
}
