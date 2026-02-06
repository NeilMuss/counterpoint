import Foundation
import CP2Geometry
import CP2Skeleton

struct StoryboardRenderer {
    static func renderCels(
        context: StoryContext,
        stages: [StoryStage],
        contextMode: StoryboardContextMode
    ) -> [StoryboardCel] {
        let ordered = stages.sorted { $0.stageNumber < $1.stageNumber }
        return ordered.map { stage in
            let svg = renderCel(context: context, stage: stage, contextMode: contextMode)
            return StoryboardCel(stage: stage, svg: svg)
        }
    }

    static func writeCels(cels: [StoryboardCel], outDir: URL) throws {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        for cel in cels {
            let outPath = outDir.appendingPathComponent(cel.stage.filename)
            guard let data = cel.svg.data(using: .utf8) else {
                throw NSError(domain: "cp2-cli.storyboard", code: 1, userInfo: [NSLocalizedDescriptionKey: "failed to encode svg for \(cel.stage.filename)"])
            }
            try data.write(to: outPath, options: .atomic)
        }
    }

    private static func renderCel(
        context: StoryContext,
        stage: StoryStage,
        contextMode: StoryboardContextMode
    ) -> String {
        let viewMinX = context.frame.minX
        let viewMinY = context.frame.minY
        let viewWidth = context.frame.width
        let viewHeight = context.frame.height
        let size = context.canvas

        let contextStages = stagesForContext(mode: contextMode, focus: stage)
        let contextGroup = renderContextGroup(stages: contextStages, context: context)
        let focusGroup = renderFocusGroup(stage: stage, context: context)

        return """
<svg xmlns="http://www.w3.org/2000/svg" width="\(size.width)" height="\(size.height)" viewBox="\(String(format: "%.4f", viewMinX)) \(String(format: "%.4f", viewMinY)) \(String(format: "%.4f", viewWidth)) \(String(format: "%.4f", viewHeight))">
  <g id="cel-\(stage.rawValue)">
    \(contextGroup)
    \(focusGroup)
  </g>
</svg>
"""
    }

    private static func stagesForContext(mode: StoryboardContextMode, focus: StoryStage) -> [StoryStage] {
        switch mode {
        case .none:
            return []
        case .prev:
            return Array(StoryStage.defaultOrder.prefix { $0 != focus })
        case .all:
            return StoryStage.defaultOrder.filter { $0 != focus }
        }
    }

    private static func renderContextGroup(stages: [StoryStage], context: StoryContext) -> String {
        guard !stages.isEmpty else { return "<g id=\"context\"></g>" }
        let parts = stages.map { stage in
            renderStage(stage: stage, context: context, groupId: "context-\(stage.rawValue)")
        }
        return """
    <g id="context" opacity="0.15" stroke-opacity="0.15" fill-opacity="0.10">
      \(parts.joined(separator: "\n      "))
    </g>
"""
    }

    private static func renderFocusGroup(stage: StoryStage, context: StoryContext) -> String {
        let groupId = stage == .final ? "final-silhouette" : "debug-\(stage.rawValue)"
        let content = renderStage(stage: stage, context: context, groupId: groupId)
        return """
    <g id="focus">
      \(content)
    </g>
"""
    }

    private static func renderStage(stage: StoryStage, context: StoryContext, groupId: String) -> String {
        if let reason = placeholderReason(stage: stage, context: context) {
            return """
  <g id="\(groupId)">
    \(placeholderContent(stage: stage, reason: reason))
  </g>
"""
        }
        switch stage {
        case .skeleton:
            return skeletonGroup(context: context, groupId: groupId)
        case .keyframes:
            return keyframesGroup(context: context, groupId: groupId)
        case .counterpoint:
            return counterpointGroup(context: context, groupId: groupId)
        case .samples:
            return samplesGroup(context: context, groupId: groupId)
        case .rails:
            return railsGroup(context: context, groupId: groupId)
        case .soup:
            return soupGroup(context: context, groupId: groupId)
        case .ring:
            return ringGroup(context: context, groupId: groupId)
        case .resolve:
            return resolveGroup(context: context, groupId: groupId)
        case .final:
            return finalGroup(context: context, groupId: groupId)
        }
    }

    private static func skeletonPathData(path: SkeletonPath) -> String {
        var parts: [String] = []
        var lastEnd: Vec2? = nil
        for (index, seg) in path.segments.enumerated() {
            let start = seg.p0
            if index == 0 || (lastEnd != nil && !Epsilon.approxEqual(lastEnd!, start)) {
                parts.append(String(format: "M %.4f %.4f", start.x, start.y))
            }
            parts.append(String(format: "C %.4f %.4f %.4f %.4f %.4f %.4f", seg.p1.x, seg.p1.y, seg.p2.x, seg.p2.y, seg.p3.x, seg.p3.y))
            lastEnd = seg.p3
        }
        return parts.joined(separator: " ")
    }

    private static func skeletonGroup(context: StoryContext, groupId: String) -> String {
        let pathData = skeletonPathData(path: context.path)
        return """
  <g id="\(groupId)">
    <path d="\(pathData)" fill="none" stroke="#111111" stroke-width="1.6" />
  </g>
"""
    }

    private static func keyframesGroup(context: StoryContext, groupId: String) -> String {
        let pathData = skeletonPathData(path: context.path)
        let skeleton = "<path d=\"\(pathData)\" fill=\"none\" stroke=\"#999999\" stroke-width=\"0.8\" />"
        let overlay: String = {
            if let params = context.params, let plan = context.plan {
                let raw = makeKeyframesOverlay(params: params, pathParam: context.pathParam, plan: plan, labels: true).svg
                return raw.replacingOccurrences(of: "id=\"debug-keyframes\"", with: "id=\"\(groupId)-markers\"")
            }
            let endpoints = [context.path.segments.first!.p0, context.path.segments.last!.p3]
            let dots = endpoints.map { p in
                String(format: "<circle cx=\"%.4f\" cy=\"%.4f\" r=\"3.0\" fill=\"#1976d2\" stroke=\"none\" />", p.x, p.y)
            }.joined(separator: "\n    ")
            return """
  <g id="\(groupId)-markers">
    \(dots)
  </g>
"""
        }()

        return """
  <g id="\(groupId)">
    \(skeleton)
    \(overlay)
  </g>
"""
    }

    private static func counterpointGroup(context: StoryContext, groupId: String) -> String {
        let pathData = skeletonPathData(path: context.path)
        let skeleton = "<path d=\"\(pathData)\" fill=\"none\" stroke=\"#999999\" stroke-width=\"0.6\" />"
        let overlay: String = {
            guard let plan = context.plan else { return "" }
            let ts = context.sampling?.ts ?? []
            let useTs = ts.isEmpty ? stride(from: 0, through: 1.0, by: 0.05).map { $0 } : ts
            let strideCount = max(1, useTs.count / 20)
            var ticks: [String] = []
            for (i, gt) in useTs.enumerated() {
                if i % strideCount != 0 { continue }
                let frame = railSampleFrameAtGlobalT(
                    param: context.pathParam,
                    warpGT: plan.warpT,
                    styleAtGT: { t in
                        SweepStyle(
                            width: plan.scaledWidthAtT(t),
                            widthLeft: plan.scaledWidthLeftAtT(t),
                            widthRight: plan.scaledWidthRightAtT(t),
                            height: plan.sweepHeight,
                            angle: plan.thetaAtT(t),
                            offset: plan.offsetAtT(t),
                            angleIsRelative: plan.angleMode == .relative
                        )
                    },
                    gt: gt,
                    index: i
                )
                let end = frame.center + frame.crossAxis.normalized() * 8.0
                ticks.append(String(format: "<line x1=\"%.4f\" y1=\"%.4f\" x2=\"%.4f\" y2=\"%.4f\" stroke=\"#ff6f00\" stroke-width=\"0.8\"/>", frame.center.x, frame.center.y, end.x, end.y))
            }
            let svg = """
  <g id="\(groupId)">
    <g id="debug-cross-axis">
      \(ticks.joined(separator: "\n      "))
    </g>
  </g>
"""
            return svg
        }()
        return """
  <g id="\(groupId)">
    \(skeleton)
    \(overlay)
  </g>
"""
    }

    private static func samplesGroup(context: StoryContext, groupId: String) -> String {
        let pathData = skeletonPathData(path: context.path)
        let skeleton = "<path d=\"\(pathData)\" fill=\"none\" stroke=\"#999999\" stroke-width=\"0.6\" />"
        let ts = context.sampling?.ts ?? [0.0, 1.0]
        let labelEvery = max(1, ts.count / 10)
        var dots: [String] = []
        var labels: [String] = []
        dots.reserveCapacity(ts.count)
        labels.reserveCapacity(ts.count / labelEvery + 1)
        for (index, t) in ts.enumerated() {
            let p = context.pathParam.position(globalT: t)
            dots.append(String(format: "<circle cx=\"%.4f\" cy=\"%.4f\" r=\"1.6\" fill=\"#000000\" stroke=\"none\" />", p.x, p.y))
            if index % labelEvery == 0 {
                labels.append(String(format: "<text x=\"%.4f\" y=\"%.4f\" font-size=\"8\" fill=\"#111111\">%d</text>", p.x + 3.0, p.y - 3.0, index))
            }
        }
        let overlay = """
  <g id="\(groupId)">
    \(dots.joined(separator: "\n    "))
    \(labels.joined(separator: "\n    "))
  </g>
"""
        return """
  <g id="\(groupId)">
    \(skeleton)
    \(overlay)
  </g>
"""
    }

    private static func finalGroup(context: StoryContext, groupId: String) -> String {
        let pathData = svgPath(for: context.ring)
        return """
  <g id="\(groupId)">
    <path d="\(pathData)" fill="black" stroke="none" fill-rule="nonzero" />
  </g>
"""
    }

    private static func railsGroup(context: StoryContext, groupId: String) -> String {
        guard let left = context.railsLeft, let right = context.railsRight else { return "" }
        func path(_ points: [Vec2]) -> String {
            guard let first = points.first else { return "" }
            var parts: [String] = [String(format: "M %.4f %.4f", first.x, first.y)]
            for p in points.dropFirst() {
                parts.append(String(format: "L %.4f %.4f", p.x, p.y))
            }
            return parts.joined(separator: " ")
        }
        let leftPath = path(left)
        let rightPath = path(right)
        let step = max(1, left.count / 20)
        var connectors: [String] = []
        for i in stride(from: 0, to: min(left.count, right.count), by: step) {
            let a = left[i]
            let b = right[i]
            connectors.append(String(format: "<line x1=\"%.4f\" y1=\"%.4f\" x2=\"%.4f\" y2=\"%.4f\" stroke=\"#00796b\" stroke-width=\"0.6\"/>", a.x, a.y, b.x, b.y))
        }
        return """
  <g id="\(groupId)">
    <path d="\(leftPath)" fill="none" stroke="#d32f2f" stroke-width="0.8" />
    <path d="\(rightPath)" fill="none" stroke="#1976d2" stroke-width="0.8" />
    \(connectors.joined(separator: "\n    "))
  </g>
"""
    }

    private static func soupGroup(context: StoryContext, groupId: String) -> String {
        guard let chains = context.soupChains, !chains.isEmpty else { return "" }
        var parts: [String] = []
        for (idx, chain) in chains.enumerated() {
            guard let first = chain.first else { continue }
            var path = [String(format: "M %.4f %.4f", first.x, first.y)]
            for p in chain.dropFirst() {
                path.append(String(format: "L %.4f %.4f", p.x, p.y))
            }
            let color = idx % 2 == 0 ? "#5c6bc0" : "#26a69a"
            parts.append("<path d=\"\(path.joined(separator: " "))\" fill=\"none\" stroke=\"\(color)\" stroke-width=\"0.6\" />")
        }
        return """
  <g id="\(groupId)">
    \(parts.joined(separator: "\n    "))
  </g>
"""
    }

    private static func ringGroup(context: StoryContext, groupId: String) -> String {
        guard let rings = context.rings, let ring = rings.first else { return "" }
        let pathData = svgPath(for: ring)
        var dots: [String] = []
        let stride = max(1, ring.count / 25)
        for (i, p) in ring.enumerated() {
            if i % stride != 0 { continue }
            dots.append(String(format: "<circle cx=\"%.4f\" cy=\"%.4f\" r=\"1.6\" fill=\"#000000\" stroke=\"none\"/>", p.x, p.y))
            dots.append(String(format: "<text x=\"%.4f\" y=\"%.4f\" font-size=\"7\" fill=\"#111111\">%d</text>", p.x + 2.0, p.y - 2.0, i))
        }
        return """
  <g id="\(groupId)">
    <path d="\(pathData)" fill="none" stroke="#000000" stroke-width="0.7" />
    \(dots.joined(separator: "\n    "))
  </g>
"""
    }

    private static func resolveGroup(context: StoryContext, groupId: String) -> String {
        guard let before = context.resolveBefore, let after = context.resolveAfter else { return "" }
        let beforePath = svgPath(for: before)
        let afterPath = svgPath(for: after)
        var points: [String] = []
        if let intersections = context.resolveIntersections, !intersections.isEmpty {
            for p in intersections {
                points.append(String(format: "<circle cx=\"%.4f\" cy=\"%.4f\" r=\"2.0\" fill=\"#d32f2f\" stroke=\"none\"/>", p.x, p.y))
            }
        }
        return """
  <g id="\(groupId)">
    <path d="\(beforePath)" fill="none" stroke=\"#9e9e9e\" stroke-width=\"0.6\" />
    <path d="\(afterPath)" fill="none" stroke=\"#000000\" stroke-width=\"1.0\" />
    \(points.joined(separator: "\n    "))
  </g>
"""
    }

    private static func placeholderContent(stage: StoryStage, reason: String) -> String {
        let label = "STAGE NOT AVAILABLE: \(stage.rawValue)"
        return """
  <g id="placeholder-\(stage.rawValue)">
    <text x=\"50%\" y=\"50%\" text-anchor=\"middle\" font-size=\"20\" fill=\"#b71c1c\">\(label)</text>
    <text x=\"50%\" y=\"50%\" text-anchor=\"middle\" font-size=\"12\" fill=\"#b71c1c\" dy=\"16\">\(reason)</text>
  </g>
"""
    }

    static func placeholderReason(stage: StoryStage, context: StoryContext) -> String? {
        switch stage {
        case .skeleton, .keyframes, .samples, .final:
            return nil
        case .counterpoint:
            return context.plan == nil ? "No SweepPlan in context" : nil
        case .rails:
            return context.railsLeft == nil || context.railsRight == nil ? "No rails in context" : nil
        case .soup:
            return context.soupChains == nil ? "No soup chains in context" : nil
        case .ring:
            return context.rings == nil ? "No rings in context" : nil
        case .resolve:
            return context.resolveAfter == nil ? "No resolve artifacts/debug" : nil
        }
    }
}
