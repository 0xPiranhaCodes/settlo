#!/usr/bin/env python3
"""Size the owner's SabkiJeb logo for the site without redrawing it."""
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
out = ROOT / 'site/images'
logo = Image.open(ROOT / 'design/brand/website/sabkijeb-logo.png').convert('RGB')


def sized(size, rounded=True):
    image = logo.resize((size, size), Image.Resampling.LANCZOS)
    if not rounded:
        return image
    # Header and browser marks get the app-icon corner; the artwork is full bleed.
    mask = Image.new('L', (size * 4, size * 4))
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size * 4 - 1, size * 4 - 1), radius=size * 0.9, fill=255)
    image.putalpha(mask.resize((size, size), Image.Resampling.LANCZOS))
    return image


sized(108).save(out / 'mark.png', optimize=True)
sized(64).save(out / 'favicon.png', optimize=True)
sized(48).save(ROOT / 'site/favicon.ico', sizes=[(16, 16), (32, 32), (48, 48)])
# A touch icon is opaque; iOS applies its own mask.
sized(180, rounded=False).save(out / 'apple-touch-icon.png', optimize=True)
