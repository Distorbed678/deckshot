#!/usr/bin/env bash
# Turns the editable SVGs in assets/art into the PNGs the game loads from assets/sprites.
# LÖVE can't read SVG. Run this after changing art, and commit the PNGs. Needs rsvg-convert.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p assets/sprites
rm -f assets/sprites/*.png
for f in assets/art/*.svg; do
  name="$(basename "$f" .svg)"
  rsvg-convert --zoom=2 "$f" -o "assets/sprites/$name.png"
done
ls assets/sprites | sed 's/\.png$//' > assets/sprites/index.txt
echo "built $(wc -l < assets/sprites/index.txt) sprites"
