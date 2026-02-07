import CP2Domain
import CP2Geometry

struct SVGRenderer {
    static func render(model: RenderGlyphModel, options: CLIOptions, warn: (String) -> Void) -> String {
        let renderSettings = model.renderSettings
        let referenceLayer = model.referenceLayer
        let referenceSVG = model.referenceSVGInner

        let viewMinX = model.frame.minX
        let viewMinY = model.frame.minY
        let viewWidth = model.frame.width
        let viewHeight = model.frame.height

        let strokeInkContent: String = {
            if model.strokeEntries.isEmpty { return "" }

            let counterGroups: [(key: String, appliesTo: [String]?, counters: [[Vec2]])] = {
                guard !model.counterRingsNormalized.isEmpty else { return [] }
                var map: [String: (appliesTo: [String]?, rings: [[Vec2]])] = [:]
                for item in model.counterRingsNormalized {
                    let appliesTo = item.appliesTo?.sorted()
                    let key = appliesTo?.joined(separator: "|") ?? "*"
                    if var existing = map[key] {
                        existing.rings.append(item.ring)
                        map[key] = existing
                    } else {
                        map[key] = (appliesTo, [item.ring])
                    }
                }
                return map.keys.sorted().compactMap { key in
                    guard let value = map[key] else { return nil }
                    return (key, value.appliesTo, value.rings)
                }
            }()

            var usedStrokeIndices: Set<Int> = []
            var parts: [String] = []
            var groupIndex = 0

            func emitCompound(
                inkRings: [[Vec2]],
                counterRings: [[Vec2]],
                idSuffix: String
            ) {
                let inkPathData = inkRings
                    .map { svgPath(for: $0) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                let counterPathData = counterRings
                    .map { svgPath(for: $0) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")

                if options.clipCountersToInk, !inkPathData.isEmpty, !counterPathData.isEmpty {
                    let inkId = idSuffix.isEmpty ? "ink-shape" : "ink-shape-\(idSuffix)"
                    let clipId = idSuffix.isEmpty ? "clip-ink" : "clip-ink-\(idSuffix)"
                    let counterId = idSuffix.isEmpty ? "counter-shape" : "counter-shape-\(idSuffix)"
                    parts.append("""
    <path id="\(inkId)" d="\(inkPathData)" fill="black" stroke="none" fill-rule="nonzero" />
    <defs>
      <clipPath id="\(clipId)">
        <use href="#\(inkId)" />
      </clipPath>
    </defs>
    <path id="\(counterId)" d="\(counterPathData)" fill="white" stroke="none" clip-path="url(#\(clipId))" />
""")
                    return
                }

                let compoundRings = inkRings + counterRings
                let compoundPathData = compoundRings
                    .map { svgPath(for: $0) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                if compoundPathData.isEmpty { return }
                let idToken = idSuffix.isEmpty ? "ink-compound" : "ink-compound-\(idSuffix)"
                parts.append("    <path id=\"\(idToken)\" d=\"\(compoundPathData)\" fill=\"black\" stroke=\"none\" fill-rule=\"nonzero\" />")
            }

            if model.counterRingsNormalized.isEmpty {
                emitCompound(inkRings: model.strokeEntries.map { $0.ring }, counterRings: [], idSuffix: "")
                return parts.joined(separator: "\n")
            }

            for group in counterGroups {
                let targetIds = group.appliesTo
                var groupStrokeIndices: [Int] = []
                if let targetIds {
                    let set = Set(targetIds)
                    groupStrokeIndices = model.strokeEntries.filter { entry in
                        if let id = entry.strokeId { return set.contains(id) }
                        return false
                    }.map { $0.index }
                    let missing = targetIds.filter { id in !model.strokeEntries.contains(where: { $0.strokeId == id }) }
                    if !missing.isEmpty {
                        warn("counter appliesTo missing stroke ids: \(missing.joined(separator: ", "))")
                    }
                } else {
                    groupStrokeIndices = model.strokeEntries.map { $0.index }
                }

                let freshIndices = groupStrokeIndices.filter { !usedStrokeIndices.contains($0) }
                if freshIndices.count != groupStrokeIndices.count {
                    warn("counter appliesTo overlaps previously scoped strokes; rendering first occurrence only")
                }
                if freshIndices.isEmpty { continue }
                for index in freshIndices { usedStrokeIndices.insert(index) }

                let groupInkRings = model.strokeEntries.filter { freshIndices.contains($0.index) }.map { $0.ring }
                emitCompound(
                    inkRings: groupInkRings,
                    counterRings: group.counters,
                    idSuffix: groupIndex == 0 ? "" : "g\(groupIndex)"
                )
                groupIndex += 1
            }

            let remaining = model.strokeEntries.filter { !usedStrokeIndices.contains($0.index) }
            for entry in remaining {
                let rawId = entry.strokeId ?? entry.inkName ?? "stroke-\(entry.index)"
                let idToken = rawId.replacingOccurrences(of: " ", with: "-")
                let pathData = svgPath(for: entry.ring)
                parts.append("    <path id=\"stroke-ink-\(idToken)\" d=\"\(pathData)\" fill=\"black\" stroke=\"none\" data-stroke-id=\"\(rawId)\" />")
            }

            return parts.joined(separator: "\n")
        }()
        let clipId = "frameClip"
        let clipPath = renderSettings.clipToFrame ? """
  <clipPath id="\(clipId)">
    <rect x="\(String(format: "%.4f", viewMinX))" y="\(String(format: "%.4f", viewMinY))" width="\(String(format: "%.4f", viewWidth))" height="\(String(format: "%.4f", viewHeight))" />
  </clipPath>
""" : ""

        let referenceFillGroup: String = {
            guard let layer = referenceLayer, let referenceSVG = referenceSVG else { return "" }
            let transform = svgTransformString(referenceTransformMatrix(layer))
            return """
  <g id="reference-fill" opacity="\(String(format: "%.4f", layer.opacity))" transform="\(transform)">
\(referenceSVG)
  </g>
"""
        }()
        let referenceOutlineGroup: String = {
            guard (options.debugCompare || options.debugCompareAll),
                  referenceLayer != nil,
                  let referenceSVG = referenceSVG else { return "" }
            let transform = svgTransformString(referenceTransformMatrix(referenceLayer!))
            return """
  <g id="reference-outline" transform="\(transform)" style="fill:none;stroke:#ff66cc;stroke-width:1;vector-effect:non-scaling-stroke">
\(referenceSVG)
  </g>
"""
        }()

        let debugSVG = model.debugOverlaySVG
        let glyphGroup = options.viewCenterlineOnly ? "" : (renderSettings.clipToFrame ? """
  <g id="glyph" clip-path="url(#\(clipId))">
    <g id="stroke-ink">
\(strokeInkContent)
    </g>
  </g>
""" : """
  <g id="stroke-ink">
\(strokeInkContent)
  </g>
""")
        let debugGroup = renderSettings.clipToFrame ? """
  <g id="debug-overlays" clip-path="url(#\(clipId))">
\(debugSVG)
  </g>
""" : """
  <g id="debug-overlays">
\(debugSVG)
  </g>
"""

        let viewTokens: [String] = {
            var tokens: [String] = []
            if options.debugCompareAll {
                tokens.append("compareAll")
            } else if options.debugCompare {
                tokens.append("compare")
            }
            if options.debugRingSpine { tokens.append("ringSpine") }
            if options.debugRingJump { tokens.append("ringJump") }
            if options.debugSamplingWhy { tokens.append("samplingWhy") }
            if options.debugCenterline { tokens.append("centerline") }
            if options.debugInkControls { tokens.append("inkControls") }
            if options.debugSVG { tokens.append("debugSVG") }
            if options.debugSoloWhy { tokens.append("soloWhy") }
            if options.debugCounters { tokens.append("counters") }
            return tokens
        }()
        let viewLabel = viewTokens.isEmpty ? "none" : viewTokens.joined(separator: ",")
        let exampleLabel = model.exampleName ?? "none"
        let infoLabel = options.viewCenterlineOnly ? "" : """
  <text x="20" y="20" font-size="14" fill="#111">example=\(exampleLabel) view=\(viewLabel) solo=\(options.debugSoloWhy)</text>
"""
        let legendLabel: String = {
            if options.viewCenterlineOnly { return "" }
            let wantsLegend = options.debugCompare || options.debugCompareAll || options.debugSVG || options.debugCenterline || options.debugInkControls || options.debugRingSpine || options.debugRingJump || options.debugSamplingWhy || options.debugCounters
            guard wantsLegend else { return "" }
            var lines: [(String, String)] = []
            if referenceLayer != nil {
                lines.append(("reference fill", "#111"))
                lines.append(("reference outline", "#ff66cc"))
            }
            lines.append(("ink fill", "#111"))
            if options.debugCenterline { lines.append(("centerline", "orange")) }
            if options.debugInkControls { lines.append(("ink controls", "gray")) }
            if options.debugRingSpine { lines.append(("ring spine", "#00c853")) }
            if options.debugRingJump { lines.append(("ring jump", "#ff1744")) }
            if options.debugCounters { lines.append(("counter paths", "#d81b60")) }
            if options.debugSamplingWhy {
                lines.append(("why: flatness", "red"))
                lines.append(("why: rail deviation", "blue"))
                lines.append(("why: both", "purple"))
                lines.append(("why: forced stop", "gray"))
            }
            var y = 40
            var text = "  <g id=\"debug-legend\">"
            for (label, color) in lines {
                text += "\n    <text x=\"20\" y=\"\(y)\" font-size=\"12\" fill=\"\(color)\">\(label)</text>"
                y += 16
            }
            text += "\n  </g>"
            return text
        }()

        return """
<svg xmlns="http://www.w3.org/2000/svg" width="\(renderSettings.canvasPx.width)" height="\(renderSettings.canvasPx.height)" viewBox="\(String(format: "%.4f", viewMinX)) \(String(format: "%.4f", viewMinY)) \(String(format: "%.4f", viewWidth)) \(String(format: "%.4f", viewHeight))">
\(clipPath)
\(referenceFillGroup)
\(glyphGroup)
\(referenceOutlineGroup)
\(debugGroup)
\(infoLabel)
\(legendLabel)
</svg>
"""
    }
}
