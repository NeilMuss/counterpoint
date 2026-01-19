Counterpoint2 baseline (independent)

Run:
  cd Counterpoint2
  swift run cp2-cli --out out/line.svg

This produces a baseline SVG outline for a straight-line skeleton using a deterministic
boundary soup + loop tracing approach (no raster, no polygon union).
