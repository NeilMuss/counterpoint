import Foundation
import CP2Geometry
import CP2Skeleton

public func renderSVGString(
    options: CLIOptions,
    spec: CP2Spec?,
    warnSink: ((String) -> Void)? = nil
) throws -> String {
    let warnHandler: (String) -> Void = { message in
        if let warnSink {
            warnSink(message)
        } else {
            warn(message)
        }
    }
    var renderSettings = spec?.render ?? RenderSettings()
    if let canvas = options.canvasOverride {
        renderSettings.canvasPx = canvas
    }
    if let fit = options.fitOverride {
        renderSettings.fitMode = fit
    }
    if let padding = options.paddingOverride {
        renderSettings.paddingWorld = padding
    }
    if let clip = options.clipOverride {
        renderSettings.clipToFrame = clip
    }
    if let worldFrame = options.worldFrameOverride {
        renderSettings.worldFrame = worldFrame
    }

    var referenceLayer = spec?.reference
    if let refPath = options.referencePath ?? referenceLayer?.path {
        let base = referenceLayer ?? ReferenceLayer(path: refPath)
        referenceLayer = ReferenceLayer(
            path: refPath,
            translateWorld: options.referenceTranslate ?? base.translateWorld,
            scale: options.referenceScale ?? base.scale,
            rotateDeg: options.referenceRotateDeg ?? base.rotateDeg,
            opacity: options.referenceOpacity ?? base.opacity,
            lockPlacement: options.referenceLockOverride ?? base.lockPlacement
        )
    }

    let exampleName = options.example ?? spec?.example

    let inkSelection = pickInkPrimitive(spec?.ink, name: options.inkName)
    let inkPrimitive = inkSelection?.primitive
    let path: SkeletonPath
    var inkPaths: [SkeletonPath] = []
    var resolvedHeartline: ResolvedHeartline? = nil
    if let inkSelection, let primitive = inkSelection.primitive as InkPrimitive? {
        switch primitive {
        case .heartline(let heartline):
            let resolved = try resolveHeartline(
                name: inkSelection.name,
                heartline: heartline,
                ink: spec?.ink ?? Ink(stem: nil, entries: [:]),
                strict: options.strictHeartline,
                warn: warnHandler
            )
            resolvedHeartline = resolved
            for subpath in resolved.subpaths {
                let segments = subpath.map { cubicForSegment($0) }
                if !segments.isEmpty {
                    inkPaths.append(SkeletonPath(segments: segments))
                }
            }
        default:
            inkPaths = try buildSkeletonPaths(
                name: inkSelection.name,
                primitive: primitive,
                strict: options.strictInk,
                epsilon: 1.0e-4,
                warn: warnHandler
            )
        }
    }
    if let inkPath = inkPaths.first {
        if inkPaths.count > 1 {
            warnHandler("ink continuity warning: multiple subpaths detected; sweeping first only")
            if options.strictInk || options.strictHeartline {
                throw InkContinuityError.discontinuity(name: inkSelection?.name ?? "ink", index: 0, dist: 0.0)
            }
        }
        path = inkPath
    } else if exampleName?.lowercased() == "scurve" {
        path = SkeletonPath(segments: [sCurveFixtureCubic()])
    } else if exampleName?.lowercased() == "fast_scurve" {
        path = SkeletonPath(segments: [fastSCurveFixtureCubic()])
    } else if exampleName?.lowercased() == "fast_scurve2" {
        path = SkeletonPath(segments: [fastSCurve2FixtureCubic()])
    } else if exampleName?.lowercased() == "twoseg" {
        path = twoSegFixturePath()
    } else if exampleName?.lowercased() == "jstem" {
        path = jStemFixturePath()
    } else if exampleName?.lowercased() == "j" {
        path = jFullFixturePath()
    } else if exampleName?.lowercased() == "j_serif_only" {
        path = jSerifOnlyFixturePath()
    } else if exampleName?.lowercased() == "poly3" {
        path = poly3FixturePath()
    } else {
        let line = lineCubic(from: Vec2(0, 0), to: Vec2(0, 100))
        path = SkeletonPath(segments: [line])
    }
    let sweepSampleCount = 64
    let sweepWidth = 20.0
    let sweepHeight = 10.0
    let sweepAngle = 0.0
    let paramSamplesPerSegment = options.arcSamples
    let widthAtT: (Double) -> Double
    let thetaAtT: (Double) -> Double
    let alphaAtT: (Double) -> Double
    let alphaStartGT = options.alphaStartGT
    let example = exampleName?.lowercased()
    let alphaEndValue: Double = {
        if example == "j" {
            return options.alphaEnd ?? -0.35
        }
        if example == "line_end_ramp" {
            return options.alphaEnd ?? 0.0
        }
        return options.alphaEnd ?? 0.0
    }()
    if example == "j" || example == "j_serif_only" {
        widthAtT = { t in
            let clamped = max(0.0, min(1.0, t))
            let midT = 0.45
            let start = 16.0
            let mid = 22.0
            let end = 16.0
            if clamped <= midT {
                let u = clamped / midT
                return start + (mid - start) * u
            }
            let u = (clamped - midT) / (1.0 - midT)
            return mid + (end - mid) * u
        }
        thetaAtT = { t in
            let clamped = max(0.0, min(1.0, t))
            let midT = 0.5
            let start = 12.0
            let mid = 4.0
            let end = 0.0
            let deg: Double
            if clamped <= midT {
                let u = clamped / midT
                deg = start + (mid - start) * u
            } else {
                let u = (clamped - midT) / (1.0 - midT)
                deg = mid + (end - mid) * u
            }
            return deg * Double.pi / 180.0
        }
        alphaAtT = { t in
            if t < alphaStartGT {
                return 0.0
            }
            let phase = (t - alphaStartGT) / max(1.0e-12, 1.0 - alphaStartGT)
            return alphaEndValue * max(0.0, min(1.0, phase))
        }
    } else if example == "line_end_ramp" {
        let rampStart = options.widthRampStartGT
        let start = options.widthStart
        let end = options.widthEnd
        widthAtT = { t in
            if t < rampStart {
                return start
            }
            let phase = (t - rampStart) / max(1.0e-12, 1.0 - rampStart)
            return start + (end - start) * max(0.0, min(1.0, phase))
        }
        thetaAtT = { _ in 0.0 }
        alphaAtT = { t in
            if t < alphaStartGT {
                return 0.0
            }
            let phase = (t - alphaStartGT) / max(1.0e-12, 1.0 - alphaStartGT)
            return alphaEndValue * max(0.0, min(1.0, phase))
        }
    } else if example == "poly3" {
        widthAtT = { t in
            let clamped = max(0.0, min(1.0, t))
            let midT = 0.5
            let start = 16.0
            let mid = 28.0
            let end = 16.0
            if clamped <= midT {
                let u = clamped / midT
                return start + (mid - start) * u
            }
            let u = (clamped - midT) / (1.0 - midT)
            return mid + (end - mid) * u
        }
        thetaAtT = { _ in 0.0 }
        alphaAtT = { t in
            if t < alphaStartGT {
                return 0.0
            }
            let phase = (t - alphaStartGT) / max(1.0e-12, 1.0 - alphaStartGT)
            return alphaEndValue * max(0.0, min(1.0, phase))
        }
    } else {
        widthAtT = { _ in sweepWidth }
        thetaAtT = { _ in 0.0 }
        alphaAtT = { _ in 0.0 }
    }

    let sweepGT: [Double] = (0..<sweepSampleCount).map {
        Double($0) / Double(max(1, sweepSampleCount - 1))
    }
    let baselineWidth = sweepWidth
    let warpT: (Double) -> Double = { t in
        let alphaValue = alphaAtT(t)
        if t <= alphaStartGT || abs(alphaValue) <= Epsilon.defaultValue {
            return t
        }
        let span = max(Epsilon.defaultValue, 1.0 - alphaStartGT)
        let phase = max(0.0, min(1.0, (t - alphaStartGT) / span))
        let exponent = max(0.05, 1.0 + alphaValue)
        let biased = pow(phase, exponent)
        return alphaStartGT + biased * span
    }
    let widths = sweepGT.map { widthAtT(warpT($0)) }
    let meanWidth = widths.reduce(0.0, +) / Double(max(1, widths.count))
    let widthScale = (options.normalizeWidth && options.example?.lowercased() == "j" && meanWidth > Epsilon.defaultValue)
        ? (baselineWidth / meanWidth)
        : 1.0
    let scaledWidthAtT: (Double) -> Double = { t in
        widthAtT(t) * widthScale
    }

    let pathParam = SkeletonPathParameterization(path: path, samplesPerSegment: paramSamplesPerSegment)
    if options.verbose || options.debugParam {
        let segmentCount = path.segments.count
        var lengths: [Double] = []
        lengths.reserveCapacity(segmentCount)
        for segment in path.segments {
            let subPath = SkeletonPath(segment)
            let param = ArcLengthParameterization(path: subPath, samplesPerSegment: paramSamplesPerSegment)
            lengths.append(param.totalLength)
        }
        let lengthList = lengths.map { String(format: "%.6f", $0) }.joined(separator: ", ")
        print("param segments=\(segmentCount) totalLength=\(String(format: "%.6f", pathParam.totalLength)) arcSamples=\(paramSamplesPerSegment)")
        print("param segmentLengths=[\(lengthList)]")
    }

    var joinGTs: [Double] = []
    if options.debugSweep, path.segments.count > 1 {
        var lengths: [Double] = []
        lengths.reserveCapacity(path.segments.count)
        for segment in path.segments {
            let subPath = SkeletonPath(segment)
            let param = ArcLengthParameterization(path: subPath, samplesPerSegment: paramSamplesPerSegment)
            lengths.append(param.totalLength)
        }
        let total = max(Epsilon.defaultValue, lengths.reduce(0.0, +))
        var accumulated = 0.0
        for (index, length) in lengths.enumerated() where index < lengths.count - 1 {
            accumulated += length
            joinGTs.append(accumulated / total)
        }
    }

    if options.debugParam {
        let count = max(1, options.probeCount)
        var probes: [Double] = []
        if count == 1 {
            probes = [0.0]
        } else {
            probes = (0..<count).map { Double($0) / Double(count - 1) }
        }
        for gt in probes {
            let mapping = pathParam.map(globalT: gt)
            let pos = pathParam.position(globalT: gt)
            print(String(format: "param probe gt=%.4f seg=%d u=%.6f pos=(%.6f,%.6f)", gt, mapping.segmentIndex, mapping.localU, pos.x, pos.y))
        }
    }

    let segmentsUsed: [Segment2] = {
        if example == "j" || example == "j_serif_only" || example == "poly3" {
            return boundarySoupVariableWidthAngleAlpha(
                path: path,
                height: sweepHeight,
                sampleCount: sweepSampleCount,
                arcSamplesPerSegment: paramSamplesPerSegment,
                adaptiveSampling: options.adaptiveSampling,
                flatnessEps: options.flatnessEps,
                maxDepth: options.maxDepth,
                maxSamples: options.maxSamples,
                widthAtT: { t in scaledWidthAtT(warpT(t)) },
                angleAtT: { t in thetaAtT(warpT(t)) },
                alphaAtT: alphaAtT,
                alphaStart: alphaStartGT
            )
        } else if example == "line_end_ramp" {
            return boundarySoupVariableWidthAngleAlpha(
                path: path,
                height: sweepHeight,
                sampleCount: sweepSampleCount,
                arcSamplesPerSegment: paramSamplesPerSegment,
                adaptiveSampling: options.adaptiveSampling,
                flatnessEps: options.flatnessEps,
                maxDepth: options.maxDepth,
                maxSamples: options.maxSamples,
                widthAtT: { t in scaledWidthAtT(warpT(t)) },
                angleAtT: { t in thetaAtT(warpT(t)) },
                alphaAtT: alphaAtT,
                alphaStart: alphaStartGT
            )
        } else {
            return boundarySoup(
                path: path,
                width: sweepWidth,
                height: sweepHeight,
                effectiveAngle: sweepAngle,
                sampleCount: sweepSampleCount,
                arcSamplesPerSegment: paramSamplesPerSegment,
                adaptiveSampling: options.adaptiveSampling,
                flatnessEps: options.flatnessEps,
                maxDepth: options.maxDepth,
                maxSamples: options.maxSamples
            )
        }
    }()

    let rings = traceLoops(segments: segmentsUsed, eps: 1.0e-6)

    let ring = rings.first ?? []

    if options.debugSweep || options.verbose {
        let ringCount = rings.count
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
        let sweepSegments = segmentsUsed
        let sweepSegmentsCount = sweepSegments.count
        let sampleCountUsed = sampleCountFromSoup(sweepSegments)

        if options.adaptiveSampling {
            print("sweep samplingMode=adaptive samples=\(sampleCountUsed) flatnessEps=\(String(format: "%.4f", options.flatnessEps)) maxDepth=\(options.maxDepth) maxSamples=\(options.maxSamples)")
        } else {
            print("sweep samplingMode=fixed samples=\(sweepSampleCount)")
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
            let joinWidths = joinProbeGT.map { scaledWidthAtT(warpT($0)) }
            let joinWidthList = joinWidths.map { String(format: "%.4f", $0) }.joined(separator: ", ")
            let joinGTList = joinProbeGT.map { String(format: "%.4f", $0) }.joined(separator: ", ")
            print("sweep joinWidthProbes=[\(joinWidthList)] gt=[\(joinGTList)]")
            if abs(alphaEndValue) > Epsilon.defaultValue {
                let joinWarped = joinProbeGT.map { warpT($0) }
                let joinWarpedList = joinWarped.map { String(format: "%.4f", $0) }.joined(separator: ", ")
                print("sweep joinWarpProbes gt=[\(joinGTList)] warped=[\(joinWarpedList)]")
            }
            if ring.count > 3 {
                let ringPoints = stripDuplicateClosure(ring)
                let halfWindow = 8
                let param = SkeletonPathParameterization(path: path, samplesPerSegment: paramSamplesPerSegment)
                for (index, join) in joinGTs.enumerated() {
                    let center = param.position(globalT: join)
                    let nearest = nearestIndex(points: ringPoints, to: center)
                    let deviation = chordDeviation(points: ringPoints, centerIndex: nearest, halfWindow: halfWindow)
                    let widthAtJoin = scaledWidthAtT(warpT(join))
                    let ratio = deviation / max(Epsilon.defaultValue, widthAtJoin)
                    print(String(format: "sweep joinBulge[%d] dev=%.6f ratio=%.6f", index, deviation, ratio))
                }
            }
        }
        if ring.count > 3 {
            let ringPoints = stripDuplicateClosure(ring)
            let widthMetric = max(Epsilon.defaultValue, scaledWidthAtT(warpT(0.5)))
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
        let widthMin = widths.min() ?? baselineWidth
        let widthMax = widths.max() ?? baselineWidth
        let heightMin = sweepHeight
        let heightMax = sweepHeight
        let probeGT: [Double] = [0.0, 0.25, 0.5, 0.75, 1.0]
        let probeWidths = probeGT.map { scaledWidthAtT(warpT($0)) }
        let probeHeights = probeGT.map { _ in sweepHeight }
        let widthList = probeWidths.map { String(format: "%.4f", $0) }.joined(separator: ", ")
        let heightList = probeHeights.map { String(format: "%.4f", $0) }.joined(separator: ", ")
        let thetaValues = sweepGT.map { thetaAtT(warpT($0)) * 180.0 / Double.pi }
        let thetaMin = thetaValues.min() ?? 0.0
        let thetaMax = thetaValues.max() ?? 0.0
        let thetaProbes = probeGT.map { thetaAtT(warpT($0)) * 180.0 / Double.pi }
        let thetaList = thetaProbes.map { String(format: "%.4f", $0) }.joined(separator: ", ")
        let alphaValues = sweepGT.map { alphaAtT($0) }
        let alphaMin = alphaValues.min() ?? 0.0
        let alphaMax = alphaValues.max() ?? 0.0
        let alphaProbes = probeGT.map { alphaAtT($0) }
        let alphaList = alphaProbes.map { String(format: "%.4f", $0) }.joined(separator: ", ")
        let endProbeGT: [Double] = [0.80, 0.85, 0.90, 0.95, 1.00]
        let endWidths = endProbeGT.map { scaledWidthAtT(warpT($0)) }
        let endWidthList = endWidths.map { String(format: "%.4f", $0) }.joined(separator: ", ")
        let warpValues = endProbeGT.map { warpT($0) }
        let warpList = warpValues.map { String(format: "%.4f", $0) }.joined(separator: ", ")
        print(String(format: "sweep widthMin=%.4f widthMax=%.4f heightMin=%.4f heightMax=%.4f", widthMin * widthScale, widthMax * widthScale, heightMin, heightMax))
        print("sweep widthProbes=[\(widthList)] gt=[0,0.25,0.5,0.75,1]")
        print("sweep widthEndProbes=[\(endWidthList)] gt=[0.80,0.85,0.90,0.95,1.00]")
        print("sweep heightProbes=[\(heightList)] gt=[0,0.25,0.5,0.75,1]")
        print(String(format: "sweep thetaMin=%.4f thetaMax=%.4f", thetaMin, thetaMax))
        print("sweep thetaProbes=[\(thetaList)] gt=[0,0.25,0.5,0.75,1]")
        print(String(format: "sweep alphaMin=%.4f alphaMax=%.4f alphaWindow=[%.2f..1.00]", alphaMin, alphaMax, alphaStartGT))
        print("sweep alphaProbes=[\(alphaList)] gt=[0,0.25,0.5,0.75,1]")
        print("sweep warpProbes gt=[0.80,0.85,0.90,0.95,1.00] warped=[\(warpList)]")
    }

    let glyphBounds = ring.isEmpty ? nil : ringBounds(ring)
    var debugOverlay: DebugOverlay? = nil
    if options.debugSVG || options.debugCenterline || options.debugInkControls {
        if let inkPrimitive, (options.debugCenterline || options.debugInkControls) {
            switch inkPrimitive {
            case .path(let inkPath):
                debugOverlay = debugOverlayForInkPath(inkPath, steps: 64)
            case .heartline:
                if let resolved = resolvedHeartline {
                    debugOverlay = debugOverlayForHeartline(resolved, steps: 64)
                }
            default:
                debugOverlay = debugOverlayForInk(inkPrimitive, steps: 64)
            }
        } else {
            let count = max(2, sweepSampleCount)
            var left: [Vec2] = []
            var right: [Vec2] = []
            left.reserveCapacity(count)
            right.reserveCapacity(count)
            var tableP: [Vec2] = []
            tableP.reserveCapacity(count)
            for i in 0..<count {
                let t = Double(i) / Double(count - 1)
                let point = pathParam.position(globalT: t)
                let tangent = pathParam.tangent(globalT: t).normalized()
                let normal = Vec2(-tangent.y, tangent.x)
                tableP.append(point)
                let warped = warpT(t)
                let halfW = scaledWidthAtT(warped) * 0.5
                let halfH = sweepHeight * 0.5
                let angle = thetaAtT(warped)
                let corners: [Vec2] = [
                    Vec2(-halfW, -halfH),
                    Vec2(halfW, -halfH),
                    Vec2(halfW, halfH),
                    Vec2(-halfW, halfH)
                ]
                let cosA = cos(angle)
                let sinA = sin(angle)
                var minDot = Double.greatestFiniteMagnitude
                var maxDot = -Double.greatestFiniteMagnitude
                var leftPoint = point
                var rightPoint = point
                for corner in corners {
                    let rotated = Vec2(
                        corner.x * cosA - corner.y * sinA,
                        corner.x * sinA + corner.y * cosA
                    )
                    let world = tangent * rotated.y + normal * rotated.x
                    let cornerWorld = point + world
                    let d = cornerWorld.dot(normal)
                    if d < minDot {
                        minDot = d
                        leftPoint = cornerWorld
                    }
                    if d > maxDot {
                        maxDot = d
                        rightPoint = cornerWorld
                    }
                }
                left.append(leftPoint)
                right.append(rightPoint)
            }

            let skeletonPath = tableP.enumerated().map { index, p in
                let cmd = index == 0 ? "M" : "L"
                return String(format: "\(cmd) %.4f %.4f", p.x, p.y)
            }.joined(separator: " ")
            let leftPath = left.enumerated().map { index, p in
                let cmd = index == 0 ? "M" : "L"
                return String(format: "\(cmd) %.4f %.4f", p.x, p.y)
            }.joined(separator: " ")
            let rightPath = right.enumerated().map { index, p in
                let cmd = index == 0 ? "M" : "L"
                return String(format: "\(cmd) %.4f %.4f", p.x, p.y)
            }.joined(separator: " ")
            var sampleDots: [String] = []
            sampleDots.reserveCapacity(count)
            for p in tableP {
                sampleDots.append(String(format: "<circle cx=\"%.4f\" cy=\"%.4f\" r=\"1.2\" fill=\"none\" stroke=\"blue\" stroke-width=\"0.5\"/>", p.x, p.y))
            }
            var normalLines: [String] = []
            normalLines.reserveCapacity(count)
            for i in 0..<count {
                let t = Double(i) / Double(count - 1)
                let point = pathParam.position(globalT: t)
                let tangent = pathParam.tangent(globalT: t).normalized()
                let normal = Vec2(-tangent.y, tangent.x)
                let end = point + normal * (sweepWidth * 0.5)
                normalLines.append(String(format: "<line x1=\"%.4f\" y1=\"%.4f\" x2=\"%.4f\" y2=\"%.4f\" stroke=\"purple\" stroke-width=\"0.5\"/>", point.x, point.y, end.x, end.y))
            }
            var debugBounds = AABB.empty
            var debugLines: [String] = []
            if options.debugCenterline {
                var controlDots: [String] = []
                controlDots.reserveCapacity(path.segments.count * 2)
                for segment in path.segments {
                    let controls = [segment.p1, segment.p2]
                    for control in controls {
                        let nearest = tableP[nearestIndex(points: tableP, to: control)]
                        debugLines.append(String(format: "<line x1=\"%.4f\" y1=\"%.4f\" x2=\"%.4f\" y2=\"%.4f\" stroke=\"#cccccc\" stroke-width=\"0.5\"/>", control.x, control.y, nearest.x, nearest.y))
                        controlDots.append(String(format: "<circle cx=\"%.4f\" cy=\"%.4f\" r=\"2.0\" fill=\"red\" stroke=\"none\"/>", control.x, control.y))
                        debugBounds.expand(by: control)
                    }
                }
                for point in tableP {
                    debugBounds.expand(by: point)
                }
                let svg = """
  <g id="debug">
    <path d="\(skeletonPath)" fill="none" stroke="orange" stroke-width="0.8" />
    \(debugLines.joined(separator: "\n    "))
    \(controlDots.joined(separator: "\n    "))
  </g>
"""
                debugOverlay = DebugOverlay(svg: svg, bounds: debugBounds)
            } else {
                for point in tableP + left + right {
                    debugBounds.expand(by: point)
                }
                let svg = """
  <g id="debug">
    <path d="\(skeletonPath)" fill="none" stroke="orange" stroke-width="0.6" />
    <path d="\(leftPath)" fill="none" stroke="green" stroke-width="0.6" />
    <path d="\(rightPath)" fill="none" stroke="green" stroke-width="0.6" />
    \(normalLines.joined(separator: "\n    "))
    \(sampleDots.joined(separator: "\n    "))
  </g>
"""
                debugOverlay = DebugOverlay(svg: svg, bounds: debugBounds)
            }
        }
    }

    var referenceSVG: String? = nil
    var referenceViewBox: WorldRect? = nil
    if let layer = referenceLayer {
        let url = URL(fileURLWithPath: layer.path)
        if let data = try? Data(contentsOf: url),
           let svgText = String(data: data, encoding: .utf8) {
            referenceViewBox = parseSVGViewBox(svgText)
            referenceSVG = extractSVGInnerContent(svgText)
        } else {
            warn("reference file not found: \(layer.path)")
        }
    }

    let referenceBoundsAABB: AABB? = {
        if let viewBox = referenceViewBox, let layer = referenceLayer {
            return referenceBounds(viewBox: viewBox, layer: layer)
        }
        return nil
    }()

    let frame = resolveWorldFrame(
        settings: renderSettings,
        glyphBounds: glyphBounds,
        referenceBounds: referenceBoundsAABB,
        debugBounds: debugOverlay?.bounds
    )

    if options.refFitToFrame, let viewBox = referenceViewBox, let layer = referenceLayer {
        let fit = fitReferenceTransform(referenceViewBox: viewBox, to: frame)
        print(String(format: "ref-fit translate=(%.6f,%.6f) scale=%.6f", fit.translate.x, fit.translate.y, fit.scale))
        if let writePath = options.refFitWritePath {
            var outSpec = spec ?? CP2Spec()
            let updated = ReferenceLayer(
                path: layer.path,
                translateWorld: fit.translate,
                scale: fit.scale,
                rotateDeg: layer.rotateDeg,
                opacity: layer.opacity,
                lockPlacement: layer.lockPlacement
            )
            outSpec.reference = updated
            writeSpec(outSpec, path: writePath)
        }
    }

    let viewMinX = frame.minX
    let viewMinY = frame.minY
    let viewWidth = frame.width
    let viewHeight = frame.height

    let pathData = svgPath(for: ring)
    let clipId = "frameClip"
    let clipPath = renderSettings.clipToFrame ? """
  <clipPath id="\(clipId)">
    <rect x="\(String(format: "%.4f", viewMinX))" y="\(String(format: "%.4f", viewMinY))" width="\(String(format: "%.4f", viewWidth))" height="\(String(format: "%.4f", viewHeight))" />
  </clipPath>
""" : ""
    let referenceGroup: String = {
        guard let layer = referenceLayer, let referenceSVG else { return "" }
        let transform = svgTransformString(referenceTransformMatrix(layer))
        return """
  <g id="reference" opacity="\(String(format: "%.4f", layer.opacity))" transform="\(transform)">
\(referenceSVG)
  </g>
"""
    }()
    let debugSVG = debugOverlay?.svg ?? ""
    let glyphGroup = renderSettings.clipToFrame ? """
  <g id="glyph" clip-path="url(#\(clipId))">
    <path d="\(pathData)" fill="none" stroke="black" stroke-width="1" />
  </g>
""" : """
  <g id="glyph">
    <path d="\(pathData)" fill="none" stroke="black" stroke-width="1" />
  </g>
"""
    let debugGroup = renderSettings.clipToFrame ? """
  <g id="debugOverlay" clip-path="url(#\(clipId))">
\(debugSVG)
  </g>
""" : debugSVG

    let svg = """
<svg xmlns="http://www.w3.org/2000/svg" width="\(renderSettings.canvasPx.width)" height="\(renderSettings.canvasPx.height)" viewBox="\(String(format: "%.4f", viewMinX)) \(String(format: "%.4f", viewMinY)) \(String(format: "%.4f", viewWidth)) \(String(format: "%.4f", viewHeight))">
\(clipPath)
\(referenceGroup)
\(glyphGroup)
\(debugGroup)
</svg>
"""
    return svg
}

public func runCLI() {
    let options = parseArgs(Array(CommandLine.arguments.dropFirst()))
    let spec = options.specPath.flatMap(loadSpec(path:))
    let outURL = URL(fileURLWithPath: options.outPath)
    do {
        let svg = try renderSVGString(options: options, spec: spec)
        try FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = svg.data(using: .utf8) else {
            warn("Failed to encode SVG to UTF-8")
            exit(1)
        }
        try data.write(to: outURL, options: .atomic)
        if options.verbose {
            print("Exported \(data.count) bytes to: \(outURL.path)")
        }
    } catch {
        warn("export failed")
        warn("error: \(error.localizedDescription)")
        warn("path: \(outURL.path)")
        warn("cwd: \(FileManager.default.currentDirectoryPath)")
        exit(1)
    }
}

func stripDuplicateClosure(_ ring: [Vec2]) -> [Vec2] {
    guard ring.count > 1, Epsilon.approxEqual(ring.first ?? Vec2(0, 0), ring.last ?? Vec2(0, 0), eps: 1.0e-9) else {
        return ring
    }
    return Array(ring.dropLast())
}

func nearestIndex(points: [Vec2], to target: Vec2) -> Int {
    var best = 0
    var bestDist = Double.greatestFiniteMagnitude
    for (index, point) in points.enumerated() {
        let d = (point - target).length
        if d < bestDist {
            bestDist = d
            best = index
        }
    }
    return best
}

func chordDeviation(points: [Vec2], centerIndex: Int, halfWindow: Int) -> Double {
    guard !points.isEmpty else { return 0.0 }
    let start = max(0, centerIndex - halfWindow)
    let end = min(points.count - 1, centerIndex + halfWindow)
    if end <= start + 1 {
        return 0.0
    }
    let a = points[start]
    let b = points[end]
    var maxDev = 0.0
    for i in (start + 1)..<end {
        let d = distancePointToSegment(points[i], a, b)
        if d > maxDev {
            maxDev = d
        }
    }
    return maxDev
}

func distancePointToSegment(_ p: Vec2, _ a: Vec2, _ b: Vec2) -> Double {
    let ab = b - a
    let ap = p - a
    let denom = max(Epsilon.defaultValue, ab.dot(ab))
    let t = max(0.0, min(1.0, ap.dot(ab) / denom))
    let proj = a + ab * t
    return (p - proj).length
}

func sampleCountFromSoup(_ segments: [Segment2]) -> Int {
    guard segments.count >= 2 else { return max(0, segments.count) }
    return max(2, (segments.count - 2) / 2 + 1)
}
