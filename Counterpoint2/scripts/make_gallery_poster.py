#!/usr/bin/env python3
import os
import sys
import subprocess
from pathlib import Path

try:
    import cairosvg  # type: ignore
    from PIL import Image, ImageDraw, ImageFont  # type: ignore
except Exception as exc:
    print(f"error: missing dependencies (cairosvg, pillow): {exc}", file=sys.stderr)
    sys.exit(1)

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "out"
GALLERY_DIR = OUT_DIR / "gallery"
POSTER_DIR = OUT_DIR / "poster"
POSTER_DIR.mkdir(parents=True, exist_ok=True)

subprocess.check_call(["swift", "run", "cp2-cli", "--gallery-lines-both", "--out", str(GALLERY_DIR)], cwd=str(ROOT))

straight_dir = GALLERY_DIR / "straight"
wavy_dir = GALLERY_DIR / "wavy"
straight_files = sorted(straight_dir.glob("*.svg"))
if not straight_files:
    print(f"error: no straight SVGs found in {straight_dir}", file=sys.stderr)
    sys.exit(1)

tile_width = 2000
tile_height = 700
rows = []

for straight_svg in straight_files:
    base = straight_svg.stem
    base_no_ver = base[:-3] if base.endswith(".v0") else base
    wavy_svg = wavy_dir / f"{base_no_ver}_wavy.v0.svg"
    if not wavy_svg.exists():
        print(f"error: missing wavy SVG for {base}: {wavy_svg}", file=sys.stderr)
        sys.exit(1)

    straight_png = POSTER_DIR / f"{base_no_ver}_straight.png"
    wavy_png = POSTER_DIR / f"{base_no_ver}_wavy.png"

    cairosvg.svg2png(url=str(straight_svg), write_to=str(straight_png), output_width=tile_width)
    cairosvg.svg2png(url=str(wavy_svg), write_to=str(wavy_png), output_width=tile_width)

    straight_img = Image.open(straight_png).convert("RGB")
    wavy_img = Image.open(wavy_png).convert("RGB")

    straight_img = straight_img.resize((tile_width, tile_height))
    wavy_img = wavy_img.resize((tile_width, tile_height))

    row = Image.new("RGB", (tile_width * 2, tile_height), "white")
    row.paste(straight_img, (0, 0))
    row.paste(wavy_img, (tile_width, 0))
    rows.append(row)

poster = Image.new("RGB", (tile_width * 2, tile_height * len(rows)), "white")
for i, row in enumerate(rows):
    poster.paste(row, (0, i * tile_height))

poster_png = POSTER_DIR / "gallery_poster.png"
poster_pdf = POSTER_DIR / "gallery_poster.pdf"
poster.save(poster_png)
poster.save(poster_pdf)

print(f"poster written: {poster_png}")
