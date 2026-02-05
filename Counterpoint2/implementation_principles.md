Counterpoint2 implementation principles (current state)

1) Vector‑first outline construction
- Boundary soup is built from explicit rail offsets + caps.
- traceLoops deterministically walks the soup into ordered rings.
- No rasterization and no polygon union in the critical outline path.

2) Determinism by construction
- CP2Geometry provides explicit epsilons and stable Vec2/AABB primitives.
- Global‑t parameterization uses fixed arc‑length sampling tables.
- Adaptive sampling is the default mode; sample lists are strictly increasing and epsilon‑deduped.
- All debug overlays are deterministic (sorted, stable formatting).

3) Clean architecture boundaries
- CP2Geometry: pure numeric types + render settings + ink primitives.
- CP2Domain: immutable pipeline artifacts + deterministic contracts + invariants.
- CP2Skeleton: path primitives, parameterization, sampling, rails, boundary soup, traceLoops.
- cp2-cli: JSON parsing, CLI flags, SVG rendering, logging.

4) Rail model correctness (major fix)
- Rails are computed from the cross‑axis:
  left = C + vRot * widthLeft
  right = C - vRot * widthRight
- This replaces the earlier diagonal corner selection that caused the J teleport chord.

5) Param tracks and interpolation
- widthLeft/widthRight use cubic Hermite with monotone limiting by default.
- Keyframes can declare knots: smooth / cusp / hold / snap.
- interpToNext.alpha scales the outgoing tangent (shape change without endpoint drift).

6) Debugging as a first‑class workflow
- compare / compareAll presets with strict layer ordering:
  reference fill → ink fill → reference outline → debug overlays
- keyframe markers (shape‑coded)
- paramsPlot mini‑graphs for width tracks and knot type
- ring diagnostics (ringSpine, ringJump, traceJumpStep)
- sampling diagnostics (samplingWhy + solo mode)

7) Contracts at boundaries
- Pipeline stages exchange immutable artifacts with explicit `validate()` invariants.
- Determinism is carried in‑band via DeterminismPolicy (eps + stable sort policy).
- Debug data is structured (DebugBundle), not prints in core modules.

8) Fixtures and regression harness
- Deterministic fixtures for line, scurve, fast_scurve, poly3, J stem/hook/serif.
- Tests assert closed rings, non‑zero area, deterministic vertex lists, bounded scallops.

Current output path
SkeletonPath → parameterization → adaptive sampling → rails → boundary soup → traceLoops → SVG.

Known limitations (explicit)
- Counter subtraction is scaffolded: counters can be parsed and visualized but are not yet subtracted.
- Terminal/appendage vocabulary (ball/elliptical terminals) is pending.
