#!/usr/bin/env python3
"""Derive launcher inputs from the unchanged owner artwork (Pillow + NumPy).

Use scripts/regenerate-app-icons.py to also run the platform generator.
No drawing: remove the white matte, preserving the original mark pixels.
"""
import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--margin', type=float, default=.18,
                    help='white on each side of the mark, as a fraction of the icon width')
margin = parser.parse_args().margin
assert 0 <= margin < .5

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'app/assets/icon'
source = Image.open(OUT / 'app-icon-v2.png')
assert source.mode == 'RGB' and source.size[0] == source.size[1] >= 1024

# Recover edge coverage from nearby mark pixels. Unmatting then compositing on
# white reproduces the supplied image within the zeroed ringing threshold.
rgb = np.array(source, dtype=float)
delta = 255 - rgb
strength = np.max(delta, axis=2)
strength[strength < 8] = 0  # JPEG ringing in the white matte
nearby = np.array(Image.fromarray(strength.astype('uint8')).filter(ImageFilter.MaxFilter(5)), dtype=float)
alpha = np.divide(strength, nearby, out=np.zeros_like(strength), where=nearby > 0)
# Solid mark pixels, closed over the JPEG dip along the gold/black seams.
solid = Image.fromarray(((strength >= 100) * 255).astype('uint8'))
alpha[np.array(solid.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.MinFilter(3))) > 0] = 1
color = 255 - np.divide(delta, alpha[:, :, None], out=np.zeros_like(delta), where=alpha[:, :, None] > 0)
rgba = np.dstack((np.clip(np.rint(color), 0, 255), np.rint(alpha * 255))).astype('uint8')
a = rgba[:, :, 3:] / 255
assert np.abs(rgba[:, :, :3] * a + 255 * (1 - a) - rgb).max() < 8, 'unmatte round trip'
y, x = np.nonzero(rgba[:, :, 3])
foreground = Image.fromarray(rgba[y.min():y.max() + 1, x.min():x.max() + 1])
w, h = foreground.size
# The mark's longer side spans 1 - 2*margin of the icon; the artwork alone
# spans `given`, so the adaptive layer shrinks by the same proportion.
given = max(w, h) / source.size[0]
shrink = (1 - 2 * margin) / given

# iOS and legacy Android: the mark centred on white.
side = round(1024 * (1 - 2 * margin))
mark = foreground.resize((round(w * side / max(w, h)), round(h * side / max(w, h))), Image.Resampling.LANCZOS)
padded = Image.new('RGBA', (1024, 1024), 'white')
padded.alpha_composite(mark, ((1024 - mark.width) // 2, (1024 - mark.height) // 2))
padded.convert('RGB').save(OUT / 'app-icon.png')

# Fit all nontransparent pixels of the trimmed mark inside a centered
# 66%-diameter safe circle on a 1024 canvas, then apply the same shrink.
radius = np.sqrt((x - x.min() - (w - 1) / 2)**2 + (y - y.min() - (h - 1) / 2)**2).max()
scale = min(1, shrink) * (1024 * .33 - 4) / radius  # resampling fringe margin
small = foreground.resize((round(w * scale), round(h * scale)), Image.Resampling.LANCZOS)
adaptive = Image.new('RGBA', (1024, 1024))
adaptive.alpha_composite(small, ((1024 - small.width) // 2, (1024 - small.height) // 2))
adaptive.save(OUT / 'adaptive-foreground.png')
mono = Image.new('RGBA', adaptive.size, (255, 255, 255, 0))
mono.putalpha(adaptive.getchannel('A'))
mono.save(OUT / 'monochrome.png')
print(f'Mark span: {given:.4f} -> {1 - 2 * margin:.4f}; foreground scale: {scale:.6f}; trimmed mark: {w}x{h}')
