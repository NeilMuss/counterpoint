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
    var debugSVG: Bool = false
    var debugCenterline: Bool = false
    var debugInkControls: Bool = false
    var debugSamplingWhy: Bool = false
    var probeCount: Int = 5
    var arcSamples: Int = 256
    var normalizeWidth: Bool = false
    var alphaEnd: Double? = nil
    var alphaStartGT: Double = 0.85
    var widthStart: Double = 16.0
    var widthEnd: Double = 28.0
    var widthRampStartGT: Double = 0.85
    var adaptiveSampling: Bool = false
    var flatnessEps: Double = 0.25
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
        } else if arg == "--debug-svg" {
            options.debugSVG = true
        } else if arg == "--debug-centerline" {
            options.debugCenterline = true
        } else if arg == "--debug-ink-controls" {
            options.debugInkControls = true
        } else if arg == "--debug-sampling-why" {
            options.debugSamplingWhy = true
        } else if arg == "--probe-count", index + 1 < args.count {
            options.probeCount = max(1, Int(args[index + 1]) ?? options.probeCount)
            index += 1
        } else if arg == "--arc-samples", index + 1 < args.count {
            options.arcSamples = max(2, Int(args[index + 1]) ?? options.arcSamples)
            index += 1
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
Usage: cp2-cli [--out <path>] [--example scurve|fast_scurve|fast_scurve2|twoseg|jstem|j|j_serif_only|poly3|line|line_end_ramp] [--verbose] [--debug-param] [--debug-sweep] [--debug-svg] [--debug-sampling-why] [--probe-count N]

Debug flags:
  --verbose        Enable verbose logging
  --debug-param    Print parameterization summary + probe mappings
  --debug-sweep    Print sweep tracing stats
  --debug-svg      Include skeleton/sample overlay in the SVG
  --debug-centerline  Centerline-only overlay with control points
  --debug-ink-controls  Ink control geometry + evaluated curve only
  --debug-sampling-why  Sampling “why dots” overlay (adaptive sampling only)
  --probe-count N  Number of globalT probe points (default: 5)
  --arc-samples N  Arc-length samples per segment (default: 256)
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
