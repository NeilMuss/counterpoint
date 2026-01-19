import CP2Geometry

public enum AdaptiveSampler {
    static let tEpsilon = 1.0e-12

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
                if !approxEqual(samples.last, b) {
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
                if !approxEqual(samples.last, b) {
                    samples.append(b)
                }
            }
        }

        subdivide(t0, t1, 0)
        return dedupeAndSort(samples, t0: t0, t1: t1)
    }
}

private func approxEqual(_ a: Double?, _ b: Double) -> Bool {
    guard let a else { return false }
    return abs(a - b) <= AdaptiveSampler.tEpsilon
}

private func dedupeAndSort(_ samples: [Double], t0: Double, t1: Double) -> [Double] {
    if samples.isEmpty {
        return [t0, t1].sorted()
    }
    var cleaned: [Double] = []
    cleaned.reserveCapacity(samples.count)
    for t in samples {
        if cleaned.isEmpty {
            cleaned.append(t)
            continue
        }
        let last = cleaned[cleaned.count - 1]
        if t - last > AdaptiveSampler.tEpsilon {
            cleaned.append(t)
        }
    }
    if let first = cleaned.first, abs(first - t0) > AdaptiveSampler.tEpsilon {
        cleaned.insert(t0, at: 0)
    }
    if let last = cleaned.last {
        if abs(last - t1) > AdaptiveSampler.tEpsilon {
            if t1 > last {
                cleaned.append(t1)
            } else {
                cleaned[cleaned.count - 1] = t1
            }
        }
    } else {
        cleaned = [t0, t1].sorted()
    }
    return cleaned
}

private func distancePointToSegment(_ p: Vec2, _ a: Vec2, _ b: Vec2) -> Double {
    let ab = b - a
    let ap = p - a
    let denom = max(Epsilon.defaultValue, ab.dot(ab))
    let t = max(0.0, min(1.0, ap.dot(ab) / denom))
    let proj = a + ab * t
    return (p - proj).length
}
