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
parser.add_argument('--home-ref', default='b66bbb68b64e38286caea04ce06b2db4202fa18c',
                    help='Git ref containing PR #142 home goldens; fetch before running')
args = parser.parse_args()
env = {k: v for k, v in os.environ.items() if not k.startswith('GIT_CONFIG_')}
out = ROOT / 'site/images'
out.mkdir(parents=True, exist_ok=True)
manifest = {'home_commit': subprocess.check_output(['git', 'rev-parse', args.home_ref], cwd=ROOT, env=env, text=True).strip(), 'sources': {}}
for name, source, ref in [
    ('welcome', 'app/test/goldens/auth_welcome_390x844_dark.png', None),
    ('home', 'app/test/goldens/home_main_390x844_dark.png', args.home_ref),
]:
    raw = subprocess.check_output(['git', 'show', f'{ref}:{source}'], cwd=ROOT, env=env) if ref else (ROOT / source).read_bytes()
    img = Image.open(io.BytesIO(raw)).convert('RGB')
    img.save(out / f'{name}.webp', quality=90, method=6)
    manifest['sources'][name] = {'path': source, 'sha256': hashlib.sha256(raw).hexdigest(), 'size': list(img.size)}
mark = Image.open(ROOT / 'packages/core/assets/brand/3.0x/settlo_mark.png').convert('RGBA')
mark.thumbnail((192, 192), Image.Resampling.LANCZOS)
mark.save(out / 'mark.png', optimize=True)
# Social card: deterministic composition, real app screen, bundled brand font.
card = Image.new('RGB', (1200, 630), '#0a0b0d')
draw = ImageDraw.Draw(card)
for radius in (360, 430, 500):
    draw.ellipse((890-radius, 310-radius, 890+radius, 310+radius), outline='#3d3425', width=2)
font_dir = ROOT / 'packages/core/assets/fonts'
def text(x, y, value, size, fill='#f3f2ee'):
    draw.text((x, y), value, font=ImageFont.truetype(str(font_dir / 'Figtree-Medium.ttf'), size), fill=fill)
smallmark = mark.copy(); smallmark.thumbnail((64,64))
card.paste(smallmark, (64,58), smallmark)
text(142, 62, 'settlo', 40)
text(64, 190, 'Good friends.', 66)
text(64, 268, 'Clear balances.', 66)
text(64, 382, 'Shared expenses. Personal loans.', 27, '#9b9d9a')
text(64, 424, 'Made for the way India settles up.', 27, '#9b9d9a')
text(64, 535, 'iPhone · TestFlight beta', 23, '#d8b36a')
screen = Image.open(out / 'home.webp'); screen.thumbnail((252, 546), Image.Resampling.LANCZOS)
card.paste(screen, (866,42))
card.save(out / 'social.png', optimize=True)
(out / 'sources.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(json.dumps(manifest, indent=2))
