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
Usage: cp2-cli [--out <path>] [--example scurve|fast_scurve|fast_scurve2|twoseg|jstem|j|j_serif_only|poly3|line|line_end_ramp] [--verbose] [--debug-param] [--debug-sweep] [--debug-svg] [--probe-count N]

Debug flags:
  --verbose        Enable verbose logging
  --debug-param    Print parameterization summary + probe mappings
  --debug-sweep    Print sweep tracing stats
  --debug-svg      Include skeleton/sample overlay in the SVG
  --debug-centerline  Centerline-only overlay with control points
  --debug-ink-controls  Ink control geometry + evaluated curve only
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

public struct CP2Spec: Codable {
    var example: String?
    var render: RenderSettings?
    var reference: ReferenceLayer?
    var ink: Ink?
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

func loadSpec(path: String) -> CP2Spec? {
    let url = URL(fileURLWithPath: path)
    guard let data = try? Data(contentsOf: url) else {
        warn("spec file not found: \(path)")
        return nil
    }
    do {
        return try JSONDecoder().decode(CP2Spec.self, from: data)
    } catch {
        warn("spec decode failed: \(path)")
        return nil
    }
}

func writeSpec(_ spec: CP2Spec, path: String) {
    let url = URL(fileURLWithPath: path)
    if let data = try? JSONEncoder().encode(spec) {
        try? data.write(to: url)
    }
}

func warn(_ message: String) {
    FileHandle.standardError.write(Data("warning: \(message)\n".utf8))
}

struct DebugOverlay {
    var svg: String
    var bounds: AABB
}

func svgTransformString(_ transform: Transform2D) -> String {
    String(
        format: "matrix(%.6f %.6f %.6f %.6f %.6f %.6f)",
        transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty
    )
}

func parseSVGViewBox(_ svg: String) -> WorldRect? {
    guard let range = svg.range(of: "viewBox=\"") else { return nil }
    let tail = svg[range.upperBound...]
    guard let end = tail.firstIndex(of: "\"") else { return nil }
    let values = tail[..<end].split(whereSeparator: { $0 == " " || $0 == "," })
    guard values.count == 4,
          let minX = Double(values[0]),
          let minY = Double(values[1]),
          let width = Double(values[2]),
          let height = Double(values[3]) else { return nil }
    return WorldRect(minX: minX, minY: minY, maxX: minX + width, maxY: minY + height)
}

func extractSVGInnerContent(_ svg: String) -> String {
    guard let openRange = svg.range(of: "<svg"),
          let openEnd = svg[openRange.upperBound...].firstIndex(of: ">"),
          let closeRange = svg.range(of: "</svg>") else {
        return svg
    }
    let contentStart = svg.index(after: openEnd)
    return String(svg[contentStart..<closeRange.lowerBound])
}

func applyTransform(_ point: Vec2, _ t: Transform2D) -> Vec2 {
    let x = t.a * point.x + t.c * point.y + t.tx
    let y = t.b * point.x + t.d * point.y + t.ty
    return Vec2(x, y)
}

func referenceBounds(viewBox: WorldRect, layer: ReferenceLayer) -> AABB {
    let t = referenceTransformMatrix(layer)
    let corners = [
        Vec2(viewBox.minX, viewBox.minY),
        Vec2(viewBox.maxX, viewBox.minY),
        Vec2(viewBox.maxX, viewBox.maxY),
        Vec2(viewBox.minX, viewBox.maxY)
    ]
    var box = AABB.empty
    for corner in corners {
        box.expand(by: applyTransform(corner, t))
    }
    return box
}

func fitReferenceTransform(
    referenceViewBox: WorldRect,
    to frame: WorldRect
) -> (translate: Vec2, scale: Double) {
    let refWidth = max(Epsilon.defaultValue, referenceViewBox.width)
    let refHeight = max(Epsilon.defaultValue, referenceViewBox.height)
    let scale = min(frame.width / refWidth, frame.height / refHeight)
    let refCenter = Vec2(
        (referenceViewBox.minX + referenceViewBox.maxX) * 0.5,
        (referenceViewBox.minY + referenceViewBox.maxY) * 0.5
    )
    let frameCenter = Vec2(
        (frame.minX + frame.maxX) * 0.5,
        (frame.minY + frame.maxY) * 0.5
    )
    let translated = frameCenter - refCenter * scale
    return (translated, scale)
}

func svgPath(for ring: [Vec2]) -> String {
    guard let first = ring.first else { return "" }
    var parts: [String] = []
    parts.append(String(format: "M %.4f %.4f", first.x, first.y))
    for point in ring.dropFirst() {
        parts.append(String(format: "L %.4f %.4f", point.x, point.y))
    }
    parts.append("Z")
    return parts.joined(separator: " ")
}

func ringBounds(_ ring: [Vec2]) -> AABB {
    var box = AABB.empty
    for point in ring {
        box.expand(by: point)
    }
    return box
}

func lineCubic(from start: Vec2, to end: Vec2) -> CubicBezier2 {
    let delta = end - start
    let p1 = start + delta * (1.0 / 3.0)
    let p2 = start + delta * (2.0 / 3.0)
    return CubicBezier2(p0: start, p1: p1, p2: p2, p3: end)
}

func vec(_ point: InkPoint) -> Vec2 {
    Vec2(point.x, point.y)
}

func sampleInkCubicPoints(_ cubic: InkCubic, steps: Int) -> [Vec2] {
    let count = max(2, steps)
    var points: [Vec2] = []
    points.reserveCapacity(count)
    let p0 = vec(cubic.p0)
    let p1 = vec(cubic.p1)
    let p2 = vec(cubic.p2)
    let p3 = vec(cubic.p3)
    for i in 0..<count {
        let t = Double(i) / Double(count - 1)
        let mt = 1.0 - t
        let mt2 = mt * mt
        let t2 = t * t
        let a = p0 * (mt2 * mt)
        let b = p1 * (3.0 * mt2 * t)
        let c = p2 * (3.0 * mt * t2)
        let d = p3 * (t2 * t)
        points.append(a + b + c + d)
    }
    return points
}

func debugOverlayForInk(_ ink: InkPrimitive, steps: Int) -> DebugOverlay {
    var bounds = AABB.empty
    var svgParts: [String] = []
    func addPoint(_ p: Vec2, radius: Double, fill: String) {
        svgParts.append(String(format: "<circle cx=\"%.4f\" cy=\"%.4f\" r=\"%.1f\" fill=\"%@\" stroke=\"none\"/>", p.x, p.y, radius, fill))
        bounds.expand(by: p)
    }
    func addLine(_ a: Vec2, _ b: Vec2, stroke: String, width: Double) {
        svgParts.append(String(format: "<line x1=\"%.4f\" y1=\"%.4f\" x2=\"%.4f\" y2=\"%.4f\" stroke=\"%@\" stroke-width=\"%.1f\"/>", a.x, a.y, b.x, b.y, stroke, width))
        bounds.expand(by: a)
        bounds.expand(by: b)
    }
    func addPolyline(_ points: [Vec2], stroke: String, width: Double) {
        guard let first = points.first else { return }
        var parts: [String] = []
        parts.append(String(format: "M %.4f %.4f", first.x, first.y))
        for point in points.dropFirst() {
            parts.append(String(format: "L %.4f %.4f", point.x, point.y))
        }
        let pathData = parts.joined(separator: " ")
        let strokeWidth = String(format: "%.1f", width)
        svgParts.append("<path d=\"\(pathData)\" fill=\"none\" stroke=\"\(stroke)\" stroke-width=\"\(strokeWidth)\" />")
        for point in points {
            bounds.expand(by: point)
        }
    }

    switch ink {
    case .line(let line):
        let p0 = vec(line.p0)
        let p1 = vec(line.p1)
        addLine(p0, p1, stroke: "orange", width: 2.0)
        addPoint(p0, radius: 4.0, fill: "blue")
        addPoint(p1, radius: 4.0, fill: "blue")
    case .cubic(let cubic):
        let p0 = vec(cubic.p0)
        let p1 = vec(cubic.p1)
        let p2 = vec(cubic.p2)
        let p3 = vec(cubic.p3)
        let samples = sampleInkCubicPoints(cubic, steps: steps)
        addLine(p0, p1, stroke: "#cccccc", width: 1.0)
        addLine(p3, p2, stroke: "#cccccc", width: 1.0)
        addPolyline(samples, stroke: "orange", width: 2.0)
        addPoint(p0, radius: 4.0, fill: "blue")
        addPoint(p3, radius: 4.0, fill: "blue")
        addPoint(p1, radius: 4.0, fill: "red")
        addPoint(p2, radius: 4.0, fill: "red")
    case .path(let path):
        return debugOverlayForInkPath(path, steps: steps)
    case .heartline:
        return DebugOverlay(svg: "<g id=\"debug\"></g>", bounds: AABB.empty)
    }

    let svg = """
  <g id="debug">
    \(svgParts.joined(separator: "\n    "))
  </g>
"""
    return DebugOverlay(svg: svg, bounds: bounds)
}

func pickInkPrimitive(_ ink: Ink?, name: String?) -> (name: String, primitive: InkPrimitive)? {
    guard let ink else {
        return nil
    }
    if let name {
        if let primitive = ink.entries[name] {
            return (name, primitive)
        }
        return nil
    }
    if let heartline = ink.entries["J_heartline"] {
        return ("J_heartline", heartline)
    }
    if let stem = ink.stem {
        return ("stem", stem)
    }
    if let firstKey = ink.entries.keys.sorted().first, let primitive = ink.entries[firstKey] {
        return (firstKey, primitive)
    }
    return nil
}

enum InkContinuityError: Error, CustomStringConvertible {
    case discontinuity(name: String, index: Int, dist: Double)
    case missingPart(name: String, part: String)
    case cyclicReference(name: String, part: String)

    var description: String {
        switch self {
        case .discontinuity(let name, let index, let dist):
            let distText = String(format: "%.6f", dist)
            return "ink continuity mismatch: \(name) segments \(index)->\(index + 1) dist=\(distText)"
        case .missingPart(let name, let part):
            return "heartline missing part: \(name) -> \(part)"
        case .cyclicReference(let name, let part):
            return "heartline cycle detected: \(name) -> \(part)"
        }
    }

    var localizedDescription: String {
        description
    }
}

func inkSegmentStart(_ segment: InkSegment) -> Vec2 {
    switch segment {
    case .line(let line):
        return vec(line.p0)
    case .cubic(let cubic):
        return vec(cubic.p0)
    }
}

func inkSegmentEnd(_ segment: InkSegment) -> Vec2 {
    switch segment {
    case .line(let line):
        return vec(line.p1)
    case .cubic(let cubic):
        return vec(cubic.p3)
    }
}

func formatVec2(_ point: Vec2) -> String {
    String(format: "(%.6f,%.6f)", point.x, point.y)
}

func cubicForSegment(_ segment: InkSegment) -> CubicBezier2 {
    switch segment {
    case .line(let line):
        return lineCubic(from: vec(line.p0), to: vec(line.p1))
    case .cubic(let cubic):
        return CubicBezier2(
            p0: vec(cubic.p0),
            p1: vec(cubic.p1),
            p2: vec(cubic.p2),
            p3: vec(cubic.p3)
        )
    }
}

struct HeartlinePart {
    var name: String
    var segments: [InkSegment]
}

struct ResolvedHeartline {
    var name: String
    var subpaths: [[InkSegment]]
    var parts: [HeartlinePart]
}

func resolveHeartline(
    name: String,
    heartline: Heartline,
    ink: Ink,
    strict: Bool,
    warn: (String) -> Void
) throws -> ResolvedHeartline {
    var parts: [HeartlinePart] = []
    var visited = Set<String>()
    visited.insert(name)
    for partName in heartline.parts {
        guard let primitive = ink.entries[partName] else {
            if strict {
                throw InkContinuityError.missingPart(name: name, part: partName)
            }
            warn("heartline warning: missing part \(partName) in \(name)")
            continue
        }
        switch primitive {
        case .line(let line):
            parts.append(HeartlinePart(name: partName, segments: [.line(line)]))
        case .cubic(let cubic):
            parts.append(HeartlinePart(name: partName, segments: [.cubic(cubic)]))
        case .path(let path):
            parts.append(HeartlinePart(name: partName, segments: path.segments))
        case .heartline:
            if strict {
                throw InkContinuityError.cyclicReference(name: name, part: partName)
            }
            warn("heartline warning: nested heartline \(partName) ignored in \(name)")
        }
    }
    var subpaths: [[InkSegment]] = []
    var current: [InkSegment] = []
    let allowGaps = heartline.allowGaps ?? false
    for (index, part) in parts.enumerated() {
        for (segmentIndex, segment) in part.segments.enumerated() {
            if let last = current.last {
                let dist = (inkSegmentEnd(last) - inkSegmentStart(segment)).length
                if dist > 1.0e-4 {
                    let distText = String(format: "%.6f", dist)
                    let message = "heartline continuity warning: \(name) part \(part.name) seg=\(segmentIndex) dist=\(distText)"
                    if strict {
                        throw InkContinuityError.discontinuity(name: name, index: index, dist: dist)
                    } else {
                        warn(message)
                    }
                    if !allowGaps {
                        subpaths.append(current)
                        current = []
                    }
                }
            }
            current.append(segment)
        }
    }
    if !current.isEmpty {
        subpaths.append(current)
    }
    return ResolvedHeartline(name: name, subpaths: subpaths, parts: parts)
}

func buildSkeletonPaths(
    name: String,
    primitive: InkPrimitive,
    strict: Bool,
    epsilon: Double,
    warn: (String) -> Void
) throws -> [SkeletonPath] {
    switch primitive {
    case .line(let line):
        let segment = lineCubic(from: vec(line.p0), to: vec(line.p1))
        return [SkeletonPath(segments: [segment])]
    case .cubic(let cubic):
        let segment = CubicBezier2(
            p0: vec(cubic.p0),
            p1: vec(cubic.p1),
            p2: vec(cubic.p2),
            p3: vec(cubic.p3)
        )
        return [SkeletonPath(segments: [segment])]
    case .path(let path):
        var paths: [SkeletonPath] = []
        var currentSegments: [CubicBezier2] = []
        for (index, segment) in path.segments.enumerated() {
            if index > 0 {
                let prev = path.segments[index - 1]
                let dist = (inkSegmentEnd(prev) - inkSegmentStart(segment)).length
                if dist > epsilon {
                    let distText = String(format: "%.6f", dist)
                    let message = "ink continuity warning: \(name) segments \(index - 1)->\(index) end=\(formatVec2(inkSegmentEnd(prev))) start=\(formatVec2(inkSegmentStart(segment))) dist=\(distText)"
                    if strict {
                        throw InkContinuityError.discontinuity(name: name, index: index - 1, dist: dist)
                    } else {
                        warn(message)
                        if !currentSegments.isEmpty {
                            paths.append(SkeletonPath(segments: currentSegments))
                            currentSegments = []
                        }
                    }
                }
            }
            currentSegments.append(cubicForSegment(segment))
        }
        if !currentSegments.isEmpty {
            paths.append(SkeletonPath(segments: currentSegments))
        }
        return paths
    case .heartline:
        return []
    }
}

func debugOverlayForInkPath(_ path: InkPath, steps: Int) -> DebugOverlay {
    var bounds = AABB.empty
    var svgParts: [String] = []
    func addPoint(_ p: Vec2, radius: Double, fill: String) {
        svgParts.append(String(format: "<circle cx=\"%.4f\" cy=\"%.4f\" r=\"%.1f\" fill=\"%@\" stroke=\"none\"/>", p.x, p.y, radius, fill))
        bounds.expand(by: p)
    }
    func addLine(_ a: Vec2, _ b: Vec2, stroke: String, width: Double) {
        svgParts.append(String(format: "<line x1=\"%.4f\" y1=\"%.4f\" x2=\"%.4f\" y2=\"%.4f\" stroke=\"%@\" stroke-width=\"%.1f\"/>", a.x, a.y, b.x, b.y, stroke, width))
        bounds.expand(by: a)
        bounds.expand(by: b)
    }
    func addPolyline(_ points: [Vec2], stroke: String, width: Double) {
        guard let first = points.first else { return }
        var parts: [String] = []
        parts.append(String(format: "M %.4f %.4f", first.x, first.y))
        for point in points.dropFirst() {
            parts.append(String(format: "L %.4f %.4f", point.x, point.y))
        }
        let pathData = parts.joined(separator: " ")
        let strokeWidth = String(format: "%.1f", width)
        svgParts.append("<path d=\"\(pathData)\" fill=\"none\" stroke=\"\(stroke)\" stroke-width=\"\(strokeWidth)\" />")
        for point in points {
            bounds.expand(by: point)
        }
    }

    for segment in path.segments {
        switch segment {
        case .line(let line):
            let p0 = vec(line.p0)
            let p1 = vec(line.p1)
            addLine(p0, p1, stroke: "orange", width: 2.0)
            addPoint(p0, radius: 4.0, fill: "blue")
            addPoint(p1, radius: 4.0, fill: "blue")
        case .cubic(let cubic):
            let p0 = vec(cubic.p0)
            let p1 = vec(cubic.p1)
            let p2 = vec(cubic.p2)
            let p3 = vec(cubic.p3)
            let samples = sampleInkCubicPoints(cubic, steps: steps)
            addLine(p0, p1, stroke: "#cccccc", width: 1.0)
            addLine(p3, p2, stroke: "#cccccc", width: 1.0)
            addPolyline(samples, stroke: "orange", width: 2.0)
            addPoint(p0, radius: 4.0, fill: "blue")
            addPoint(p3, radius: 4.0, fill: "blue")
            addPoint(p1, radius: 4.0, fill: "red")
            addPoint(p2, radius: 4.0, fill: "red")
        }
    }

    let svg = """
  <g id="debug">
    \(svgParts.joined(separator: "\n    "))
  </g>
"""
    return DebugOverlay(svg: svg, bounds: bounds)
}

func debugOverlayForHeartline(_ resolved: ResolvedHeartline, steps: Int) -> DebugOverlay {
    var bounds = AABB.empty
    var svgParts: [String] = []
    func addPoint(_ p: Vec2, radius: Double, fill: String) {
        svgParts.append(String(format: "<circle cx=\"%.4f\" cy=\"%.4f\" r=\"%.1f\" fill=\"%@\" stroke=\"none\"/>", p.x, p.y, radius, fill))
        bounds.expand(by: p)
    }
    func addLine(_ a: Vec2, _ b: Vec2, stroke: String, width: Double) {
        svgParts.append(String(format: "<line x1=\"%.4f\" y1=\"%.4f\" x2=\"%.4f\" y2=\"%.4f\" stroke=\"%@\" stroke-width=\"%.1f\"/>", a.x, a.y, b.x, b.y, stroke, width))
        bounds.expand(by: a)
        bounds.expand(by: b)
    }
    func addPolyline(_ points: [Vec2], stroke: String, width: Double) {
        guard let first = points.first else { return }
        var parts: [String] = []
        parts.append(String(format: "M %.4f %.4f", first.x, first.y))
        for point in points.dropFirst() {
            parts.append(String(format: "L %.4f %.4f", point.x, point.y))
        }
        let pathData = parts.joined(separator: " ")
        let strokeWidth = String(format: "%.1f", width)
        svgParts.append("<path d=\"\(pathData)\" fill=\"none\" stroke=\"\(stroke)\" stroke-width=\"\(strokeWidth)\" />")
        for point in points {
            bounds.expand(by: point)
        }
    }
    func addLabel(_ text: String, at point: Vec2) {
        svgParts.append(String(format: "<text x=\"%.4f\" y=\"%.4f\" font-size=\"10\" fill=\"#444444\">%@</text>", point.x, point.y, text))
        bounds.expand(by: point)
    }

    for part in resolved.parts {
        var samplePoints: [Vec2] = []
        for segment in part.segments {
            switch segment {
            case .line(let line):
                let p0 = vec(line.p0)
                let p1 = vec(line.p1)
                addLine(p0, p1, stroke: "orange", width: 2.0)
                addPoint(p0, radius: 4.0, fill: "blue")
                addPoint(p1, radius: 4.0, fill: "blue")
                samplePoints.append(p0)
                samplePoints.append(p1)
            case .cubic(let cubic):
                let p0 = vec(cubic.p0)
                let p1 = vec(cubic.p1)
                let p2 = vec(cubic.p2)
                let p3 = vec(cubic.p3)
                let samples = sampleInkCubicPoints(cubic, steps: steps)
                addLine(p0, p1, stroke: "#cccccc", width: 1.0)
                addLine(p3, p2, stroke: "#cccccc", width: 1.0)
                addPolyline(samples, stroke: "orange", width: 2.0)
                addPoint(p0, radius: 4.0, fill: "blue")
                addPoint(p3, radius: 4.0, fill: "blue")
                addPoint(p1, radius: 4.0, fill: "red")
                addPoint(p2, radius: 4.0, fill: "red")
                samplePoints.append(contentsOf: samples)
            }
        }
        if !samplePoints.isEmpty {
            let mid = samplePoints[samplePoints.count / 2]
            addLabel(part.name, at: mid + Vec2(4.0, -4.0))
        }
    }

    let svg = """
  <g id="debug">
    \(svgParts.joined(separator: "\n    "))
  </g>
"""
    return DebugOverlay(svg: svg, bounds: bounds)
}

func pathFromInk(_ ink: Ink?) -> SkeletonPath? {
    guard let stem = ink?.stem else {
        return nil
    }
    switch stem {
    case .line(let line):
        let cubic = lineCubic(from: vec(line.p0), to: vec(line.p1))
        return SkeletonPath(segments: [cubic])
    case .cubic(let cubic):
        let segment = CubicBezier2(
            p0: vec(cubic.p0),
            p1: vec(cubic.p1),
            p2: vec(cubic.p2),
            p3: vec(cubic.p3)
        )
        return SkeletonPath(segments: [segment])
    case .path:
        return nil
    case .heartline:
        return nil
    }
}

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
    do {
        let svg = try renderSVGString(options: options, spec: spec)
        let outURL = URL(fileURLWithPath: options.outPath)
        try? FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? svg.data(using: .utf8)?.write(to: outURL)
    } catch {
        warn(error.localizedDescription)
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
