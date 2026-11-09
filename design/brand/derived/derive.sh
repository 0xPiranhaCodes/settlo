#!/usr/bin/env bash
# Derives the launch and icon images from the owner's marks (#32). Needs ImageMagick 7.
# Run from anywhere: design/brand/derived/derive.sh
set -euo pipefail
cd "$(dirname "$0")"
gold='#D8B36A'

# Transparent gold S: the cream mark's luminance becomes the alpha (bg ~#06070B -> 0, cream -> 1), recoloured gold.
magick ../mark-cream-on-black.png -colorspace gray -level 8%,85% mask.tmp.png
magick ../mark-cream-on-black.png -fill "$gold" -colorize 100 mask.tmp.png \
  -alpha off -compose CopyOpacity -composite -trim +repage mark-gold-transparent.png
rm mask.tmp.png

# place <out> <canvas px> <mark box px>: centre the mark, scaled to fit the box, on a transparent square.
place() {
  magick mark-gold-transparent.png -resize "$3x$3" -background none -gravity center -extent "$2x$2" "$1"
}
# Android 12+ splash icon: 1152 canvas, mark inside the 768 px masked circle (box 520 keeps the diagonal < 768).
place android12-splash.png 1152 520
# Pre-12 Android and iOS launch image, used at 4x: 288 px -> 72 pt box, ~60 pt tall mark.
place splash.png 288 240
# Adaptive icon foreground: 1024 canvas (108 dp), mark inside the 66 dp safe circle (box 440 keeps the diagonal < 626).
place adaptive-foreground.png 1024 440
