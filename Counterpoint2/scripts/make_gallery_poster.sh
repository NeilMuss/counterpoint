#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${ROOT_DIR}/out"
GALLERY_DIR="${OUT_DIR}/gallery"
POSTER_DIR="${OUT_DIR}/poster"

mkdir -p "${POSTER_DIR}"

if ! command -v magick >/dev/null 2>&1; then
  echo "error: ImageMagick 'magick' not found in PATH" >&2
  exit 1
fi

swift run cp2-cli --gallery-lines-both --out "${GALLERY_DIR}"

STRAIGHT_DIR="${GALLERY_DIR}/straight"
WAVY_DIR="${GALLERY_DIR}/wavy"

mapfile -t straight_files < <(ls "${STRAIGHT_DIR}"/*.svg | sort)

if [[ ${#straight_files[@]} -eq 0 ]]; then
  echo "error: no straight gallery SVGs found in ${STRAIGHT_DIR}" >&2
  exit 1
fi

rows=()
for straight_svg in "${straight_files[@]}"; do
  base="$(basename "${straight_svg}" .svg)"
  base_no_ver="${base%.v0}"
  wavy_svg="${WAVY_DIR}/${base_no_ver}_wavy.v0.svg"
  if [[ ! -f "${wavy_svg}" ]]; then
    echo "error: missing wavy SVG for ${base}: ${wavy_svg}" >&2
    exit 1
  fi
  straight_png="${POSTER_DIR}/${base}_straight.png"
  wavy_png="${POSTER_DIR}/${base}_wavy.png"
  row_png="${POSTER_DIR}/${base}_row.png"

  magick -density 300 "${straight_svg}" -background white -alpha remove -alpha off -resize 2000x -extent 2000x700 -gravity center "${straight_png}"
  magick -density 300 "${wavy_svg}" -background white -alpha remove -alpha off -resize 2000x -extent 2000x700 -gravity center "${wavy_png}"
  magick "${straight_png}" "${wavy_png}" +append "${row_png}"
  rows+=("${row_png}")
done

magick "${rows[@]}" -append "${POSTER_DIR}/gallery_poster.png"
magick "${POSTER_DIR}/gallery_poster.png" "${POSTER_DIR}/gallery_poster.pdf"

echo "poster written: ${POSTER_DIR}/gallery_poster.png"
