# CP2 Sampling (Global-T)

This folder defines how Counterpoint2 chooses sample positions along **globalT**
(the arc-length parameterization of the skeleton). The goal is deterministic,
explainable sampling that can be debugged and tuned without guessing.

## Pipeline (high level)

```
SkeletonPath
  -> SkeletonPathParameterization (arc-length)
  -> GlobalTSampler (adaptive or fixed)
  -> left/right rails
  -> boundary soup
  -> loop trace -> outline ring
```

## Why the refactor happened

The original sampling was a mix of heuristics that were hard to attribute.
Symptoms included:
- scallops on fast curves
- hairline kinks near joins
- “mystery” over/under-sampling

The refactor makes **every subdivision explainable** by an explicit trigger
and makes it trivial to render *why* dots in the SVG.

## What GlobalTSampler does

GlobalTSampler is a deterministic recursive subdivider. For a segment
`t0..t1`, it evaluates the midpoint `tm` and checks explicit criteria.
If any trigger exceeds its epsilon, it subdivides. Otherwise it accepts.

Primary triggers:
1) **Path flatness** — midpoint-to-chord deviation
2) **Rail deviation** — left/right rails bend even if the centerline is straight

Guardrails:
- maxDepth
- maxSamples
- epsilon collapse (dedupe/merge)

### Subdivision intuition (ASCII)

```
[t0--------------t1]
       tm
if err(tm) > eps:
    recurse [t0..tm] + [tm..t1]
else:
    accept [t0..t1]
```

## Data model

### SamplingConfig
All tuning knobs in one place:
- mode: fixed(count) or adaptive
- flatnessEps
- railEps
- maxDepth
- maxSamples

### SamplingResult
```
SamplingResult
  ts     : [Double]      // final, sorted, unique samples
  trace  : [SampleDecision]
  stats  : SamplingStats
```

### SampleDecision
Each decision includes:
- t0, t1, tm
- depth
- action: accepted | subdivided | forcedStop
- reasons: [SampleReason]
- errors: SampleErrors (flatness, rail, param)

## Debug hook threading

```
boundarySoupGeneral(..., debugSampling: { SamplingResult in
    // cp2-cli stores this in SweepResult
})
```

cp2-cli then renders the sampling trace as **why dots** in SVG.

## “Why dots” overlay

The overlay draws dots at subdivision midpoints, color-coded by trigger:
- flatness  -> red
- rail      -> blue
- both      -> purple
- forced    -> gray

Dot radius scales with normalized severity (err / eps).
The top N worst dots are labeled with rank + reason + severity.

Enable in CLI:

```
cp2-cli --debug-sampling-why --adaptive-sampling --debug-svg
```

## Flatness vs rail deviation (intuition)

```
Centerline straight, width changes:

  |\            /|
  | \          / |
  |  \________/  |
      ^ rail bends even if centerline doesn’t

Flatness checks centerline bend.
Rail deviation checks how much the actual offset rails bend.
```

## Tuning guide

- **flatnessEps** controls geometric smoothness of the centerline.
  Lower -> more samples on curves.
- **railEps** controls how much rail deviation is tolerated.
  Lower -> more samples where width/angle changes cause rail bending.

Typical approach on a real glyph (e.g. Big Caslon J tail):
1) turn on `--debug-sampling-why`
2) look at dot clusters (flatness vs rail)
3) adjust eps values until dots move from “everywhere” to the few
   high-curvature / high-rail-deviation areas that matter

## File map

- SamplingConfig.swift — all knobs in one place
- SamplingInvariants.swift — must-always-hold rules
- SamplingTrace.swift — action/reason/error types
- SamplingResult.swift — output + stats
- ErrorMetrics.swift — pure error math
- RailProbe.swift — rail evaluation for the sampler
- GlobalTSampler.swift — deterministic recursion
- SamplingDebug.swift — trace -> debug points
- SamplingWhyDots.swift — trace -> “why dots” with severity
