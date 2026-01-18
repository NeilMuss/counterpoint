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

    struct DebugRect: Equatable {
        let min: Point
        let max: Point
        let stroke: String
        let strokeWidth: Double
    }

    struct AlphaDebugChart: Equatable {
        let alphaRaw: Double
        let alphaUsed: Double
        let t0: Double
        let t1: Double
        let trackLabel: String
        let biasSamples: [Point]
        let valueSamples: [Point]
        let valueMin: Double
        let valueMax: Double
        let startValue: Double
        let endValue: Double
        let dMid: Double
    }

    struct RefDiffOverlay: Equatable {
        let origin: Point
        let pixelSize: Double
        let width: Int
        let height: Int
        let data: [UInt8]
        let matchCount: Int
        let missingCount: Int
        let excessCount: Int
    }

    struct KeyframeMarker: Equatable {
        let point: Point
        let color: String
        let radius: Double
        let shape: KeyframeMarkerShape
    }

    enum KeyframeMarkerShape: String, Equatable {
        case circle
        case square
        case diamond
        case triangle
        case invertedTriangle
        case triangleLeft
        case triangleRight
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
        let debug = debugOverlay.map { debugGroup($0, polygons: polygons, viewBox: viewBox) } ?? ""

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
        referenceOnTop: Bool = false,
        centerlinePaths: [String] = [],
        polygons: PolygonSet = [],
        fittedPaths: [FittedPath]? = nil,
        debugRects: [DebugRect] = [],
        debugOverlay: SVGDebugOverlay? = nil
    ) -> String {
        let generatedBounds = frameBounds
        let referenceBounds = reference.map { transformedBackgroundBounds($0, generatedBounds: generatedBounds) }
        let polygonBounds = (polygons.isEmpty && fittedPaths == nil && debugOverlay == nil) ? nil : boundsFor(polygons: polygons, fittedPaths: fittedPaths, debugOverlay: debugOverlay)
        let bounds = unionBounds(unionBounds(generatedBounds, referenceBounds), polygonBounds)
        let padded = bounds.insetBy(dx: -padding, dy: -padding)
        let viewBox = padded
        let width = size?.width ?? viewBox.width
        let height = size?.height ?? viewBox.height
        let referenceGroup: String
        if let reference {
            let render: BackgroundGlyphRender
            if referenceOnTop {
                render = BackgroundGlyphRender(
                    elements: reference.elements,
                    bounds: reference.bounds,
                    fill: "none",
                    stroke: "#ffd200",
                    strokeWidth: reference.strokeWidth,
                    opacity: reference.opacity,
                    zoom: reference.zoom,
                    align: reference.align,
                    manualTransform: reference.manualTransform
                )
            } else {
                render = reference
            }
            referenceGroup = backgroundGlyphElements(render, generatedBounds: generatedBounds)
        } else {
            referenceGroup = ""
        }
        let centerlines = centerlinePaths.joined(separator: "\n")
        let debugRectGroup = debugRects.isEmpty ? "" : debugRectElements(debugRects)
        let debugGroupContent = debugOverlay.map { debugGroup($0, polygons: polygons, viewBox: viewBox) } ?? ""
        let polygonPaths: String
        if let fittedPaths {
            polygonPaths = fittedPaths.map { pathData(for: $0) }.joined(separator: "\n")
        } else {
            polygonPaths = polygons.map { pathData(for: $0) }.joined(separator: "\n")
        }

        let elements: [String]
        if referenceOnTop {
            elements = [debugRectGroup, polygonPaths, debugGroupContent, centerlines, referenceGroup].filter { !$0.isEmpty }
        } else {
            elements = [referenceGroup, debugRectGroup, polygonPaths, debugGroupContent, centerlines].filter { !$0.isEmpty }
        }
        let body = elements.joined(separator: "\n  ")

        return """
        <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(format(width))\" height=\"\(format(height))\" viewBox=\"\(format(viewBox.minX)) \(format(viewBox.minY)) \(format(viewBox.width)) \(format(viewBox.height))\">
          \(body)
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

    private func debugRectElements(_ rects: [DebugRect]) -> String {
        let elements = rects.map { rect in
            let x = rect.min.x
            let y = rect.min.y
            let width = rect.max.x - rect.min.x
            let height = rect.max.y - rect.min.y
            return "<rect x=\"\(format(x))\" y=\"\(format(y))\" width=\"\(format(width))\" height=\"\(format(height))\" fill=\"none\" stroke=\"\(rect.stroke)\" stroke-width=\"\(format(rect.strokeWidth))\"/>"
        }
        return elements.joined(separator: "\n")
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
            for sample in overlay.leftRailSamples + overlay.rightRailSamples {
                minX = min(minX, sample.point.x)
                maxX = max(maxX, sample.point.x)
                minY = min(minY, sample.point.y)
                maxY = max(maxY, sample.point.y)
                if overlay.showRailsNormals {
                    let dir = sample.normal.normalized() ?? Point(x: 0, y: 0)
                    let end = sample.point + dir * 10.0
                    minX = min(minX, end.x)
                    maxX = max(maxX, end.x)
                    minY = min(minY, end.y)
                    maxY = max(maxY, end.y)
                }
            }
            for point in overlay.offsetCenterline {
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
            for ring in overlay.junctionPatches {
                for point in ring {
                    minX = min(minX, point.x)
                    maxX = max(maxX, point.x)
                    minY = min(minY, point.y)
                    maxY = max(maxY, point.y)
                }
            }
            for ring in overlay.junctionCorridors {
                for point in ring {
                    minX = min(minX, point.x)
                    maxX = max(maxX, point.x)
                    minY = min(minY, point.y)
                    maxY = max(maxY, point.y)
                }
            }
            for point in overlay.junctionControlPoints {
                minX = min(minX, point.x)
                maxX = max(maxX, point.x)
                minY = min(minY, point.y)
                maxY = max(maxY, point.y)
            }
            if let refDiff = overlay.refDiff {
                let refMinX = refDiff.origin.x
                let refMinY = refDiff.origin.y
                let refMaxX = refDiff.origin.x + Double(refDiff.width) * refDiff.pixelSize
                let refMaxY = refDiff.origin.y + Double(refDiff.height) * refDiff.pixelSize
                minX = min(minX, refMinX)
                maxX = max(maxX, refMaxX)
                minY = min(minY, refMinY)
                maxY = max(maxY, refMaxY)
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

    private func debugGroup(_ overlay: SVGDebugOverlay, polygons: PolygonSet, viewBox: CGRect) -> String {
        let skeletonPath = polylinePath(overlay.skeleton)
        let stampPaths = overlay.stamps.map { ringPath($0) }.filter { !$0.isEmpty }
        let bridgePaths = overlay.bridges.map { ringPath($0) }.filter { !$0.isEmpty }
        let tangentPath = rayPath(overlay.tangentRays)
        let anglePath = rayPath(overlay.angleRays)
        let offsetPath = rayPath(overlay.offsetRays)
        let offsetCenterlinePath = polylinePath(overlay.offsetCenterline)
        let leftRail = polylinePath(overlay.envelopeLeft)
        let rightRail = polylinePath(overlay.envelopeRight)
        let outlineRail = overlay.envelopeOutline.isEmpty ? "" : ringPath(overlay.envelopeOutline)
        let points = overlay.samplePoints.map { "<circle cx=\"\(format($0.x))\" cy=\"\(format($0.y))\" r=\"\(format(0.6))\" fill=\"#222222\" fill-opacity=\"0.5\"/>" }.joined(separator: "\n    ")
        let keyframeMarkers = overlay.keyframeMarkers.map { markerElement($0) }.joined(separator: "\n    ")
        let capPoints = overlay.capPoints.map { "<circle cx=\"\(format($0.x))\" cy=\"\(format($0.y))\" r=\"\(format(1.4))\" fill=\"#ff0033\" fill-opacity=\"0.85\"/>" }.joined(separator: "\n    ")
        let junctionOutline = overlay.junctionPatches.map { ringPath($0) }.filter { !$0.isEmpty }.map {
            "<path fill=\"none\" stroke=\"#d32f2f\" stroke-opacity=\"0.8\" stroke-width=\"0.8\" d=\"\($0)\"/>"
        }.joined(separator: "\n    ")
        let junctionCorridors = overlay.junctionCorridors.map { ringPath($0) }.filter { !$0.isEmpty }.map {
            "<path fill=\"none\" stroke=\"#00897b\" stroke-opacity=\"0.7\" stroke-width=\"0.7\" stroke-dasharray=\"3 2\" d=\"\($0)\"/>"
        }.joined(separator: "\n    ")
        let junctionControls = overlay.junctionControlPoints.map {
            "<circle cx=\"\(format($0.x))\" cy=\"\(format($0.y))\" r=\"\(format(1.8))\" fill=\"#d32f2f\" fill-opacity=\"0.9\" stroke=\"#ffffff\" stroke-width=\"0.6\"/>"
        }.joined(separator: "\n    ")

        let stampElements = stampPaths.map { "<path fill=\"none\" stroke=\"#0066ff\" stroke-opacity=\"0.3\" stroke-width=\"0.5\" d=\"\($0)\"/>" }.joined(separator: "\n    ")
        let bridgeElements = bridgePaths.map { "<path fill=\"none\" stroke=\"#00aa66\" stroke-opacity=\"0.25\" stroke-width=\"0.5\" d=\"\($0)\"/>" }.joined(separator: "\n    ")
        let offsetElements = [
            offsetCenterlinePath.isEmpty ? nil : "<path fill=\"none\" stroke=\"#00aaff\" stroke-opacity=\"0.6\" stroke-width=\"0.7\" stroke-dasharray=\"3 2\" d=\"\(offsetCenterlinePath)\"/>",
            offsetPath.isEmpty ? nil : "<path fill=\"none\" stroke=\"#00aaff\" stroke-opacity=\"0.6\" stroke-width=\"0.6\" d=\"\(offsetPath)\"/>"
        ].compactMap { $0 }.joined(separator: "\n    ")
        let unionSource = overlay.unionPolygons ?? polygons
        let unionOutline = overlay.showUnionOutline ? unionSource.map { outlinePath(for: $0) }.joined(separator: "\n    ") : ""
        let envelopeElements = [
            leftRail.isEmpty ? nil : "<path fill=\"none\" stroke=\"#8844ff\" stroke-opacity=\"0.6\" stroke-width=\"0.6\" d=\"\(leftRail)\"/>",
            rightRail.isEmpty ? nil : "<path fill=\"none\" stroke=\"#8844ff\" stroke-opacity=\"0.6\" stroke-width=\"0.6\" d=\"\(rightRail)\"/>",
            outlineRail.isEmpty ? nil : "<path fill=\"none\" stroke=\"#8844ff\" stroke-opacity=\"0.35\" stroke-width=\"0.6\" d=\"\(outlineRail)\"/>"
        ].compactMap { $0 }.joined(separator: "\n    ")
        let railSampleElements = railsSampleGroup(overlay, viewBox: viewBox)
        let railSupportElements = railsSupportGroup(overlay)
        let railJumpElements = railsJumpsGroup(overlay)
        let railRunsElements = railsRunsGroup(overlay)
        let railRingElements = railsRingGroup(overlay, viewBox: viewBox, name: "railsRing", useWindow: true)
        let railRingSelectedElements = railsRingGroup(overlay, viewBox: viewBox, name: "railsRingSelected", useWindow: true)
        let railConnectorsOnlyElements = railsConnectorsOnlyGroup(overlay, viewBox: viewBox)
        let alphaChart = overlay.alphaChart.map { alphaChartElements($0, viewBox: viewBox) } ?? ""
        let refDiff = overlay.refDiff.map { refDiffElements($0) } ?? ""

        return """
        <g id=\"debug\">
          \(refDiff)
          <path fill=\"none\" stroke=\"#ff3366\" stroke-opacity=\"0.6\" stroke-width=\"0.5\" d=\"\(skeletonPath)\"/>
          <path fill=\"none\" stroke=\"#ff9900\" stroke-opacity=\"0.6\" stroke-width=\"0.6\" d=\"\(tangentPath)\"/>
          <path fill=\"none\" stroke=\"#222222\" stroke-opacity=\"0.7\" stroke-width=\"0.6\" d=\"\(anglePath)\"/>
          \(offsetElements)
          \(envelopeElements)
          \(stampElements)
          \(bridgeElements)
          \(unionOutline)
          \(junctionOutline)
          \(junctionCorridors)
          \(junctionControls)
          \(points)
          \(keyframeMarkers)
          \(capPoints)
          \(railSampleElements)
          \(railSupportElements)
          \(railJumpElements)
          \(railRunsElements)
          \(railRingElements)
          \(railRingSelectedElements)
          \(railConnectorsOnlyElements)
          \(alphaChart)
        </g>
        """
    }

    private func railsConnectorsOnlyGroup(_ overlay: SVGDebugOverlay, viewBox: CGRect) -> String {
        guard overlay.showRailsConnectorsOnly else { return "" }
        let labelColor = "#ff1744"
        let lineColor = "#ff1744"
        let labelX = viewBox.minX + 20.0
        let labelY = viewBox.minY + 80.0
        var elements: [String] = []
        let connectors = overlay.railConnectors
        if connectors.isEmpty {
            let emptyLabel = "<text x=\"\(format(labelX))\" y=\"\(format(labelY))\" font-size=\"10\" fill=\"\(labelColor)\">railsConnectorsOnly empty</text>"
            return "<g id=\"debug-railsConnectorsOnly\">\(emptyLabel)</g>"
        }
        let requestedStart = max(0, overlay.ringSampleOptions.start)
        let requestedCount = max(0, overlay.ringSampleOptions.count)
        let windowEnd = requestedCount > 0 ? (requestedStart + requestedCount - 1) : requestedStart
        let winT0 = overlay.railsWindowT0 ?? -Double.greatestFiniteMagnitude
        let winT1 = overlay.railsWindowT1 ?? Double.greatestFiniteMagnitude
        let rectFilter = overlay.railsWindowRect
        var totalLen = 0.0
        var maxLen = 0.0
        var idx = 0
        for connector in connectors {
            totalLen += connector.length
            maxLen = max(maxLen, connector.length)
            let inIndexWindow = connector.railIndexStart >= requestedStart && connector.railIndexStart <= windowEnd
            let inTWindow = connector.tEnd >= winT0 && connector.tStart <= winT1
            let inRectWindow: Bool
            if let rectFilter {
                inRectWindow = connector.points.contains { rectFilter.contains(CGPoint(x: $0.x, y: $0.y)) }
            } else {
                inRectWindow = true
            }
            if requestedCount > 0 && !inIndexWindow {
                idx += 1
                continue
            }
            if !inTWindow || !inRectWindow {
                idx += 1
                continue
            }
            let path = polylinePath(connector.points)
            if !path.isEmpty {
                elements.append("<path fill=\"none\" stroke=\"\(lineColor)\" stroke-width=\"2.0\" stroke-opacity=\"0.9\" d=\"\(path)\"/>")
            }
            if let mid = connector.points.dropFirst().dropLast().first ?? connector.points.first {
                let label = "connector#\(idx) k=\(connector.railIndexStart) len=\(format(connector.length))"
                elements.append("<text x=\"\(format(mid.x + 3.0))\" y=\"\(format(mid.y + 3.0))\" font-size=\"9\" fill=\"\(labelColor)\">\(label)</text>")
            }
            idx += 1
        }
        let summary = "<text x=\"\(format(labelX))\" y=\"\(format(labelY))\" font-size=\"10\" fill=\"\(labelColor)\">railsConnectors count=\(connectors.count) totalLen=\(format(totalLen)) maxLen=\(format(maxLen))</text>"
        elements.append(summary)
        return """
        <g id=\"debug-railsConnectorsOnly\">
            \(elements.joined(separator: "\n    "))
        </g>
        """
    }

    private struct RailSampleStats {
        let items: [(index: Int, sample: SVGDebugOverlay.RailDebugSample, globalT: Double?)]
        let total: Int
        let afterWindow: Int
        let afterDecimation: Int
        let drawn: Int
        let requestedStart: Int
        let requestedCount: Int
        let clampedStart: Int
        let clampedCount: Int
        let available: Int
        let totalMinT: Double?
        let totalMaxT: Double?
        let windowMinT: Double?
        let windowMaxT: Double?
        let totalMinGlobalT: Double?
        let totalMaxGlobalT: Double?
        let windowMinGlobalT: Double?
        let windowMaxGlobalT: Double?
    }

    private func railsSampleGroup(_ overlay: SVGDebugOverlay, viewBox: CGRect) -> String {
        guard overlay.showRailsSamples || overlay.showRailsNormals || overlay.showRailsIndices else { return "" }
        let ringPoints = overlay.railsRings.first.map { ring in
            (ring.count > 1 && ring.first == ring.last) ? Array(ring.dropLast()) : ring
        }
        let ringGT = ringPoints.flatMap { arcLengthParam(points: $0) }
        let resolvedRingWindow = resolveRingWindowGT(overlay: overlay, ringPoints: ringPoints, ringGT: ringGT)
        let left = filteredRailSamples(overlay.leftRailSamples, options: overlay.railsSampleOptions, overlay: overlay, ringPoints: ringPoints, ringGT: ringGT, ringWindowGT0: resolvedRingWindow.gt0, ringWindowGT1: resolvedRingWindow.gt1)
        let right = filteredRailSamples(overlay.rightRailSamples, options: overlay.railsSampleOptions, overlay: overlay, ringPoints: ringPoints, ringGT: ringGT, ringWindowGT0: resolvedRingWindow.gt0, ringWindowGT1: resolvedRingWindow.gt1)

        let totalL = left.total
        let totalR = right.total
        let windowedL = left.afterWindow
        let windowedR = right.afterWindow
        let afterDecimation = left.afterDecimation + right.afterDecimation
        let drawn = afterDecimation

        let leftColor = "#ff2bd6"
        let rightColor = "#00c8ff"
        let radius = 1.5
        let normalLen = 10.0

        let leftPoints = overlay.showRailsSamples ? left.items.map { item in
            "<circle cx=\"\(format(item.sample.point.x))\" cy=\"\(format(item.sample.point.y))\" r=\"\(format(radius))\" fill=\"\(leftColor)\" fill-opacity=\"0.65\" stroke=\"#ffffff\" stroke-width=\"0.3\"/>"
        }.joined(separator: "\n    ") : ""

        let rightPoints = overlay.showRailsSamples ? right.items.map { item in
            "<circle cx=\"\(format(item.sample.point.x))\" cy=\"\(format(item.sample.point.y))\" r=\"\(format(radius))\" fill=\"\(rightColor)\" fill-opacity=\"0.65\" stroke=\"#ffffff\" stroke-width=\"0.3\"/>"
        }.joined(separator: "\n    ") : ""

        let leftNormals = overlay.showRailsNormals ? left.items.map { item in
            let start = item.sample.point
            let dir = item.sample.normal.normalized() ?? Point(x: 0, y: 0)
            let end = start + dir * normalLen
            return "<path fill=\"none\" stroke=\"\(leftColor)\" stroke-opacity=\"0.6\" stroke-width=\"0.6\" d=\"M \(format(start.x)) \(format(start.y)) L \(format(end.x)) \(format(end.y))\"/>"
        }.joined(separator: "\n    ") : ""

        let rightNormals = overlay.showRailsNormals ? right.items.map { item in
            let start = item.sample.point
            let dir = item.sample.normal.normalized() ?? Point(x: 0, y: 0)
            let end = start + dir * normalLen
            return "<path fill=\"none\" stroke=\"\(rightColor)\" stroke-opacity=\"0.6\" stroke-width=\"0.6\" d=\"M \(format(start.x)) \(format(start.y)) L \(format(end.x)) \(format(end.y))\"/>"
        }.joined(separator: "\n    ") : ""

        let windowActive = overlay.railsWindowT0 != nil || overlay.railsWindowT1 != nil || overlay.railsWindowGT0 != nil || overlay.railsWindowGT1 != nil || overlay.railsWindowRect != nil || overlay.railsWindowSkeleton != nil
        let labelStride = windowActive ? 1 : max(1, overlay.railsSampleOptions.step * 5)
        var drawnLabelsLeft = 0
        var drawnLabelsRight = 0
        let leftLabels = overlay.showRailsIndices ? left.items.enumerated().compactMap { idx, item in
            guard idx % labelStride == 0 else { return nil }
            let globalText = item.globalT.map { format($0) } ?? "nil"
            let label = windowActive ? "i=\(item.index) gt=\(globalText) t=\(format(item.sample.t))" : "L\(item.index)"
            drawnLabelsLeft += 1
            return "<text x=\"\(format(item.sample.point.x + 2.5))\" y=\"\(format(item.sample.point.y - 2.5))\" font-size=\"6\" fill=\"\(leftColor)\" stroke=\"#ffffff\" stroke-opacity=\"0.7\" stroke-width=\"0.25\">\(label)</text>"
        }.joined(separator: "\n    ") : ""

        let rightLabels = overlay.showRailsIndices ? right.items.enumerated().compactMap { idx, item in
            guard idx % labelStride == 0 else { return nil }
            let globalText = item.globalT.map { format($0) } ?? "nil"
            let label = windowActive ? "i=\(item.index) gt=\(globalText) t=\(format(item.sample.t))" : "R\(item.index)"
            drawnLabelsRight += 1
            return "<text x=\"\(format(item.sample.point.x + 2.5))\" y=\"\(format(item.sample.point.y - 2.5))\" font-size=\"6\" fill=\"\(rightColor)\" stroke=\"#ffffff\" stroke-opacity=\"0.7\" stroke-width=\"0.25\">\(label)</text>"
        }.joined(separator: "\n    ") : ""

        let labelX = viewBox.minX + 20.0
        let labelY = viewBox.minY + 40.0
        let preMin = [left.totalMinT, right.totalMinT].compactMap { $0 }.min()
        let preMax = [left.totalMaxT, right.totalMaxT].compactMap { $0 }.max()
        let postMin = [left.windowMinT, right.windowMinT].compactMap { $0 }.min()
        let postMax = [left.windowMaxT, right.windowMaxT].compactMap { $0 }.max()
        let preMinGlobal = [left.totalMinGlobalT, right.totalMinGlobalT].compactMap { $0 }.min()
        let preMaxGlobal = [left.totalMaxGlobalT, right.totalMaxGlobalT].compactMap { $0 }.max()
        let postMinGlobal = [left.windowMinGlobalT, right.windowMinGlobalT].compactMap { $0 }.min()
        let postMaxGlobal = [left.windowMaxGlobalT, right.windowMaxGlobalT].compactMap { $0 }.max()
        let preMinText = preMin.map { format($0) } ?? "nil"
        let preMaxText = preMax.map { format($0) } ?? "nil"
        let postMinText = postMin.map { format($0) } ?? "nil"
        let postMaxText = postMax.map { format($0) } ?? "nil"
        let preMinGlobalText = preMinGlobal.map { format($0) } ?? "nil"
        let preMaxGlobalText = preMaxGlobal.map { format($0) } ?? "nil"
        let postMinGlobalText = postMinGlobal.map { format($0) } ?? "nil"
        let postMaxGlobalText = postMaxGlobal.map { format($0) } ?? "nil"
        let label = "<text x=\"\(format(labelX))\" y=\"\(format(labelY))\" font-size=\"9\" fill=\"#00A3FF\">railsSamples source=\(overlay.railsSamplesSource) L=\(totalL) R=\(totalR) windowedL=\(windowedL) windowedR=\(windowedR) decim=\(afterDecimation) drawn=\(drawn) step=\(overlay.railsSampleOptions.step) reqStart=\(left.requestedStart) reqCount=\(left.requestedCount) clampL=\(left.clampedStart)+\(left.clampedCount) clampR=\(right.clampedStart)+\(right.clampedCount) availL=\(left.available) availR=\(right.available) tPre=[\(preMinText)..\(preMaxText)] tWin=[\(postMinText)..\(postMaxText)] gtPre=[\(preMinGlobalText)..\(preMaxGlobalText)] gtWin=[\(postMinGlobalText)..\(postMaxGlobalText)]</text>"
        let crossX = labelX - 10.0
        let crossY = labelY - 10.0
        let crosshair = """
        <line x1="\(format(crossX - 3.0))" y1="\(format(crossY))" x2="\(format(crossX + 3.0))" y2="\(format(crossY))" stroke="#111111" stroke-opacity="0.6" stroke-width="0.6"/>
        <line x1="\(format(crossX))" y1="\(format(crossY - 3.0))" x2="\(format(crossX))" y2="\(format(crossY + 3.0))" stroke="#111111" stroke-opacity="0.6" stroke-width="0.6"/>
        """

        if overlay.showRailsSamples || overlay.showRailsNormals || overlay.showRailsIndices {
            print("debugRails: source=\(overlay.railsSamplesSource) preFilter L=\(totalL) R=\(totalR) tPre=[\(preMinText)..\(preMaxText)] gtPre=[\(preMinGlobalText)..\(preMaxGlobalText)] postWindow L=\(windowedL) R=\(windowedR) tWin=[\(postMinText)..\(postMaxText)] gtWin=[\(postMinGlobalText)..\(postMaxGlobalText)] decim=\(afterDecimation) drawn=\(drawn) step=\(overlay.railsSampleOptions.step) reqStart=\(left.requestedStart) reqCount=\(left.requestedCount) clampL=\(left.clampedStart)+\(left.clampedCount) clampR=\(right.clampedStart)+\(right.clampedCount) availL=\(left.available) availR=\(right.available)")
            if left.available > 0 && (left.requestedStart != left.clampedStart || left.requestedCount != left.clampedCount) {
                print("debugRails: clamp L requestedStart=\(left.requestedStart) requestedCount=\(left.requestedCount) -> clampedStart=\(left.clampedStart) clampedCount=\(left.clampedCount) available=\(left.available)")
            }
            if right.available > 0 && (right.requestedStart != right.clampedStart || right.requestedCount != right.clampedCount) {
                print("debugRails: clamp R requestedStart=\(right.requestedStart) requestedCount=\(right.requestedCount) -> clampedStart=\(right.clampedStart) clampedCount=\(right.clampedCount) available=\(right.available)")
            }
            print("overlaySummary: availL=\(windowedL) availR=\(windowedR) drawnL=\(drawnLabelsLeft) drawnR=\(drawnLabelsRight) gtWin=[\(postMinGlobalText)..\(postMaxGlobalText)]")
            if overlay.assertRailsWindow && windowActive {
                if windowedL == 0 && drawnLabelsLeft > 0 {
                    preconditionFailure("railsWindow invariant failed: L avail=0 drawn=\(drawnLabelsLeft) gtWin=[\(postMinGlobalText)..\(postMaxGlobalText)]")
                }
                if windowedR == 0 && drawnLabelsRight > 0 {
                    preconditionFailure("railsWindow invariant failed: R avail=0 drawn=\(drawnLabelsRight) gtWin=[\(postMinGlobalText)..\(postMaxGlobalText)]")
                }
                if windowedL > 0 && drawnLabelsLeft == 0 {
                    preconditionFailure("railsWindow invariant failed: L avail=\(windowedL) drawn=0 gtWin=[\(postMinGlobalText)..\(postMaxGlobalText)]")
                }
                if windowedR > 0 && drawnLabelsRight == 0 {
                    preconditionFailure("railsWindow invariant failed: R avail=\(windowedR) drawn=0 gtWin=[\(postMinGlobalText)..\(postMaxGlobalText)]")
                }
            }
        }

        return """
        <g id=\"debug-rails-samples\">
          \(label)
          \(crosshair)
          \(leftPoints)
          \(rightPoints)
          \(leftNormals)
          \(rightNormals)
          \(leftLabels)
          \(rightLabels)
        </g>
        """
    }

    private func railsSupportGroup(_ overlay: SVGDebugOverlay) -> String {
        guard overlay.showRailsSupport else { return "" }
        let ringPoints = overlay.railsRings.first.map { ring in
            (ring.count > 1 && ring.first == ring.last) ? Array(ring.dropLast()) : ring
        }
        let ringGT = ringPoints.flatMap { arcLengthParam(points: $0) }
        let resolvedRingWindow = resolveRingWindowGT(overlay: overlay, ringPoints: ringPoints, ringGT: ringGT)
        let left = filteredRailSamples(overlay.leftRailSamples, options: overlay.railsSampleOptions, overlay: overlay, ringPoints: ringPoints, ringGT: ringGT, ringWindowGT0: resolvedRingWindow.gt0, ringWindowGT1: resolvedRingWindow.gt1)
        let right = filteredRailSamples(overlay.rightRailSamples, options: overlay.railsSampleOptions, overlay: overlay, ringPoints: ringPoints, ringGT: ringGT, ringWindowGT0: resolvedRingWindow.gt0, ringWindowGT1: resolvedRingWindow.gt1)
        let leftColor = "#ff2bd6"
        let rightColor = "#00c8ff"
        let windowActive = overlay.railsWindowT0 != nil || overlay.railsWindowT1 != nil || overlay.railsWindowGT0 != nil || overlay.railsWindowGT1 != nil || overlay.railsWindowRect != nil || overlay.railsWindowSkeleton != nil
        let labelStride = windowActive ? 1 : max(1, overlay.railsSampleOptions.step * 5)

        func supportLabel(_ value: String?) -> String? {
            guard let value else { return nil }
            switch value {
            case "topRight": return "TR"
            case "bottomRight": return "BR"
            case "topLeft": return "TL"
            case "bottomLeft": return "BL"
            case "rightMid": return "RM"
            case "leftMid": return "LM"
            case "topMid": return "TM"
            case "bottomMid": return "BM"
            case "L": return "L"
            case "R": return "R"
            default: return value
            }
        }

        var leftElements: [String] = []
        leftElements.reserveCapacity(left.items.count)
        var prevLeft: String? = nil
        for (idx, item) in left.items.enumerated() {
            guard let label = supportLabel(item.sample.supportCase) else { continue }
            let shouldLabel = (label != prevLeft) || (idx % labelStride == 0)
            if shouldLabel {
                leftElements.append("<text x=\"\(format(item.sample.point.x + 3.0))\" y=\"\(format(item.sample.point.y - 3.0))\" font-size=\"6\" fill=\"\(leftColor)\">\(label)</text>")
                prevLeft = label
            }
        }

        var rightElements: [String] = []
        rightElements.reserveCapacity(right.items.count)
        var prevRight: String? = nil
        for (idx, item) in right.items.enumerated() {
            guard let label = supportLabel(item.sample.supportCase) else { continue }
            let shouldLabel = (label != prevRight) || (idx % labelStride == 0)
            if shouldLabel {
                rightElements.append("<text x=\"\(format(item.sample.point.x + 3.0))\" y=\"\(format(item.sample.point.y - 3.0))\" font-size=\"6\" fill=\"\(rightColor)\">\(label)</text>")
                prevRight = label
            }
        }

        let elements = (leftElements + rightElements).joined(separator: "\n    ")
        return """
        <g id=\"debug-rails-support\">
          \(elements)
        </g>
        """
    }

    private func railsJumpsGroup(_ overlay: SVGDebugOverlay) -> String {
        guard overlay.showRailsJumps else { return "" }
        let leftSamples = overlay.leftRailJumpSamples.isEmpty ? overlay.leftRailSamples : overlay.leftRailJumpSamples
        let rightSamples = overlay.rightRailJumpSamples.isEmpty ? overlay.rightRailSamples : overlay.rightRailJumpSamples
        let threshold = max(0.0, overlay.railsJumpThreshold)
        let tMin = overlay.railsSampleOptions.tMin
        let tMax = overlay.railsSampleOptions.tMax

        func shouldInclude(_ a: SVGDebugOverlay.RailDebugSample, _ b: SVGDebugOverlay.RailDebugSample) -> Bool {
            guard let tMin, let tMax else { return true }
            return (a.t >= tMin && a.t <= tMax) && (b.t >= tMin && b.t <= tMax)
        }

        func jumpElements(_ samples: [SVGDebugOverlay.RailDebugSample], label: String) -> [String] {
            guard samples.count >= 2 else { return [] }
            var elements: [String] = []
            for i in 0..<(samples.count - 1) {
                let a = samples[i]
                let b = samples[i + 1]
                if !shouldInclude(a, b) { continue }
                let segLen = (b.point - a.point).length
                if segLen <= threshold { continue }
                let mid = Point(x: (a.point.x + b.point.x) * 0.5, y: (a.point.y + b.point.y) * 0.5)
                elements.append("<path fill=\"none\" stroke=\"#ff0033\" stroke-opacity=\"0.85\" stroke-width=\"3.5\" d=\"M \(format(a.point.x)) \(format(a.point.y)) L \(format(b.point.x)) \(format(b.point.y))\"/>")
                elements.append("<circle cx=\"\(format(mid.x))\" cy=\"\(format(mid.y))\" r=\"1.6\" fill=\"#ff0033\" fill-opacity=\"0.9\"/>")
                elements.append("<text x=\"\(format(mid.x + 3.0))\" y=\"\(format(mid.y - 3.0))\" font-size=\"8\" fill=\"#ff0033\">\(label)\(i) \(format(segLen))</text>")
            }
            return elements
        }

        let elements = (jumpElements(leftSamples, label: "L") + jumpElements(rightSamples, label: "R")).joined(separator: "\n    ")
        return """
        <g id=\"debug-rails-jumps\">
          \(elements)
        </g>
        """
    }

    private func railsRunsGroup(_ overlay: SVGDebugOverlay) -> String {
        guard overlay.showRailsRuns else { return "" }
        let leftRuns = overlay.leftRailRuns
        let rightRuns = overlay.rightRailRuns
        let dashPatterns = ["4 3", "2 3", "1 2", "6 2", "3 2 1 2"]
        let leftColor = "#ff2bd6"
        let rightColor = "#00c8ff"

        func runElements(_ runs: [[Point]], color: String, prefix: String) -> [String] {
            var elements: [String] = []
            for (index, run) in runs.enumerated() {
                guard run.count >= 2 else { continue }
                let path = polylinePath(run)
                let dash = dashPatterns[index % dashPatterns.count]
                elements.append("<path fill=\"none\" stroke=\"\(color)\" stroke-opacity=\"0.7\" stroke-width=\"1.0\" stroke-dasharray=\"\(dash)\" d=\"\(path)\"/>")
                let first = run[0]
                elements.append("<text x=\"\(format(first.x + 3.0))\" y=\"\(format(first.y - 3.0))\" font-size=\"7\" fill=\"\(color)\">\(prefix)run\(index) n=\(run.count)</text>")
                if index > 0 {
                    let marker = [
                        "<line x1=\"\(format(first.x - 2.5))\" y1=\"\(format(first.y - 2.5))\" x2=\"\(format(first.x + 2.5))\" y2=\"\(format(first.y + 2.5))\" stroke=\"\(color)\" stroke-width=\"0.9\"/>",
                        "<line x1=\"\(format(first.x - 2.5))\" y1=\"\(format(first.y + 2.5))\" x2=\"\(format(first.x + 2.5))\" y2=\"\(format(first.y - 2.5))\" stroke=\"\(color)\" stroke-width=\"0.9\"/>"
                    ].joined(separator: "\n    ")
                    elements.append(marker)
                }
            }
            return elements
        }

        let elements = (runElements(leftRuns, color: leftColor, prefix: "L") + runElements(rightRuns, color: rightColor, prefix: "R")).joined(separator: "\n    ")
        return """
        <g id=\"debug-rails-runs\">
            \(elements)
        </g>
        """
    }

    private struct RingSliceStats {
        let points: [Point]
        let requestedStart: Int
        let requestedCount: Int
        let clampedStart: Int
        let clampedCount: Int
        let available: Int
    }

    private func sliceRing(_ points: [Point], options: SVGDebugOverlay.RingSampleOptions) -> RingSliceStats {
        let available = points.count
        let requestedStart = max(0, options.start)
        let requestedCount = max(0, options.count)
        let clampedStart = min(requestedStart, max(0, available - 1))
        let clampedCount = min(requestedCount, max(0, available - clampedStart))
        let sliced = (clampedCount == 0) ? [] : Array(points[clampedStart..<(clampedStart + clampedCount)])
        return RingSliceStats(
            points: sliced,
            requestedStart: requestedStart,
            requestedCount: requestedCount,
            clampedStart: clampedStart,
            clampedCount: clampedCount,
            available: available
        )
    }

    private func railsRingGroup(_ overlay: SVGDebugOverlay, viewBox: CGRect, name: String, useWindow: Bool) -> String {
        let shouldShow = (name == "railsRing") ? overlay.showRailsRing : overlay.showRailsRingSelected
        guard shouldShow else { return "" }
        let ringColor = "#ff9f1a"
        let arrowColor = "#ff6f00"
        let labelColor = "#ffb300"
        let arrowStep = 20
        let arrowLength = 8.0
        let arrowHead = 3.0
        let connectorColor = "#00c853"
        let ringLabelX = viewBox.minX + 20.0
        let ringLabelY = viewBox.minY + 60.0
        var elements: [String] = []
        if overlay.railsRings.isEmpty {
            let emptyLabel = "<text x=\"\(format(ringLabelX))\" y=\"\(format(ringLabelY))\" font-size=\"10\" fill=\"\(labelColor)\">\(name) empty</text>"
            return "<g id=\"debug-\(name)\">\(emptyLabel)</g>"
        }
        for (ringIndex, ring) in overlay.railsRings.enumerated() {
            let stats = useWindow ? sliceRing(ring, options: overlay.ringSampleOptions) : RingSliceStats(
                points: ring,
                requestedStart: 0,
                requestedCount: ring.count,
                clampedStart: 0,
                clampedCount: ring.count,
                available: ring.count
            )
            let ringIndexable = (ring.count > 1 && ring.first == ring.last) ? Array(ring.dropLast()) : ring
            let ringGT = arcLengthParam(points: ringIndexable)
            let ringWindowResolved = resolveRingWindowGT(overlay: overlay, ringPoints: ringIndexable, ringGT: ringGT)
            let ringWindowActive = ringWindowResolved.gt0 != nil || ringWindowResolved.gt1 != nil
            let ringWindowT0 = ringWindowResolved.gt0 ?? -Double.greatestFiniteMagnitude
            let ringWindowT1 = ringWindowResolved.gt1 ?? Double.greatestFiniteMagnitude
            var windowIndices: [Int] = []
            if ringWindowActive, let ringGT {
                for i in 0..<ringGT.count {
                    let value = ringGT[i]
                    let inWindow: Bool
                    if ringWindowT0 <= ringWindowT1 {
                        inWindow = value >= ringWindowT0 && value <= ringWindowT1
                    } else {
                        inWindow = value >= ringWindowT0 || value <= ringWindowT1
                    }
                    if inWindow { windowIndices.append(i) }
                }
            }
            let points: [Point]
            if ringWindowActive, !windowIndices.isEmpty {
                points = windowIndices.map { ringIndexable[$0] }
            } else {
                points = stats.points
            }
            let windowStats = RingSliceStats(
                points: points,
                requestedStart: stats.requestedStart,
                requestedCount: stats.requestedCount,
                clampedStart: ringWindowActive ? (windowIndices.first ?? 0) : stats.clampedStart,
                clampedCount: ringWindowActive ? windowIndices.count : stats.clampedCount,
                available: ringWindowActive ? ringIndexable.count : stats.available
            )
            let labelStep = overlay.ringSampleOptions.labelStep ?? max(10, max(1, points.count / 20))
            let pathPoints = ringWindowActive && !points.isEmpty ? points : ((name == "railsRing") ? ring : points)
            let ringPath = polylinePath(pathPoints)
            if !ringPath.isEmpty {
                elements.append("<path fill=\"none\" stroke=\"\(ringColor)\" stroke-opacity=\"0.85\" stroke-width=\"0.9\" d=\"\(ringPath)\"/>")
            }
            if !points.isEmpty {
                let dots = points.map { point in
                    "<circle cx=\"\(format(point.x))\" cy=\"\(format(point.y))\" r=\"0.8\" fill=\"\(ringColor)\" fill-opacity=\"0.8\"/>"
                }.joined(separator: "\n    ")
                elements.append(dots)
            }
            if points.count >= 2 {
                for i in stride(from: 0, to: points.count - 1, by: arrowStep) {
                    let p = points[i]
                    let q = points[i + 1]
                    let dir = (q - p).normalized() ?? Point(x: 1.0, y: 0.0)
                    let tip = p + dir * arrowLength
                    let normal = Point(x: -dir.y, y: dir.x)
                    let left = tip - dir * arrowHead + normal * (arrowHead * 0.6)
                    let right = tip - dir * arrowHead - normal * (arrowHead * 0.6)
                    elements.append("<line x1=\"\(format(p.x))\" y1=\"\(format(p.y))\" x2=\"\(format(tip.x))\" y2=\"\(format(tip.y))\" stroke=\"\(arrowColor)\" stroke-width=\"0.9\"/>")
                    elements.append("<line x1=\"\(format(left.x))\" y1=\"\(format(left.y))\" x2=\"\(format(tip.x))\" y2=\"\(format(tip.y))\" stroke=\"\(arrowColor)\" stroke-width=\"0.9\"/>")
                    elements.append("<line x1=\"\(format(right.x))\" y1=\"\(format(right.y))\" x2=\"\(format(tip.x))\" y2=\"\(format(tip.y))\" stroke=\"\(arrowColor)\" stroke-width=\"0.9\"/>")
                }
                if let labelCount = overlay.ringSampleOptions.labelCount, labelCount > 0, points.count > 1 {
                    var cumulative: [Double] = [0.0]
                    cumulative.reserveCapacity(points.count)
                    for i in 1..<points.count {
                        cumulative.append(cumulative[i - 1] + (points[i] - points[i - 1]).length)
                    }
                    let totalLength = cumulative.last ?? 0.0
                    var usedIndices = Set<Int>()
                    for i in 0..<labelCount {
                        let target = totalLength * (Double(i) / Double(labelCount))
                        var index = 0
                        for j in 0..<cumulative.count {
                            if cumulative[j] >= target {
                                index = j
                                break
                            }
                        }
                        if usedIndices.insert(index).inserted {
                            let p = points[index]
                            let labelIndex = ringWindowActive && !windowIndices.isEmpty ? windowIndices[index] : (stats.clampedStart + index)
                            let gtText = ringGT.map { format($0[labelIndex]) } ?? "nil"
                            let label = ringWindowActive ? "k=\(labelIndex) gt=\(gtText)" : "k=\(labelIndex)"
                            elements.append("<text x=\"\(format(p.x + 3.0))\" y=\"\(format(p.y - 3.0))\" font-size=\"9\" fill=\"\(labelColor)\">\(label)</text>")
                        }
                    }
                } else {
                    let strideValue = ringWindowActive ? 1 : labelStep
                    for i in stride(from: 0, to: points.count, by: strideValue) {
                        let p = points[i]
                        let labelIndex = ringWindowActive && !windowIndices.isEmpty ? windowIndices[i] : (stats.clampedStart + i)
                        let gtText = ringGT.map { format($0[labelIndex]) } ?? "nil"
                        let label = ringWindowActive ? "k=\(labelIndex) gt=\(gtText)" : "k=\(labelIndex)"
                        elements.append("<text x=\"\(format(p.x + 3.0))\" y=\"\(format(p.y - 3.0))\" font-size=\"9\" fill=\"\(labelColor)\">\(label)</text>")
                    }
                }
            }
            if points.count >= 4 {
                let segments = segments(from: points, ensureClosed: false)
                guard segments.count >= 3 else { continue }
                for i in 0..<segments.count {
                    let jStart = i + 2
                    if jStart >= segments.count { continue }
                    for j in jStart..<segments.count {
                        if i == 0 && j == segments.count - 1 { continue }
                        if j == i + 1 { continue }
                        let hit = intersect(segments[i], segments[j], tol: 1.0e-8)
                        let intersection: Point?
                        switch hit {
                        case .proper(let point), .endpoint(let point):
                            intersection = point
                        default:
                            intersection = nil
                        }
                        guard let intersection else { continue }
                        let xSize = 3.0
                        let a = Point(x: intersection.x - xSize, y: intersection.y - xSize)
                        let b = Point(x: intersection.x + xSize, y: intersection.y + xSize)
                        let c = Point(x: intersection.x - xSize, y: intersection.y + xSize)
                        let d = Point(x: intersection.x + xSize, y: intersection.y - xSize)
                        elements.append("<line x1=\"\(format(a.x))\" y1=\"\(format(a.y))\" x2=\"\(format(b.x))\" y2=\"\(format(b.y))\" stroke=\"#ff0033\" stroke-width=\"1.2\"/>")
                        elements.append("<line x1=\"\(format(c.x))\" y1=\"\(format(c.y))\" x2=\"\(format(d.x))\" y2=\"\(format(d.y))\" stroke=\"#ff0033\" stroke-width=\"1.2\"/>")
                        elements.append("<text x=\"\(format(intersection.x + 4.0))\" y=\"\(format(intersection.y - 4.0))\" font-size=\"9\" fill=\"#ff0033\">\(i)/\(j)</text>")
                    }
                }
            }
            if overlay.showRailsRingConnectors, !overlay.railJoinSeams.isEmpty, !ringIndexable.isEmpty {
                let windowStart = stats.clampedStart
                let windowEnd = stats.clampedStart + max(0, stats.clampedCount - 1)
                let ringGTWindow = ringGT
                for seam in overlay.railJoinSeams where seam.ringIndex >= 0 && seam.ringIndex < ringIndexable.count {
                    if useWindow && (seam.ringIndex < windowStart || seam.ringIndex > windowEnd) {
                        continue
                    }
                    if ringWindowActive, let ringGTWindow {
                        let value = ringGTWindow[seam.ringIndex]
                        let inWindow: Bool
                        if ringWindowT0 <= ringWindowT1 {
                            inWindow = value >= ringWindowT0 && value <= ringWindowT1
                        } else {
                            inWindow = value >= ringWindowT0 || value <= ringWindowT1
                        }
                        if !inWindow { continue }
                    }
                    let p = ringIndexable[seam.ringIndex]
                    let seamColor = seam.side == "L" ? "#00e5ff" : "#00c853"
                    elements.append("<circle cx=\"\(format(p.x))\" cy=\"\(format(p.y))\" r=\"2.2\" fill=\"\(seamColor)\" fill-opacity=\"0.9\"/>")
                    elements.append("<text x=\"\(format(p.x + 3.0))\" y=\"\(format(p.y + 3.0))\" font-size=\"9\" fill=\"\(seamColor)\">seam k=\(seam.ringIndex) \(seam.side)</text>")
                }
            }
            let label = "<text x=\"\(format(ringLabelX))\" y=\"\(format(ringLabelY + Double(ringIndex) * 12.0))\" font-size=\"10\" fill=\"\(labelColor)\">\(name)[\(ringIndex)] avail=\(windowStats.available) start=\(windowStats.requestedStart) count=\(windowStats.requestedCount) clamp=\(windowStats.clampedStart)+\(windowStats.clampedCount)</text>"
            elements.append(label)
            print("ringOverlay name=\(name) total=\(windowStats.available) reqStart=\(windowStats.requestedStart) reqCount=\(windowStats.requestedCount) clampedStart=\(windowStats.clampedStart) clampedCount=\(windowStats.clampedCount)")
            if let ringGT {
                let minGT = ringGT.min().map { format($0) } ?? "nil"
                let maxGT = ringGT.max().map { format($0) } ?? "nil"
                print("ringGT name=\(name) gtPre=[\(minGT)..\(maxGT)] totalLen=\(format(ringGT.count > 1 ? (ringGT.last ?? 0.0) : 0.0))")
            }
            if let ringGT, overlay.ringWindowExtrema != nil {
                let extrema = resolveRingWindowGT(overlay: overlay, ringPoints: ringIndexable, ringGT: ringGT)
                if let index = extrema.extremaIndex, let gt = extrema.extremaGT {
                    let extremaLabel = overlay.ringWindowExtrema ?? ""
                    print("ringExtremaGT \(extremaLabel) idx=\(index) gt=\(format(gt))")
                    if overlay.assertRingWindowHitsExtrema {
                        let inWindow: Bool
                        if ringWindowT0 <= ringWindowT1 {
                            inWindow = gt >= ringWindowT0 && gt <= ringWindowT1
                        } else {
                            inWindow = gt >= ringWindowT0 || gt <= ringWindowT1
                        }
                        if !inWindow {
                            let extremaLabel = overlay.ringWindowExtrema ?? ""
                            preconditionFailure("ringWindow extrema not in window: extrema=\(extremaLabel) gt=\(format(gt)) window=[\(format(ringWindowT0))..\(format(ringWindowT1))]")
                        }
                    }
                }
            }
            if overlay.assertRingWindow && ringWindowActive && windowStats.clampedCount == 0 {
                print("ringGT ERROR: windowed=0")
            }
        }

        if overlay.showRailsRingConnectors {
            let leftCount = overlay.leftRailSamples.count
            let rightCount = overlay.rightRailSamples.count
            let maxCount = min(leftCount, rightCount)
            if maxCount > 0 {
                let requestedStart = max(0, overlay.ringSampleOptions.start)
                let requestedCount = max(0, overlay.ringSampleOptions.count)
                let clampedStart = min(requestedStart, max(0, maxCount - 1))
                let clampedCount = min(requestedCount, max(0, maxCount - clampedStart))
                if clampedCount > 0 {
                    let end = clampedStart + clampedCount
                    for i in stride(from: clampedStart, to: end, by: arrowStep) {
                        let left = overlay.leftRailSamples[i].point
                        let right = overlay.rightRailSamples[i].point
                        elements.append("<line x1=\"\(format(left.x))\" y1=\"\(format(left.y))\" x2=\"\(format(right.x))\" y2=\"\(format(right.y))\" stroke=\"\(connectorColor)\" stroke-opacity=\"0.6\" stroke-width=\"0.7\"/>")
                    }
                }
            }
        }

        return """
        <g id=\"debug-\(name)\">
            \(elements.joined(separator: "\n    "))
        </g>
        """
    }

    private func filteredRailSamples(
        _ samples: [SVGDebugOverlay.RailDebugSample],
        options: SVGDebugOverlay.RailsSampleOptions,
        overlay: SVGDebugOverlay,
        ringPoints: [Point]?,
        ringGT: [Double]?,
        ringWindowGT0: Double?,
        ringWindowGT1: Double?
    ) -> RailSampleStats {
        guard !samples.isEmpty else {
            return RailSampleStats(items: [], total: 0, afterWindow: 0, afterDecimation: 0, drawn: 0, requestedStart: options.start, requestedCount: options.count, clampedStart: 0, clampedCount: 0, available: 0, totalMinT: nil, totalMaxT: nil, windowMinT: nil, windowMaxT: nil, totalMinGlobalT: nil, totalMaxGlobalT: nil, windowMinGlobalT: nil, windowMaxGlobalT: nil)
        }
        let tMin = options.tMin ?? -Double.greatestFiniteMagnitude
        let tMax = options.tMax ?? Double.greatestFiniteMagnitude
        let winT0 = overlay.railsWindowT0 ?? -Double.greatestFiniteMagnitude
        let winT1 = overlay.railsWindowT1 ?? Double.greatestFiniteMagnitude
        let winGT0 = overlay.railsWindowGT0 ?? -Double.greatestFiniteMagnitude
        let winGT1 = overlay.railsWindowGT1 ?? Double.greatestFiniteMagnitude
        let skeletonFilter = overlay.railsWindowSkeleton
        let rectFilter = overlay.railsWindowRect
        let totalMinT = samples.map(\.t).min()
        let totalMaxT = samples.map(\.t).max()
        let railsWindowActive = overlay.railsWindowT0 != nil || overlay.railsWindowT1 != nil
        let railsGTWindowActive = overlay.railsWindowGT0 != nil || overlay.railsWindowGT1 != nil
        let ringWindowActive = ringWindowGT0 != nil || ringWindowGT1 != nil
        let ringWindowT0 = ringWindowGT0 ?? -Double.greatestFiniteMagnitude
        let ringWindowT1 = ringWindowGT1 ?? Double.greatestFiniteMagnitude
        var cumulative: [Double] = []
        cumulative.reserveCapacity(samples.count)
        var totalLength = 0.0
        cumulative.append(0.0)
        if samples.count >= 2 {
            for i in 1..<samples.count {
                totalLength += (samples[i].point - samples[i - 1].point).length
                cumulative.append(totalLength)
            }
        }
        let localGlobalTByIndex: [Double?] = cumulative.map { totalLength > 0.0 ? ($0 / totalLength) : nil }
        let totalMinLocalGlobalT = localGlobalTByIndex.compactMap { $0 }.min()
        let totalMaxLocalGlobalT = localGlobalTByIndex.compactMap { $0 }.max()
        let totalMinGlobalT = ringWindowActive ? ringGT?.min() : totalMinLocalGlobalT
        let totalMaxGlobalT = ringWindowActive ? ringGT?.max() : totalMaxLocalGlobalT
        var filtered: [(index: Int, sample: SVGDebugOverlay.RailDebugSample)] = []
        filtered.reserveCapacity(samples.count)
        for (index, sample) in samples.enumerated() where sample.t >= tMin && sample.t <= tMax {
            if let skeletonFilter, let sampleId = sample.skeletonId, sampleId != skeletonFilter {
                continue
            }
            if ringWindowActive {
                guard let ringPoints, let ringGT, !ringPoints.isEmpty, ringPoints.count == ringGT.count else {
                    continue
                }
                var nearestIndex = 0
                var bestDist = Double.greatestFiniteMagnitude
                for i in 0..<ringPoints.count {
                    let dist = (ringPoints[i] - sample.point).length
                    if dist < bestDist {
                        bestDist = dist
                        nearestIndex = i
                    }
                }
                let globalT = ringGT[nearestIndex]
                let inWindow: Bool
                if ringWindowT0 <= ringWindowT1 {
                    inWindow = globalT >= ringWindowT0 && globalT <= ringWindowT1
                } else {
                    inWindow = globalT >= ringWindowT0 || globalT <= ringWindowT1
                }
                if !inWindow { continue }
            } else if railsGTWindowActive {
                let globalT = localGlobalTByIndex[index]
                let inWindow: Bool
                if let globalT {
                    if winGT0 <= winGT1 {
                        inWindow = globalT >= winGT0 && globalT <= winGT1
                    } else {
                        inWindow = globalT >= winGT0 || globalT <= winGT1
                    }
                } else {
                    inWindow = false
                }
                if !inWindow { continue }
            } else if railsWindowActive {
                let inWindow: Bool
                if winT0 <= winT1 {
                    inWindow = sample.t >= winT0 && sample.t <= winT1
                } else {
                    inWindow = sample.t >= winT0 || sample.t <= winT1
                }
                if !inWindow { continue }
            }
            if let rect = rectFilter, !rect.contains(CGPoint(x: sample.point.x, y: sample.point.y)) {
                continue
            }
            filtered.append((index: index, sample: sample))
        }

        let step = max(1, options.step)
        let requestedStart = max(0, options.start)
        let requestedCount = max(0, options.count)
        let available = filtered.count
        let clampedStart: Int
        if available == 0 {
            clampedStart = 0
        } else {
            clampedStart = min(requestedStart, max(0, available - 1))
        }
        let clampedCount: Int
        if available == 0 {
            clampedCount = 0
        } else if requestedCount <= 0 {
            clampedCount = available - clampedStart
        } else {
            clampedCount = min(requestedCount, available - clampedStart)
        }
        let windowMinT = filtered.map { $0.sample.t }.min()
        let windowMaxT = filtered.map { $0.sample.t }.max()
        let windowMinGlobalT: Double?
        let windowMaxGlobalT: Double?
        if ringWindowActive, let ringGT, let ringPoints, ringPoints.count == ringGT.count {
            var minValue = Double.greatestFiniteMagnitude
            var maxValue = -Double.greatestFiniteMagnitude
            for item in filtered {
                var nearestIndex = 0
                var bestDist = Double.greatestFiniteMagnitude
                for i in 0..<ringPoints.count {
                    let dist = (ringPoints[i] - item.sample.point).length
                    if dist < bestDist {
                        bestDist = dist
                        nearestIndex = i
                    }
                }
                let value = ringGT[nearestIndex]
                minValue = min(minValue, value)
                maxValue = max(maxValue, value)
            }
            windowMinGlobalT = minValue.isFinite ? minValue : nil
            windowMaxGlobalT = maxValue.isFinite ? maxValue : nil
        } else {
            windowMinGlobalT = filtered.compactMap { localGlobalTByIndex[$0.index] }.min()
            windowMaxGlobalT = filtered.compactMap { localGlobalTByIndex[$0.index] }.max()
        }
        if clampedCount == 0 {
            return RailSampleStats(items: [], total: samples.count, afterWindow: filtered.count, afterDecimation: 0, drawn: 0, requestedStart: requestedStart, requestedCount: requestedCount, clampedStart: clampedStart, clampedCount: clampedCount, available: available, totalMinT: totalMinT, totalMaxT: totalMaxT, windowMinT: windowMinT, windowMaxT: windowMaxT, totalMinGlobalT: totalMinGlobalT, totalMaxGlobalT: totalMaxGlobalT, windowMinGlobalT: windowMinGlobalT, windowMaxGlobalT: windowMaxGlobalT)
        }
        var result: [(index: Int, sample: SVGDebugOverlay.RailDebugSample)] = []
        result.reserveCapacity(min(clampedCount, filtered.count))
        var filteredIndex = 0
        for item in filtered {
            if filteredIndex < clampedStart {
                filteredIndex += 1
                continue
            }
            if result.count >= clampedCount { break }
            if ((filteredIndex - clampedStart) % step) == 0 {
                result.append(item)
            }
            filteredIndex += 1
        }
        let decimCount = result.count
        let withGlobal = result.map { item -> (index: Int, sample: SVGDebugOverlay.RailDebugSample, globalT: Double?) in
            if ringWindowActive, let ringGT, let ringPoints, ringPoints.count == ringGT.count {
                var nearestIndex = 0
                var bestDist = Double.greatestFiniteMagnitude
                for i in 0..<ringPoints.count {
                    let dist = (ringPoints[i] - item.sample.point).length
                    if dist < bestDist {
                        bestDist = dist
                        nearestIndex = i
                    }
                }
                return (index: item.index, sample: item.sample, globalT: ringGT[nearestIndex])
            }
            return (index: item.index, sample: item.sample, globalT: localGlobalTByIndex[item.index])
        }
        return RailSampleStats(items: withGlobal, total: samples.count, afterWindow: filtered.count, afterDecimation: decimCount, drawn: decimCount, requestedStart: requestedStart, requestedCount: requestedCount, clampedStart: clampedStart, clampedCount: clampedCount, available: available, totalMinT: totalMinT, totalMaxT: totalMaxT, windowMinT: windowMinT, windowMaxT: windowMaxT, totalMinGlobalT: totalMinGlobalT, totalMaxGlobalT: totalMaxGlobalT, windowMinGlobalT: windowMinGlobalT, windowMaxGlobalT: windowMaxGlobalT)
    }

    private func arcLengthParam(points: [Point]) -> [Double]? {
        guard points.count >= 2 else { return nil }
        var cumulative: [Double] = Array(repeating: 0.0, count: points.count)
        var total = 0.0
        for i in 1..<points.count {
            total += (points[i] - points[i - 1]).length
            cumulative[i] = total
        }
        guard total > 0.0 else { return nil }
        return cumulative.map { $0 / total }
    }

    private func resolveRingWindowGT(overlay: SVGDebugOverlay, ringPoints: [Point]?, ringGT: [Double]?) -> (gt0: Double?, gt1: Double?, extremaIndex: Int?, extremaGT: Double?) {
        guard let ringPoints, let ringGT, ringPoints.count == ringGT.count, !ringPoints.isEmpty else {
            return (overlay.ringWindowGT0 ?? overlay.ringWindowT0, overlay.ringWindowGT1 ?? overlay.ringWindowT1, nil, nil)
        }
        let extrema = overlay.ringWindowExtrema
        let radius = overlay.ringWindowRadius ?? 0.0
        if let extrema {
            var minX = ringPoints[0].x
            var maxX = ringPoints[0].x
            var minY = ringPoints[0].y
            var maxY = ringPoints[0].y
            var minXIndex = 0
            var maxXIndex = 0
            var minYIndex = 0
            var maxYIndex = 0
            for (idx, point) in ringPoints.enumerated() {
                if point.x < minX { minX = point.x; minXIndex = idx }
                if point.x > maxX { maxX = point.x; maxXIndex = idx }
                if point.y < minY { minY = point.y; minYIndex = idx }
                if point.y > maxY { maxY = point.y; maxYIndex = idx }
            }
            let chosenIndex: Int
            switch extrema {
            case "minX": chosenIndex = minXIndex
            case "maxX": chosenIndex = maxXIndex
            case "minY": chosenIndex = minYIndex
            case "maxY": chosenIndex = maxYIndex
            default:
                return (overlay.ringWindowGT0 ?? overlay.ringWindowT0, overlay.ringWindowGT1 ?? overlay.ringWindowT1, nil, nil)
            }
            let gt = ringGT[chosenIndex]
            let clamped0 = max(0.0, gt - radius)
            let clamped1 = min(1.0, gt + radius)
            return (clamped0, clamped1, chosenIndex, gt)
        }
        return (overlay.ringWindowGT0 ?? overlay.ringWindowT0, overlay.ringWindowGT1 ?? overlay.ringWindowT1, nil, nil)
    }

    struct RailOverlayItem: Equatable {
        let side: String
        let index: Int
        let point: Point
        let localT: Double
        let globalT: Double
    }

    struct RingOverlayItem: Equatable {
        let index: Int
        let point: Point
        let ringGT: Double
    }

    func railOverlayItems(_ overlay: SVGDebugOverlay) -> [RailOverlayItem] {
        let ringPoints = overlay.railsRings.first.map { ring in
            (ring.count > 1 && ring.first == ring.last) ? Array(ring.dropLast()) : ring
        }
        let ringGT = ringPoints.flatMap { arcLengthParam(points: $0) }
        let resolvedRingWindow = resolveRingWindowGT(overlay: overlay, ringPoints: ringPoints, ringGT: ringGT)
        let left = filteredRailSamples(overlay.leftRailSamples, options: overlay.railsSampleOptions, overlay: overlay, ringPoints: ringPoints, ringGT: ringGT, ringWindowGT0: resolvedRingWindow.gt0, ringWindowGT1: resolvedRingWindow.gt1)
        let right = filteredRailSamples(overlay.rightRailSamples, options: overlay.railsSampleOptions, overlay: overlay, ringPoints: ringPoints, ringGT: ringGT, ringWindowGT0: resolvedRingWindow.gt0, ringWindowGT1: resolvedRingWindow.gt1)
        let leftItems = left.items.compactMap { item -> RailOverlayItem? in
            guard let globalT = item.globalT else { return nil }
            return RailOverlayItem(side: "L", index: item.index, point: item.sample.point, localT: item.sample.t, globalT: globalT)
        }
        let rightItems = right.items.compactMap { item -> RailOverlayItem? in
            guard let globalT = item.globalT else { return nil }
            return RailOverlayItem(side: "R", index: item.index, point: item.sample.point, localT: item.sample.t, globalT: globalT)
        }
        return leftItems + rightItems
    }

    func ringOverlayItems(_ overlay: SVGDebugOverlay, name: String) -> [RingOverlayItem] {
        let shouldShow = (name == "railsRing") ? overlay.showRailsRing : overlay.showRailsRingSelected
        guard shouldShow else { return [] }
        guard let ring = overlay.railsRings.first else { return [] }
        let ringIndexable = (ring.count > 1 && ring.first == ring.last) ? Array(ring.dropLast()) : ring
        guard let ringGT = arcLengthParam(points: ringIndexable), ringGT.count == ringIndexable.count else { return [] }
        let resolvedRingWindow = resolveRingWindowGT(overlay: overlay, ringPoints: ringIndexable, ringGT: ringGT)
        let ringWindowActive = resolvedRingWindow.gt0 != nil || resolvedRingWindow.gt1 != nil
        let ringWindowT0 = resolvedRingWindow.gt0 ?? -Double.greatestFiniteMagnitude
        let ringWindowT1 = resolvedRingWindow.gt1 ?? Double.greatestFiniteMagnitude
        var items: [RingOverlayItem] = []
        items.reserveCapacity(ringIndexable.count)
        for i in 0..<ringIndexable.count {
            let gt = ringGT[i]
            if ringWindowActive {
                let inWindow: Bool
                if ringWindowT0 <= ringWindowT1 {
                    inWindow = gt >= ringWindowT0 && gt <= ringWindowT1
                } else {
                    inWindow = gt >= ringWindowT0 || gt <= ringWindowT1
                }
                if !inWindow { continue }
            }
            items.append(RingOverlayItem(index: i, point: ringIndexable[i], ringGT: gt))
        }
        return items
    }

    private func markerElement(_ marker: SVGPathBuilder.KeyframeMarker) -> String {
        let stroke = "stroke=\"#ffffff\" stroke-width=\"0.5\""
        let fill = "fill=\"\(marker.color)\" fill-opacity=\"0.85\""
        let x = marker.point.x
        let y = marker.point.y
        let r = marker.radius
        switch marker.shape {
        case .circle:
            return "<circle cx=\"\(format(x))\" cy=\"\(format(y))\" r=\"\(format(r))\" \(fill) \(stroke)/>"
        case .square:
            let side = r * 1.6
            let half = side * 0.5
            return "<rect x=\"\(format(x - half))\" y=\"\(format(y - half))\" width=\"\(format(side))\" height=\"\(format(side))\" \(fill) \(stroke)/>"
        case .diamond:
            let d = r * 1.8
            let path = "M \(format(x)) \(format(y - d)) L \(format(x + d)) \(format(y)) L \(format(x)) \(format(y + d)) L \(format(x - d)) \(format(y)) Z"
            return "<path d=\"\(path)\" \(fill) \(stroke)/>"
        case .triangle:
            let d = r * 1.9
            let path = "M \(format(x)) \(format(y - d)) L \(format(x + d)) \(format(y + d)) L \(format(x - d)) \(format(y + d)) Z"
            return "<path d=\"\(path)\" \(fill) \(stroke)/>"
        case .invertedTriangle:
            let d = r * 1.9
            let path = "M \(format(x)) \(format(y + d)) L \(format(x + d)) \(format(y - d)) L \(format(x - d)) \(format(y - d)) Z"
            return "<path d=\"\(path)\" \(fill) \(stroke)/>"
        case .triangleLeft:
            let d = r * 1.9
            let path = "M \(format(x - d)) \(format(y)) L \(format(x + d)) \(format(y - d)) L \(format(x + d)) \(format(y + d)) Z"
            return "<path d=\"\(path)\" \(fill) \(stroke)/>"
        case .triangleRight:
            let d = r * 1.9
            let path = "M \(format(x + d)) \(format(y)) L \(format(x - d)) \(format(y - d)) L \(format(x - d)) \(format(y + d)) Z"
            return "<path d=\"\(path)\" \(fill) \(stroke)/>"
        }
    }

    private func debugReferencePath(_ reference: DebugReference) -> String {
        let trimmed = reference.svgPathD.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let opacity = reference.opacity.map { " opacity=\"\(format($0))\"" } ?? ""
        let transform = reference.transform.map { " transform=\"\($0)\"" } ?? ""
        return "<path id=\"debug-reference\" fill=\"none\" stroke=\"#999999\" stroke-opacity=\"0.6\" stroke-width=\"0.7\"\(opacity)\(transform) d=\"\(trimmed)\"/>"
    }

    private func alphaChartElements(_ chart: AlphaDebugChart, viewBox: CGRect) -> String {
        let chartWidth: Double = 220.0
        let chartHeight: Double = 140.0
        let origin = Point(x: viewBox.minX + 8.0, y: viewBox.minY + 8.0)

        let border = "<rect x=\"\(format(origin.x))\" y=\"\(format(origin.y))\" width=\"\(format(chartWidth))\" height=\"\(format(chartHeight))\" fill=\"none\" stroke=\"#222222\" stroke-width=\"0.8\"/>"

        let diagStart = Point(x: origin.x, y: origin.y + chartHeight)
        let diagEnd = Point(x: origin.x + chartWidth, y: origin.y)
        let diagPath = "M \(format(diagStart.x)) \(format(diagStart.y)) L \(format(diagEnd.x)) \(format(diagEnd.y))"

        let sampleCount = 64
        var biasPoints: [Point] = []
        var valuePoints: [Point] = []
        biasPoints.reserveCapacity(sampleCount)
        valuePoints.reserveCapacity(sampleCount)
        let span = chart.endValue - chart.startValue
        let valueSpan = chart.valueMax - chart.valueMin

        for i in 0..<sampleCount {
            let u = Double(i) / Double(sampleCount - 1)
            let uPrime = DefaultParamEvaluator.biasCurveValue(u, bias: chart.alphaUsed)
            let x = origin.x + u * chartWidth
            let y = origin.y + (1.0 - uPrime) * chartHeight
            biasPoints.append(Point(x: x, y: y))
            if valueSpan > 1.0e-12 {
                let value = chart.startValue + span * uPrime
                let normalized = ScalarMath.clamp01((value - chart.valueMin) / valueSpan)
                let valueY = origin.y + (1.0 - normalized) * chartHeight
                valuePoints.append(Point(x: x, y: valueY))
            }
        }

        let biasPath = polylinePath(biasPoints)
        let valuePath = valuePoints.isEmpty ? "" : polylinePath(valuePoints)

        let labelAlpha = "alphaRaw=\(String(format: "%.3f", chart.alphaRaw)) alphaUsed=\(String(format: "%.3f", chart.alphaUsed))"
        let labelSegment = "segment [\(String(format: "%.3f", chart.t0))..\(String(format: "%.3f", chart.t1))]"
        let labelTrack = "\(chart.trackLabel) [\(String(format: "%.3f", chart.valueMin))..\(String(format: "%.3f", chart.valueMax))]"

        let textX = format(origin.x + 6.0)
        let textY = format(origin.y + 14.0)
        let textY2 = format(origin.y + 26.0)
        let textY3 = format(origin.y + 38.0)
        let textY4 = format(origin.y + 50.0)
        let textY5 = format(origin.y + 62.0)
        let textY6 = format(origin.y + 74.0)

        let valuePathElement = valuePath.isEmpty ? "" : "<path fill=\"none\" stroke=\"#fb8c00\" stroke-opacity=\"0.8\" stroke-width=\"1.0\" d=\"\(valuePath)\"/>"

        let f025 = DefaultParamEvaluator.biasCurveValue(0.25, bias: chart.alphaUsed)
        let f050 = DefaultParamEvaluator.biasCurveValue(0.50, bias: chart.alphaUsed)
        let f075 = DefaultParamEvaluator.biasCurveValue(0.75, bias: chart.alphaUsed)
        let labelF = "f(0.25)=\(String(format: "%.3f", f025)) f(0.5)=\(String(format: "%.3f", f050)) f(0.75)=\(String(format: "%.3f", f075))"
        let labelMid = "dMid=\(String(format: "%.3f", chart.dMid))"
        let sampleUs: [Double] = [0.0, 0.25, 0.5, 0.75, 1.0]
        let sampleValues = sampleUs.map { DefaultParamEvaluator.biasCurveValue($0, bias: chart.alphaUsed) }
        let minValue = sampleValues.min() ?? 0.0
        let maxValue = sampleValues.max() ?? 0.0
        var monotone = true
        let epsilon = 1.0e-9
        for index in 1..<sampleValues.count {
            if sampleValues[index] + epsilon < sampleValues[index - 1] {
                monotone = false
                break
            }
        }
        if minValue < -epsilon || maxValue > 1.0 + epsilon {
            monotone = false
        }
        let labelMonotone = "monotone=\(monotone) u'[min=\(String(format: "%.3f", minValue)) max=\(String(format: "%.3f", maxValue))]"

        let markerUs: [Double] = [0.25, 0.5, 0.75]
        let markerRadius = format(6.0)
        let markerElements = markerUs.map { u -> String in
            let diagX = origin.x + u * chartWidth
            let diagY = origin.y + (1.0 - u) * chartHeight
            let uPrime = DefaultParamEvaluator.biasCurveValue(u, bias: chart.alphaUsed)
            let biasX = diagX
            let biasY = origin.y + (1.0 - uPrime) * chartHeight
            let diagCircle = "<circle cx=\"\(format(diagX))\" cy=\"\(format(diagY))\" r=\"\(markerRadius)\" fill=\"#ffffff\" stroke=\"#333333\" stroke-width=\"1.5\"/>"
            let biasCircle = "<circle cx=\"\(format(biasX))\" cy=\"\(format(biasY))\" r=\"\(markerRadius)\" fill=\"#1565c0\" stroke=\"#ffffff\" stroke-width=\"1.5\"/>"
            return diagCircle + "\n          " + biasCircle
        }.joined(separator: "\n          ")

        return """
        <g id=\"alpha-chart\">
          \(border)
          <path fill=\"none\" stroke=\"#777777\" stroke-opacity=\"0.6\" stroke-width=\"2.0\" stroke-dasharray=\"4 3\" d=\"\(diagPath)\"/>
          <path fill=\"none\" stroke=\"#1565c0\" stroke-opacity=\"0.9\" stroke-width=\"8.0\" d=\"\(biasPath)\"/>
          \(markerElements)
          \(valuePathElement)
          <text x=\"\(textX)\" y=\"\(textY)\" font-size=\"8\" fill=\"#222222\">\(labelAlpha)</text>
          <text x=\"\(textX)\" y=\"\(textY2)\" font-size=\"8\" fill=\"#222222\">\(labelSegment)</text>
          <text x=\"\(textX)\" y=\"\(textY3)\" font-size=\"8\" fill=\"#222222\">\(labelTrack)</text>
          <text x=\"\(textX)\" y=\"\(textY4)\" font-size=\"8\" fill=\"#222222\">\(labelF)</text>
          <text x=\"\(textX)\" y=\"\(textY5)\" font-size=\"8\" fill=\"#222222\">\(labelMid)</text>
          <text x=\"\(textX)\" y=\"\(textY6)\" font-size=\"8\" fill=\"#222222\">\(labelMonotone)</text>
        </g>
        """
    }

    private func refDiffElements(_ overlay: RefDiffOverlay) -> String {
        let matchColor = "#c0c0c0"
        let missingColor = "#2563eb"
        let excessColor = "#dc2626"
        let opacity = "0.55"
        let width = overlay.width
        let height = overlay.height
        let pixelSize = overlay.pixelSize

        var elements: [String] = []
        elements.reserveCapacity(height * 2)
        for y in 0..<height {
            var x = 0
            while x < width {
                let index = y * width + x
                let state = overlay.data[index]
                if state == 0 {
                    x += 1
                    continue
                }
                var end = x + 1
                while end < width && overlay.data[y * width + end] == state {
                    end += 1
                }
                let rectX = overlay.origin.x + Double(x) * pixelSize
                let rectY = overlay.origin.y + Double(y) * pixelSize
                let rectW = Double(end - x) * pixelSize
                let rectH = pixelSize
                let fill: String
                switch state {
                case 1:
                    fill = matchColor
                case 2:
                    fill = missingColor
                case 3:
                    fill = excessColor
                default:
                    fill = matchColor
                }
                elements.append("<rect x=\"\(format(rectX))\" y=\"\(format(rectY))\" width=\"\(format(rectW))\" height=\"\(format(rectH))\" fill=\"\(fill)\" fill-opacity=\"\(opacity)\"/>")
                x = end
            }
        }
        let summary = "diff match=\(overlay.matchCount) missing=\(overlay.missingCount) excess=\(overlay.excessCount)"
        let label = "<text x=\"\(format(overlay.origin.x + 4.0))\" y=\"\(format(overlay.origin.y + 14.0))\" font-size=\"10\" fill=\"#111111\" font-family=\"Menlo, monospace\">\(summary)</text>"
        let body = elements.joined(separator: "\n    ")
        return """
        <g id=\"ref-diff\">
          \(body)
          \(label)
        </g>
        """
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

    func referencePolygons(from background: BackgroundGlyphRender, generatedBounds: CGRect, sampleSteps: Int = 16) -> PolygonSet {
        let global = backgroundTransform(background, generatedBounds: generatedBounds)
        var polygons: PolygonSet = []
        for element in background.elements {
            let combined = global.concatenating(element.transform)
            let rings = flattenPath(d: element.d, transform: combined, steps: sampleSteps)
            for ring in rings where ring.count >= 3 {
                polygons.append(Polygon(outer: ring, holes: []))
            }
        }
        return polygons
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

private func flattenPath(d: String, transform: CGAffineTransform, steps: Int) -> [Ring] {
    var tokenizer = PathTokenizer(d)
    var current = CGPoint.zero
    var start = CGPoint.zero
    var lastControl: CGPoint?
    var command: Character?
    var rings: [Ring] = []
    var currentRing: Ring = []

    func pushPoint(_ point: CGPoint) {
        let transformed = point.applying(transform)
        currentRing.append(Point(x: transformed.x, y: transformed.y))
    }

    func finishRingIfNeeded() {
        if currentRing.count >= 3 {
            rings.append(currentRing)
        }
        currentRing = []
    }

    func sampleCubic(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint) {
        let count = max(2, steps)
        for i in 1...count {
            let t = Double(i) / Double(count)
            let mt = 1.0 - t
            let a = mt * mt * mt
            let b = 3.0 * mt * mt * t
            let c = 3.0 * mt * t * t
            let d = t * t * t
            let x = a * p0.x + b * p1.x + c * p2.x + d * p3.x
            let y = a * p0.y + b * p1.y + c * p2.y + d * p3.y
            pushPoint(CGPoint(x: x, y: y))
        }
        current = p3
        lastControl = p2
    }

    func sampleQuad(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint) {
        let count = max(2, steps)
        for i in 1...count {
            let t = Double(i) / Double(count)
            let mt = 1.0 - t
            let a = mt * mt
            let b = 2.0 * mt * t
            let c = t * t
            let x = a * p0.x + b * p1.x + c * p2.x
            let y = a * p0.y + b * p1.y + c * p2.y
            pushPoint(CGPoint(x: x, y: y))
        }
        current = p2
        lastControl = p1
    }

    while let token = tokenizer.nextToken() {
        switch token {
        case .command(let cmd):
            command = cmd
            if cmd == "Z" || cmd == "z" {
                pushPoint(start)
                finishRingIfNeeded()
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
                finishRingIfNeeded()
                pushPoint(current)
            case "L", "l":
                let isRelative = cmd == "l"
                guard let x = tokenizer.nextNumber(), let y = tokenizer.nextNumber() else { break }
                let point = CGPoint(x: x, y: y)
                let target = isRelative ? CGPoint(x: current.x + point.x, y: current.y + point.y) : point
                pushPoint(target)
                current = target
                lastControl = nil
            case "H", "h":
                let isRelative = cmd == "h"
                guard let x = tokenizer.nextNumber() else { break }
                let targetX = isRelative ? current.x + x : x
                let target = CGPoint(x: targetX, y: current.y)
                pushPoint(target)
                current = target
                lastControl = nil
            case "V", "v":
                let isRelative = cmd == "v"
                guard let y = tokenizer.nextNumber() else { break }
                let targetY = isRelative ? current.y + y : y
                let target = CGPoint(x: current.x, y: targetY)
                pushPoint(target)
                current = target
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
                let reflected = lastControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
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
                let reflected = lastControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                sampleQuad(current, reflected, end)
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
                pushPoint(end)
                current = end
                lastControl = nil
            default:
                break
            }
        }
    }
    finishRingIfNeeded()
    return rings
}

struct SVGDebugOverlay {
    struct RailDebugSample {
        var t: Double
        var point: Point
        var normal: Point
        var supportCase: String? = nil
        var skeletonId: String? = nil
        var runId: Int? = nil
    }
    struct RingSeam {
        var ringIndex: Int
        var side: String
        var dotForward: Double
        var dotReversed: Double
        var chosen: String
    }
    struct RailConnector {
        var side: String
        var railIndexStart: Int
        var points: [Point]
        var length: Double
        var tStart: Double
        var tEnd: Double
    }

    struct RailsSampleOptions {
        var step: Int = 25
        var start: Int = 0
        var count: Int = 200
        var tMin: Double? = nil
        var tMax: Double? = nil
    }

    struct RingSampleOptions {
        var start: Int = 0
        var count: Int = 2000
        var labelStep: Int? = nil
        var labelCount: Int? = nil
    }

    var skeleton: [Point]
    var stamps: [Ring]
    var bridges: [Ring]
    var samplePoints: [Point]
    var keyframeMarkers: [SVGPathBuilder.KeyframeMarker] = []
    var tangentRays: [(Point, Point)]
    var angleRays: [(Point, Point)]
    var offsetRays: [(Point, Point)]
    var offsetCenterline: [Point] = []
    var envelopeLeft: [Point]
    var envelopeRight: [Point]
    var envelopeOutline: Ring
    var capPoints: [Point]
    var leftRailSamples: [RailDebugSample] = []
    var rightRailSamples: [RailDebugSample] = []
    var leftRailRuns: [[Point]] = []
    var rightRailRuns: [[Point]] = []
    var railsRings: [[Point]] = []
    var railJoinSeams: [RingSeam] = []
    var railConnectors: [RailConnector] = []
    var leftRailJumpSamples: [RailDebugSample] = []
    var rightRailJumpSamples: [RailDebugSample] = []
    var showRailsSamples: Bool = false
    var showRailsNormals: Bool = false
    var showRailsIndices: Bool = false
    var showRailsJumps: Bool = false
    var showRailsSupport: Bool = false
    var showRailsRuns: Bool = false
    var showRailsRing: Bool = false
    var showRailsRingSelected: Bool = false
    var showRailsRingConnectors: Bool = false
    var showRailsConnectorsOnly: Bool = false
    var railsSampleOptions: RailsSampleOptions = RailsSampleOptions()
    var ringSampleOptions: RingSampleOptions = RingSampleOptions()
    var railsJumpThreshold: Double = 20.0
    var railsSamplesSource: String = "selected"
    var railsWindowSkeleton: String? = nil
    var railsWindowT0: Double? = nil
    var railsWindowT1: Double? = nil
    var railsWindowGT0: Double? = nil
    var railsWindowGT1: Double? = nil
    var ringWindowT0: Double? = nil
    var ringWindowT1: Double? = nil
    var ringWindowGT0: Double? = nil
    var ringWindowGT1: Double? = nil
    var railsWindowRect: CGRect? = nil
    var assertRailsWindow: Bool = false
    var assertRingWindow: Bool = false
    var ringWindowExtrema: String? = nil
    var ringWindowRadius: Double? = nil
    var assertRingWindowHitsExtrema: Bool = false
    var junctionPatches: [Ring]
    var junctionCorridors: [Ring]
    var junctionControlPoints: [Point]
    var showUnionOutline: Bool
    var unionPolygons: PolygonSet?
    var alphaChart: SVGPathBuilder.AlphaDebugChart?
    var refDiff: SVGPathBuilder.RefDiffOverlay? = nil
}
