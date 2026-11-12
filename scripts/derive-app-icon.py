#!/usr/bin/env python3
"""Derive launcher inputs from the unchanged owner artwork (Pillow + NumPy).

Use scripts/regenerate-app-icons.py to also run the platform generator.
No drawing: remove the white matte, preserving the original mark pixels.
--full-bleed instead takes the SabkiJeb logo, which brings its own dark
background, and lifts its mark off that background for the Android layers.
"""
import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--margin', type=float, default=.18,
                    help='white on each side of the mark, as a fraction of the icon width')
parser.add_argument('--full-bleed', action='store_true',
                    help='source is sabkijeb-logo.png on its own background (use --margin 0)')
args = parser.parse_args()
margin = args.margin
assert 0 <= margin < .5

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'app/assets/icon'


def full_bleed():
    source = Image.open(OUT / 'sabkijeb-logo.png')
    assert source.mode == 'RGB' and source.size[0] == source.size[1] >= 1024
    rgb = np.array(source, dtype=float)
    edge = np.concatenate([rgb[:20], rgb[-20:], rgb[:, :20].swapaxes(0, 1), rgb[:, -20:].swapaxes(0, 1)])
    bg = np.median(edge.reshape(-1, 3), axis=0)  # deep forest, #01351B
    print('Adaptive background: #%02X%02X%02X' % tuple(int(v) for v in bg))

    # iOS and legacy Android: the logo itself, opaque, `margin` of background per side.
    side = round(1024 * (1 - 2 * margin))
    icon = Image.new('RGB', (1024, 1024), tuple(int(v) for v in bg))
    icon.paste(source.resize((side, side), Image.Resampling.LANCZOS), ((1024 - side) // 2,) * 2)
    icon.save(OUT / 'app-icon.png')

    # Colour-to-alpha against the background, so the cutout recomposites over
    # the adaptive background without a dark halo. Away from the mark only
    # lighter pixels count (its glow); the darker vignette stays behind.
    mark = np.abs(rgb - bg).max(axis=2) > 30
    near = np.array(Image.fromarray(mark).filter(ImageFilter.MaxFilter(15))) > 0
    lift = np.clip(rgb - bg, 0, None) / (255 - bg)
    dark = np.clip(bg - rgb, 0, None) / np.maximum(bg, 1)
    alpha = np.maximum(lift.max(axis=2), np.where(near, dark[:, :, 1:].max(axis=2), 0))
    alpha[(alpha < .04) & ~near] = 0  # vignette, up to 7 levels above the corners
    color = bg + np.divide(rgb - bg, alpha[:, :, None], out=np.zeros_like(rgb), where=alpha[:, :, None] > 0)
    rgba = np.dstack((np.clip(np.rint(color), 0, 255), np.rint(alpha * 255))).astype('uint8')
    a = rgba[:, :, 3:] / 255
    over = rgba[:, :, :3] * a + bg * (1 - a)
    assert np.abs(over - rgb)[near].max() < 3, 'cutout round trip over the background'

    # The whole cutout, glow included, fits the centred 66% safe circle.
    y, x = np.nonzero(rgba[:, :, 3])
    c = (source.size[0] - 1) / 2
    radius = np.sqrt((x - c)**2 + (y - c)**2).max()
    scale = (1024 * .33 - 4) / radius  # resampling fringe margin
    n = round(source.size[0] * scale)
    adaptive = Image.new('RGBA', (1024, 1024))
    adaptive.alpha_composite(Image.fromarray(rgba).resize((n, n), Image.Resampling.LANCZOS), ((1024 - n) // 2,) * 2)
    adaptive.save(OUT / 'adaptive-foreground.png')

    # Monochrome: the check and pocket without the glow. The translucent
    # pocket dips below the threshold, so fill enclosed holes, then keep the
    # shadow slits (darker than the background) that part check from pocket.
    solid = Image.fromarray((np.abs(rgb - bg).max(axis=2) > 100).astype('uint8') * 255).copy()  # floodfill needs its own buffer
    ImageDraw.floodfill(solid, (0, 0), 128)
    shape = Image.fromarray(((np.array(solid) != 128) * 255).astype('uint8'))
    inside = np.array(shape.filter(ImageFilter.MinFilter(25))) > 0  # not the outline's own shadow
    cut = np.array(shape) > 0
    cut &= ~(inside & (rgb[:, :, 1] < bg[1] - 8))
    silhouette = Image.fromarray(cut.astype('uint8') * 255).filter(ImageFilter.GaussianBlur(1.5))
    silhouette = silhouette.resize((n, n), Image.Resampling.LANCZOS)
    mono = Image.new('RGBA', (1024, 1024), (255, 255, 255, 0))
    mono.paste((255, 255, 255, 255), ((1024 - n) // 2,) * 2, silhouette)
    mono.save(OUT / 'monochrome.png')
    # In-app mark: the whole logo in a circle, 30pt at 1x/2x/3x (#203).
    brand = ROOT / 'packages/core/assets/brand'
    for scale_dir, px in (('', 30), ('2.0x/', 60), ('3.0x/', 90)):
        disc = Image.new('L', (px * 8, px * 8))
        ImageDraw.Draw(disc).ellipse((0, 0, px * 8 - 1, px * 8 - 1), fill=255)
        logo = source.resize((px, px), Image.Resampling.LANCZOS).convert('RGBA')
        logo.putalpha(disc.resize((px, px), Image.Resampling.LANCZOS))
        logo.save(brand / f'{scale_dir}sabkijeb_mark.png')
    print(f'Logo margin: {margin:.4f}; foreground scale: {scale:.6f}; cutout radius: {radius / source.size[0]:.4f}')


if args.full_bleed:
    full_bleed()
    raise SystemExit
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
