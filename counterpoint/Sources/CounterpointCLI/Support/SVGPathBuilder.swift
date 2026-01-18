import Foundation
import CoreGraphics
import Domain

struct SVGPathBuilder {
    let precision: Int

    init(precision: Int = 4) {
        self.precision = precision
    }

    struct BackgroundGlyphElement: Equatable {
        let d: String
        let transform: CGAffineTransform
    }

    struct BackgroundGlyphRender: Equatable {
        let elements: [BackgroundGlyphElement]
        let bounds: CGRect
        let fill: String
        let stroke: String
        let strokeWidth: Double
        let opacity: Double
        let zoom: Double
        let align: BackgroundGlyphAlign
        let manualTransform: CGAffineTransform
    }

    static func loadBackgroundGlyph(from svgPath: String) -> BackgroundGlyphSource? {
        let url = URL(fileURLWithPath: svgPath)
        guard let data = try? Data(contentsOf: url),
              let xml = String(data: data, encoding: .utf8) else {
            return nil
        }
        let parser = BackgroundSVGParser(xml: xml)
        parser.parse()
        guard !parser.elements.isEmpty else { return nil }
        let viewBox = parseViewBox(from: xml)
        let bounds = parser.bounds ?? .zero
        return BackgroundGlyphSource(elements: parser.elements, bounds: bounds, viewBox: viewBox)
    }

    func svgDocument(
        for polygons: PolygonSet,
        fittedPaths: [FittedPath]? = nil,
        size: CGSize?,
        padding: Double,
        debugOverlay: SVGDebugOverlay? = nil,
        debugReference: DebugReference? = nil,
        backgroundGlyph: BackgroundGlyphRender? = nil
    ) -> String {
        let generatedBounds = boundsFor(
            polygons: polygons,
            fittedPaths: fittedPaths,
            debugOverlay: debugOverlay
        )
        let backgroundBounds = backgroundGlyph.map { transformedBackgroundBounds($0, generatedBounds: generatedBounds) }
        let bounds = unionBounds(generatedBounds, backgroundBounds)
        let padded = bounds.insetBy(dx: -padding, dy: -padding)
        let viewBox = padded
        let width = size?.width ?? viewBox.width
        let height = size?.height ?? viewBox.height
        let pathElements: String
        if let fittedPaths {
            pathElements = fittedPaths.map { pathData(for: $0) }.joined(separator: "\n")
        } else {
            pathElements = polygons.map { pathData(for: $0) }.joined(separator: "\n")
        }
        let background = backgroundGlyph.map { backgroundGlyphElements($0, generatedBounds: generatedBounds) } ?? ""
        let reference = debugReference.map { debugReferencePath($0) } ?? ""
        let debug = debugOverlay.map { debugGroup($0, polygons: polygons) } ?? ""

        return """
        <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(format(width))\" height=\"\(format(height))\" viewBox=\"\(format(viewBox.minX)) \(format(viewBox.minY)) \(format(viewBox.width)) \(format(viewBox.height))\">
          \(background)
          \(reference)
          \(pathElements)
          \(debug)
        </svg>
        """
    }

    func svgDocumentForGlyphReference(
        frameBounds: CGRect,
        size: CGSize?,
        padding: Double,
        reference: BackgroundGlyphRender?,
        centerlinePaths: [String] = [],
        polygons: PolygonSet = [],
        fittedPaths: [FittedPath]? = nil
    ) -> String {
        let generatedBounds = frameBounds
        let referenceBounds = reference.map { transformedBackgroundBounds($0, generatedBounds: generatedBounds) }
        let polygonBounds = (polygons.isEmpty && fittedPaths == nil) ? nil : boundsFor(polygons: polygons, fittedPaths: fittedPaths, debugOverlay: nil)
        let bounds = unionBounds(unionBounds(generatedBounds, referenceBounds), polygonBounds)
        let padded = bounds.insetBy(dx: -padding, dy: -padding)
        let viewBox = padded
        let width = size?.width ?? viewBox.width
        let height = size?.height ?? viewBox.height
        let referenceGroup = reference.map { backgroundGlyphElements($0, generatedBounds: generatedBounds) } ?? ""
        let centerlines = centerlinePaths.joined(separator: "\n")
        let polygonPaths: String
        if let fittedPaths {
            polygonPaths = fittedPaths.map { pathData(for: $0) }.joined(separator: "\n")
        } else {
            polygonPaths = polygons.map { pathData(for: $0) }.joined(separator: "\n")
        }

        return """
        <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(format(width))\" height=\"\(format(height))\" viewBox=\"\(format(viewBox.minX)) \(format(viewBox.minY)) \(format(viewBox.width)) \(format(viewBox.height))\">
          \(referenceGroup)
          \(centerlines)
          \(polygonPaths)
        </svg>
        """
    }

    func centerlinePathElement(for segments: [GlyphSegment], stroke: String, strokeWidth: Double) -> String {
        var parts: [String] = []
        var started = false
        for segment in segments {
            guard case .cubic(let cubic) = segment else { continue }
            if !started {
                parts.append("M \(format(cubic.p0.x)) \(format(cubic.p0.y))")
                started = true
            }
            parts.append("C \(format(cubic.p1.x)) \(format(cubic.p1.y)) \(format(cubic.p2.x)) \(format(cubic.p2.y)) \(format(cubic.p3.x)) \(format(cubic.p3.y))")
        }
        guard !parts.isEmpty else { return "" }
        let d = parts.joined(separator: " ")
        return "<path fill=\"none\" stroke=\"\(stroke)\" stroke-width=\"\(format(strokeWidth))\" stroke-linecap=\"round\" stroke-linejoin=\"round\" d=\"\(d)\"/>"
    }

    func pathData(for polygon: Polygon) -> String {
        let outer = ringPath(polygon.outer)
        let holes = polygon.holes.map { ringPath($0) }.joined(separator: " ")
        let combined = holes.isEmpty ? outer : "\(outer) \(holes)"
        return "<path fill=\"black\" stroke=\"none\" fill-rule=\"evenodd\" d=\"\(combined)\"/>"
    }

    func pathData(for fittedPath: FittedPath) -> String {
        let combined = fittedPath.subpaths.map { pathData(for: $0) }.joined(separator: " ")
        return "<path fill=\"black\" stroke=\"none\" fill-rule=\"nonzero\" d=\"\(combined)\"/>"
    }

    private func pathData(for subpath: FittedSubpath) -> String {
        guard let first = subpath.segments.first else { return "" }
        var parts: [String] = []
        parts.reserveCapacity(subpath.segments.count + 2)
        parts.append("M \(format(first.p0.x)) \(format(first.p0.y))")
        for segment in subpath.segments {
            parts.append("C \(format(segment.p1.x)) \(format(segment.p1.y)) \(format(segment.p2.x)) \(format(segment.p2.y)) \(format(segment.p3.x)) \(format(segment.p3.y))")
        }
        parts.append("Z")
        return parts.joined(separator: " ")
    }

    private func ringPath(_ ring: Ring) -> String {
        let closed = closeRing(ring)
        guard let first = closed.first else { return "" }
        var parts: [String] = []
        parts.reserveCapacity(closed.count + 2)
        parts.append("M \(format(first.x)) \(format(first.y))")
        for point in closed.dropFirst() {
            parts.append("L \(format(point.x)) \(format(point.y))")
        }
        parts.append("Z")
        return parts.joined(separator: " ")
    }

    private func closeRing(_ ring: Ring) -> Ring {
        guard let first = ring.first else { return ring }
        if ring.last != first {
            return ring + [first]
        }
        return ring
    }

    private func boundsFor(
        polygons: PolygonSet,
        fittedPaths: [FittedPath]?,
        debugOverlay: SVGDebugOverlay?
    ) -> CGRect {
        var minX = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude

        for polygon in polygons {
            for point in polygon.outer {
                minX = min(minX, point.x)
                maxX = max(maxX, point.x)
                minY = min(minY, point.y)
                maxY = max(maxY, point.y)
            }
            for hole in polygon.holes {
                for point in hole {
                    minX = min(minX, point.x)
                    maxX = max(maxX, point.x)
                    minY = min(minY, point.y)
                    maxY = max(maxY, point.y)
                }
            }
        }

        if let fittedPaths {
            for path in fittedPaths {
                for subpath in path.subpaths {
                    for segment in subpath.segments {
                        let points = [segment.p0, segment.p1, segment.p2, segment.p3]
                        for point in points {
                            minX = min(minX, point.x)
                            maxX = max(maxX, point.x)
                            minY = min(minY, point.y)
                            maxY = max(maxY, point.y)
                        }
                    }
                }
            }
        }

        if !minX.isFinite || !maxX.isFinite || !minY.isFinite || !maxY.isFinite {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }

        if let overlay = debugOverlay {
            for point in overlay.skeleton {
                minX = min(minX, point.x)
                maxX = max(maxX, point.x)
                minY = min(minY, point.y)
                maxY = max(maxY, point.y)
            }
            for ring in overlay.stamps + overlay.bridges {
                for point in ring {
                    minX = min(minX, point.x)
                    maxX = max(maxX, point.x)
                    minY = min(minY, point.y)
                    maxY = max(maxY, point.y)
                }
            }
            for point in overlay.samplePoints {
                minX = min(minX, point.x)
                maxX = max(maxX, point.x)
                minY = min(minY, point.y)
                maxY = max(maxY, point.y)
            }
            for ray in overlay.tangentRays + overlay.angleRays + overlay.offsetRays {
                minX = min(minX, ray.0.x, ray.1.x)
                maxX = max(maxX, ray.0.x, ray.1.x)
                minY = min(minY, ray.0.y, ray.1.y)
                maxY = max(maxY, ray.0.y, ray.1.y)
            }
            for point in overlay.envelopeLeft + overlay.envelopeRight + overlay.envelopeOutline {
                minX = min(minX, point.x)
                maxX = max(maxX, point.x)
                minY = min(minY, point.y)
                maxY = max(maxY, point.y)
            }
        }

        let width = max(0.0, maxX - minX)
        let height = max(0.0, maxY - minY)
        return CGRect(x: minX, y: minY, width: width, height: height)
    }

    private func format(_ value: Double) -> String {
        let factor = pow(10.0, Double(precision))
        let rounded = (value * factor).rounded() / factor
        if rounded == -0.0 { return "0" }
        return String(format: "%0.*f", precision, rounded)
    }

    private func debugGroup(_ overlay: SVGDebugOverlay, polygons: PolygonSet) -> String {
        let skeletonPath = polylinePath(overlay.skeleton)
        let stampPaths = overlay.stamps.map { ringPath($0) }.filter { !$0.isEmpty }
        let bridgePaths = overlay.bridges.map { ringPath($0) }.filter { !$0.isEmpty }
        let tangentPath = rayPath(overlay.tangentRays)
        let anglePath = rayPath(overlay.angleRays)
        let offsetPath = rayPath(overlay.offsetRays)
        let leftRail = polylinePath(overlay.envelopeLeft)
        let rightRail = polylinePath(overlay.envelopeRight)
        let outlineRail = overlay.envelopeOutline.isEmpty ? "" : ringPath(overlay.envelopeOutline)
        let points = overlay.samplePoints.map { "<circle cx=\"\(format($0.x))\" cy=\"\(format($0.y))\" r=\"\(format(0.6))\" fill=\"#222222\" fill-opacity=\"0.5\"/>" }.joined(separator: "\n    ")

        let stampElements = stampPaths.map { "<path fill=\"none\" stroke=\"#0066ff\" stroke-opacity=\"0.3\" stroke-width=\"0.5\" d=\"\($0)\"/>" }.joined(separator: "\n    ")
        let bridgeElements = bridgePaths.map { "<path fill=\"none\" stroke=\"#00aa66\" stroke-opacity=\"0.25\" stroke-width=\"0.5\" d=\"\($0)\"/>" }.joined(separator: "\n    ")
        let unionSource = overlay.unionPolygons ?? polygons
        let unionOutline = overlay.showUnionOutline ? unionSource.map { outlinePath(for: $0) }.joined(separator: "\n    ") : ""
        let envelopeElements = [
            leftRail.isEmpty ? nil : "<path fill=\"none\" stroke=\"#8844ff\" stroke-opacity=\"0.6\" stroke-width=\"0.6\" d=\"\(leftRail)\"/>",
            rightRail.isEmpty ? nil : "<path fill=\"none\" stroke=\"#8844ff\" stroke-opacity=\"0.6\" stroke-width=\"0.6\" d=\"\(rightRail)\"/>",
            outlineRail.isEmpty ? nil : "<path fill=\"none\" stroke=\"#8844ff\" stroke-opacity=\"0.35\" stroke-width=\"0.6\" d=\"\(outlineRail)\"/>"
        ].compactMap { $0 }.joined(separator: "\n    ")

        return """
        <g id=\"debug\">
          <path fill=\"none\" stroke=\"#ff3366\" stroke-opacity=\"0.6\" stroke-width=\"0.5\" d=\"\(skeletonPath)\"/>
          <path fill=\"none\" stroke=\"#ff9900\" stroke-opacity=\"0.6\" stroke-width=\"0.6\" d=\"\(tangentPath)\"/>
          <path fill=\"none\" stroke=\"#222222\" stroke-opacity=\"0.7\" stroke-width=\"0.6\" d=\"\(anglePath)\"/>
          <path fill=\"none\" stroke=\"#00aaff\" stroke-opacity=\"0.6\" stroke-width=\"0.6\" d=\"\(offsetPath)\"/>
          \(points)
          \(envelopeElements)
          \(stampElements)
          \(bridgeElements)
          \(unionOutline)
        </g>
        """
    }

    private func debugReferencePath(_ reference: DebugReference) -> String {
        let trimmed = reference.svgPathD.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let opacity = reference.opacity.map { " opacity=\"\(format($0))\"" } ?? ""
        let transform = reference.transform.map { " transform=\"\($0)\"" } ?? ""
        return "<path id=\"debug-reference\" fill=\"none\" stroke=\"#999999\" stroke-opacity=\"0.6\" stroke-width=\"0.7\"\(opacity)\(transform) d=\"\(trimmed)\"/>"
    }

    private func backgroundGlyphElements(_ background: BackgroundGlyphRender, generatedBounds: CGRect) -> String {
        let global = backgroundTransform(background, generatedBounds: generatedBounds)
        let globalTransform = svgMatrix(global)
        let opacity = " opacity=\"\(format(background.opacity))\""
        let strokeWidth = " stroke-width=\"\(format(background.strokeWidth))\""
        let attributes = "fill=\"\(background.fill)\" stroke=\"\(background.stroke)\"\(strokeWidth)\(opacity) transform=\"\(globalTransform)\""
        let paths = background.elements.map { element -> String in
            let transform = svgMatrix(element.transform)
            return "<path transform=\"\(transform)\" d=\"\(element.d)\"/>"
        }.joined(separator: "\n  ")
        return "<g id=\"background-glyph\" \(attributes)>\n  \(paths)\n</g>"
    }

    private static func parseViewBox(from xml: String) -> CGRect? {
        let pattern = "viewBox\\s*=\\s*[\"']([^\"']+)[\"']"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        guard let match = regex.firstMatch(in: xml, options: [], range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: xml) else {
            return nil
        }
        let parts = xml[valueRange].split(whereSeparator: { $0 == " " || $0 == "," })
        guard parts.count == 4,
              let minX = Double(parts[0]),
              let minY = Double(parts[1]),
              let width = Double(parts[2]),
              let height = Double(parts[3]) else {
            return nil
        }
        return CGRect(x: minX, y: minY, width: width, height: height)
    }

    static func parseTransformString(_ value: String?) -> CGAffineTransform {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .identity
        }
        var transform = CGAffineTransform.identity
        let pattern = "([a-zA-Z]+)\\s*\\(([^\\)]*)\\)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return .identity
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        let matches = regex.matches(in: value, options: [], range: range)
        for match in matches {
            guard match.numberOfRanges == 3,
                  let nameRange = Range(match.range(at: 1), in: value),
                  let argsRange = Range(match.range(at: 2), in: value) else {
                continue
            }
            let name = value[nameRange].lowercased()
            let args = parseTransformArgs(String(value[argsRange]))
            let next: CGAffineTransform
            switch name {
            case "matrix":
                if args.count == 6 {
                    next = CGAffineTransform(a: args[0], b: args[1], c: args[2], d: args[3], tx: args[4], ty: args[5])
                } else {
                    continue
                }
            case "translate":
                let tx = args.count > 0 ? args[0] : 0.0
                let ty = args.count > 1 ? args[1] : 0.0
                next = CGAffineTransform(translationX: tx, y: ty)
            case "scale":
                let sx = args.count > 0 ? args[0] : 1.0
                let sy = args.count > 1 ? args[1] : sx
                next = CGAffineTransform(scaleX: sx, y: sy)
            case "rotate":
                let angle = (args.count > 0 ? args[0] : 0.0) * .pi / 180.0
                if args.count > 2 {
                    let cx = args[1]
                    let cy = args[2]
                    var t = CGAffineTransform(translationX: cx, y: cy)
                    t = t.rotated(by: angle)
                    t = t.translatedBy(x: -cx, y: -cy)
                    next = t
                } else {
                    next = CGAffineTransform(rotationAngle: angle)
                }
            case "skewx":
                let angle = (args.count > 0 ? args[0] : 0.0) * .pi / 180.0
                next = CGAffineTransform(a: 1, b: 0, c: tan(angle), d: 1, tx: 0, ty: 0)
            case "skewy":
                let angle = (args.count > 0 ? args[0] : 0.0) * .pi / 180.0
                next = CGAffineTransform(a: 1, b: tan(angle), c: 0, d: 1, tx: 0, ty: 0)
            default:
                continue
            }
            transform = transform.concatenating(next)
        }
        return transform
    }

    private static func parseTransformArgs(_ text: String) -> [Double] {
        text.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }
    }

    private func transformedBackgroundBounds(_ background: BackgroundGlyphRender, generatedBounds: CGRect) -> CGRect {
        let transform = backgroundTransform(background, generatedBounds: generatedBounds)
        let rect = background.bounds
        let points = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY)
        ].map { $0.applying(transform) }
        var minX = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        for point in points {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        let width = max(0.0, maxX - minX)
        let height = max(0.0, maxY - minY)
        return CGRect(x: minX, y: minY, width: width, height: height)
    }

    private func unionBounds(_ a: CGRect, _ b: CGRect?) -> CGRect {
        guard let b else { return a }
        let minX = min(a.minX, b.minX)
        let minY = min(a.minY, b.minY)
        let maxX = max(a.maxX, b.maxX)
        let maxY = max(a.maxY, b.maxY)
        return CGRect(x: minX, y: minY, width: max(0.0, maxX - minX), height: max(0.0, maxY - minY))
    }

    private func backgroundTransform(_ background: BackgroundGlyphRender, generatedBounds: CGRect) -> CGAffineTransform {
        let zoomScale = background.zoom / 100.0
        let center = CGPoint(x: background.bounds.midX, y: background.bounds.midY)
        var zoomTransform = CGAffineTransform(translationX: center.x, y: center.y)
        zoomTransform = zoomTransform.scaledBy(x: zoomScale, y: zoomScale)
        zoomTransform = zoomTransform.translatedBy(x: -center.x, y: -center.y)
        var transform = zoomTransform.concatenating(background.manualTransform)

        if background.align == .center {
            let targetCenter = CGPoint(x: generatedBounds.midX, y: generatedBounds.midY)
            let sourceCenter = center.applying(transform)
            let dx = targetCenter.x - sourceCenter.x
            let dy = targetCenter.y - sourceCenter.y
            transform = transform.translatedBy(x: dx, y: dy)
        }
        return transform
    }

    private func svgMatrix(_ transform: CGAffineTransform) -> String {
        "matrix(\(format(transform.a)) \(format(transform.b)) \(format(transform.c)) \(format(transform.d)) \(format(transform.tx)) \(format(transform.ty)))"
    }

    private func polylinePath(_ points: [Point]) -> String {
        guard let first = points.first else { return "" }
        var parts: [String] = ["M \(format(first.x)) \(format(first.y))"]
        for point in points.dropFirst() {
            parts.append("L \(format(point.x)) \(format(point.y))")
        }
        return parts.joined(separator: " ")
    }

    private func rayPath(_ rays: [(Point, Point)]) -> String {
        guard !rays.isEmpty else { return "" }
        var parts: [String] = []
        for ray in rays {
            parts.append("M \(format(ray.0.x)) \(format(ray.0.y)) L \(format(ray.1.x)) \(format(ray.1.y))")
        }
        return parts.joined(separator: " ")
    }

    private func outlinePath(for polygon: Polygon) -> String {
        let outer = ringPath(polygon.outer)
        let holes = polygon.holes.map { ringPath($0) }.joined(separator: " ")
        let combined = holes.isEmpty ? outer : "\(outer) \(holes)"
        return "<path fill=\"none\" stroke=\"#111111\" stroke-opacity=\"0.6\" stroke-width=\"0.7\" d=\"\(combined)\"/>"
    }
}

struct BackgroundGlyphSource: Equatable {
    let elements: [SVGPathBuilder.BackgroundGlyphElement]
    let bounds: CGRect
    let viewBox: CGRect?
}

private final class BackgroundSVGParser: NSObject, XMLParserDelegate {
    private let parser: XMLParser
    private var transformStack: [CGAffineTransform] = [.identity]
    private(set) var elements: [SVGPathBuilder.BackgroundGlyphElement] = []
    private(set) var bounds: CGRect?

    init(xml: String) {
        parser = XMLParser(data: Data(xml.utf8))
        super.init()
        parser.delegate = self
    }

    func parse() {
        parser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        let localTransform = SVGPathBuilder.parseTransformString(attributeDict["transform"])
        let current = transformStack.last ?? .identity
        let combined = current.concatenating(localTransform)

        switch elementName.lowercased() {
        case "svg", "g":
            transformStack.append(combined)
        case "path":
            if let d = attributeDict["d"], let box = pathBounds(d: d, transform: combined) {
                record(bounds: box)
                elements.append(SVGPathBuilder.BackgroundGlyphElement(d: d, transform: combined))
            }
        case "rect":
            if let (d, box) = rectData(attributes: attributeDict, transform: combined) {
                record(bounds: box)
                elements.append(SVGPathBuilder.BackgroundGlyphElement(d: d, transform: combined))
            }
        case "circle":
            if let (d, box) = circleData(attributes: attributeDict, transform: combined) {
                record(bounds: box)
                elements.append(SVGPathBuilder.BackgroundGlyphElement(d: d, transform: combined))
            }
        case "ellipse":
            if let (d, box) = ellipseData(attributes: attributeDict, transform: combined) {
                record(bounds: box)
                elements.append(SVGPathBuilder.BackgroundGlyphElement(d: d, transform: combined))
            }
        case "polygon", "polyline":
            if let (d, box) = polyData(points: attributeDict["points"], close: elementName.lowercased() == "polygon", transform: combined) {
                record(bounds: box)
                elements.append(SVGPathBuilder.BackgroundGlyphElement(d: d, transform: combined))
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName.lowercased() {
        case "svg", "g":
            if transformStack.count > 1 {
                transformStack.removeLast()
            }
        default:
            break
        }
    }

    private func record(bounds newBounds: CGRect) {
        if let existing = bounds {
            bounds = existing.union(newBounds)
        } else {
            bounds = newBounds
        }
    }

    private func pathBounds(d: String, transform: CGAffineTransform) -> CGRect? {
        guard let box = PathBoundsCalculator.bounds(for: d) else { return nil }
        return apply(transform: transform, to: box)
    }

    private func rectData(attributes: [String: String], transform: CGAffineTransform) -> (String, CGRect)? {
        guard let width = Double(attributes["width"] ?? ""),
              let height = Double(attributes["height"] ?? "") else { return nil }
        let x = Double(attributes["x"] ?? "") ?? 0.0
        let y = Double(attributes["y"] ?? "") ?? 0.0
        let rect = CGRect(x: x, y: y, width: width, height: height)
        let d = "M \(x) \(y) L \(x + width) \(y) L \(x + width) \(y + height) L \(x) \(y + height) Z"
        return (d, apply(transform: transform, to: rect))
    }

    private func circleData(attributes: [String: String], transform: CGAffineTransform) -> (String, CGRect)? {
        guard let r = Double(attributes["r"] ?? "") else { return nil }
        let cx = Double(attributes["cx"] ?? "") ?? 0.0
        let cy = Double(attributes["cy"] ?? "") ?? 0.0
        let rect = CGRect(x: cx - r, y: cy - r, width: r * 2.0, height: r * 2.0)
        let d = "M \(cx + r) \(cy) A \(r) \(r) 0 1 0 \(cx - r) \(cy) A \(r) \(r) 0 1 0 \(cx + r) \(cy) Z"
        return (d, apply(transform: transform, to: rect))
    }

    private func ellipseData(attributes: [String: String], transform: CGAffineTransform) -> (String, CGRect)? {
        guard let rx = Double(attributes["rx"] ?? ""),
              let ry = Double(attributes["ry"] ?? "") else { return nil }
        let cx = Double(attributes["cx"] ?? "") ?? 0.0
        let cy = Double(attributes["cy"] ?? "") ?? 0.0
        let rect = CGRect(x: cx - rx, y: cy - ry, width: rx * 2.0, height: ry * 2.0)
        let d = "M \(cx + rx) \(cy) A \(rx) \(ry) 0 1 0 \(cx - rx) \(cy) A \(rx) \(ry) 0 1 0 \(cx + rx) \(cy) Z"
        return (d, apply(transform: transform, to: rect))
    }

    private func polyData(points: String?, close: Bool, transform: CGAffineTransform) -> (String, CGRect)? {
        guard let points else { return nil }
        let values = points.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }
        guard values.count >= 2 else { return nil }
        var minX = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        var index = 0
        var pathParts: [String] = []
        while index + 1 < values.count {
            let x = values[index]
            let y = values[index + 1]
            let point = CGPoint(x: x, y: y).applying(transform)
            if pathParts.isEmpty {
                pathParts.append("M \(x) \(y)")
            } else {
                pathParts.append("L \(x) \(y)")
            }
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
            index += 2
        }
        if close {
            pathParts.append("Z")
        }
        let rect = CGRect(x: minX, y: minY, width: max(0.0, maxX - minX), height: max(0.0, maxY - minY))
        return (pathParts.joined(separator: " "), rect)
    }

    private func apply(transform: CGAffineTransform, to rect: CGRect) -> CGRect {
        let points = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY)
        ].map { $0.applying(transform) }
        var minX = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        for point in points {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: max(0.0, maxX - minX), height: max(0.0, maxY - minY))
    }
}

private enum PathBoundsCalculator {
    static func bounds(for d: String) -> CGRect? {
        var tokenizer = PathTokenizer(d)
        var current = CGPoint.zero
        var start = CGPoint.zero
        var lastControl: CGPoint?
        var havePoint = false
        var minX = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude

        func include(_ point: CGPoint) {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
            havePoint = true
        }

        func includeLine(to point: CGPoint) {
            include(point)
            current = point
        }

        func sampleCubic(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint) {
            let steps = 12
            for i in 0...steps {
                let t = Double(i) / Double(steps)
                let mt = 1.0 - t
                let a = mt * mt * mt
                let b = 3.0 * mt * mt * t
                let c = 3.0 * mt * t * t
                let d = t * t * t
                let x = a * p0.x + b * p1.x + c * p2.x + d * p3.x
                let y = a * p0.y + b * p1.y + c * p2.y + d * p3.y
                include(CGPoint(x: x, y: y))
            }
            current = p3
            lastControl = p2
        }

        func sampleQuad(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint) {
            let steps = 12
            for i in 0...steps {
                let t = Double(i) / Double(steps)
                let mt = 1.0 - t
                let a = mt * mt
                let b = 2.0 * mt * t
                let c = t * t
                let x = a * p0.x + b * p1.x + c * p2.x
                let y = a * p0.y + b * p1.y + c * p2.y
                include(CGPoint(x: x, y: y))
            }
            current = p2
            lastControl = p1
        }

        var command: Character?
        while let token = tokenizer.nextToken() {
            switch token {
            case .command(let cmd):
                command = cmd
                if cmd == "Z" || cmd == "z" {
                    includeLine(to: start)
                    lastControl = nil
                }
            case .number(let number):
                guard let cmd = command else { continue }
                tokenizer.pushback(number)
                switch cmd {
                case "M", "m":
                    let isRelative = cmd == "m"
                    guard let x = tokenizer.nextNumber(), let y = tokenizer.nextNumber() else { break }
                    let point = CGPoint(x: x, y: y)
                    current = isRelative ? CGPoint(x: current.x + point.x, y: current.y + point.y) : point
                    start = current
                    include(current)
                    command = (cmd == "m") ? "l" : "L"
                case "L", "l":
                    let isRelative = cmd == "l"
                    guard let x = tokenizer.nextNumber(), let y = tokenizer.nextNumber() else { break }
                    let point = CGPoint(x: x, y: y)
                    let target = isRelative ? CGPoint(x: current.x + point.x, y: current.y + point.y) : point
                    includeLine(to: target)
                    lastControl = nil
                case "H", "h":
                    let isRelative = cmd == "h"
                    guard let x = tokenizer.nextNumber() else { break }
                    let targetX = isRelative ? current.x + x : x
                    includeLine(to: CGPoint(x: targetX, y: current.y))
                    lastControl = nil
                case "V", "v":
                    let isRelative = cmd == "v"
                    guard let y = tokenizer.nextNumber() else { break }
                    let targetY = isRelative ? current.y + y : y
                    includeLine(to: CGPoint(x: current.x, y: targetY))
                    lastControl = nil
                case "C", "c":
                    let isRelative = cmd == "c"
                    guard let x1 = tokenizer.nextNumber(),
                          let y1 = tokenizer.nextNumber(),
                          let x2 = tokenizer.nextNumber(),
                          let y2 = tokenizer.nextNumber(),
                          let x = tokenizer.nextNumber(),
                          let y = tokenizer.nextNumber() else { break }
                    let p1 = CGPoint(x: x1, y: y1)
                    let p2 = CGPoint(x: x2, y: y2)
                    let p3 = CGPoint(x: x, y: y)
                    let c1 = isRelative ? CGPoint(x: current.x + p1.x, y: current.y + p1.y) : p1
                    let c2 = isRelative ? CGPoint(x: current.x + p2.x, y: current.y + p2.y) : p2
                    let end = isRelative ? CGPoint(x: current.x + p3.x, y: current.y + p3.y) : p3
                    sampleCubic(current, c1, c2, end)
                case "S", "s":
                    let isRelative = cmd == "s"
                    guard let x2 = tokenizer.nextNumber(),
                          let y2 = tokenizer.nextNumber(),
                          let x = tokenizer.nextNumber(),
                          let y = tokenizer.nextNumber() else { break }
                    let p2 = CGPoint(x: x2, y: y2)
                    let p3 = CGPoint(x: x, y: y)
                    let reflected = lastControl.map { CGPoint(x: 2.0 * current.x - $0.x, y: 2.0 * current.y - $0.y) } ?? current
                    let c2 = isRelative ? CGPoint(x: current.x + p2.x, y: current.y + p2.y) : p2
                    let end = isRelative ? CGPoint(x: current.x + p3.x, y: current.y + p3.y) : p3
                    sampleCubic(current, reflected, c2, end)
                case "Q", "q":
                    let isRelative = cmd == "q"
                    guard let x1 = tokenizer.nextNumber(),
                          let y1 = tokenizer.nextNumber(),
                          let x = tokenizer.nextNumber(),
                          let y = tokenizer.nextNumber() else { break }
                    let p1 = CGPoint(x: x1, y: y1)
                    let p2 = CGPoint(x: x, y: y)
                    let c1 = isRelative ? CGPoint(x: current.x + p1.x, y: current.y + p1.y) : p1
                    let end = isRelative ? CGPoint(x: current.x + p2.x, y: current.y + p2.y) : p2
                    sampleQuad(current, c1, end)
                case "T", "t":
                    let isRelative = cmd == "t"
                    guard let x = tokenizer.nextNumber(),
                          let y = tokenizer.nextNumber() else { break }
                    let p = CGPoint(x: x, y: y)
                    let end = isRelative ? CGPoint(x: current.x + p.x, y: current.y + p.y) : p
                    let control = lastControl.map { CGPoint(x: 2.0 * current.x - $0.x, y: 2.0 * current.y - $0.y) } ?? current
                    sampleQuad(current, control, end)
                case "A", "a":
                    let isRelative = cmd == "a"
                    guard tokenizer.nextNumber() != nil,
                          tokenizer.nextNumber() != nil,
                          tokenizer.nextNumber() != nil,
                          tokenizer.nextNumber() != nil,
                          tokenizer.nextNumber() != nil,
                          let x = tokenizer.nextNumber(),
                          let y = tokenizer.nextNumber() else { break }
                    let end = isRelative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                    includeLine(to: end)
                    lastControl = nil
                default:
                    break
                }
            }
        }

        guard havePoint else { return nil }
        return CGRect(x: minX, y: minY, width: max(0.0, maxX - minX), height: max(0.0, maxY - minY))
    }
}

private struct PathTokenizer {
    private var chars: [Character]
    private var index: Int = 0
    private var numberBuffer: [Double] = []

    init(_ d: String) {
        chars = Array(d)
    }

    mutating func nextToken() -> PathToken? {
        if let number = numberBuffer.popLast() {
            return .number(number)
        }
        skipSeparators()
        guard index < chars.count else { return nil }
        let ch = chars[index]
        if ch.isLetter {
            index += 1
            return .command(ch)
        }
        if let number = parseNumber() {
            return .number(number)
        }
        index += 1
        return nextToken()
    }

    mutating func pushback(_ number: Double) {
        numberBuffer.append(number)
    }

    mutating func nextNumber() -> Double? {
        if case .number(let value)? = nextToken() {
            return value
        }
        return nil
    }

    private mutating func skipSeparators() {
        while index < chars.count {
            let ch = chars[index]
            if ch == " " || ch == "," || ch == "\n" || ch == "\t" || ch == "\r" {
                index += 1
            } else {
                break
            }
        }
    }

    private mutating func parseNumber() -> Double? {
        let start = index
        var hasNumber = false
        if index < chars.count, (chars[index] == "+" || chars[index] == "-") {
            index += 1
        }
        while index < chars.count, chars[index].isNumber {
            index += 1
            hasNumber = true
        }
        if index < chars.count, chars[index] == "." {
            index += 1
            while index < chars.count, chars[index].isNumber {
                index += 1
                hasNumber = true
            }
        }
        if index < chars.count, chars[index] == "e" || chars[index] == "E" {
            index += 1
            if index < chars.count, (chars[index] == "+" || chars[index] == "-") {
                index += 1
            }
            while index < chars.count, chars[index].isNumber {
                index += 1
                hasNumber = true
            }
        }
        guard hasNumber else {
            index = start
            return nil
        }
        let text = String(chars[start..<index])
        return Double(text)
    }
}

private enum PathToken {
    case command(Character)
    case number(Double)
}

struct SVGDebugOverlay {
    var skeleton: [Point]
    var stamps: [Ring]
    var bridges: [Ring]
    var samplePoints: [Point]
    var tangentRays: [(Point, Point)]
    var angleRays: [(Point, Point)]
    var offsetRays: [(Point, Point)]
    var envelopeLeft: [Point]
    var envelopeRight: [Point]
    var envelopeOutline: Ring
    var showUnionOutline: Bool
    var unionPolygons: PolygonSet?
}
