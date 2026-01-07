## Counterpoint Geometry + SVG Rendering Context

This repo uses simple polygon types in `counterpoint/Sources/Domain/Geometry.swift`:

- `Point`: `{ x: Double, y: Double }`
- `Ring`: typealias for `[Point]`
- `Polygon`: `outer: Ring`, `holes: [Ring]`
- `PolygonSet`: typealias for `[Polygon]`

SVG rendering for these types happens in
`counterpoint/Sources/CounterpointCLI/Support/SVGPathBuilder.swift`:

- `pathData(for polygon: Polygon)`:
  - Builds an SVG `<path>` with `fill-rule="evenodd"`.
  - Converts `outer` and `holes` via `ringPath(_:)`.
- `ringPath(_ ring: Ring)`:
  - Converts points to an `M/L/Z` path string.
  - Ensures closure by appending the first point if needed.
- `svgDocument(...)`:
  - Wraps all polygon paths into an `<svg>` root with computed viewBox and optional overlays.

If you need the exact Swift code, reference those files directly.

## Envelope Output

The envelope/stroke pipeline returns a `PolygonSet` (array of `Polygon`).
In some debug contexts you may see intermediate “rings” (arrays of `Ring`)
before they are assembled into `PolygonSet` and/or unioned.
