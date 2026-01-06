# Counterpoint

Core prototype for a macOS Swift "Font Design App" stroke engine. This repository is a pure, deterministic, JSON-serializable core that renders a rectangular counterpoint (pen tip) swept along a Bezier skeleton path. No UI, no AppKit, no hidden state.

## Noordzij Mental Model
The stroke is a pen tip (here, a rectangle) swept along a skeleton path. Width, height, and rotation vary along the path, and the outline is built from stamped rectangles that are later unioned.

## Architecture Boundaries
- `Sources/Domain`: Pure entities + protocols. No UI, no side effects, JSON-ready `Codable` structs.
- `Sources/UseCases`: Orchestrates sampling, parameter evaluation, and stroke outlining.
- `Sources/Adapters`: Pluggable geometry backend (polygon union). Current adapter wraps `iOverlay`, with a pass-through adapter used only in tests.

## v0 Behavior
- Skeleton: Bezier paths with cubic segments.
- Sampling: flatten cubic to polyline (flatness tolerance), then adaptively refine using envelope chunkiness until tolerance or limits are met.
- Stroke: stamp counterpoint polygons (rectangle or ellipse) at samples, build bridge envelopes, add caps/joins, then union into output polygon rings.
- Output: array of closed rings (polygons) with deterministic ordering.

## Sampling Details
- Flatten each cubic until control points are within a flatness tolerance of the chord.
- Adaptive refinement: test the midpoint stamp against the envelope formed by the end stamps + bridge pieces.
- Refine when the midpoint stamp falls outside the envelope by more than `SamplingPolicy.envelopeTolerance`.
- Always split deterministically at the midpoint, left then right.
- After sampling, enforce a maximum spacing between samples (maxSpacing or baseSpacing).
- Keyframes are evaluated using arclength progress, not parametric u.
- Optional keyframeGrid mode samples directly at keyframe times (with maxSpacing coverage).

## JSON Example
Example encoding for a simple stroke spec and path:

```json
{
  "path": {
    "segments": [
      {
        "p0": {"x": 0, "y": 0},
        "p1": {"x": 33, "y": 0},
        "p2": {"x": 66, "y": 0},
        "p3": {"x": 100, "y": 0}
      }
    ]
  },
  "width": {"keyframes": [{"t": 0, "value": 10}, {"t": 1, "value": 10}]},
  "height": {"keyframes": [{"t": 0, "value": 20}, {"t": 1, "value": 20}]},
  "theta": {"keyframes": [{"t": 0, "value": 0}, {"t": 1, "value": 0}]},
  "alpha": {"keyframes": [{"t": 0, "value": 0}, {"t": 1, "value": 0}]},
  "offset": {"keyframes": [{"t": 0, "value": 0}, {"t": 1, "value": 0}]},
  "angleMode": "absolute",
  "capStyle": "round",
  "joinStyle": {"type": "miter", "miterLimit": 4.0},
  "output": {"coordinateMode": "normalized"},
  "sampling": {
    "mode": "adaptive",
    "baseSpacing": 2.0,
    "maxSpacing": 2.0,
    "flatnessTolerance": 0.5,
    "rotationThresholdDegrees": 5.0,
    "minimumSpacing": 0.0001,
    "maxSamples": 256,
    "keyframeDensity": 1
  },
  "samplingPolicy": {
    "flattenTolerance": 1.5,
    "envelopeTolerance": 1.0,
    "maxSamples": 80,
    "maxRecursionDepth": 7,
    "minParamStep": 0.01
  }
}
```

## Glyph JSON v0 (Fixed Frame / One-Way Evaluation)
- Glyph placement and metrics live only in `frame`; geometry is never translated to encode metrics.
- `derived` is an optional cache. It never feeds back into inputs or validation.
- Schema models live in `Sources/Domain/GlyphDocumentV0.swift`; validation lives in `Sources/Domain/Validation/GlyphValidation.swift`.

## Tests
Run tests:

```
swift test
```

Fast vs slow tests:
- Default `swift test` runs fast tests only.
- Slow/render-heavy tests are gated; run with `RUN_SLOW_TESTS=1 swift test`.

Tests are fast, deterministic, and validate:
- Straight line bounds at `theta = 0` and `theta = pi/2`
- L-shaped skeleton produces closed rings
- Tangent-relative rotation behavior
- Width variation expanding bounds
- Angle unwrap across the +/-pi boundary

## Extending Later
- Additional counterpoint shapes (circle, union-of-circles brush)
- Whitespace as first-class objects
- Strict DAG evaluation for derived values
- Scriptable hooks via JSON-driven evaluation
- Swap in alternative polygon union adapters in `Sources/Adapters`

## Notes on Geometry
The `IOverlayPolygonUnionAdapter` performs polygon boolean union through `iOverlay`. The `PassthroughPolygonUnioner` is retained for fast, deterministic unit tests where union results are not required.

## CLI Example
The package includes a small CLI that reads a `StrokeSpec` JSON and prints the polygon outline JSON.

From a file:

```
swift run counterpoint-cli path/to/spec.json
```

From stdin:

```
cat path/to/spec.json | swift run counterpoint-cli -
```

Built-in example:

```
swift run counterpoint-cli --example
```

S-curve example:

```
swift run counterpoint-cli --example s-curve
```

Alpha terminal example (teardrop-like terminal via keyframe alpha bias):

```
swift run counterpoint-cli --example alpha-terminal --svg alpha-terminal.svg
```

Teardrop demo (ellipse counterpoint + alpha bias):

```
swift run counterpoint-cli --example teardrop-demo --svg teardrop-demo.svg
```

Global angle S-curve demo (angle interpolated over total arc length):

```
swift run counterpoint-cli --example global-angle-scurve --svg global-angle-scurve.svg --debug-samples --show-envelope
```

S-curve playground mode (interactive CLI):

```
swift run counterpoint-cli scurve --svg scurve.svg --view envelope --envelope-mode union
```

```
swift run counterpoint-cli scurve --svg scurve.svg --view envelope,rays --angle-start 10 --angle-end 75 --angle-mode absolute --envelope-mode union
```

```
swift run counterpoint-cli scurve --svg scurve.svg --view envelope,samples --angle-start -20 --angle-end 110 --alpha-start -0.5 --alpha-end 0.5 --envelope-mode union
```

Envelope rails mode is a fast approximation and can show gaps when silhouette sidedness flips. Use union mode for correct inked envelopes.
Union mode enforces overlap/coverage to prevent dotted gaps when counterpoints rotate quickly or shrink.
Final renders can optionally fit cubic Béziers to the union boundary to remove micro-facets.
Preview quality uses adaptive sampling with a loose tolerance; final uses tighter tolerance. The `--samples` flag is treated as a max sample cap for adaptive sampling.
Union envelope mode prints diagnostics about effective sample count, envelope sides, and union components.

Scurve playground options:
```
counterpoint-cli scurve --svg <outputPath>
  [--angle-start N] [--angle-end N]
  [--size-start N] [--size-end N]
  [--aspect-start N] [--aspect-end N]
  [--width-start N] [--width-end N]
  [--height-start N] [--height-end N]
  [--alpha-start N] [--alpha-end N]
  [--angle-mode absolute|relative]
  [--samples N] [--quality preview|final]
  [--envelope-mode rails|union] [--envelope-sides N]
  [--outline-fit none|simplify|bezier] [--fit-tolerance N] [--simplify-tolerance N]
  [--view envelope,samples,rays,rails,union,centerline,offset|all|none]
  [--dump-samples <path>]
  [--no-centerline]
  [--verbose]
```

Line playground mode (same options, straight path):

```
swift run counterpoint-cli line --svg line.svg --view envelope --envelope-mode union
```

Line playground options:
```
counterpoint-cli line --svg <outputPath>
  [--angle-start N] [--angle-end N]
  [--size-start N] [--size-end N]
  [--aspect-start N] [--aspect-end N]
  [--width-start N] [--width-end N]
  [--height-start N] [--height-end N]
  [--alpha-start N] [--alpha-end N]
  [--angle-mode absolute|relative]
  [--samples N] [--quality preview|final]
  [--envelope-mode rails|union] [--envelope-sides N]
  [--outline-fit none|simplify|bezier] [--fit-tolerance N] [--simplify-tolerance N]
  [--view envelope,samples,rays,rails,union,centerline,offset|all|none]
  [--dump-samples <path>]
  [--no-centerline]
  [--verbose]
```

Outline fitting example:

```
swift run counterpoint-cli scurve --svg out.svg --view envelope --envelope-mode union --quality final --outline-fit bezier --fit-tolerance 0.5 --no-centerline
```

## Showcase / Presets
Generate a curated set of preset SVGs:

```
swift run counterpoint-cli showcase --out Fixtures/Showcase --quality final
```

Showcase goldens are not rendered during a normal test run. To run the heavy showcase tests:

```
RUN_SLOW_TESTS=1 swift test
```

Showcase commands (copy/paste):

1) Baseline broad-nib sweep (constant size/aspect)
```
swift run counterpoint-cli scurve --svg scurve_broadnib.svg --view envelope,centerline --envelope-mode union --size-start 16 --size-end 16 --aspect-start 0.8 --aspect-end 0.8 --angle-start 20 --angle-end 20
```

2) Hairline → sail (dramatic ramp, final quality)
```
swift run counterpoint-cli scurve --svg scurve_hairline_sail_final.svg --view envelope --envelope-mode union --quality final --size-start 2 --size-end 26 --aspect-start 0.35 --aspect-end 0.35 --angle-start 10 --angle-end 75
```

3) Hairline → sail, swelling earlier (alpha reduced)
```
swift run counterpoint-cli scurve --svg scurve_hairline_sail_early.svg --view envelope --envelope-mode union --alpha-start -0.4 --alpha-end 0.2 --size-start 2 --size-end 26 --aspect-start 0.35 --aspect-end 0.35 --angle-start 10 --angle-end 75
```

4) Absolute vs relative comparison
```
swift run counterpoint-cli scurve --svg scurve_absolute.svg --view envelope,rays --envelope-mode union --angle-mode absolute --angle-start 10 --angle-end 75
```
```
swift run counterpoint-cli scurve --svg scurve_relative.svg --view envelope,rays --envelope-mode union --angle-mode relative --angle-start 10 --angle-end 75
```

5) Sharp-ish vs flat brush
```
swift run counterpoint-cli scurve --svg scurve_sharp_brush.svg --view envelope --envelope-mode union --size-start 14 --size-end 14 --aspect-start 0.2 --aspect-end 0.2 --angle-start 25 --angle-end 25
```
```
swift run counterpoint-cli scurve --svg scurve_flat_brush.svg --view envelope --envelope-mode union --size-start 14 --size-end 14 --aspect-start 1.8 --aspect-end 1.8 --angle-start 25 --angle-end 25
```

6) Debug bundle (all overlays)
```
swift run counterpoint-cli scurve --svg scurve_debug_bundle.svg --view envelope,samples,rays,rails,centerline --envelope-mode union --angle-start 10 --angle-end 75
```

7) Kinked joins (rails mode)
```
swift run counterpoint-cli line --svg kink_join_round.svg --view envelope,rails --envelope-mode rails --outline-fit bezier --join round --kink --size-start 18 --size-end 18 --aspect-start 1.0 --aspect-end 1.0 --angle-start 0 --angle-end 0
```
```
swift run counterpoint-cli line --svg kink_join_bevel.svg --view envelope,rails --envelope-mode rails --outline-fit bezier --join bevel --kink --size-start 18 --size-end 18 --aspect-start 1.0 --aspect-end 1.0 --angle-start 0 --angle-end 0
```
```
swift run counterpoint-cli line --svg kink_join_miter.svg --view envelope,rails --envelope-mode rails --outline-fit bezier --join miter --miter-limit 4 --kink --size-start 18 --size-end 18 --aspect-start 1.0 --aspect-end 1.0 --angle-start 0 --angle-end 0
```

Note: join styles currently apply to the rails-derived envelope. For union mode, switch to `--envelope-mode rails` to see them.

Straight-line trumpet presets:
```
swift run counterpoint-cli line --svg line_trumpet_neutral.svg --view envelope,centerline --envelope-mode union --size-start 5 --size-end 50 --aspect-start 0.35 --aspect-end 0.35 --angle-start 30 --angle-end 30 --alpha-start 0 --alpha-end 0
```
```
swift run counterpoint-cli line --svg line_trumpet_pos.svg --view envelope,centerline --envelope-mode union --size-start 5 --size-end 50 --aspect-start 0.35 --aspect-end 0.35 --angle-start 30 --angle-end 30 --alpha-end 0.9
```
```
swift run counterpoint-cli line --svg line_trumpet_neg.svg --view envelope,centerline --envelope-mode union --size-start 5 --size-end 50 --aspect-start 0.35 --aspect-end 0.35 --angle-start 30 --angle-end 30 --alpha-start -0.9
```

One-sided modulation via offset:
```
swift run counterpoint-cli line --svg one_sided.svg --view envelope --envelope-mode union --outline-fit bezier --quality final --no-centerline --angle-start 30 --angle-end 30 --aspect-start 0.35 --aspect-end 0.35 --size-start 8 --size-end 40 --offset-start 0 --offset-end 18
```
```
swift run counterpoint-cli scurve --svg scurve_offset.svg --view envelope --envelope-mode union --outline-fit bezier --quality final --no-centerline --angle-mode relative --angle-start 20 --angle-end 75 --size-start 12 --size-end 30 --alpha-end 0.5 --offset-start 0 --offset-end 10
```

SVG output:

```
swift run counterpoint-cli --example s-curve --svg out.svg
```

```
swift run counterpoint-cli input.json --svg out.svg --padding 20
```

Bridge envelopes (on by default):

```
swift run counterpoint-cli --example s-curve --svg out.svg --no-bridges
```

Join/cap variations (via JSON):

```
swift run counterpoint-cli spec.json --svg out.svg
```

Background glyph overlay (via JSON):

```
{
  "backgroundGlyph": {
    "svgPath": "/path/to/glyph.svg",
    "fill": "#e0e0e0",
    "stroke": "#4169e1",
    "strokeWidth": 1.0,
    "opacity": 0.25,
    "zoom": 100,
    "align": "center"
  }
}
```

Centerline-only mode (glyph JSON):
- Render ink paths as thin stroked centerlines (no envelopes or fills).

```
swift run counterpoint-cli Fixtures/glyphs/J.v0.json --centerline-only --svg out/J.svg
```

Stroke preview mode (glyph JSON):
- Render ink paths as simple stroked envelopes with a constant rectangular counterpoint.
- Relative preview angles orient the nib so width stays perpendicular to the tangent (vertical stems remain broad when width > height).

```
swift run counterpoint-cli Fixtures/glyphs/J.v0.json --stroke-preview --svg out/J.svg
```

Authored strokes (glyph JSON):
- Add `type: "stroke"` items that reference one or more skeleton paths and provide param curves.
- Normal rendering produces filled outlines; `--quality final` enables union by default.

```
{
  "id": "stroke:main",
  "type": "stroke",
  "skeletons": ["ink:spine", "ink:hook"],
  "params": {
    "angleMode": "tangentRelative",
    "width":  { "keyframes": [{ "t": 0, "value": 28 }, { "t": 1, "value": 28 }] },
    "height": { "keyframes": [{ "t": 0, "value": 6 },  { "t": 1, "value": 6 }] },
    "theta":  { "keyframes": [{ "t": 0, "value": 0 },  { "t": 1, "value": 0 }] }
  },
  "samplingPolicy": {
    "flattenTolerance": 1.0,
    "envelopeTolerance": 0.75,
    "maxSamples": 320,
    "maxRecursionDepth": 10,
    "minParamStep": 0.005
  },
  "joins": {
    "capStyle": "round",
    "joinStyle": { "type": "miter", "miterLimit": 4.0 }
  }
}
```

```
swift run counterpoint-cli Fixtures/glyphs/J.v0.json --quality final --svg out/J_final.svg
```

Preview sampling controls:
- `--preview-samples N` (samples per cubic; higher is smoother)
- `--preview-quality preview|final` (affects flattening tolerance)
- `--preview-angle-mode absolute|relative` (rotate nib with tangent in relative mode)
- `--preview-angle-deg N` (angle offset in degrees; default 30)
- `--preview-width N` (preview width; default 24)
- `--preview-height N` (preview height; default 8)
- `--preview-nib-rotate-deg N` (rotate nib before angle/tangent; default 0)
- `--preview-union auto|never|always` (default never; `auto` selects based on ring count)
- `--final-union auto|never|always` (default auto; skips union if too complex)
- `--union-simplify-tol N` (default 0.75; simplify rings before union)
- `--union-max-verts N` (default 5000; cap per-ring vertices for union)
- `--union-batch-size N` (default 50; union in batches)
- `--union-area-eps N` (default 1e-6; drop tiny rings)
- `--union-weld-eps N` (default 1e-5; merge near-duplicate points)
- `--union-edge-eps N` (default 1e-5; drop tiny edges)
- `--union-min-ring-area N` (default 5.0; drop tiny rings before union)
- `--union-auto-time-budget-ms N` (default 1500; auto union bailout time budget)
- `--union-input-filter none|silhouette` (default none; keep largest rings by bbox)

Outline fitting (glyph JSON):
- `--outline-fit none|simplify|bezier` (default none)
- `--fit-tolerance N`, `--simplify-tolerance N`

Quality presets and overrides:

```
swift run counterpoint-cli spec.json --quality preview
swift run counterpoint-cli spec.json --quality final --envelope-tol 0.2 --flatten-tol 0.5 --max-samples 320
```

Angle mode override (absolute vs tangent-relative):

```
swift run counterpoint-cli --example global-angle-scurve --angle-mode relative --svg global-angle-relative.svg --debug-samples --show-envelope
```

Debug sampling overlay:

```
swift run counterpoint-cli --example teardrop-demo --svg teardrop-demo.svg --debug-samples
```

Dump samples to CSV (and sanity-check monotone runs):

```
swift run counterpoint-cli spec.json --dump-samples out/samples.csv --quiet
python3 Scripts/check_samples_csv.py out/samples.csv
```

Envelope rails in debug overlay:

```
swift run counterpoint-cli --example global-angle-scurve --svg global-angle-scurve.svg --debug-samples --show-envelope --no-rays
```

Counterpoint size override for the demo:

```
swift run counterpoint-cli --example global-angle-scurve --svg global-angle-scurve.svg --debug-samples --show-envelope --cp-size 10
```

## Bridge Envelopes
To reduce gaps and jaggies between stamped samples, the core constructs an envelope between adjacent counterpoints by connecting corresponding edges into quads (or splitting into triangles when edges invert). The union includes both stamps and bridges. Use `--no-bridges` to compare results.

## Golden Fixtures
Golden SVG fixtures live in `Fixtures/specs` and `Fixtures/expected`. Tests compare the SVG output for each spec against the expected file.

Update golden files:

```
./Scripts/update_golden.sh
```

Showcase fixtures are generated outside of tests:

```
swift run counterpoint-cli showcase --out Fixtures/Showcase --quality final
```
