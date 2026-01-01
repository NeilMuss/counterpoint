#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

specs=(
  "straight-absolute"
  "straight-tangent-relative"
  "s-curve"
  "l-shape"
  "alpha-terminal"
  "teardrop-demo"
)

for name in "${specs[@]}"; do
  echo "Generating ${name}..."
  out_path="${ROOT_DIR}/Fixtures/expected/${name}.svg"
  swift run counterpoint-cli --example "$name" --svg "$out_path" --quiet --bridges
  echo "Wrote Fixtures/expected/${name}.svg"
done
