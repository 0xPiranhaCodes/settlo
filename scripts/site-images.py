#!/usr/bin/env python3
"""Regenerate marketing assets. Requires Pillow 13.0.0 (see docs/brand.md)."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--ref', default='HEAD',
                    help='Git ref whose app goldens are exported; fetch before running')
args = parser.parse_args()
env = {k: v for k, v in os.environ.items() if not k.startswith('GIT_CONFIG_')}
out = ROOT / 'site/images'
out.mkdir(parents=True, exist_ok=True)
manifest = {'commit': subprocess.check_output(['git', 'rev-parse', args.ref], cwd=ROOT, env=env, text=True).strip(), 'sources': {}}
# Lossless: the screens are shown at their real 390px width, so every glyph stays crisp.
# Crop rows are blank gaps below the last whole card, above the floating navigation;
# 24px of the screen's own background follows so the rounded frame clips nothing.
crops = {'home_main': 662, 'settle_pay': None, 'spaces_balances': 754, 'loans_detail': 542, 'confirm_repayment': 787}
for name, crop in crops.items():
    source = f'app/test/goldens/{name}_390x844_dark.png'
    raw = subprocess.check_output(['git', 'show', f'{args.ref}:{source}'], cwd=ROOT, env=env)
    img = Image.open(io.BytesIO(raw)).convert('RGB')
    size = list(img.size)
    if crop:
        row = img.crop((0, crop, img.width, crop + 1)).convert('L').getextrema()
        assert row[1] - row[0] < 48, f'{name}: crop row {crop} is not a blank gap; re-pick it'
        shown = Image.new('RGB', (img.width, crop + 24), img.getpixel((0, crop)))
        shown.paste(img.crop((0, 0, img.width, crop)))
        img = shown
    img.save(out / f'{name}.webp', lossless=True, method=6)
    manifest['sources'][name] = {'path': source, 'sha256': hashlib.sha256(raw).hexdigest(), 'size': size, 'crop_rows': crop}
mark = Image.open(ROOT / 'packages/core/assets/brand/3.0x/settlo_mark.png').convert('RGBA')
mark.thumbnail((192, 192), Image.Resampling.LANCZOS)
mark.save(out / 'mark.png', optimize=True)
# Social card: deterministic composition, real app screen, bundled brand font.
card = Image.new('RGB', (1200, 630), '#0a0b0d')
draw = ImageDraw.Draw(card)
for radius in (360, 430, 500):
    draw.ellipse((890-radius, 310-radius, 890+radius, 310+radius), outline='#3d3425', width=2)
font_dir = ROOT / 'packages/core/assets/fonts'
def text(x, y, value, size, fill='#f3f2ee', tracking=0):
    font = ImageFont.truetype(str(font_dir / 'Figtree-Medium.ttf'), size)
    for char in value if tracking else [value]:
        draw.text((x, y), char, font=font, fill=fill)
        x += font.getlength(char) + tracking
smallmark = mark.copy(); smallmark.thumbnail((64,64))
card.paste(smallmark, (64,58), smallmark)
text(142, 66, 'SETTLO', 34, tracking=3)  # the app's spaced-caps lockup
text(64, 190, 'Good friends.', 66)
text(64, 268, 'Clear balances.', 66)
text(64, 382, 'Shared expenses. Personal loans.', 27, '#9b9d9a')
text(64, 424, 'Made for the way India settles up.', 27, '#9b9d9a')
text(64, 535, 'iPhone · TestFlight beta', 23, '#d8b36a')
screen = Image.open(out / 'home_main.webp'); screen.thumbnail((252, 546), Image.Resampling.LANCZOS)
card.paste(screen, (866,42))
card.save(out / 'social.png', optimize=True)
(out / 'sources.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(json.dumps(manifest, indent=2))
