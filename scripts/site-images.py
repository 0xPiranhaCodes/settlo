#!/usr/bin/env python3
"""Regenerate marketing assets. Requires Pillow 13.0.0 (see docs/brand.md)."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
from PIL import Image

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
# Social cards are rendered from the SVG illustrations by scripts/site-cards.cjs.
(out / 'sources.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(json.dumps(manifest, indent=2))
