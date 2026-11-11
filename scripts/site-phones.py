#!/usr/bin/env python3
"""Compose generated hardware around real, unretouched golden screens.

Run site-images.py first. Pillow 13.0.0; no API or image model at rebuild time.
The model only supplied studio-frame.png. Screen pixels are pasted last and
never receive generated reflections, lighting, colour grading or retouching.
"""
import hashlib
import json
import io
import os
import subprocess
from pathlib import Path
from PIL import Image, ImageDraw, ImageEnhance

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'site/images'
FRAME = OUT / 'device/studio-frame.png'
# Measured interior opening in the committed 852 x 1846 generated asset.
OPENING = (52, 64, 798, 1700)
ANGLES = {'home_main': 0, 'settle_pay': 3, 'spaces_balances': -3,
          'loans_detail': 3, 'confirm_repayment': 0}


def compose(screen, angle):
    # Scale hardware to the screen; never squeeze the screen to fit hardware.
    # Two pixels of screen-colour margin protect content at rounded corners.
    scale = 2
    w, h = screen.size
    x0, y0, x1, y1 = OPENING
    sx = sy = (w + 4) * scale / (x1-x0)
    frame = Image.open(FRAME).convert('RGBA')
    # Neutralise coloured fringe on generated hardware only.
    frame = ImageEnhance.Color(frame).enhance(0.12)
    frame = frame.resize((round(frame.width*sx), round(frame.height*sy)), Image.Resampling.LANCZOS)
    # Opaque screenshot rectangle replaces all generated screen pixels.
    panel = Image.new('RGBA', (round((x1-x0)*sx), round((y1-y0)*sy)), screen.getpixel((0, 0)))
    panel.paste(screen.resize((w*scale, h*scale), Image.Resampling.NEAREST), (4, 4))
    mask = Image.new('L', panel.size)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, panel.width-1, panel.height-1), radius=24*scale, fill=255)
    frame.paste(panel, (round(x0*sx), round(y0*sy)), mask)
    # Plain 2D rotation, applied equally to UI and hardware.
    if angle:
        frame = frame.rotate(angle, Image.Resampling.BICUBIC, expand=True)
    # Transparent padding contains every tilted corner within the layout box.
    canvas = Image.new('RGBA', (frame.width+16, frame.height+16))
    canvas.alpha_composite(frame, (8, 8))
    return canvas


def main():
    manifest = json.loads((OUT / 'sources.json').read_text())
    manifest['device'] = {
        'path': 'site/images/device/studio-frame.png',
        'sha256': hashlib.sha256(FRAME.read_bytes()).hexdigest(),
        'generator': 'built-in image_gen',
        'prompt_path': 'site/images/device/prompt.txt',
        'opening_xyxy': list(OPENING),
        'recipe': 'scripts/site-phones.py',
        'screen_policy': 'Full approved golden pasted without retouching into a uniformly scaled device; screen background fills spare opening rows. Final geometric resampling and lossy WebP encoding only.',
    }
    for name, angle in ANGLES.items():
        source = manifest['sources'][name]
        env = {k: v for k, v in os.environ.items() if not k.startswith('GIT_CONFIG_')}
        raw = subprocess.check_output(['git', 'show', f"{manifest['commit']}:{source['path']}"], cwd=ROOT, env=env)
        assert hashlib.sha256(raw).hexdigest() == source['sha256']
        screen = Image.open(io.BytesIO(raw)).convert('RGBA')
        composed = compose(screen, angle)
        height = round(composed.height*390/composed.width)
        base = composed.resize((390, height), Image.Resampling.LANCZOS)
        quality = 80 if name == 'home_main' else 88
        base.save(OUT / f'{name}-phone.webp', quality=quality, method=6, exact=True)
        (OUT / f'{name}-phone@2x.webp').unlink(missing_ok=True)
        manifest['sources'][name]['phone'] = {
            'angle_degrees': angle, 'size_1x': [390, height],
            'outputs': [f'{name}-phone.webp'],
            'density_note': 'Single 390px composite for the maximum rendered width; no artificial 2x.',
            'screen_crop_rows': None,
            'encoding': {'format': 'WebP', 'quality': quality, 'method': 6, 'exact': True},
            'uniform_frame_scale': 788 / 746,
        }
    (OUT / 'sources.json').write_text(json.dumps(manifest, indent=2)+'\n')


if __name__ == '__main__':
    main()
