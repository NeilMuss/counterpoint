# Gallery: Straight Line Series

All fixtures share the same render/world frame and a single horizontal heartline from (0,0) to (460,0). Base widths are 50/50 unless specified.

- line_01_default.v0.json — Butt/butt, constant symmetric width.
- line_02_roundcap_end.v0.json — End cap round, start butt.
- line_03_ramp_symmetric.v0.json — Symmetric width ramp 50 → 62.5.
- line_04_ramp_left_only.v0.json — Left-side ramp only (right constant).
- line_05_piecewise_symmetric.v0.json — Piecewise symmetric widths at t=0,0.33,0.66,1.0.
- line_06_ramp_alpha.v0.json — Symmetric ramp with alpha easing.
- line_07_piecewise_alpha_middle.v0.json — Piecewise widths with alpha applied only to the middle segment.
- line_08_fillet_left.v0.json — End fillet (left corner), start butt.
- line_09_fillet_both.v0.json — End fillet (both corners), start butt.
- line_10_mixed_round_fillet.v0.json — Start round, end fillet (both).
- line_11_asym_ramp_fillet_right.v0.json — Left ramp 50 → 70, right constant, end fillet (right).
- line_12_staggered_ramps.v0.json — Staggered left/right ramps (left at t=0.40, right at t=0.60).
- line_14_offset.v0.json — Constant widths with center offset = 10.

Wavy clones:

- line_01_default_wavy.v0.json — Wavy heartline clone of line_01_default.
- line_02_roundcap_end_wavy.v0.json — Wavy heartline clone of line_02_roundcap_end.
- line_03_ramp_symmetric_wavy.v0.json — Wavy heartline clone of line_03_ramp_symmetric.
- line_04_ramp_left_only_wavy.v0.json — Wavy heartline clone of line_04_ramp_left_only.
- line_05_piecewise_symmetric_wavy.v0.json — Wavy heartline clone of line_05_piecewise_symmetric.
- line_06_ramp_alpha_wavy.v0.json — Wavy heartline clone of line_06_ramp_alpha.
- line_07_piecewise_alpha_middle_wavy.v0.json — Wavy heartline clone of line_07_piecewise_alpha_middle.
- line_08_fillet_left_wavy.v0.json — Wavy heartline clone of line_08_fillet_left.
- line_09_fillet_both_wavy.v0.json — Wavy heartline clone of line_09_fillet_both.
- line_10_mixed_round_fillet_wavy.v0.json — Wavy heartline clone of line_10_mixed_round_fillet.
- line_11_asym_ramp_fillet_right_wavy.v0.json — Wavy heartline clone of line_11_asym_ramp_fillet_right.
- line_12_staggered_ramps_wavy.v0.json — Wavy heartline clone of line_12_staggered_ramps.
- line_14_offset_wavy.v0.json — Wavy heartline clone of line_14_offset.

Render all:

```bash
for f in Fixtures/glyphs/gallery_lines/*.json; do
  swift run cp2-cli "$f" --out "out/gallery/$(basename "${f%.json}").svg"
done
```
