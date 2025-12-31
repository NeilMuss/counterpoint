# Counterpoint

Core prototype for a macOS Swift "Font Design App" stroke engine. This repository is a pure, deterministic, JSON-serializable core that renders a rectangular counterpoint (pen tip) swept along a Bezier skeleton path. No UI, no AppKit, no hidden state.

## Noordzij Mental Model
The stroke is a pen tip (here, a rectangle) swept along a skeleton path. Width, height, and rotation vary along the path, and the outline is built from stamped rectangles that are later unioned.

## Architecture Boundaries
- `Sources/Domain`: Pure entities + protocols. No UI, no side effects, JSON-ready `Codable` structs.
- `Sources/UseCases`: Orchestrates sampling, parameter evaluation, and stroke outlining.
- `Sources/Adapters`: Pluggable geometry backend (polygon union). Current adapter is pass-through.

## v0 Behavior
- Skeleton: Bezier paths with cubic segments.
- Sampling: flatten cubic to polyline (flatness tolerance), resample by arc-length-ish spacing, refine when rotation changes too fast.
- Stroke: stamp rectangles at samples and union into output polygon rings.
- Output: array of closed rings (polygons) with deterministic ordering.

## Sampling Details
- Flatten each cubic until control points are within a flatness tolerance of the chord.
- Resample polyline by length with `spacing <= min(width, height) / 4` (capped by `SamplingSpec.baseSpacing`).
- Refine when `|deltaRotation| > 5°` between adjacent samples (configurable).
- If tangent magnitude is near zero, reuse the prior tangent direction.

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
  "angleMode": "absolute",
  "sampling": {
    "baseSpacing": 2.0,
    "flatnessTolerance": 0.5,
    "rotationThresholdDegrees": 5.0,
    "minimumSpacing": 0.0001
  }
}
```

## Tests
Run tests:

```
swift test
```

Tests are fast, deterministic, and validate:
- Straight line bounds at `theta = 0` and `theta = pi/2`
- L-shaped skeleton produces closed rings
- Tangent-relative rotation behavior
- Width variation expanding bounds
- Angle unwrap across the +/-pi boundary

## Extending Later
- Alpha biasing and other counterpoint shapes (circle, union-of-circles brush)
- Whitespace as first-class objects
- Strict DAG evaluation for derived values
- Scriptable hooks via JSON-driven evaluation
- Swap in a robust polygon union adapter in `Sources/Adapters`

## Notes on Geometry
The current `PassthroughPolygonUnioner` does not perform true polygon boolean union. It returns the stamped rectangles as independent rings for clarity and determinism in v0 tests. Swap this adapter for a real union implementation when needed.

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
