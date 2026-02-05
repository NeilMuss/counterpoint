import Foundation
import CP2Geometry
import CP2Skeleton

public struct CLIOptions {
    var outPath: String = "out/line.svg"
    var example: String? = nil
    var specPath: String? = nil
    var inkName: String? = nil
    var strictInk: Bool = false
    var strictHeartline: Bool = false
    var verbose: Bool = false
    var debugParam: Bool = false
    var debugSweep: Bool = false
    var debugParams: Bool = false
    var debugSVG: Bool = false
    var debugCenterline: Bool = false
    var debugInkControls: Bool = false
    var debugSamplingWhy: Bool = false
    var debugSoloWhy: Bool = false
    var debugRingSpine: Bool = false
    var debugRingJump: Bool = false
    var debugRingTopology: Bool = false
    var debugRingSelfXHit: Int? = nil
    var resolveSelfOverlap: Bool = false
    var debugKeyframes: Bool = false
    var keyframesLabels: Bool = false
    var debugParamsPlot: Bool = false
    var debugCounters: Bool = false
    var debugTraceJumpStep: Bool = false
    var debugSoupPreRepair: Bool = false
    var debugSoupNeighborhoodCenter: Vec2? = nil
    var debugSoupNeighborhoodRadius: Double = 5.0
    var debugDumpCapSegments: Bool = false
    var debugDumpCapSegmentsTop: Int = 10
    var debugDumpCapEndpoints: Bool = false
    var debugDumpRailEndpoints: Bool = false
    var debugDumpRailEndpointsPrefix: Int = 5
    var debugDumpRailFrames: Bool = false
    var debugDumpRailFramesPrefix: Int = 6
    var debugCapBoundary: Bool = false
    var debugRailInvariants: Bool = false
    var debugRailInvariantsOnlyFails: Bool = false
    var debugRailWidthEps: Double = 1.0e-3
    var debugRailPerpEps: Double = 1.0e-3
    var debugRailUnitEps: Double = 1.0e-3
    var capFilletArcSegments: Int = 8
    var capRoundArcSegments: Int = 64
    var capFilletFixtureOverlays: Bool = false
    var galleryLinesWavy: Bool = false
    var galleryLinesBoth: Bool = false
    var debugDumpRailCorners: Bool = false
    var debugDumpRailCornersIndex: Int = 0
    var debugCompare: Bool = false
    var debugCompareAll: Bool = false
    var debugHeartlineResolve: Bool = false
    var viewCenterlineOnly: Bool = false
    var clipCountersToInk: Bool = false
    var probeCount: Int = 5
    var arcSamples: Int = 256
    var normalizeWidth: Bool = false
    var alphaEnd: Double? = nil
    var alphaStartGT: Double = 0.85
    var widthStart: Double = 16.0
    var widthEnd: Double = 28.0
    var widthRampStartGT: Double = 0.85
    var adaptiveSampling: Bool = true
    var adaptiveSamplingWasSet: Bool = false
    var allowFixedSampling: Bool = false
    var arcSamplesWasSet: Bool = false
    var flatnessEps: Double = 0.25
    var adaptiveAttrEps: Double = 0.25
    var adaptiveAttrEpsAngleDeg: Double = 0.25
    var maxDepth: Int = 12
    var maxSamples: Int = 512
    var canvasOverride: CanvasSize? = nil
    var fitOverride: RenderFitMode? = nil
    var paddingOverride: Double? = nil
    var clipOverride: Bool? = nil
    var worldFrameOverride: WorldRect? = nil
    var referencePath: String? = nil
    var referenceTranslate: Vec2? = nil
    var referenceScale: Double? = nil
    var referenceRotateDeg: Double? = nil
    var referenceOpacity: Double? = nil
    var referenceLockOverride: Bool? = nil
    var refFitToFrame: Bool = false
    var refFitWritePath: String? = nil

    public init() {}
}

func parseArgs(_ args: [String]) -> CLIOptions {
    var options = CLIOptions()
    var index = 0
    while index < args.count {
        let arg = args[index]
        if arg == "--help" || arg == "-h" {
            printUsage()
            exit(0)
        } else if arg == "--out", index + 1 < args.count {
            options.outPath = args[index + 1]
            index += 1
        } else if arg == "--spec", index + 1 < args.count {
            options.specPath = args[index + 1]
            index += 1
        } else if arg == "--example", index + 1 < args.count {
            options.example = args[index + 1]
            index += 1
        } else if arg == "--ink", index + 1 < args.count {
            options.inkName = args[index + 1]
            index += 1
        } else if arg == "--strict-ink" {
            options.strictInk = true
        } else if arg == "--strict-heartline" {
            options.strictHeartline = true
        } else if arg == "--verbose" {
            options.verbose = true
        } else if arg == "--debug-param" {
            options.debugParam = true
        } else if arg == "--debug-sweep" {
            options.debugSweep = true
        } else if arg == "--debug-params" {
            options.debugParams = true
        } else if arg == "--debug-svg" {
            options.debugSVG = true
        } else if arg == "--debug-centerline" {
            options.debugCenterline = true
        } else if arg == "--debug-ink-controls" {
            options.debugInkControls = true
        } else if arg == "--debug-sampling-why" {
            options.debugSamplingWhy = true
        } else if arg == "--debug-solo-why" {
            options.debugSoloWhy = true
        } else if arg == "--debug-ring-spine" {
            options.debugRingSpine = true
        } else if arg == "--debug-ring-jump" {
            options.debugRingJump = true
        } else if arg == "--debug-ring-topology" {
            options.debugRingTopology = true
        } else if arg == "--debug-ring-self-x-hit", index + 1 < args.count {
            if let value = Int(args[index + 1]) {
                options.debugRingSelfXHit = value
                index += 1
            }
        } else if arg == "--debug-keyframes" {
            options.debugKeyframes = true
        } else if arg == "--keyframes-labels" {
            options.keyframesLabels = true
        } else if arg == "--debug-params-plot" {
            options.debugParamsPlot = true
        } else if arg == "--debug-counters" {
            options.debugCounters = true
        } else if arg == "--debug-trace-jump-step" {
            options.debugTraceJumpStep = true
        } else if arg == "--debug-soup-pre-repair" {
            options.debugSoupPreRepair = true
        } else if arg == "--debug-soup-neighborhood", index + 3 < args.count {
            if let x = Double(args[index + 1]),
               let y = Double(args[index + 2]),
               let r = Double(args[index + 3]) {
                options.debugSoupNeighborhoodCenter = Vec2(x, y)
                options.debugSoupNeighborhoodRadius = r
                index += 3
            }
        } else if arg == "--debug-dump-cap-segments" {
            options.debugDumpCapSegments = true
        } else if arg == "--debug-dump-cap-endpoints" {
            options.debugDumpCapEndpoints = true
        } else if arg == "--debug-dump-rail-endpoints" {
            options.debugDumpRailEndpoints = true
        } else if arg == "--debug-dump-rail-endpoints-prefix", index + 1 < args.count {
            options.debugDumpRailEndpointsPrefix = max(1, Int(args[index + 1]) ?? options.debugDumpRailEndpointsPrefix)
            index += 1
        } else if arg == "--debug-dump-rail-frames" {
            options.debugDumpRailFrames = true
        } else if arg == "--debug-dump-rail-frames-prefix", index + 1 < args.count {
            options.debugDumpRailFramesPrefix = max(1, Int(args[index + 1]) ?? options.debugDumpRailFramesPrefix)
            index += 1
        } else if arg == "--debug-cap-boundary" {
            options.debugCapBoundary = true
        } else if arg == "--debug-rail-invariants" {
            options.debugRailInvariants = true
        } else if arg == "--debug-rail-invariants-only-fails" {
            options.debugRailInvariantsOnlyFails = true
        } else if arg == "--debug-rail-width-eps", index + 1 < args.count {
            options.debugRailWidthEps = Double(args[index + 1]) ?? options.debugRailWidthEps
            index += 1
        } else if arg == "--debug-rail-perp-eps", index + 1 < args.count {
            options.debugRailPerpEps = Double(args[index + 1]) ?? options.debugRailPerpEps
            index += 1
        } else if arg == "--debug-rail-unit-eps", index + 1 < args.count {
            options.debugRailUnitEps = Double(args[index + 1]) ?? options.debugRailUnitEps
            index += 1
        } else if arg == "--cap-fillet-arc-segments", index + 1 < args.count {
            if let value = Int(args[index + 1]) {
                options.capFilletArcSegments = max(2, value)
                index += 1
            }
        } else if arg == "--cap-round-arc-segments", index + 1 < args.count {
            if let value = Int(args[index + 1]) {
                options.capRoundArcSegments = max(2, value)
                index += 1
            }
        } else if arg == "--gallery-lines-wavy" {
            options.galleryLinesWavy = true
        } else if arg == "--gallery-lines-both" {
            options.galleryLinesBoth = true
        } else if arg == "--cap-fillet-fixture-overlays", index + 1 < args.count {
            let value = args[index + 1].lowercased()
            if value == "on" {
                options.capFilletFixtureOverlays = true
                index += 1
            } else if value == "off" {
                options.capFilletFixtureOverlays = false
                index += 1
            }
        } else if arg == "--resolve-self-overlap", index + 1 < args.count {
            let value = args[index + 1].lowercased()
            if value == "on" {
                options.resolveSelfOverlap = true
                index += 1
            } else if value == "off" {
                options.resolveSelfOverlap = false
                index += 1
            }
        } else if arg == "--debug-dump-rail-corners" {
            options.debugDumpRailCorners = true
        } else if arg == "--debug-dump-rail-corners-index", index + 1 < args.count {
            options.debugDumpRailCornersIndex = max(0, Int(args[index + 1]) ?? options.debugDumpRailCornersIndex)
            index += 1
        } else if arg == "--debug-heartline-resolve" {
            options.debugHeartlineResolve = true
        } else if arg == "--clip-counters-to-ink" {
            options.clipCountersToInk = true
        } else if arg == "--debug-dump-cap-segments-top", index + 1 < args.count {
            options.debugDumpCapSegmentsTop = max(1, Int(args[index + 1]) ?? options.debugDumpCapSegmentsTop)
            index += 1
        } else if arg == "--view", index + 1 < args.count {
            let tokens = args[index + 1].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if tokens.contains("compare") {
                options.debugCompare = true
            }
            if tokens.contains("compareAll") {
                options.debugCompare = true
                options.debugCompareAll = true
                options.debugSVG = true
                options.debugCenterline = true
                options.debugInkControls = true
                options.debugSamplingWhy = true
                options.debugRingSpine = true
                options.debugRingJump = true
                options.debugTraceJumpStep = true
            }
            if tokens.contains("ringSpine") {
                options.debugRingSpine = true
            }
            if tokens.contains("ringJump") || tokens.contains("ringJumps") {
                options.debugRingJump = true
            }
            if tokens.contains("samplingWhy") {
                options.debugSamplingWhy = true
            }
            if tokens.contains("keyframes") {
                options.debugKeyframes = true
            }
            if tokens.contains("paramsPlot") {
                options.debugParamsPlot = true
            }
            if tokens.contains("counters") {
                options.debugCounters = true
            }
            if tokens.contains("centerlineOnly") {
                options.viewCenterlineOnly = true
                options.debugCenterline = true
            }
            index += 1
        } else if arg == "--probe-count", index + 1 < args.count {
            options.probeCount = max(1, Int(args[index + 1]) ?? options.probeCount)
            index += 1
        } else if arg == "--arc-samples", index + 1 < args.count {
            options.arcSamples = max(2, Int(args[index + 1]) ?? options.arcSamples)
            options.arcSamplesWasSet = true
            index += 1
        } else if arg == "--allow-fixed-sampling" {
            options.allowFixedSampling = true
        } else if arg == "--adaptive-sampling" {
            options.adaptiveSampling = true
            options.adaptiveSamplingWasSet = true
        } else if arg == "--no-adaptive-sampling" {
            options.adaptiveSampling = false
            options.adaptiveSamplingWasSet = true
        } else if arg == "--normalize-width" {
            options.normalizeWidth = true
        } else if arg == "--alpha-end", index + 1 < args.count {
            options.alphaEnd = Double(args[index + 1])
            index += 1
        } else if arg == "--alpha-start-gt", index + 1 < args.count {
            options.alphaStartGT = Double(args[index + 1]) ?? options.alphaStartGT
            index += 1
        } else if arg == "--width-start", index + 1 < args.count {
            options.widthStart = Double(args[index + 1]) ?? options.widthStart
            index += 1
        } else if arg == "--width-end", index + 1 < args.count {
            options.widthEnd = Double(args[index + 1]) ?? options.widthEnd
            index += 1
        } else if arg == "--width-ramp-start-gt", index + 1 < args.count {
            options.widthRampStartGT = Double(args[index + 1]) ?? options.widthRampStartGT
            index += 1
        } else if arg == "--adaptive-sampling" {
            options.adaptiveSampling = true
        } else if arg == "--flatness-eps", index + 1 < args.count {
            options.flatnessEps = Double(args[index + 1]) ?? options.flatnessEps
            index += 1
        } else if arg == "--adaptive-attr-eps", index + 1 < args.count {
            options.adaptiveAttrEps = Double(args[index + 1]) ?? options.adaptiveAttrEps
            index += 1
        } else if arg == "--adaptive-attr-eps-angle", index + 1 < args.count {
            options.adaptiveAttrEpsAngleDeg = Double(args[index + 1]) ?? options.adaptiveAttrEpsAngleDeg
            index += 1
        } else if arg == "--max-depth", index + 1 < args.count {
            options.maxDepth = max(0, Int(args[index + 1]) ?? options.maxDepth)
            index += 1
        } else if arg == "--max-samples", index + 1 < args.count {
            options.maxSamples = max(2, Int(args[index + 1]) ?? options.maxSamples)
            index += 1
        } else if arg == "--canvas", index + 1 < args.count {
            if let canvas = parseCanvas(args[index + 1]) {
                options.canvasOverride = canvas
            }
            index += 1
        } else if arg == "--fit", index + 1 < args.count {
            if let mode = RenderFitMode(rawValue: args[index + 1]) {
                options.fitOverride = mode
            } else if args[index + 1] == "glyph+ref" {
                options.fitOverride = .glyphPlusReference
            }
            index += 1
        } else if arg == "--padding", index + 1 < args.count {
            options.paddingOverride = Double(args[index + 1])
            index += 1
        } else if arg == "--clip" {
            options.clipOverride = true
        } else if arg == "--world-frame", index + 1 < args.count {
            options.worldFrameOverride = parseWorldFrame(args[index + 1])
            index += 1
        } else if arg == "--ref", index + 1 < args.count {
            options.referencePath = args[index + 1]
            index += 1
        } else if arg == "--ref-translate", index + 1 < args.count {
            if let vec = parseVec2(args[index + 1]) {
                options.referenceTranslate = vec
            }
            index += 1
        } else if arg == "--ref-scale", index + 1 < args.count {
            options.referenceScale = Double(args[index + 1])
            index += 1
        } else if arg == "--ref-rotate", index + 1 < args.count {
            options.referenceRotateDeg = Double(args[index + 1])
            index += 1
        } else if arg == "--ref-opacity", index + 1 < args.count {
            options.referenceOpacity = Double(args[index + 1])
            index += 1
        } else if arg == "--ref-lock" {
            options.referenceLockOverride = true
        } else if arg == "--no-ref-lock" {
            options.referenceLockOverride = false
        } else if arg == "--ref-fit-to-frame" {
            options.refFitToFrame = true
        } else if arg == "--ref-fit-write", index + 1 < args.count {
            options.refFitWritePath = args[index + 1]
            index += 1
        }
        index += 1
    }
    return options
}

func printUsage() {
    let text = """
Usage: cp2-cli [--out <path>] [--example scurve|fast_scurve|fast_scurve2|twoseg|jstem|j|j_serif_only|poly3|line|line_end_ramp|e|gallery_lines] [--verbose] [--debug-param] [--debug-params] [--debug-sweep] [--debug-svg] [--debug-sampling-why] [--debug-solo-why] [--probe-count N]

Debug flags:
  --verbose        Enable verbose logging
  --debug-param    Print parameterization summary + probe mappings
  --debug-params   Print evaluated params at probe GTs
  --debug-sweep    Print sweep tracing stats
  --debug-svg      Include skeleton/sample overlay in the SVG
  --debug-centerline  Centerline-only overlay with control points
  --debug-ink-controls  Ink control geometry + evaluated curve only
  --debug-sampling-why  Sampling “why dots” overlay (adaptive sampling only)
  --debug-solo-why  Render only outline + sampling why dots
  --debug-ring-spine Render traced ring polyline with index breadcrumbs
  --debug-ring-jump  Highlight longest ring segment (teleport diagnostic)
  --debug-ring-topology Dump ring count/area/winding and self-intersections
  --debug-ring-self-x-hit N  Highlight N-th self-intersection hit (0-based)
  --debug-trace-jump-step  Dump trace decision for max jump segment
  --debug-soup-pre-repair  Dump soup degree stats before any repair
  --debug-soup-neighborhood x y r  Dump soup nodes within radius r of (x,y)
  --debug-dump-cap-segments  Dump cap segments (matches jump if present)
  --debug-dump-cap-endpoints  Dump cap endpoint selection (intended vs emitted)
  --debug-dump-cap-segments-top N  Limit cap segment dump (default: 10)
  --debug-dump-rail-endpoints  Dump rail endpoints (start/end/prefix)
  --debug-dump-rail-endpoints-prefix N  Rail prefix count (default: 5)
  --debug-dump-rail-frames  Dump rail frames (center/tangent/normal/width)
  --debug-dump-rail-frames-prefix N  Rail frame prefix count (default: 6)
  --debug-cap-boundary  Dump cap boundary chain + chosen corners
  --debug-rail-invariants  Print rail invariant checks
  --debug-rail-invariants-only-fails  Only print invariant failures
  --debug-rail-width-eps N  Width error epsilon (default: 1e-3)
  --debug-rail-perp-eps N   Perp dot epsilon (default: 1e-3)
  --debug-rail-unit-eps N   Normal length epsilon (default: 1e-3)
  --cap-fillet-arc-segments N  Fillet arc segments (default: 8)
  --cap-round-arc-segments N   Round cap arc segments (default: 64)
  --gallery-lines-wavy  Render wavy-only line gallery
  --gallery-lines-both  Render straight + wavy line gallery
  --cap-fillet-fixture-overlays {off|on}  Cap fillet fixture-only overlays (default: off)
  --adaptive-attr-eps N  Adaptive sampling attribute epsilon (default: 0.25)
  --adaptive-attr-eps-angle N  Adaptive sampling angle epsilon in degrees (default: 0.25)
  --debug-dump-rail-corners  Dump rail corner basis/corners for one index
  --debug-dump-rail-corners-index K  Rail corner index (default: 0)
  --debug-heartline-resolve  Dump ink keys and heartline resolution summary
  --clip-counters-to-ink  Clip counter preview to ink shape (SVG-only)
  --debug-keyframes  Render keyframe markers overlay
  --keyframes-labels  Label keyframe markers with t values
  --debug-params-plot  Render parameter plot overlay
  --debug-counters   Render counter paths overlay (no subtraction yet)
  --view LIST      Comma-separated debug views (e.g. ringSpine,samplingWhy,compare,compareAll,counters,centerlineOnly)
  --probe-count N  Number of globalT probe points (default: 5)
  --arc-samples N  Arc-length samples per segment (default: 256)
  --allow-fixed-sampling  Allow fixed sampling mode (escape hatch)
  --adaptive-sampling     Force adaptive sampling on
  --no-adaptive-sampling  Force adaptive sampling off (requires --allow-fixed-sampling)
  --canvas WxH     Output canvas pixel size (default: 1200x1200)
  --fit MODE       glyph|glyph+ref|everything|none (default: glyph)
  --padding N      World padding around fit bounds (default: 30)
  --clip           Clip to frame
  --world-frame minX,minY,maxX,maxY  Explicit world frame
  --ref PATH       Reference SVG path
  --ref-translate x,y  Reference translate in world units
  --ref-scale N    Reference scale
  --ref-rotate N   Reference rotation degrees
  --ref-opacity N  Reference opacity (default: 0.35)
  --ref-lock       Lock reference placement (default)
  --no-ref-lock    Allow reference placement to be updated
  --ref-fit-to-frame  Print suggested ref translate/scale to fit frame
  --ref-fit-write PATH Write suggested ref transform into JSON spec
  --spec PATH      JSON spec with optional render/reference blocks
  --ink NAME       Select ink entry by name (default: stem)
  --strict-ink     Error on continuity mismatches
  --strict-heartline Error on heartline resolution errors
  --normalize-width  Normalize width to match baseline mean (example-only)
  --alpha-end N      Alpha end value (example-only; default: -0.35 for j)
  --alpha-start-gt N Alpha ramp start gt (default: 0.85)
  --width-start N    Line end ramp width start (default: 16)
  --width-end N      Line end ramp width end (default: 28)
  --width-ramp-start-gt N  Line end ramp start gt (default: 0.85)
  --adaptive-sampling Enable adaptive sampling
  --flatness-eps N     Adaptive flatness epsilon (default: 0.25)
  --max-depth N        Adaptive max recursion depth (default: 12)
  --max-samples N      Adaptive max samples (default: 512)
"""
    print(text)
}

func parseCanvas(_ value: String) -> CanvasSize? {
    let parts = value.lowercased().split(separator: "x")
    guard parts.count == 2,
          let w = Int(parts[0]),
          let h = Int(parts[1]) else { return nil }
    return CanvasSize(width: max(1, w), height: max(1, h))
}

func parseVec2(_ value: String) -> Vec2? {
    let parts = value.split(separator: ",")
    guard parts.count == 2,
          let x = Double(parts[0]),
          let y = Double(parts[1]) else { return nil }
    return Vec2(x, y)
}

func parseWorldFrame(_ value: String) -> WorldRect? {
    let parts = value.split(separator: ",")
    guard parts.count == 4,
          let minX = Double(parts[0]),
          let minY = Double(parts[1]),
          let maxX = Double(parts[2]),
          let maxY = Double(parts[3]) else { return nil }
    return WorldRect(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
}
