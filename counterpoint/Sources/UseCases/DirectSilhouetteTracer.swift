import Foundation
import Domain

public struct DirectSilhouetteResult: Equatable {
    public let outline: Ring
    public let leftRail: [Point]
    public let rightRail: [Point]
    public let endCap: [Point]
    public let startCap: [Point]
    public let junctionPatches: [Ring]
    public let junctionControlPoints: [Point]
    public let junctionDiagnostics: [DirectSilhouetteTracer.JunctionDiagnostic]
    public let junctionCorridors: [Ring]
    public let capPoints: [Point]
}

public struct DirectSilhouetteOptions: Equatable {
    public var enableCornerRefine: Bool
    public var cornerRefineMaxDepth: Int
    public var cornerRefineMinStep: Double
    public var cornerRefineEpsilon: Double
    public var enableRailRefine: Bool
    public var railRefineMaxDepth: Int
    public var railRefineMinStep: Double

    public init(
        enableCornerRefine: Bool = true,
        cornerRefineMaxDepth: Int = 8,
        cornerRefineMinStep: Double = 1.0e-4,
        cornerRefineEpsilon: Double = 1.0e-9,
        enableRailRefine: Bool = true,
        railRefineMaxDepth: Int = 8,
        railRefineMinStep: Double = 1.0e-4
    ) {
        self.enableCornerRefine = enableCornerRefine
        self.cornerRefineMaxDepth = cornerRefineMaxDepth
        self.cornerRefineMinStep = cornerRefineMinStep
        self.cornerRefineEpsilon = cornerRefineEpsilon
        self.enableRailRefine = enableRailRefine
        self.railRefineMaxDepth = railRefineMaxDepth
        self.railRefineMinStep = railRefineMinStep
    }

    public static let `default` = DirectSilhouetteOptions()
}

public struct DirectSilhouetteTraceWindow: Equatable {
    public let tMin: Double
    public let tMax: Double
    public let label: String?

    public init(tMin: Double, tMax: Double, label: String? = nil) {
        self.tMin = min(tMin, tMax)
        self.tMax = max(tMin, tMax)
        self.label = label
    }

    public func contains(_ t: Double) -> Bool {
        t >= tMin && t <= tMax
    }

    public func intersects(_ a: Double, _ b: Double) -> Bool {
        max(min(a, b), tMin) <= min(max(a, b), tMax)
    }
}

public enum DirectSilhouetteTracer {
    public typealias DirectSilhouetteParamProvider = (_ t: Double, _ tangentAngle: Double) -> (width: Double, height: Double, theta: Double, effectiveRotation: Double, alpha: Double)
    public struct JunctionContext: Equatable {
        public let joinIndex: Int
        public let prev: Sample?
        public let a: Sample
        public let b: Sample
        public let next: Sample?

        public init(joinIndex: Int, prev: Sample?, a: Sample, b: Sample, next: Sample?) {
            self.joinIndex = joinIndex
            self.prev = prev
            self.a = a
            self.b = b
            self.next = next
        }
    }

    public struct JunctionDiagnostic: Equatable {
        public let joinIndex: Int
        public let tA: Double
        public let tB: Double
        public let usedBridge: Bool
        public let reason: String
        public let clipped: Bool
        public let clipReason: String
    }

    public static func trace(
        samples: [Sample],
        junctions: [JunctionContext] = [],
        capStyle: CapStyle = .butt,
        railTolerance: Double = 0.0,
        options: DirectSilhouetteOptions = .default,
        paramsProvider: DirectSilhouetteParamProvider? = nil,
        traceWindow: DirectSilhouetteTraceWindow? = nil,
        verbose: Bool = false,
        epsilon: Double = 1.0e-9
    ) -> DirectSilhouetteResult {
        guard samples.count >= 2 else {
            return DirectSilhouetteResult(outline: [], leftRail: [], rightRail: [], endCap: [], startCap: [], junctionPatches: [], junctionControlPoints: [], junctionDiagnostics: [], junctionCorridors: [], capPoints: [])
        }

        if let window = traceWindow {
            print("direct-trace window t=[\(format(window.tMin))..\((format(window.tMax)))] label=\(window.label ?? "none") samples=\(samples.count)")
        }

        let refinedSamples = refineSamples(
            samples: samples,
            options: options,
            railTolerance: railTolerance,
            paramsProvider: paramsProvider,
            traceWindow: traceWindow,
            epsilon: epsilon
        )

        var leftRail: [Point] = []
        var rightRail: [Point] = []
        var windowLeft: [Point] = []
        var windowRight: [Point] = []
        leftRail.reserveCapacity(refinedSamples.count)
        rightRail.reserveCapacity(refinedSamples.count)

        for sample in refinedSamples {
            let tangent = Point(x: cos(sample.tangentAngle), y: sin(sample.tangentAngle))
            let normal = tangent.leftNormal()
            let leftOffset = supportOffset(direction: normal, width: sample.width, height: sample.height, thetaWorld: sample.effectiveRotation, epsilon: epsilon)
            let rightOffset = supportOffset(direction: normal * -1.0, width: sample.width, height: sample.height, thetaWorld: sample.effectiveRotation, epsilon: epsilon)
            leftRail.append(sample.point + leftOffset)
            rightRail.append(sample.point + rightOffset)
            if let window = traceWindow, window.contains(sample.t) {
                let leftPoint = sample.point + leftOffset
                let rightPoint = sample.point + rightOffset
                windowLeft.append(leftPoint)
                windowRight.append(rightPoint)
                print("direct-sample t=\(format(sample.t)) center=(\(format(sample.point.x)),\(format(sample.point.y))) width=\(format(sample.width)) height=\(format(sample.height)) theta=\(format(sample.theta)) effRot=\(format(sample.effectiveRotation))")
                print("direct-rail t=\(format(sample.t)) left=(\(format(leftPoint.x)),\(format(leftPoint.y))) right=(\(format(rightPoint.x)),\(format(rightPoint.y)))")
            }
        }

        if traceWindow != nil {
            print("direct-rail cleanup left pre=\(leftRail.count) right pre=\(rightRail.count)")
        }
        let leftDedup = removeConsecutiveDuplicates(leftRail, tol: epsilon)
        let rightDedup = removeConsecutiveDuplicates(rightRail, tol: epsilon)
        let leftAfter = removeTinyEdges(leftDedup, epsilon: epsilon)
        let rightAfter = removeTinyEdges(rightDedup, epsilon: epsilon)
        if traceWindow != nil {
            let leftDupRemoved = leftRail.count - leftDedup.count
            let rightDupRemoved = rightRail.count - rightDedup.count
            let leftTinyRemoved = leftDedup.count - leftAfter.count
            let rightTinyRemoved = rightDedup.count - rightAfter.count
            print("direct-rail postprocess removedDup left=\(leftDupRemoved) right=\(rightDupRemoved) removedTiny left=\(leftTinyRemoved) right=\(rightTinyRemoved)")
        }
        leftRail = leftAfter
        rightRail = rightAfter
        if traceWindow != nil {
            print("direct-rail cleanup left post=\(leftRail.count) right post=\(rightRail.count)")
            if !windowLeft.isEmpty || !windowRight.isEmpty {
                let leftMissing = missingPointCount(points: windowLeft, within: leftRail, epsilon: epsilon)
                let rightMissing = missingPointCount(points: windowRight, within: rightRail, epsilon: epsilon)
                print("direct-rail windowMissing left=\(leftMissing) right=\(rightMissing)")
            }
        }

        let startSample = refinedSamples.first!
        let endSample = refinedSamples.last!
        let startTangent = Point(x: cos(startSample.tangentAngle), y: sin(startSample.tangentAngle))
        let endTangent = Point(x: cos(endSample.tangentAngle), y: sin(endSample.tangentAngle))

        let capTolerance = max(railTolerance, epsilon)
        var capPoints: [Point] = []

        let endCap: [Point]
        let startCap: [Point]
        switch capStyle {
        case .round:
            let endArc = roundCapArc(
                center: endSample.point,
                from: leftRail.last!,
                to: rightRail.last!,
                faceDir: endTangent,
                tolerance: capTolerance,
                maxDepth: max(6, options.railRefineMaxDepth),
                epsilon: epsilon
            )
            let startArc = roundCapArc(
                center: startSample.point,
                from: rightRail.first!,
                to: leftRail.first!,
                faceDir: startTangent * -1.0,
                tolerance: capTolerance,
                maxDepth: max(6, options.railRefineMaxDepth),
                epsilon: epsilon
            )
            capPoints.append(contentsOf: endArc)
            capPoints.append(contentsOf: startArc)
            endCap = trimArcPoints(endArc)
            startCap = trimArcPoints(startArc)
        default:
            let startCorners = rectangleCornersWorld(
                center: startSample.point,
                width: startSample.width,
                height: startSample.height,
                thetaWorld: startSample.effectiveRotation
            )
            let endCorners = rectangleCornersWorld(
                center: endSample.point,
                width: endSample.width,
                height: endSample.height,
                thetaWorld: endSample.effectiveRotation
            )
            endCap = endCapPoints(
                corners: endCorners,
                center: endSample.point,
                faceDir: endTangent,
                from: leftRail.last!,
                to: rightRail.last!,
                epsilon: epsilon
            )
            startCap = endCapPoints(
                corners: startCorners,
                center: startSample.point,
                faceDir: startTangent * -1.0,
                from: rightRail.first!,
                to: leftRail.first!,
                epsilon: epsilon
            )
            capPoints.append(contentsOf: endCap)
            capPoints.append(contentsOf: startCap)
        }

        var outline = leftRail
        outline.append(contentsOf: endCap)
        outline.append(contentsOf: rightRail.reversed())
        outline.append(contentsOf: startCap)
        if traceWindow != nil {
            print("direct-outline pre-clean count=\(outline.count) capPoints=\(capPoints.count)")
        }
        let outlineDedup = removeConsecutiveDuplicates(outline, tol: epsilon)
        let outlineAfter = removeTinyEdges(outlineDedup, epsilon: epsilon)
        if traceWindow != nil {
            let removedDup = outline.count - outlineDedup.count
            let removedTiny = outlineDedup.count - outlineAfter.count
            print("direct-outline postprocess removedDup=\(removedDup) removedTiny=\(removedTiny)")
            print("direct-postprocess note=removeConsecutiveDuplicates+removeTinyEdges")
            print("direct-outline post-clean count=\(outlineAfter.count)")
            if !windowLeft.isEmpty || !windowRight.isEmpty {
                for (index, point) in windowLeft.enumerated() {
                    let present = containsPoint(outlineAfter, point, epsilon: epsilon)
                    print("direct-outline window-left idx=\(index) present=\(present) point=(\(format(point.x)),\(format(point.y)))")
                }
                for (index, point) in windowRight.enumerated() {
                    let present = containsPoint(outlineAfter, point, epsilon: epsilon)
                    print("direct-outline window-right idx=\(index) present=\(present) point=(\(format(point.x)),\(format(point.y)))")
                }
            }
        }
        outline = outlineAfter
        outline = closeRingIfNeeded(outline, tol: epsilon)

        var patches: [Ring] = []
        var junctionControlPoints: [Point] = []
        var junctionDiagnostics: [JunctionDiagnostic] = []
        var junctionCorridors: [Ring] = []
        patches.reserveCapacity(junctions.count)
        junctionDiagnostics.reserveCapacity(junctions.count)
        for junction in junctions {
            guard let patch = junctionPatch(from: junction, epsilon: epsilon, verbose: verbose) else { continue }
            var finalRing = patch.ring
            var diagnostic = patch.diagnostic
            var corridorRing: Ring? = nil
            if let corridor = buildJunctionCorridor(
                samples: refinedSamples,
                leftRail: leftRail,
                rightRail: rightRail,
                context: junction,
                window: 8,
                epsilon: epsilon
            ) {
                corridorRing = corridor
                junctionCorridors.append(corridor)
            }
            if let corridor = corridorRing {
                let clip = clipJunctionPatch(
                    ring: finalRing,
                    corridor: corridor,
                    context: junction,
                    epsilon: epsilon,
                    verbose: verbose
                )
                if let clipped = clip.ring {
                    finalRing = clipped
                }
                if verbose {
                    print("junction-clip joinIndex=\(junction.joinIndex) applied=\(clip.applied) reason=\(clip.reason)")
                }
                diagnostic = JunctionDiagnostic(
                    joinIndex: diagnostic.joinIndex,
                    tA: diagnostic.tA,
                    tB: diagnostic.tB,
                    usedBridge: diagnostic.usedBridge,
                    reason: diagnostic.reason,
                    clipped: clip.applied,
                    clipReason: clip.reason
                )
            } else {
                diagnostic = JunctionDiagnostic(
                    joinIndex: diagnostic.joinIndex,
                    tA: diagnostic.tA,
                    tB: diagnostic.tB,
                    usedBridge: diagnostic.usedBridge,
                    reason: diagnostic.reason,
                    clipped: false,
                    clipReason: "noCorridor"
                )
            }
            patches.append(finalRing)
            junctionControlPoints.append(contentsOf: patch.controlPoints)
            junctionDiagnostics.append(diagnostic)
        }
        let cleanedCaps = removeTinyEdges(removeConsecutiveDuplicates(capPoints, tol: epsilon), epsilon: epsilon)
        return DirectSilhouetteResult(
            outline: outline,
            leftRail: leftRail,
            rightRail: rightRail,
            endCap: endCap,
            startCap: startCap,
            junctionPatches: patches,
            junctionControlPoints: junctionControlPoints,
            junctionDiagnostics: junctionDiagnostics,
            junctionCorridors: junctionCorridors,
            capPoints: cleanedCaps
        )
    }

    public static func supportOffset(direction: Point, width: Double, height: Double, thetaWorld: Double, epsilon: Double = 1.0e-9) -> Point {
        let local = GeometryMath.rotate(point: direction, by: -thetaWorld)
        let halfW = width * 0.5
        let halfH = height * 0.5
        let sx = signWithZero(local.x, epsilon: epsilon)
        let sy = signWithZero(local.y, epsilon: epsilon)
        let localCorner = Point(x: sx * halfW, y: sy * halfH)
        return GeometryMath.rotate(point: localCorner, by: thetaWorld)
    }

    public static func leftRailPoint(sample: Sample, epsilon: Double = 1.0e-9) -> Point {
        railPointInternal(sample: sample, side: .left, epsilon: epsilon)
    }

    public static func rightRailPoint(sample: Sample, epsilon: Double = 1.0e-9) -> Point {
        railPointInternal(sample: sample, side: .right, epsilon: epsilon)
    }

    private static func rectangleCornersWorld(center: Point, width: Double, height: Double, thetaWorld: Double) -> [Point] {
        let halfW = width * 0.5
        let halfH = height * 0.5
        let local = [
            Point(x: -halfW, y: -halfH),
            Point(x: halfW, y: -halfH),
            Point(x: halfW, y: halfH),
            Point(x: -halfW, y: halfH)
        ]
        return local.map { center + GeometryMath.rotate(point: $0, by: thetaWorld) }
    }

    private static func endCapPoints(corners: [Point], center: Point, faceDir: Point, from: Point, to: Point, epsilon: Double) -> [Point] {
        guard !corners.isEmpty else { return [] }
        let maxDot = corners.map { ($0 - center).dot(faceDir) }.max() ?? 0.0
        var candidates: [Point] = []
        for corner in corners {
            if abs((corner - center).dot(faceDir) - maxDot) <= epsilon {
                candidates.append(corner)
            }
        }
        if candidates.count < 2 {
            let sorted = corners.sorted { ($0 - center).dot(faceDir) > ($1 - center).dot(faceDir) }
            candidates = Array(sorted.prefix(2))
        }
        if candidates.count > 2 {
            candidates = Array(candidates.prefix(2))
        }
        guard candidates.count == 2 else { return candidates }
        let first = candidates[0]
        let second = candidates[1]
        let distFirst = (first - from).length
        let distSecond = (second - from).length
        if abs(distFirst - distSecond) <= epsilon {
            let ordered = [first, second].sorted { (a, b) in
                if a.x != b.x { return a.x < b.x }
                return a.y < b.y
            }
            return ordered
        }
        return distFirst <= distSecond ? [first, second] : [second, first]
    }

    private static func signWithZero(_ value: Double, epsilon: Double) -> Double {
        if abs(value) <= epsilon { return 0.0 }
        return value < 0 ? -1.0 : 1.0
    }

    private enum RailSide {
        case left
        case right
    }

    private static func refineSamples(
        samples: [Sample],
        options: DirectSilhouetteOptions,
        railTolerance: Double,
        paramsProvider: DirectSilhouetteParamProvider?,
        traceWindow: DirectSilhouetteTraceWindow?,
        epsilon: Double
    ) -> [Sample] {
        guard samples.count >= 2 else { return samples }
        var refined: [Sample] = []
        refined.reserveCapacity(samples.count)
        refined.append(samples[0])
        for index in 0..<(samples.count - 1) {
            let a = samples[index]
            let b = samples[index + 1]
            let segment = refinePair(
                a,
                b,
                depth: 0,
                options: options,
                railTolerance: railTolerance,
                paramsProvider: paramsProvider,
                traceWindow: traceWindow,
                epsilon: epsilon
            )
            if segment.count > 1 {
                refined.append(contentsOf: segment.dropFirst())
            }
        }
        return refined
    }

    private static func refinePair(
        _ a: Sample,
        _ b: Sample,
        depth: Int,
        options: DirectSilhouetteOptions,
        railTolerance: Double,
        paramsProvider: DirectSilhouetteParamProvider?,
        traceWindow: DirectSilhouetteTraceWindow?,
        epsilon: Double
    ) -> [Sample] {
        let maxDepth = max(options.cornerRefineMaxDepth, options.railRefineMaxDepth)
        if depth >= maxDepth {
            if let window = traceWindow, window.intersects(a.t, b.t) {
                print("direct-refine depthCap t=[\(format(a.t))..\((format(b.t)))] depth=\(depth)")
            }
            return [a, b]
        }
        let minStep = min(options.cornerRefineMinStep, options.railRefineMinStep)
        if abs(b.t - a.t) <= minStep {
            if let window = traceWindow, window.intersects(a.t, b.t) {
                print("direct-refine minStep t=[\(format(a.t))..\((format(b.t)))] step=\(format(abs(b.t - a.t)))")
            }
            return [a, b]
        }
        if !needsRailSplit(a, b, options: options, railTolerance: railTolerance, paramsProvider: paramsProvider, traceWindow: traceWindow, epsilon: epsilon) {
            return [a, b]
        }
        let mid = interpolateSample(a, b, paramsProvider: paramsProvider)
        let left = refinePair(a, mid, depth: depth + 1, options: options, railTolerance: railTolerance, paramsProvider: paramsProvider, traceWindow: traceWindow, epsilon: epsilon)
        let right = refinePair(mid, b, depth: depth + 1, options: options, railTolerance: railTolerance, paramsProvider: paramsProvider, traceWindow: traceWindow, epsilon: epsilon)
        if left.isEmpty { return right }
        if right.isEmpty { return left }
        return Array(left.dropLast()) + right
    }

    private static func needsRailSplit(
        _ a: Sample,
        _ b: Sample,
        options: DirectSilhouetteOptions,
        railTolerance: Double,
        paramsProvider: DirectSilhouetteParamProvider?,
        traceWindow: DirectSilhouetteTraceWindow?,
        epsilon: Double
    ) -> Bool {
        let inWindow = traceWindow?.intersects(a.t, b.t) ?? false
        if options.enableCornerRefine, cornerSwitchesBetween(a, b, epsilon: options.cornerRefineEpsilon) {
            if inWindow {
                print("direct-refine cornerSwitch t=[\(format(a.t))..\((format(b.t)))]")
            }
            return true
        }
        var deviation: Double = 0.0
        if options.enableRailRefine, railTolerance > 0 {
            deviation = railDeviation(a: a, b: b, paramsProvider: paramsProvider, traceWindow: traceWindow, epsilon: epsilon)
            if inWindow {
                print("direct-refine railDeviation t=[\(format(a.t))..\((format(b.t)))] dev=\(format(deviation)) tol=\(format(railTolerance))")
            }
            if deviation > railTolerance {
                return true
            }
        }
        if inWindow {
            let reason: String
            if !options.enableCornerRefine && !(options.enableRailRefine && railTolerance > 0) {
                reason = "disabled"
            } else if options.enableRailRefine && railTolerance > 0 {
                reason = "withinTolerance"
            } else {
                reason = "noCornerSwitch"
            }
            print("direct-refine keep t=[\(format(a.t))..\((format(b.t)))] reason=\(reason) dev=\(format(deviation))")
        }
        return false
    }

    private static func cornerSwitchesBetween(_ a: Sample, _ b: Sample, epsilon: Double) -> Bool {
        let leftA = cornerKey(for: a, side: .left, epsilon: epsilon)
        let leftB = cornerKey(for: b, side: .left, epsilon: epsilon)
        if leftA != leftB { return true }
        let rightA = cornerKey(for: a, side: .right, epsilon: epsilon)
        let rightB = cornerKey(for: b, side: .right, epsilon: epsilon)
        return rightA != rightB
    }

    private static func cornerKey(for sample: Sample, side: RailSide, epsilon: Double) -> (Int, Int) {
        let tangent = Point(x: cos(sample.tangentAngle), y: sin(sample.tangentAngle))
        var normal = tangent.leftNormal()
        if side == .right {
            normal = normal * -1.0
        }
        let local = GeometryMath.rotate(point: normal, by: -sample.effectiveRotation)
        let sx = signIntWithZero(local.x, epsilon: epsilon)
        let sy = signIntWithZero(local.y, epsilon: epsilon)
        return (sx, sy)
    }

    private static func signIntWithZero(_ value: Double, epsilon: Double) -> Int {
        if abs(value) <= epsilon { return 0 }
        return value < 0 ? -1 : 1
    }

    internal static func interpolatedSample(_ a: Sample, _ b: Sample, fraction: Double) -> Sample {
        interpolateSample(a, b, fraction: fraction)
    }

    internal static func railDeviationForTest(a: Sample, b: Sample, paramsProvider: DirectSilhouetteParamProvider?, epsilon: Double) -> Double {
        railDeviation(a: a, b: b, paramsProvider: paramsProvider, traceWindow: nil, epsilon: epsilon)
    }

    private static func interpolateSample(_ a: Sample, _ b: Sample, fraction: Double = 0.5, paramsProvider: DirectSilhouetteParamProvider? = nil) -> Sample {
        let t = ScalarMath.clamp01(fraction)
        let point = Point(
            x: ScalarMath.lerp(a.point.x, b.point.x, t),
            y: ScalarMath.lerp(a.point.y, b.point.y, t)
        )
        let tangentA = Point(x: cos(a.tangentAngle), y: sin(a.tangentAngle))
        let tangentB = Point(x: cos(b.tangentAngle), y: sin(b.tangentAngle))
        let tangent = (tangentA + tangentB).normalized() ?? tangentA
        let tangentAngle = atan2(tangent.y, tangent.x)
        let theta = a.theta + AngleMath.shortestDelta(from: a.theta, to: b.theta) * t
        let effectiveRotation = a.effectiveRotation + AngleMath.shortestDelta(from: a.effectiveRotation, to: b.effectiveRotation) * t
        var width = ScalarMath.lerp(a.width, b.width, t)
        var height = ScalarMath.lerp(a.height, b.height, t)
        var alpha = ScalarMath.lerp(a.alpha, b.alpha, t)
        var resolvedTheta = theta
        var resolvedRotation = effectiveRotation
        if let provider = paramsProvider {
            let params = provider(ScalarMath.lerp(a.t, b.t, t), tangentAngle)
            width = params.width
            height = params.height
            alpha = params.alpha
            resolvedTheta = params.theta
            resolvedRotation = params.effectiveRotation
        }
        return Sample(
            uGeom: ScalarMath.lerp(a.uGeom, b.uGeom, t),
            uGrid: ScalarMath.lerp(a.uGrid, b.uGrid, t),
            t: ScalarMath.lerp(a.t, b.t, t),
            point: point,
            tangentAngle: tangentAngle,
            width: width,
            height: height,
            theta: resolvedTheta,
            effectiveRotation: resolvedRotation,
            alpha: alpha
        )
    }

    private static func railDeviation(a: Sample, b: Sample, paramsProvider: DirectSilhouetteParamProvider?, traceWindow: DirectSilhouetteTraceWindow?, epsilon: Double) -> Double {
        let tm = 0.5 * (a.t + b.t)
        let mid = interpolateSample(a, b, paramsProvider: paramsProvider)
        let left0 = railPointInternal(sample: a, side: .left, epsilon: epsilon)
        let left1 = railPointInternal(sample: b, side: .left, epsilon: epsilon)
        let leftMid = railPointInternal(sample: mid, side: .left, epsilon: epsilon)
        let leftLinear = Point(
            x: ScalarMath.lerp(left0.x, left1.x, 0.5),
            y: ScalarMath.lerp(left0.y, left1.y, 0.5)
        )
        let right0 = railPointInternal(sample: a, side: .right, epsilon: epsilon)
        let right1 = railPointInternal(sample: b, side: .right, epsilon: epsilon)
        let rightMid = railPointInternal(sample: mid, side: .right, epsilon: epsilon)
        let rightLinear = Point(
            x: ScalarMath.lerp(right0.x, right1.x, 0.5),
            y: ScalarMath.lerp(right0.y, right1.y, 0.5)
        )
        let leftError = (leftMid - leftLinear).length
        let rightError = (rightMid - rightLinear).length
        if let window = traceWindow, window.intersects(a.t, b.t) {
            print("[DEV] t0=\(format(a.t)) t1=\(format(b.t)) tm=\(format(tm))")
            print("      L0=(\(format(left0.x)),\(format(left0.y))) Lm=(\(format(leftMid.x)),\(format(leftMid.y))) L1=(\(format(left1.x)),\(format(left1.y))) Llin=(\(format(leftLinear.x)),\(format(leftLinear.y))) devL=\(format(leftError))")
            print("      R0=(\(format(right0.x)),\(format(right0.y))) Rm=(\(format(rightMid.x)),\(format(rightMid.y))) R1=(\(format(right1.x)),\(format(right1.y))) Rlin=(\(format(rightLinear.x)),\(format(rightLinear.y))) devR=\(format(rightError))")
        }
        return max(leftError, rightError)
    }

    private static func railPointInternal(sample: Sample, side: RailSide, epsilon: Double) -> Point {
        let tangent = Point(x: cos(sample.tangentAngle), y: sin(sample.tangentAngle))
        var normal = tangent.leftNormal()
        if side == .right {
            normal = normal * -1.0
        }
        let offset = supportOffset(
            direction: normal,
            width: sample.width,
            height: sample.height,
            thetaWorld: sample.effectiveRotation,
            epsilon: epsilon
        )
        return sample.point + offset
    }

    private static func removeTinyEdges(_ points: [Point], epsilon: Double) -> [Point] {
        guard !points.isEmpty else { return points }
        var result: [Point] = []
        result.reserveCapacity(points.count)
        var last = points[0]
        result.append(last)
        for point in points.dropFirst() {
            if (point - last).length > epsilon {
                result.append(point)
                last = point
            }
        }
        return result
    }

    private static func containsPoint(_ points: [Point], _ target: Point, epsilon: Double) -> Bool {
        for point in points {
            if (point - target).length <= epsilon {
                return true
            }
        }
        return false
    }

    private static func missingPointCount(points: [Point], within target: [Point], epsilon: Double) -> Int {
        var missing = 0
        for point in points {
            if !containsPoint(target, point, epsilon: epsilon) {
                missing += 1
            }
        }
        return missing
    }

    private static func roundCapArc(center: Point, from: Point, to: Point, faceDir: Point, tolerance: Double, maxDepth: Int, epsilon: Double) -> [Point] {
        let startVec = from - center
        let endVec = to - center
        let startRadius = startVec.length
        let endRadius = endVec.length
        let radius = max(startRadius, endRadius)
        if radius <= epsilon { return [] }
        let startAngle = atan2(startVec.y, startVec.x)
        let endAngle = atan2(endVec.y, endVec.x)
        let face = faceDir.normalized() ?? faceDir
        let ccwDelta = normalizedAngle(endAngle - startAngle)
        let cwDelta = ccwDelta - (2.0 * .pi)
        let ccwMid = startAngle + ccwDelta * 0.5
        let cwMid = startAngle + cwDelta * 0.5
        let ccwDot = Point(x: cos(ccwMid), y: sin(ccwMid)).dot(face)
        let cwDot = Point(x: cos(cwMid), y: sin(cwMid)).dot(face)
        let useDelta = (cwDot > ccwDot + epsilon) ? cwDelta : ccwDelta
        let endAngleAdjusted = startAngle + useDelta

        var points: [Point] = []
        points.reserveCapacity(16)
        points.append(from)
        func recurse(_ a: Double, _ b: Double, depth: Int) {
            let pa = Point(x: center.x + cos(a) * radius, y: center.y + sin(a) * radius)
            let pb = Point(x: center.x + cos(b) * radius, y: center.y + sin(b) * radius)
            let mid = 0.5 * (a + b)
            let pm = Point(x: center.x + cos(mid) * radius, y: center.y + sin(mid) * radius)
            let chordMid = Point(
                x: ScalarMath.lerp(pa.x, pb.x, 0.5),
                y: ScalarMath.lerp(pa.y, pb.y, 0.5)
            )
            let error = (pm - chordMid).length
            if error <= tolerance || depth >= maxDepth {
                points.append(pb)
                return
            }
            recurse(a, mid, depth: depth + 1)
            recurse(mid, b, depth: depth + 1)
        }
        recurse(startAngle, endAngleAdjusted, depth: 0)
        return points
    }

    private static func normalizedAngle(_ value: Double) -> Double {
        var result = value
        let twoPi = 2.0 * .pi
        while result < 0 { result += twoPi }
        while result >= twoPi { result -= twoPi }
        return result
    }

    private static func trimArcPoints(_ points: [Point]) -> [Point] {
        if points.count <= 2 { return [] }
        return Array(points.dropFirst().dropLast())
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.6f", value)
    }

    private struct JunctionPatchResult {
        let ring: Ring
        let controlPoints: [Point]
        let diagnostic: JunctionDiagnostic
    }

    private struct JunctionClipResult {
        let ring: Ring?
        let applied: Bool
        let reason: String
    }

    private enum JunctionInvalidReason: String {
        case containsNaN
        case degenerate
        case areaTooSmall
        case selfIntersect
        case railsCross
        case orientationFlip
        case unknown
    }

    private static func junctionPatch(from context: JunctionContext, epsilon: Double, verbose: Bool) -> JunctionPatchResult? {
        let leftA = leftRailPoint(sample: context.a, epsilon: epsilon)
        let rightA = rightRailPoint(sample: context.a, epsilon: epsilon)
        let leftB = leftRailPoint(sample: context.b, epsilon: epsilon)
        let rightB = rightRailPoint(sample: context.b, epsilon: epsilon)

        let leftPrev = context.prev.map { leftRailPoint(sample: $0, epsilon: epsilon) }
        let rightPrev = context.prev.map { rightRailPoint(sample: $0, epsilon: epsilon) }
        let leftNext = context.next.map { leftRailPoint(sample: $0, epsilon: epsilon) }
        let rightNext = context.next.map { rightRailPoint(sample: $0, epsilon: epsilon) }

        let fallbackA = Point(x: cos(context.a.tangentAngle), y: sin(context.a.tangentAngle))
        let fallbackB = Point(x: cos(context.b.tangentAngle), y: sin(context.b.tangentAngle))

        let dLeftA = railTangent(prev: leftPrev, current: leftA, next: leftB, fallback: fallbackA, epsilon: epsilon)
        let dLeftB = railTangent(prev: leftA, current: leftB, next: leftNext, fallback: fallbackB, epsilon: epsilon)
        let dRightA = railTangent(prev: rightPrev, current: rightA, next: rightB, fallback: fallbackA, epsilon: epsilon)
        let dRightB = railTangent(prev: rightA, current: rightB, next: rightNext, fallback: fallbackB, epsilon: epsilon)

        let avgWidth = max(epsilon, 0.5 * (context.a.width + context.b.width))
        let minHandle = max(0.25, avgWidth * 0.02)
        let maxHandle = max(minHandle, avgWidth * 0.6)
        let baseHandle = clamp(avgWidth * 0.25, min: minHandle, max: maxHandle)
        let span = min((leftB - leftA).length, (rightB - rightA).length)
        let spanLimit = max(minHandle, span * 0.35)
        let handleBase = min(baseHandle, spanLimit)
        let handleCandidates = [handleBase, handleBase * 0.5, handleBase * 0.25, handleBase * 0.125].filter { $0 >= minHandle * 0.1 }

        let hasNeighbors = context.prev != nil && context.next != nil
        let fallbackReason = hasNeighbors ? "invalidPatch" : "missingNeighbors"
        var lastReason: JunctionInvalidReason = .unknown
        var lastHandle = handleBase

        if verbose {
            print("junction joinIndex=\(context.joinIndex) tA=\(format(context.a.t)) tB=\(format(context.b.t)) handleBase=\(format(handleBase)) span=\(format(span)) minHandle=\(format(minHandle))")
            print("junction-left L_A=(\(format(leftA.x)),\(format(leftA.y))) L_B=(\(format(leftB.x)),\(format(leftB.y))) dL_A=(\(format(dLeftA.x)),\(format(dLeftA.y))) dL_B=(\(format(dLeftB.x)),\(format(dLeftB.y)))")
            print("junction-right R_A=(\(format(rightA.x)),\(format(rightA.y))) R_B=(\(format(rightB.x)),\(format(rightB.y))) dR_A=(\(format(dRightA.x)),\(format(dRightA.y))) dR_B=(\(format(dRightB.x)),\(format(dRightB.y)))")
        }

        for handle in handleCandidates {
            lastHandle = handle
            let leftC1 = leftA + dLeftA * handle
            let leftC2 = leftB - dLeftB * handle
            let rightC1 = rightB + (dRightB * -1.0) * handle
            let rightC2 = rightA - (dRightA * -1.0) * handle

            let leftCurve = sampleCubic(p0: leftA, p1: leftC1, p2: leftC2, p3: leftB, segments: 12)
            let rightCurve = sampleCubic(p0: rightB, p1: rightC1, p2: rightC2, p3: rightA, segments: 12)

            var ring = leftCurve + rightCurve
            ring = removeTinyEdges(removeConsecutiveDuplicates(ring, tol: epsilon), epsilon: epsilon)
            ring = closeRingIfNeeded(ring, tol: epsilon)
            let reason = validateBridgePatch(
                ring: ring,
                leftCurve: leftCurve,
                rightCurve: rightCurve,
                epsilon: epsilon
            )
            if reason == nil {
                let controls = [leftC1, leftC2, rightC1, rightC2]
                let diagnostic = JunctionDiagnostic(
                    joinIndex: context.joinIndex,
                    tA: context.a.t,
                    tB: context.b.t,
                    usedBridge: true,
                    reason: "ok",
                    clipped: false,
                    clipReason: "none"
                )
                if verbose {
                    print("junction joinIndex=\(context.joinIndex) tA=\(format(context.a.t)) tB=\(format(context.b.t)) used=bridge reason=ok")
                    print("junction-left L_A=(\(format(leftA.x)),\(format(leftA.y))) L_B=(\(format(leftB.x)),\(format(leftB.y))) dL_A=(\(format(dLeftA.x)),\(format(dLeftA.y))) dL_B=(\(format(dLeftB.x)),\(format(dLeftB.y))) C1=(\(format(leftC1.x)),\(format(leftC1.y))) C2=(\(format(leftC2.x)),\(format(leftC2.y)))")
                    print("junction-right R_A=(\(format(rightA.x)),\(format(rightA.y))) R_B=(\(format(rightB.x)),\(format(rightB.y))) dR_A=(\(format(dRightA.x)),\(format(dRightA.y))) dR_B=(\(format(dRightB.x)),\(format(dRightB.y))) C1=(\(format(rightC2.x)),\(format(rightC2.y))) C2=(\(format(rightC1.x)),\(format(rightC1.y)))")
                }
                return JunctionPatchResult(ring: ring, controlPoints: controls, diagnostic: diagnostic)
            } else {
                lastReason = reason ?? .unknown
                if verbose {
                    print("junction-handle handle=\(format(handle)) invalid=\(lastReason.rawValue)")
                }
            }
        }

        let chordLeft = (leftB - leftA).normalized(epsilon: epsilon)
        let chordRight = (rightB - rightA).normalized(epsilon: epsilon)
        if let chordLeft, let chordRight {
            let chordHandle = max(minHandle, min(handleBase, span * 0.35))
            let leftC1 = leftA + chordLeft * chordHandle
            let leftC2 = leftB - chordLeft * chordHandle
            let rightC1 = rightB + (chordRight * -1.0) * chordHandle
            let rightC2 = rightA - (chordRight * -1.0) * chordHandle

            let leftCurve = sampleCubic(p0: leftA, p1: leftC1, p2: leftC2, p3: leftB, segments: 12)
            let rightCurve = sampleCubic(p0: rightB, p1: rightC1, p2: rightC2, p3: rightA, segments: 12)
            var ring = leftCurve + rightCurve
            ring = removeTinyEdges(removeConsecutiveDuplicates(ring, tol: epsilon), epsilon: epsilon)
            ring = closeRingIfNeeded(ring, tol: epsilon)
            let reason = validateBridgePatch(
                ring: ring,
                leftCurve: leftCurve,
                rightCurve: rightCurve,
                epsilon: epsilon
            )
            if reason == nil {
                let controls = [leftC1, leftC2, rightC1, rightC2]
                let diagnostic = JunctionDiagnostic(
                    joinIndex: context.joinIndex,
                    tA: context.a.t,
                    tB: context.b.t,
                    usedBridge: true,
                    reason: "okChord",
                    clipped: false,
                    clipReason: "none"
                )
                if verbose {
                    print("junction joinIndex=\(context.joinIndex) tA=\(format(context.a.t)) tB=\(format(context.b.t)) used=bridge reason=okChord")
                }
                return JunctionPatchResult(ring: ring, controlPoints: controls, diagnostic: diagnostic)
            } else {
                lastReason = reason ?? .unknown
                if verbose {
                    print("junction-chord invalid=\(lastReason.rawValue) handle=\(format(chordHandle))")
                }
            }
        }

        let quad = closeRingIfNeeded([leftA, leftB, rightB, rightA], tol: epsilon)
        if quad.count >= 4, abs(signedArea(quad)) > epsilon, !ringSelfIntersects(quad, epsilon: epsilon) {
            let diagnostic = JunctionDiagnostic(
                joinIndex: context.joinIndex,
                tA: context.a.t,
                tB: context.b.t,
                usedBridge: true,
                reason: "quad",
                clipped: false,
                clipReason: "none"
            )
            if verbose {
                print("junction joinIndex=\(context.joinIndex) tA=\(format(context.a.t)) tB=\(format(context.b.t)) used=bridge reason=quad")
            }
            return JunctionPatchResult(ring: quad, controlPoints: [], diagnostic: diagnostic)
        }

        let reason = hasNeighbors ? fallbackReason : "missingNeighbors"
        if verbose {
            print("junction joinIndex=\(context.joinIndex) tA=\(format(context.a.t)) tB=\(format(context.b.t)) used=hull reason=\(reason)")
            print("junction-invalid reason=\(lastReason.rawValue) handle=\(format(lastHandle))")
        }
        return convexHullPatch(from: context, epsilon: epsilon, reason: reason, verbose: verbose)
    }

    private static func validateBridgePatch(
        ring: Ring,
        leftCurve: [Point],
        rightCurve: [Point],
        epsilon: Double
    ) -> JunctionInvalidReason? {
        if ring.contains(where: { !$0.x.isFinite || !$0.y.isFinite }) { return .containsNaN }
        if ring.count < 4 { return .degenerate }
        let area = abs(signedArea(ring))
        if area <= epsilon { return .areaTooSmall }
        if ringSelfIntersects(ring, epsilon: epsilon) { return .selfIntersect }
        if railsCross(leftCurve: leftCurve, rightCurve: rightCurve, epsilon: epsilon) { return .railsCross }
        return nil
    }

    private static func railsCross(leftCurve: [Point], rightCurve: [Point], epsilon: Double) -> Bool {
        guard leftCurve.count >= 2, rightCurve.count >= 2 else { return false }
        let leftSegments = segmentsFromPolyline(leftCurve)
        let rightSegments = segmentsFromPolyline(rightCurve)
        for ls in leftSegments {
            for rs in rightSegments {
                switch intersect(ls, rs, tol: epsilon) {
                case .proper, .collinearOverlap:
                    return true
                case .endpoint, .none:
                    continue
                }
            }
        }
        return false
    }

    private static func segmentsFromPolyline(_ points: [Point]) -> [Segment] {
        guard points.count >= 2 else { return [] }
        var segments: [Segment] = []
        segments.reserveCapacity(points.count - 1)
        for i in 0..<(points.count - 1) {
            let a = points[i]
            let b = points[i + 1]
            if a != b {
                segments.append(Segment(a: a, b: b))
            }
        }
        return segments
    }

    private static func convexHullPatch(from context: JunctionContext, epsilon: Double, reason: String, verbose: Bool) -> JunctionPatchResult? {
        let cornersA = rectangleCornersWorld(center: context.a.point, width: context.a.width, height: context.a.height, thetaWorld: context.a.effectiveRotation)
        let cornersB = rectangleCornersWorld(center: context.b.point, width: context.b.width, height: context.b.height, thetaWorld: context.b.effectiveRotation)
        let hull = convexHull(points: cornersA + cornersB, epsilon: epsilon)
        guard hull.count >= 3 else { return nil }
        let area = signedArea(hull)
        if abs(area) <= epsilon { return nil }
        let cleaned = removeTinyEdges(removeConsecutiveDuplicates(hull, tol: epsilon), epsilon: epsilon)
        let closed = closeRingIfNeeded(cleaned, tol: epsilon)
        if closed.count < 4 { return nil }
        let diagnostic = JunctionDiagnostic(
            joinIndex: context.joinIndex,
            tA: context.a.t,
            tB: context.b.t,
            usedBridge: false,
            reason: reason,
            clipped: false,
            clipReason: "none"
        )
        if verbose {
            print("junction-hull joinIndex=\(context.joinIndex) area=\(format(abs(area))) points=\(closed.count)")
        }
        return JunctionPatchResult(ring: closed, controlPoints: [], diagnostic: diagnostic)
    }

    private static func buildJunctionCorridor(
        samples: [Sample],
        leftRail: [Point],
        rightRail: [Point],
        context: JunctionContext,
        window: Int,
        epsilon: Double
    ) -> Ring? {
        guard samples.count == leftRail.count, samples.count == rightRail.count, samples.count > 1 else { return nil }
        guard let indexA = nearestSampleIndex(samples, target: context.a),
              let indexB = nearestSampleIndex(samples, target: context.b) else { return nil }
        let minIndex = max(0, min(indexA, indexB) - window)
        let maxIndex = min(samples.count - 1, max(indexA, indexB) + window)
        guard maxIndex > minIndex else { return nil }
        let leftSlice = Array(leftRail[minIndex...maxIndex])
        let rightSlice = Array(rightRail[minIndex...maxIndex].reversed())
        var corridor = leftSlice + rightSlice
        corridor = removeTinyEdges(removeConsecutiveDuplicates(corridor, tol: epsilon), epsilon: epsilon)
        corridor = closeRingIfNeeded(corridor, tol: epsilon)
        if corridor.count < 4 { return nil }
        if abs(signedArea(corridor)) <= epsilon { return nil }
        return corridor
    }

    private static func nearestSampleIndex(_ samples: [Sample], target: Sample) -> Int? {
        guard !samples.isEmpty else { return nil }
        var bestIndex = 0
        var bestDelta = abs(samples[0].t - target.t)
        for i in 1..<samples.count {
            let delta = abs(samples[i].t - target.t)
            if delta < bestDelta {
                bestDelta = delta
                bestIndex = i
            }
        }
        return bestIndex
    }

    private static func clipJunctionPatch(
        ring: Ring,
        corridor: Ring,
        context: JunctionContext,
        epsilon: Double,
        verbose: Bool
    ) -> JunctionClipResult {
        guard let patchBounds = boundingBox(ring), let corridorBounds = boundingBox(corridor) else {
            return JunctionClipResult(ring: nil, applied: false, reason: "invalidBounds")
        }
        let minX = min(patchBounds.min.x, corridorBounds.min.x)
        let minY = min(patchBounds.min.y, corridorBounds.min.y)
        let maxX = max(patchBounds.max.x, corridorBounds.max.x)
        let maxY = max(patchBounds.max.y, corridorBounds.max.y)
        let width = maxX - minX
        let height = maxY - minY
        guard width.isFinite, height.isFinite, width > 0.0, height > 0.0 else {
            return JunctionClipResult(ring: nil, applied: false, reason: "invalidBounds")
        }
        let minDim = min(width, height)
        let pixelSize = max(epsilon, minDim / 64.0)
        let padding = pixelSize * 2.0
        let bounds = Rasterizer.RasterBounds(
            minX: minX - padding,
            minY: minY - padding,
            maxX: maxX + padding,
            maxY: maxY + padding
        )
        let patchGrid = Rasterizer.rasterizeFixed(polygons: [Polygon(outer: ring, holes: [])], bounds: bounds, pixelSize: pixelSize)
        let corridorGrid = Rasterizer.rasterizeFixed(polygons: [Polygon(outer: corridor, holes: [])], bounds: bounds, pixelSize: pixelSize)
        var intersectGrid = patchGrid.grid
        for i in 0..<intersectGrid.data.count {
            intersectGrid.data[i] = (patchGrid.grid.data[i] != 0 && corridorGrid.grid.data[i] != 0) ? 1 : 0
        }
        let contours = ContourTracer.trace(grid: intersectGrid, origin: patchGrid.origin, pixelSize: patchGrid.pixelSize)
        guard let clipped = largestRing(contours) else {
            let quad = closeRingIfNeeded([leftRailPoint(sample: context.a, epsilon: epsilon),
                                          leftRailPoint(sample: context.b, epsilon: epsilon),
                                          rightRailPoint(sample: context.b, epsilon: epsilon),
                                          rightRailPoint(sample: context.a, epsilon: epsilon)], tol: epsilon)
            if verbose {
                print("junction-clip result=empty fallback=quad joinIndex=\(context.joinIndex)")
            }
            return JunctionClipResult(ring: quad, applied: false, reason: "emptyIntersection")
        }
        if verbose {
            print("junction-clip applied joinIndex=\(context.joinIndex) pixelSize=\(format(pixelSize))")
        }
        return JunctionClipResult(ring: clipped, applied: true, reason: "ok")
    }

    private static func largestRing(_ rings: [Ring]) -> Ring? {
        guard !rings.isEmpty else { return nil }
        var best = rings[0]
        var bestArea = abs(signedArea(best))
        for ring in rings.dropFirst() {
            let area = abs(signedArea(ring))
            if area > bestArea {
                best = ring
                bestArea = area
            }
        }
        return best
    }

    private static func railTangent(prev: Point?, current: Point, next: Point?, fallback: Point, epsilon: Double) -> Point {
        if let prev {
            if let dir = (current - prev).normalized(epsilon: epsilon) { return dir }
        }
        if let next {
            if let dir = (next - current).normalized(epsilon: epsilon) { return dir }
        }
        return fallback.normalized(epsilon: epsilon) ?? Point(x: 1.0, y: 0.0)
    }

    private static func clamp(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
        if value < minValue { return minValue }
        if value > maxValue { return maxValue }
        return value
    }

    private static func sampleCubic(p0: Point, p1: Point, p2: Point, p3: Point, segments: Int) -> [Point] {
        let steps = max(2, segments)
        var points: [Point] = []
        points.reserveCapacity(steps + 1)
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let mt = 1.0 - t
            let mt2 = mt * mt
            let t2 = t * t
            let a = mt2 * mt
            let b = 3.0 * mt2 * t
            let c = 3.0 * mt * t2
            let d = t2 * t
            let point = Point(
                x: p0.x * a + p1.x * b + p2.x * c + p3.x * d,
                y: p0.y * a + p1.y * b + p2.y * c + p3.y * d
            )
            points.append(point)
        }
        return points
    }

    private static func convexHull(points: [Point], epsilon: Double) -> [Point] {
        guard points.count > 1 else { return points }
        let sorted = points.sorted { a, b in
            if a.x != b.x { return a.x < b.x }
            return a.y < b.y
        }
        var unique: [Point] = []
        unique.reserveCapacity(sorted.count)
        for point in sorted {
            if let last = unique.last, (point - last).length <= epsilon {
                continue
            }
            unique.append(point)
        }
        guard unique.count >= 2 else { return unique }

        func cross(_ o: Point, _ a: Point, _ b: Point) -> Double {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }

        var lower: [Point] = []
        for p in unique {
            while lower.count >= 2, cross(lower[lower.count - 2], lower[lower.count - 1], p) <= epsilon {
                lower.removeLast()
            }
            lower.append(p)
        }
        var upper: [Point] = []
        for p in unique.reversed() {
            while upper.count >= 2, cross(upper[upper.count - 2], upper[upper.count - 1], p) <= epsilon {
                upper.removeLast()
            }
            upper.append(p)
        }
        lower.removeLast()
        upper.removeLast()
        var hull = lower + upper
        if hull.count < 3 { return hull }
        if signedArea(hull) < 0 {
            hull.reverse()
        }
        var startIndex = 0
        for i in 1..<hull.count {
            let a = hull[i]
            let b = hull[startIndex]
            if a.x < b.x || (a.x == b.x && a.y < b.y) {
                startIndex = i
            }
        }
        if startIndex > 0 {
            hull = Array(hull[startIndex...] + hull[..<startIndex])
        }
        return hull
    }

    private static func ringSelfIntersects(_ ring: Ring, epsilon: Double) -> Bool {
        let segmentsList = segments(from: ring, ensureClosed: true)
        guard segmentsList.count >= 4 else { return false }
        for i in 0..<segmentsList.count {
            let s1 = segmentsList[i]
            for j in (i + 1)..<segmentsList.count {
                if abs(i - j) <= 1 { continue }
                if i == 0 && j == segmentsList.count - 1 { continue }
                let s2 = segmentsList[j]
                switch intersect(s1, s2, tol: epsilon) {
                case .none:
                    continue
                case .endpoint:
                    continue
                case .proper, .collinearOverlap:
                    return true
                }
            }
        }
        return false
    }
}
