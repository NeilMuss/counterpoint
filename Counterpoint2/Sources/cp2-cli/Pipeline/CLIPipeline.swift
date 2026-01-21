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
    
    // 1. Resolve Settings
    let (renderSettings, referenceLayer) = resolveEffectiveSettings(options: options, spec: spec)

    // 2. Resolve Path & Resolved Heartline
    let (exampleName, inkPrimitive, path, resolvedHeartline) = try resolveEffectivePath(
        options: options,
        spec: spec,
        warn: warnHandler
    )

    // 3. Build Parameterization & Plan
    let pathParam = SkeletonPathParameterization(path: path, samplesPerSegment: options.arcSamples)
    
    if options.verbose || options.debugParam {
        print("param segments=\(path.segments.count) totalLength=\(String(format: "%.6f", pathParam.totalLength)) arcSamples=\(options.arcSamples)")
        let lengths = path.segments.map { ArcLengthParameterization(path: SkeletonPath($0), samplesPerSegment: options.arcSamples).totalLength }
        print("param segmentLengths=[\(lengths.map { String(format: "%.6f", $0) }.joined(separator: ", "))]")
    }
    
    var joinGTs: [Double] = []
    if options.debugSweep, path.segments.count > 1 {
        let lengths = path.segments.map { ArcLengthParameterization(path: SkeletonPath($0), samplesPerSegment: options.arcSamples).totalLength }
        let total = max(Epsilon.defaultValue, lengths.reduce(0.0, +))
        var accumulated = 0.0
        for i in 0..<lengths.count-1 {
            accumulated += lengths[i]
            joinGTs.append(accumulated / total)
        }
    }

    if options.debugParam {
        let count = max(1, options.probeCount)
        let probes = count == 1 ? [0.0] : (0..<count).map { Double($0) / Double(count - 1) }
        for gt in probes {
            let mapping = pathParam.map(globalT: gt)
            let pos = pathParam.position(globalT: gt)
            print(String(format: "param probe gt=%.4f seg=%d u=%.6f pos=(%.6f,%.6f)", gt, mapping.segmentIndex, mapping.localU, pos.x, pos.y))
        }
    }

    let plan = makeSweepPlan(
        options: options,
        exampleName: exampleName,
        baselineWidth: 20.0,
        sweepWidth: 20.0,
        sweepHeight: 10.0,
        sweepSampleCount: 64
    )

    // 4. Run Sweep
    let result = runSweep(path: path, plan: plan, options: options)

    // 5. Diagnostics
    emitSweepDiagnostics(
        options: options,
        path: path,
        pathParam: pathParam,
        plan: plan,
        result: result,
        joinGTs: joinGTs
    )

    // 6. Debug Overlay
    var debugOverlay: DebugOverlay? = nil
    if options.debugSVG || options.debugCenterline || options.debugInkControls {
        if let inkPrimitive, (options.debugCenterline || options.debugInkControls) {
            switch inkPrimitive {
            case .path(let inkPath): debugOverlay = debugOverlayForInkPath(inkPath, steps: 64)
            case .heartline: if let resolved = resolvedHeartline { debugOverlay = debugOverlayForHeartline(resolved, steps: 64) }
            default: debugOverlay = debugOverlayForInk(inkPrimitive, steps: 64)
            }
        } else {
            debugOverlay = makeCenterlineDebugOverlay(options: options, path: path, pathParam: pathParam, plan: plan)
        }
    }

    // 7. Reference Asset
    var referenceSVG: String? = nil
    var referenceViewBox: WorldRect? = nil
    if let layer = referenceLayer {
        if let asset = loadReferenceAsset(layer: layer, warn: warnHandler) {
            referenceSVG = asset.inner
            referenceViewBox = asset.viewBox
        }
    }

    // 8. Visual Assembly
    let referenceBoundsAABB = (referenceViewBox != nil && referenceLayer != nil) ? referenceBounds(viewBox: referenceViewBox!, layer: referenceLayer!) : nil
    
    let frame = resolveWorldFrame(
        settings: renderSettings,
        glyphBounds: result.glyphBounds,
        referenceBounds: referenceBoundsAABB,
        debugBounds: debugOverlay?.bounds
    )

    if options.refFitToFrame, let viewBox = referenceViewBox, let layer = referenceLayer {
        let fit = fitReferenceTransform(referenceViewBox: viewBox, to: frame)
        print(String(format: "ref-fit translate=(%.6f,%.6f) scale=%.6f", fit.translate.x, fit.translate.y, fit.scale))
        if let writePath = options.refFitWritePath {
            var outSpec = spec ?? CP2Spec()
            outSpec.reference = ReferenceLayer(path: layer.path, translateWorld: fit.translate, scale: fit.scale, rotateDeg: layer.rotateDeg, opacity: layer.opacity, lockPlacement: layer.lockPlacement)
            writeSpec(outSpec, path: writePath)
        }
    }

    let viewMinX = frame.minX, viewMinY = frame.minY, viewWidth = frame.width, viewHeight = frame.height
    let pathData = svgPath(for: result.ring)
    let clipId = "frameClip"
    let clipPath = renderSettings.clipToFrame ? """
  <clipPath id="\(clipId)">
    <rect x="\(String(format: "%.4f", viewMinX))" y="\(String(format: "%.4f", viewMinY))" width="\(String(format: "%.4f", viewWidth))" height="\(String(format: "%.4f", viewHeight))" />
  </clipPath>
""" : ""

    let referenceGroup: String = {
        guard let layer = referenceLayer, let referenceSVG = referenceSVG else { return "" }
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

    return """
<svg xmlns="http://www.w3.org/2000/svg" width="\(renderSettings.canvasPx.width)" height="\(renderSettings.canvasPx.height)" viewBox="\(String(format: "%.4f", viewMinX)) \(String(format: "%.4f", viewMinY)) \(String(format: "%.4f", viewWidth)) \(String(format: "%.4f", viewHeight))">
\(clipPath)
\(referenceGroup)
\(glyphGroup)
\(debugGroup)
</svg>
"""
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

private func resolveEffectiveSettings(
    options: CLIOptions,
    spec: CP2Spec?
) -> (render: RenderSettings, reference: ReferenceLayer?) {
    var renderSettings = spec?.render ?? RenderSettings()
    if let canvas = options.canvasOverride { renderSettings.canvasPx = canvas }
    if let fit = options.fitOverride { renderSettings.fitMode = fit }
    if let padding = options.paddingOverride { renderSettings.paddingWorld = padding }
    if let clip = options.clipOverride { renderSettings.clipToFrame = clip }
    if let worldFrame = options.worldFrameOverride { renderSettings.worldFrame = worldFrame }

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
    return (renderSettings, referenceLayer)
}

private func resolveEffectivePath(
    options: CLIOptions,
    spec: CP2Spec?,
    warn: (String) -> Void
) throws -> (
    exampleName: String?,
    primitive: InkPrimitive?,
    path: SkeletonPath,
    resolvedHeartline: ResolvedHeartline?
) {
    let exampleName = options.example ?? spec?.example
    let inkSelection = pickInkPrimitive(spec?.ink, name: options.inkName)
    let inkPrimitive = inkSelection?.primitive
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
                warn: warn
            )
            resolvedHeartline = resolved
            for subpath in resolved.subpaths {
                let segments = subpath.map { cubicForSegment($0) }
                if !segments.isEmpty { inkPaths.append(SkeletonPath(segments: segments)) }
            }
        default:
            inkPaths = try buildSkeletonPaths(
                name: inkSelection.name,
                primitive: primitive,
                strict: options.strictInk,
                epsilon: 1.0e-4,
                warn: warn
            )
        }
    }
    
    let path: SkeletonPath
    if let inkPath = inkPaths.first {
        if inkPaths.count > 1 {
            warn("ink continuity warning: multiple subpaths detected; sweeping first only")
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
        path = SkeletonPath(segments: [lineCubic(from: Vec2(0, 0), to: Vec2(0, 100))])
    }
    
    return (exampleName, inkPrimitive, path, resolvedHeartline)
}
