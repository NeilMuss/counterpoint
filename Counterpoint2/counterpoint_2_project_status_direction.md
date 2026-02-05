# Counterpoint2 — Project status & direction (current)

## Status snapshot
- Deterministic vector‑first outline engine is operational.
- Pipeline: SkeletonPath → global‑t arc‑length → adaptive sampling → rails → boundary soup → traceLoops → SVG.
- Adaptive sampling is the default and includes keyframe t’s; rail‑aware refinement reduces faceting at sharp ramps.
- J is visually convincing; remaining mismatch is terminal vocabulary (ball/elliptical terminals).
- Debug overlays are stable and layered (reference fill → ink → reference outline → overlays).

## Recent fixes
- J bottom cut‑off traced to diagonal nib corner selection; fixed via cross‑axis rail offsets.
- Width tracks now use cubic Hermite (monotone) with knot semantics.
- interpToNext.alpha is tangent scaling (shape control without endpoint drift).

## Known limitations
- Counter subtraction is scaffolded only: counters are parsed and can be visualized, but subtraction is not yet implemented.
- Terminal/appendage shapes are pending.

## Direction
Next workstream: Big Caslon “e”
1) Self‑overlap correctness (winding preserved, no accidental holes)
2) Counter subtraction (non‑ink hole) — implement boolean subtraction or dedicated counter pipeline
3) Lower‑lip rounding vocabulary (appendage system)

## Refactor planning: Stage contracts
- Introduce CP2Domain artifacts as explicit, immutable contracts between stages.
- Pipeline chain: Spec → Skeleton → Parameterization → Samples → Rails → BoundarySoup → Rings → Silhouette.
- Each artifact carries DeterminismPolicy and `validate()` invariants.
- Debug is structured data (DebugBundle), not print‑side effects.

## ResolveSelfOverlap micro‑pipeline (current)
- Ring → PlanarizedSegments → HalfEdgeGraph → FaceSet → SelectionResult.
- Each stage emits a Codable artifact with invariants and optional DebugBundle payloads.
- SelectionPolicy is pluggable; current policy for line gallery is “max abs(area)”.

## Determinism doctrine
- Same JSON → same SVG bytes (stable float formatting)
- No raster or polygon union in the critical path
- Debugging is adversarial: isolate layer errors before heuristics
