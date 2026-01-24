// Sources/CP2Skeleton/Sampling/GlobalTSampler.swift
import Foundation
import CP2Geometry

public struct GlobalTSampler {
    public typealias PositionAtS = @Sendable (Double) -> Vec2

    public init() {}

    public func sampleGlobalT(
        config: SamplingConfig,
        positionAt: PositionAtS,
        railProbe: (any RailProbe)? = nil,
        paramsAt: (@Sendable (Double) -> StrokeParamsSample?)? = nil
    ) -> SamplingResult {
        switch config.mode {
        case .fixed(let count):
            let ts = fixedSamples(count: count)
            return SamplingResult(ts: ts, trace: [], stats: SamplingStats())

        case .adaptive:
            // STEP 2: geometry-only adaptive sampling (path flatness only).
            // railProbe/paramsAt are intentionally ignored in Step 2.
            return adaptiveSamples(config: config, positionAt: positionAt, railProbe: railProbe)
        }
    }

    // MARK: - Fixed

    private func fixedSamples(count: Int) -> [Double] {
        let n = max(2, count)
        if n == 2 { return [0.0, 1.0] }
        return (0..<n).map { Double($0) / Double(n - 1) }
    }

    // MARK: - Adaptive (Step 2: geometry-only)

    /// Geometry-only adaptive subdivision.
    ///
    /// We treat the parameter as `s` in [0,1] (normalized arc-length fraction).
    /// We subdivide segments [s0,s1] if the midpoint deviates from a straight chord:
    ///
    ///     p0 *-----* p1
    ///           |
    ///          pm   (midpoint on the curve)
    ///
    /// error = distance(pm, (p0+p1)/2)
    ///
    /// Determinism:
    /// - always split at sm = (s0+s1)/2
    /// - recurse left first, then right
    ///
    /// Boundaries:
    /// - always include s=0 and s=1
    /// - respect maxDepth and maxSamples; when hit, we "forcedStop" and accept the segment
    private func adaptiveSamples(
        config: SamplingConfig,
        positionAt: PositionAtS,
        railProbe: (any RailProbe)?
    ) -> SamplingResult {

        // Accumulate accepted endpoints; we'll sort+dedup at the end.
        var acceptedS: [Double] = []
        acceptedS.reserveCapacity(min(config.maxSamples, 1024))

        var trace: [SampleDecision] = []
        trace.reserveCapacity(1024)

        var stats = SamplingStats()

        // Always include endpoints (Rule 0).
        acceptedS.append(0.0)
        acceptedS.append(1.0)

        func recordWorst(flatnessErr: Double) {
            if flatnessErr > stats.worstFlatnessErr { stats.worstFlatnessErr = flatnessErr }
        }

        /// Accept a segment [s0,s1] and ensure its endpoints are in the accepted set.
        func acceptSegment(s0: Double, s1: Double, depth: Int, reasons: [SampleReason], errors: SampleErrors, action: SampleAction) {
            stats.acceptedSegments += 1
            stats.maxDepthReached = max(stats.maxDepthReached, depth)

            // Endpoints will be de-duplicated later.
            acceptedS.append(s0)
            acceptedS.append(s1)

            let sm = 0.5 * (s0 + s1)
            trace.append(SampleDecision(
                t0: s0, t1: s1, tm: sm, depth: depth,
                action: action,
                reasons: reasons,
                errors: errors
            ))
        }

        /// Decide if we should subdivide based on skeleton flatness only.
        func flatnessError(s0: Double, sm: Double, s1: Double) -> Double {
            let p0 = positionAt(s0)
            let pm = positionAt(sm)
            let p1 = positionAt(s1)
            return ErrorMetrics.midpointDeviation(p0: p0, pm: pm, p1: p1)
        }

        /// Recursive subdivision driver.
        func recurse(s0: Double, s1: Double, depth: Int) {
            let sm = 0.5 * (s0 + s1)

            // If segment is degenerate in parameter space, accept.
            if abs(s1 - s0) <= config.tEps {
                acceptSegment(
                    s0: s0, s1: s1, depth: depth,
                    reasons: [.forcedEndpoint],
                    errors: SampleErrors(),
                    action: .accepted
                )
                return
            }

            let err = flatnessError(s0: s0, sm: sm, s1: s1)
            recordWorst(flatnessErr: err)

            var needsSubdivision = false
            var reasons: [SampleReason] = []
            var errors = SampleErrors()

            // Rule 1: path flatness
            if err > config.flatnessEps {
                needsSubdivision = true
                reasons.append(.subdividePathFlatness(err: err))
                errors.flatnessErr = err
            }

            // Rule 2: rail deviation
            if let railProbe = railProbe {
                let rails0 = railProbe.rails(atGlobalT: s0)
                let railsM = railProbe.rails(atGlobalT: sm)
                let rails1 = railProbe.rails(atGlobalT: s1)

                let railErr = ErrorMetrics.railDeviation(
                    l0: rails0.left, lm: railsM.left, l1: rails1.left,
                    r0: rails0.right, rm: railsM.right, r1: rails1.right
                )

                stats.worstRailErr = max(stats.worstRailErr, railErr)

                if railErr > config.railEps {
                    needsSubdivision = true
                    reasons.append(.subdivideRailDeviation(err: railErr))
                    errors.railErr = railErr
                }
            }

            // ✅ Accept ONLY if all rules passed
            if !needsSubdivision {
                acceptSegment(
                    s0: s0, s1: s1, depth: depth,
                    reasons: [.forcedEndpoint],
                    errors: errors,
                    action: .accepted
                )
                return
            }

            // Needs subdivision.
            stats.subdividedSegments += 1
            trace.append(SampleDecision(
                t0: s0, t1: s1, tm: sm, depth: depth,
                action: .subdivided,
                reasons: reasons,
                errors: errors
            ))

            // Guardrails: maxDepth
            if depth >= config.maxDepth {
                stats.forcedStops += 1
                acceptSegment(
                    s0: s0, s1: s1, depth: depth,
                    reasons: [.maxDepthHit, .subdividePathFlatness(err: err)],
                    errors: SampleErrors(flatnessErr: err),
                    action: .forcedStop
                )
                return
            }

            // Guardrails: maxSamples (conservative)
            // Subdividing adds at most one *new* sample (the midpoint) per accepted leaf,
            // but since we store endpoints then de-dup, use a conservative check.
            if acceptedS.count >= config.maxSamples * 2 {
                stats.forcedStops += 1
                acceptSegment(
                    s0: s0, s1: s1, depth: depth,
                    reasons: [.maxSamplesHit, .subdividePathFlatness(err: err)],
                    errors: SampleErrors(flatnessErr: err),
                    action: .forcedStop
                )
                return
            }

            // Deterministic recursion
            recurse(s0: s0, s1: sm, depth: depth + 1)
            recurse(s0: sm, s1: s1, depth: depth + 1)
            return

        }

        // Kick it off.
        recurse(s0: 0.0, s1: 1.0, depth: 0)

        // Finalize: sort, de-dup (epsilon), clamp to [0,1]
        let ts = finalizeSamples(acceptedS, tEps: config.tEps, maxSamples: config.maxSamples)

        // Validate invariants (throwing here would be annoying in production; keep it non-throwing).
        // In tests, you can call SamplingInvariants.validate(ts:maxSamples:tEps:) explicitly.

        return SamplingResult(ts: ts, trace: trace, stats: stats)
    }

    private func finalizeSamples(_ raw: [Double], tEps: Double, maxSamples: Int) -> [Double] {
        var xs = raw.map { max(0.0, min(1.0, $0)) }
        xs.sort()

        var out: [Double] = []
        out.reserveCapacity(min(maxSamples, xs.count))

        for x in xs {
            if out.isEmpty {
                out.append(x)
            } else if x > out[out.count - 1] + tEps {
                out.append(x)
            } else {
                // within epsilon: drop
            }
            if out.count >= maxSamples { break }
        }

        // Ensure endpoints (best effort)
        if out.isEmpty { return [0.0, 1.0] }
        if abs(out.first! - 0.0) > tEps { out.insert(0.0, at: 0) }
        if abs(out.last! - 1.0) > tEps { out.append(1.0) }

        // Re-dedup after forcing endpoints, just in case.
        var out2: [Double] = []
        out2.reserveCapacity(out.count)
        for x in out {
            if out2.isEmpty || x > out2[out2.count - 1] + tEps {
                out2.append(x)
            }
        }
        return out2
    }

    // Optional: used later (Step 3+)
    public struct StrokeParamsSample: Sendable, Equatable {
        public let width: Double
        public let theta: Double
        public let offset: Double
        public init(width: Double, theta: Double, offset: Double) {
            self.width = width
            self.theta = theta
            self.offset = offset
        }
    }
}
