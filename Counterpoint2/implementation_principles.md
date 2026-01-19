Counterpoint2 implementation notes (principles in practice)

Overview
Counterpoint2 is a clean, deterministic geometry engine that implements the reboot
principles in counterpoint_2_reboot.md. This document maps those principles to
concrete code in the current Counterpoint2 package.

1) Vector-first, no raster, no union
- SweepTrace constructs a boundary soup from explicit left/right rails and caps.
- traceLoops walks the boundary soup into a closed ring (polyline only).
- There is no rasterization or polygon-union stage in the outline path.

2) Determinism by construction
- CP2Geometry defines Vec2, AABB, and Epsilon with explicit tolerances.
- SkeletonPathParameterization uses fixed sampling tables (arcSamples) and
  deterministic interpolation for arc-length mapping.
- Adaptive sampling (when enabled) is recursive with strict ordering, epsilon
  de-dupe, and explicit maxDepth/maxSamples caps.
- traceLoops uses epsilon-snapped endpoints and deterministic next-edge rules.

3) Tight module boundaries
- CP2Geometry: pure numeric types (Vec2, AABB, Epsilon).
- CP2Skeleton: path primitives (CubicBezier2, SkeletonPath) and deterministic
  parameterization + sampling helpers.
- cp2-cli: the only place that prints debug output or writes SVGs.

4) TDD + invariants
Core invariants are enforced by tests in CP2SkeletonTests:
- Single closed ring output (rings == 1).
- Closed loop with epsilon-closure.
- Non-zero area.
- Deterministic vertex list across runs.
- Arc-length mapping correctness and monotonicity.

5) Debug visibility (CLI only)
cp2-cli provides deterministic debug output:
- --debug-param: parameterization probes (globalT -> segment + localU + position).
- --debug-sweep: sweep stats, join probes (if present), bulge metrics,
  scallop metrics (raw + filtered).
- --debug-svg: optional overlay of skeleton + sample points.

6) Example fixtures as regression harness
Examples are deterministic and repeatable:
- line, scurve, fast_scurve, fast_scurve2, twoseg, jstem, j, j_serif_only, poly3,
  line_end_ramp.
- Each example has SweepTrace invariants; stress examples have scallop metrics.

7) Explicit epsilons and numeric stability
- All comparisons use explicit epsilon values (no hidden globals).
- AdaptiveSampler ensures endpoint inclusion and strictly increasing sample lists.
- Scallop metrics are computed on stripped, epsilon-closed rings.

Current output path
SkeletonPath -> parameterization -> boundary soup (rails + caps) -> traceLoops
-> single closed ring -> SVG polyline.

Non-goals (still true)
- No polygon union.
- No raster passes.
- No UI layer in core modules.
*** End Patch"}}
