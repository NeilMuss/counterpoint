import Foundation
import CP2Geometry
import CP2Skeleton

func emitSweepDiagnostics(
    options: CLIOptions,
    path: SkeletonPath,
    pathParam: SkeletonPathParameterization,
    plan: SweepPlan,
    result: SweepResult,
    joinGTs: [Double]
) {
    if options.debugSweep || options.verbose {
        let ringCount = result.rings.count
        let ring = result.ring
        let vertexCount = ring.count
        let firstPoint = ring.first ?? Vec2(0, 0)
        let lastPoint = ring.last ?? Vec2(0, 0)
        let closure = (firstPoint - lastPoint).length
        let area = signedArea(ring)
        let absArea = abs(area)
        let winding: String
        if area < -Epsilon.defaultValue {
            winding = "CW"
        } else if area > Epsilon.defaultValue {
            winding = "CCW"
        } else {
            winding = "flat"
        }
        let sweepSegments = result.segmentsUsed
        let sweepSegmentsCount = sweepSegments.count
        let sampleCountUsed = sampleCountFromSoup(sweepSegments)

        if options.adaptiveSampling {
            print("sweep samplingMode=adaptive samples=\(sampleCountUsed) flatnessEps=\(String(format: "%.4f", options.flatnessEps)) maxDepth=\(options.maxDepth) maxSamples=\(options.maxSamples)")
        } else {
            print("sweep samplingMode=fixed samples=\(plan.sweepSampleCount)")
        }
        print("sweep segments=\(sweepSegmentsCount) rings=\(ringCount)")
        print(String(format: "sweep ringVertices=%d closure=%.6f area=%.6f absArea=%.6f winding=%@", vertexCount, closure, area, absArea, winding))
        
        if !joinGTs.isEmpty {
            let joinList = joinGTs.map { String(format: "%.4f", $0) }.joined(separator: ", ")
            print("sweep joinGTs=[\(joinList)]")
            let joinProbeOffsets: [Double] = [-0.02, -0.01, 0.0, 0.01, 0.02]
            var joinProbeGT: [Double] = []
            for join in joinGTs {
                for offset in joinProbeOffsets {
                    let gt = max(0.0, min(1.0, join + offset))
                    joinProbeGT.append(gt)
                }
            }
            let joinWidths = joinProbeGT.map { plan.scaledWidthAtT($0) }
            let joinWidthList = joinWidths.map { String(format: "%.4f", $0) }.joined(separator: ", ")
            let joinGTList = joinProbeGT.map { String(format: "%.4f", $0) }.joined(separator: ", ")
            print("sweep joinWidthProbes=[\(joinWidthList)] gt=[\(joinGTList)]")
            if ring.count > 3 {
                let ringPoints = stripDuplicateClosure(ring)
                let halfWindow = 8
                for (index, join) in joinGTs.enumerated() {
                    let center = pathParam.position(globalT: join)
                    let nearest = nearestIndex(points: ringPoints, to: center)
                    let deviation = chordDeviation(points: ringPoints, centerIndex: nearest, halfWindow: halfWindow)
                    let widthAtJoin = plan.scaledWidthAtT(join)
                    let ratio = deviation / max(Epsilon.defaultValue, widthAtJoin)
                    print(String(format: "sweep joinBulge[%d] dev=%.6f ratio=%.6f", index, deviation, ratio))
                }
            }
        }
        
        if ring.count > 3 {
            let ringPoints = stripDuplicateClosure(ring)
            let widthMetric = max(Epsilon.defaultValue, plan.scaledWidthAtT(0.5))
            let metrics = analyzeScallops(
                points: ringPoints,
                width: widthMetric,
                halfWindow: 20,
                epsilon: 1.0e-6,
                cornerThreshold: 2.5,
                capTrim: 4
            )
            print(String(format: "sweep scallopWindow center=%d window=%d", metrics.centerIndex, metrics.windowSize))
            print(String(format: "sweep scallopMetricsRaw extrema=%d peaks=%d maxDev=%.6f ratio=%.6f", metrics.raw.turnExtremaCount, metrics.raw.chordPeakCount, metrics.raw.maxChordDeviation, metrics.raw.normalizedMaxChordDeviation))
            print(String(format: "sweep scallopMetricsFiltered extrema=%d peaks=%d maxDev=%.6f ratio=%.6f", metrics.filtered.turnExtremaCount, metrics.filtered.chordPeakCount, metrics.filtered.maxChordDeviation, metrics.filtered.normalizedMaxChordDeviation))
        }
        
        let widthMin = plan.widths.min() ?? plan.sweepWidth
        let widthMax = plan.widths.max() ?? plan.sweepWidth
        let heightMin = plan.sweepHeight
        let heightMax = plan.sweepHeight
        let probeGT: [Double] = [0.0, 0.25, 0.5, 0.75, 1.0]
        let probeWidths = probeGT.map { plan.scaledWidthAtT($0) }
        let probeHeights = probeGT.map { _ in plan.sweepHeight }
        let widthList = probeWidths.map { String(format: "%.4f", $0) }.joined(separator: ", ")
        let heightList = probeHeights.map { String(format: "%.4f", $0) }.joined(separator: ", ")
        let thetaValues = plan.sweepGT.map { plan.thetaAtT($0) * 180.0 / Double.pi }
        let thetaMin = thetaValues.min() ?? 0.0
        let thetaMax = thetaValues.max() ?? 0.0
        let thetaProbes = probeGT.map { plan.thetaAtT($0) * 180.0 / Double.pi }
        let thetaList = thetaProbes.map { String(format: "%.4f", $0) }.joined(separator: ", ")
        let alphaValues = plan.sweepGT.map { plan.alphaAtT($0) }
        let alphaMin = alphaValues.min() ?? 0.0
        let alphaMax = alphaValues.max() ?? 0.0
        let alphaProbes = probeGT.map { plan.alphaAtT($0) }
        let alphaList = alphaProbes.map { String(format: "%.4f", $0) }.joined(separator: ", ")
        let endProbeGT: [Double] = [0.80, 0.85, 0.90, 0.95, 1.00]
        let endWidths = endProbeGT.map { plan.scaledWidthAtT($0) }
        let endWidthList = endWidths.map { String(format: "%.4f", $0) }.joined(separator: ", ")
        
        print(String(format: "sweep widthMin=%.4f widthMax=%.4f heightMin=%.4f heightMax=%.4f", widthMin * plan.widthScale, widthMax * plan.widthScale, heightMin, heightMax))
        print("sweep widthProbes=[\(widthList)] gt=[0,0.25,0.5,0.75,1]")
        print("sweep widthEndProbes=[\(endWidthList)] gt=[0.80,0.85,0.90,0.95,1.00]")
        print("sweep heightProbes=[\(heightList)] gt=[0,0.25,0.5,0.75,1]")
        print(String(format: "sweep thetaMin=%.4f thetaMax=%.4f", thetaMin, thetaMax))
        print("sweep thetaProbes=[\(thetaList)] gt=[0,0.25,0.5,0.75,1]")
        print(String(format: "sweep alphaMin=%.4f alphaMax=%.4f alphaWindow=[%.2f..1.00]", alphaMin, alphaMax, plan.alphaStartGT))
        print("sweep alphaProbes=[\(alphaList)] gt=[0,0.25,0.5,0.75,1]")
    }
}
