#!/usr/bin/env python3
"""Compose review sheets from Linux golden PNGs; never modify the goldens."""
from collections import defaultdict
from pathlib import Path
import re
from PIL import Image, ImageDraw, ImageFont

root = Path(__file__).resolve().parent.parent
before = root / 'docs/design/145/before'
after = root / 'app/test/goldens'
out = root / 'docs/design/145/comparisons'
out.mkdir(parents=True, exist_ok=True)
font = ImageFont.truetype(str(root / 'packages/core/assets/fonts/Figtree-Regular.ttf'), 20)
groups = defaultdict(dict)
for path in sorted(after.glob('*.png')):
    match = re.fullmatch(r'(.+)_(360x800|390x844)(_text200)?_(.+)', path.stem)
    if not match:
        continue
    name, device, large, suffix = match.groups()
    if name in {'home_comparison', 'golden_harness', 'auth_welcome_pressed'}:
        continue
    theme = 'dark' if 'dark' in suffix else 'light' if 'light' in suffix else None
    if theme is None:
        continue
    state = suffix.replace(theme, '').strip('_')
    name += '_' + state if state else ''
    groups[name][(device, theme, bool(large))] = path
for name, variants in groups.items():
    rows = [(device, theme) for device in ('360x800', '390x844')
            for theme in ('dark', 'light') if (device, theme, False) in variants]
    sheet = Image.new('RGB', (1200, len(rows) * 900), '#e6e2d8')
    draw = ImageDraw.Draw(sheet)
    for row, (device, theme) in enumerate(rows):
        current = variants[(device, theme, False)]
        for col, (label, path) in enumerate([
            ('Before', before / current.name),
            ('After', current),
            ('After at 200%', variants.get((device, theme, True))),
        ]):
            x, y = col * 400, row * 900
            draw.text((x + 8, y + 6), f'{label} · {device} · {theme}', fill='#1b1b18', font=font)
            if path is not None and path.exists():
                im = Image.open(path).convert('RGB')
                sheet.paste(im, (x + (400 - im.width) // 2, y + 40))
            else:
                draw.text((x + 8, y + 80), 'No baseline for this added state', fill='#1b1b18', font=font)
    sheet.save(out / f'{name}.png', optimize=True)
print(f'Composed {len(groups)} review sheets from Linux artifacts.')

# Compare content above the navigation region, ignoring small raster noise.
from PIL import ImageChops
lines = ['# Linux pixel deltas', '',
         'Baseline: b60a54cc5872a4aa15ca93d5a7d395e9447e3e7b. '
         'Generated from Linux PNGs; RGB channel delta >8 counts as changed. '
         'The bottom 120 pixels are excluded to isolate content from navigation.',
         '', '| Image | Content pixels changed |', '| --- | ---: |']
for path in sorted(after.glob('*.png')):
    old = before / path.name
    if not old.exists():
        continue
    a, b = Image.open(old).convert('RGB'), Image.open(path).convert('RGB')
    if a.size != b.size:
        continue
    box = (0, 0, a.width, max(1, a.height - 120))
    pixels = list(ImageChops.difference(a.crop(box), b.crop(box)).getdata())
    changed = sum(max(pixel) > 8 for pixel in pixels)
    lines.append(f'| {path.name} | {changed / len(pixels):.2%} |')
(root / 'docs/design/145/pixel-deltas.md').write_text('\n'.join(lines) + '\n')
