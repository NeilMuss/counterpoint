#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CASES=(
  "straight-absolute"
  "straight-tangent-relative"
  "s-curve"
  "l-shape"
  "alpha-terminal"
  "teardrop-demo"
  "global-angle-scurve"
  "line_asym_width"
  "line_circle_endcap"
)

for name in "${CASES[@]}"; do
  echo "Generating ${name}..."
  out_path="${ROOT_DIR}/Fixtures/expected/${name}.svg"
  spec_path="${ROOT_DIR}/Fixtures/specs/${name}.json"
  if [[ -f "$spec_path" ]]; then
    swift run counterpoint-cli "$spec_path" --svg "$out_path" --quiet --bridges
  else
    swift run counterpoint-cli --example "$name" --svg "$out_path" --quiet --bridges
  fi
  echo "Wrote Fixtures/expected/${name}.svg"
done
