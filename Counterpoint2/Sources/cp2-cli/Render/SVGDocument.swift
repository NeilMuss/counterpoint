import Foundation
import CP2Geometry
import CP2Skeleton

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
