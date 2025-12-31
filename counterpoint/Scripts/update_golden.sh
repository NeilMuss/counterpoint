#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

specs=(
  "straight-absolute"
  "straight-tangent-relative"
  "s-curve"
  "l-shape"
)

for name in "${specs[@]}"; do
  swift run counterpoint-cli "Fixtures/specs/${name}.json" --svg "Fixtures/expected/${name}.svg" --quiet
  echo "Wrote Fixtures/expected/${name}.svg"
done
