# Counterpoint2 — Project status & direction

## Why the reboot still stands
The legacy engine’s final outline depended on polygon union behavior that could hang or skip unpredictably. Counterpoint2 exists to make the geometry correct first: deterministic, vector‑first, test‑locked.

## What exists now (as implemented)
- Deterministic pipeline:
  SkeletonPath → global‑t (arc‑length) → adaptive sampling → rails → boundary soup → traceLoops → SVG
- No rasterization, no polygon union in the critical outline path.
- Multi‑segment skeletons, heartlines, and named ink parts (spine/hook/etc.).

### Key fixes completed
- J bottom cut‑off traced to **diagonal nib corner selection** → fixed by cross‑axis rail offsets.
- Adaptive sampling now **includes keyframe t’s** and **rail‑aware refinement**, eliminating faceting at sharp ramps.
- Param tracks upgraded to **cubic Hermite (monotone)** by default with optional knot semantics.

### Debug workflow (deterministic)
- compare / compareAll presets with strict layer ordering:
  reference fill → ink fill → reference outline → debug overlays
- ring diagnostics: ringSpine + ringJump + traceJumpStep
- sampling diagnostics: samplingWhy + solo mode
- keyframe markers and paramsPlot overlays

## Where we are now
- Big Caslon J is typographically convincing.
- Remaining mismatch is terminal vocabulary (ball/elliptical terminal) which will be added as a first‑class appendage shape (not hacked via width).
- CLI is sufficient for engine validation; GUI/micro‑editing is the current bottleneck.

## Next up: Big Caslon “e”
We are starting a new scaffolded workstream:
1) **Self‑overlap correctness** (no unintended white holes; winding preserved)
2) **Counter subtraction** (non‑ink hole); currently stubbed as debug overlay only
3) **Lower‑lip rounding vocabulary** (future terminal/appendage system)

## Constraints we keep
- Determinism: same input JSON → same SVG bytes.
- Adaptive sampling is the only normal mode.
- Clean architecture boundaries are respected; IO/debug in CLI only.
