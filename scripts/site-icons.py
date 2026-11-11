#!/usr/bin/env python3
"""Size the owner's transparent website artwork without redrawing it."""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
out = ROOT / 'site/images'
for source, name in [('owner-white.png', 'mark'), ('owner-black.png', 'mark-light')]:
    image = Image.open(ROOT / 'design/brand/website' / source).convert('RGBA')
    image = image.crop(image.getbbox())
    for size, filename in [(192, f'{name}.png'), (64, f'favicon-{name}.png')]:
        mark = image.copy()
        mark.thumbnail((round(size * .88), round(size * .88)), Image.Resampling.LANCZOS)
        canvas = Image.new('RGBA', (size, size))
        canvas.alpha_composite(mark, ((size-mark.width)//2, (size-mark.height)//2))
        canvas.save(out / filename, optimize=True)
# A touch icon is opaque, unlike browser favicons and header artwork.
Image.open(ROOT / 'app/assets/icon/opaque.png').convert('RGB').resize(
    (180, 180), Image.Resampling.LANCZOS,
).save(out / 'apple-touch-icon.png', optimize=True)
