# Counterpoint2 — Reboot Context (Jan 2026)

## Why we restarted

The original Counterpoint engine reached a structural failure mode:

- The *final outline* depended on polygon union behavior that could **hang, skip, or become nondeterministic** (notably via the `iOverlay` adapter).
- Attempts to retrofit a **raster → trace silhouette path** inside the existing architecture produced unusable output and increased complexity.
- Debugging became reactive and local: we were patching symptoms rather than enforcing global guarantees.

**Conclusion:**  
The codebase had fallen into a local minimum. The only viable path forward was a clean rebuild with strict invariants, deterministic geometry, and tests at every layer.

---

## New direction: Counterpoint2

Counterpoint2 is a **from-scratch implementation** living alongside (but not coupled to) the original engine.

### Core philosophy

- **Vector-first, Lee-style direct silhouette generation**
- Build a *boundary soup* (explicit envelope boundary segments)
- **Deterministically trace closed loops**
- **No rasterization**
- **No polygon union** in the critical path
- Tight module boundaries
- Deterministic behavior by construction
- Test-driven development at every step

This is a geometry engine, not a UI system and not a patch on the old one.

---

## What exists now (working baseline)

A new SwiftPM package at `Counterpoint2/` with the following modules:

### CP2Geometry

- `Vec2`, `AABB`, `Epsilon`
- Fully tested
- Explicit tolerances, no hidden globals

### CP2Skeleton

- `CubicBezier2`
  - evaluate
  - derivative
  - tangent
- `SkeletonPath`
  - currently: single cubic
- Deterministic **arc-length parameterization**
  - sampling table
  - tests enforce stability

### SweepTrace

- Lee-style boundary soup construction
- Sweeps a **rectangular counterpoint** along the skeleton
- For each sample:
  - compute left/right support points
- Adds simple caps
- Endpoint snapping via epsilon
- Deterministic segment walking
- Produces **exactly one closed ring**
- Deterministic ordering

### Tests (SweepTraceTests)

Hard invariants enforced by tests:

- exactly one ring
- closed loop
- non-zero area
- deterministic output (bit-identical vertex lists across runs)

### cp2-cli

- Minimal CLI for rendering
- Current demo: straight-line skeleton → `line.svg`
- Output is clean, rectangular, and visually correct

---

## Current status

```bash
cd Counterpoint2
swift test
swift run cp2-cli --out out/line.svg
```

All tests pass. Output is clean and deterministic.

This is a **known-good foundation**.

---

## Immediate next steps (agreed plan)

1. **Multi-cubic skeleton paths**
   - Preserve determinism
   - Preserve global parameterization
   - No per-segment hacks

2. **Curved skeleton sweep**
   - S-curve fixture
   - Same boundary-soup + trace method
   - No special cases

3. **Incremental Big Caslon J**
   - Stem first
   - Then hook
   - Each addition gated by tests + invariants

4. *(Optional, later)*  
   Add `CP2CLITests` to assert SVG structure (e.g. single closed path). Non-blocking.

---

## Non-goals (for now)

- No polygon union
- No raster passes
- No adaptive heuristics without proofs
- No UI abstractions
- No compatibility shims for the old engine

Counterpoint2 exists to **make the geometry correct first**.

