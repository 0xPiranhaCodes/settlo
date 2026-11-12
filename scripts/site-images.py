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
# Provenance only: the page shows placeholders until SabkiJeb captures exist (#204).
for name in ('home_main', 'settle_pay', 'spaces_balances', 'loans_detail', 'confirm_repayment'):
    source = f'app/test/goldens/{name}_390x844_dark.png'
    raw = subprocess.check_output(['git', 'show', f'{args.ref}:{source}'], cwd=ROOT, env=env)
    size = list(Image.open(io.BytesIO(raw)).size)
    manifest['sources'][name] = {'path': source, 'sha256': hashlib.sha256(raw).hexdigest(), 'size': size}
subprocess.run([os.sys.executable, str(ROOT / 'scripts/site-icons.py')], check=True)
mark = Image.open(out / 'mark.png').convert('RGBA')
# Social card: deterministic composition, owner logo, bundled brand font.
card = Image.new('RGB', (1200, 630), '#01381e')
draw = ImageDraw.Draw(card)
for radius in (360, 430, 500):
    draw.ellipse((890-radius, 310-radius, 890+radius, 310+radius), outline='#01672d', width=2)
font_dir = ROOT / 'packages/core/assets/fonts'
def text(x, y, value, size, fill='#fef0ce'):
    font = ImageFont.truetype(str(font_dir / 'Figtree-Medium.ttf'), size)
    draw.text((x, y), value, font=font, fill=fill)
card.paste(mark.resize((64, 64), Image.Resampling.LANCZOS), (64, 58), mark.resize((64, 64), Image.Resampling.LANCZOS))
text(146, 66, 'SabkiJeb', 36)
text(64, 190, 'Good friends.', 66)
text(64, 268, 'Clear balances.', 66)
text(64, 382, 'Shared expenses. Personal loans.', 27, '#a9bcb0')
text(64, 424, 'Made for the way India settles up.', 27, '#a9bcb0')
text(64, 535, 'iPhone · TestFlight beta', 23, '#febd11')
logo = Image.open(ROOT / 'design/brand/website/sabkijeb-logo.png').resize((340, 340), Image.Resampling.LANCZOS)
rounded = Image.new('L', (340, 340))
ImageDraw.Draw(rounded).rounded_rectangle((0, 0, 339, 339), radius=76, fill=255)
card.paste(logo, (720, 145), rounded)
card.save(out / 'social.png', optimize=True)
(out / 'sources.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(json.dumps(manifest, indent=2))
