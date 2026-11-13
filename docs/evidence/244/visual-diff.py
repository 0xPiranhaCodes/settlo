#!/usr/bin/env python3
"""Compare the #244 phone PNG fallbacks with their pre-#244 versions (commit 4ed95b1).

Writes diff.json, an amplified difference map and 2x nearest-neighbour before/after crops.
"""
import io
import json
import subprocess
from pathlib import Path
from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).parent
BASE = '4ed95b1'
NAMES = ['settle_pay', 'spaces_balances', 'home_main', 'loans_detail', 'confirm_repayment']
# Text, a soft card shadow and the blurred tab bar: the areas most prone to visible banding.
CROPS = {'settle_pay': {'text': (30, 60, 230, 200), 'shadow': (40, 240, 240, 420), 'tabbar': (60, 700, 260, 790)},
         'spaces_balances': {'text': (55, 230, 255, 420), 'shadow': (40, 470, 240, 660), 'tabbar': (60, 690, 260, 790)}}


def before(name):
    raw = subprocess.run(['git', 'show', f'{BASE}:site/images/{name}-phone.png'],
                         cwd=ROOT, check=True, capture_output=True).stdout
    return Image.open(io.BytesIO(raw)).convert('RGBA')


report = {}
for name in NAMES:
    old, path = before(name), ROOT / f'site/images/{name}-phone.png'
    new = Image.open(path).convert('RGBA')
    diff = ImageChops.difference(old, new)
    hist = diff.histogram()
    channels = [hist[i*256:(i+1)*256] for i in range(4)]
    total = sum(sum(c) for c in channels)
    mean = sum(v * n for c in channels for v, n in enumerate(c)) / total
    worst = max(v for c in channels for v, n in enumerate(c) if n)
    report[name] = {'bytes_before': len(subprocess.run(['git', 'show', f'{BASE}:site/images/{name}-phone.png'],
                                                       cwd=ROOT, capture_output=True).stdout),
                    'bytes_after': path.stat().st_size,
                    'mean_abs_diff_per_channel_of_255': round(mean, 4), 'max_abs_diff_of_255': worst}
    if name in CROPS:
        diff.convert('RGB').point(lambda v: min(255, v * 128)).save(HERE / f'{name}-diff-x128.png', optimize=True)
        for label, box in CROPS[name].items():
            for tag, image in (('before', old), ('after', new)):
                crop = image.crop(box)
                crop.resize((crop.width * 2, crop.height * 2), Image.Resampling.NEAREST).save(
                    HERE / f'{name}-{label}-{tag}@2x.png', optimize=True)
assert all(r['mean_abs_diff_per_channel_of_255'] <= 1 and r['bytes_after'] < 150_000 for r in report.values())
(HERE / 'diff.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report, indent=2))
