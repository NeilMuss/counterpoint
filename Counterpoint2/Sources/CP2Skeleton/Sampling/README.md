# CP2 Sampling (Global-T)

This folder defines how Counterpoint2 chooses sample positions along `global-t`
(i.e., the arc-length parameterization of the skeleton).

Design goals:
- Deterministic (same inputs → same samples)
- Explainable (returns a trace of *why* it subdivided)
- Testable (pure metrics + fixture-based tests)
- Bounded (maxDepth, maxSamples)

Files:
- SamplingConfig.swift — all knobs in one place
- SamplingInvariants.swift — what must always be true
- SamplingTrace.swift — the “why” data model
- SamplingResult.swift — result + stats
- ErrorMetrics.swift — pure error math
- RailProbe.swift — adapter for computing left/right rails at a given t
- GlobalTSampler.swift — deterministic recursion that produces the sample list
