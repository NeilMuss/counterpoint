import CP2Geometry

public enum AdaptiveSampler {
    public static func sampleCubic(
        cubic: CubicBezier2,
        t0: Double = 0.0,
        t1: Double = 1.0,
        maxDepth: Int,
        flatnessEps: Double,
        maxSamples: Int
    ) -> [Double] {
        return sampleParameter(
            t0: t0,
            t1: t1,
            maxDepth: maxDepth,
            flatnessEps: flatnessEps,
            maxSamples: maxSamples
        ) { t in
            cubic.evaluate(t)
        }
    }

    public static func sampleParameter(
        t0: Double = 0.0,
        t1: Double = 1.0,
        maxDepth: Int,
        flatnessEps: Double,
        maxSamples: Int,
        evaluate: (Double) -> Vec2
    ) -> [Double] {
        var samples: [Double] = [t0]
        samples.reserveCapacity(maxSamples)
        let maxDepthClamped = max(0, maxDepth)
        let maxSamplesClamped = max(2, maxSamples)

        func subdivide(_ a: Double, _ b: Double, _ depth: Int) {
            if samples.count >= maxSamplesClamped {
                if samples.last != b {
                    samples.append(b)
                }
                return
            }
            let pa = evaluate(a)
            let pb = evaluate(b)
            let mid = 0.5 * (a + b)
            let pm = evaluate(mid)
            let deviation = distancePointToSegment(pm, pa, pb)
            if deviation > flatnessEps && depth < maxDepthClamped {
                subdivide(a, mid, depth + 1)
                subdivide(mid, b, depth + 1)
            } else {
                if samples.last != b {
                    samples.append(b)
                }
            }
        }

        subdivide(t0, t1, 0)
        return samples
    }
}

private func distancePointToSegment(_ p: Vec2, _ a: Vec2, _ b: Vec2) -> Double {
    let ab = b - a
    let ap = p - a
    let denom = max(Epsilon.defaultValue, ab.dot(ab))
    let t = max(0.0, min(1.0, ap.dot(ab) / denom))
    let proj = a + ab * t
    return (p - proj).length
}
