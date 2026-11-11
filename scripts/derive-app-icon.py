#!/usr/bin/env python3
"""Derive launcher inputs from the unchanged owner artwork (Pillow + NumPy).

Use scripts/regenerate-app-icons.py to also run the platform generator.
No drawing: remove the flat matte, preserving the original shaded S pixels.
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'app/assets/icon'
BG = (10, 11, 13)
source = Image.open(OUT / 'owner-icon.png').convert('RGBA')
assert source.size == (1024, 1024)
flat = Image.new('RGBA', source.size, BG + (255,))
flat.alpha_composite(source)
flat = flat.convert('RGB')
flat.save(OUT / 'opaque.png')

# Recover edge coverage from nearby gold pixels. Unmatting then compositing on
# the original background reproduces the supplied image to rounding precision.
rgb = np.array(flat, dtype=float)
delta = rgb - np.array(BG)
strength = np.max(delta, axis=2)
nearby = np.array(Image.fromarray(strength.astype('uint8')).filter(ImageFilter.MaxFilter(5)), dtype=float)
alpha = np.divide(strength, nearby, out=np.zeros_like(strength), where=nearby > 0)
alpha[strength >= 100] = 1
color = np.array(BG) + np.divide(delta, alpha[:, :, None], out=np.zeros_like(delta), where=alpha[:, :, None] > 0)
rgba = np.dstack((np.clip(np.rint(color), 0, 255), np.rint(alpha * 255))).astype('uint8')
foreground = Image.fromarray(rgba)

# Fit all nontransparent pixels inside a centered 66%-diameter safe circle.
y, x = np.nonzero(rgba[:, :, 3])
radius = np.sqrt((x - 511.5)**2 + (y - 511.5)**2).max()
scale = min(1, (1024 * .33 - 4) / radius)  # resampling fringe margin
size = round(1024 * scale)
small = foreground.resize((size, size), Image.Resampling.LANCZOS)
adaptive = Image.new('RGBA', source.size)
adaptive.alpha_composite(small, ((1024-size)//2, (1024-size)//2))
adaptive.save(OUT / 'adaptive-foreground.png')
mono = Image.new('RGBA', source.size, (255, 255, 255, 0))
mono.putalpha(adaptive.getchannel('A'))
mono.save(OUT / 'monochrome.png')
print(f'Foreground scale: {scale:.6f}; original bounds: {foreground.getbbox()}')
