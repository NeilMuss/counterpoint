import Foundation
import CP2Geometry
import CP2Skeleton

struct CLIOptions {
    var outPath: String = "out/line.svg"
}

func parseArgs(_ args: [String]) -> CLIOptions {
    var options = CLIOptions()
    var index = 0
    while index < args.count {
        let arg = args[index]
        if arg == "--out", index + 1 < args.count {
            options.outPath = args[index + 1]
            index += 1
        }
        index += 1
    }
    return options
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

let options = parseArgs(Array(CommandLine.arguments.dropFirst()))

let bezier = CubicBezier2(
    p0: Vec2(0, 0),
    p1: Vec2(0, 33),
    p2: Vec2(0, 66),
    p3: Vec2(0, 100)
)
let path = SkeletonPath(segments: [bezier])
let soup = boundarySoup(
    path: path,
    width: 20,
    height: 10,
    effectiveAngle: 0,
    sampleCount: 64
)
let rings = traceLoops(segments: soup, eps: 1.0e-6)
let ring = rings.first ?? []

let padding = 10.0
let bounds = ringBounds(ring)
let minX = bounds.min.x - padding
let minY = bounds.min.y - padding
let width = bounds.width + padding * 2.0
let height = bounds.height + padding * 2.0

let pathData = svgPath(for: ring)
let svg = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="\(String(format: "%.4f", minX)) \(String(format: "%.4f", minY)) \(String(format: "%.4f", width)) \(String(format: "%.4f", height))">
  <path d="\(pathData)" fill="none" stroke="black" stroke-width="1" />
</svg>
"""

let outURL = URL(fileURLWithPath: options.outPath)
try? FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try? svg.data(using: .utf8)?.write(to: outURL)
