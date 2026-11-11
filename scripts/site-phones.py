#!/usr/bin/env python3
"""Compose generated hardware around real, unretouched 3x app exports.

Run app/test/marketing_export.dart and site-images.py first. Pillow 13.0.0; no API or image model at rebuild time.
The model only supplied studio-frame.png. Screen pixels are pasted last and
never receive generated reflections, lighting, colour grading or retouching.
"""
import hashlib
import json
import io
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
    density = screen.width / 390
    w, h = screen.size
    x0, y0, x1, y1 = OPENING
    sx = sy = (w + 4 * density) / (x1-x0)
    frame = Image.open(FRAME).convert('RGBA')
    # Neutralise coloured fringe on generated hardware only.
    frame = ImageEnhance.Color(frame).enhance(0.12)
    frame = frame.resize((round(frame.width*sx), round(frame.height*sy)), Image.Resampling.LANCZOS)
    # Opaque screenshot rectangle replaces all generated screen pixels.
    panel = Image.new('RGBA', (round((x1-x0)*sx), round((y1-y0)*sy)), screen.getpixel((0, 0)))
    panel.paste(screen, (round(2*density), round(2*density)))
    mask = Image.new('L', panel.size)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, panel.width-1, panel.height-1), radius=24*density, fill=255)
    frame.paste(panel, (round(x0*sx), round(y0*sy)), mask)
    # Plain 2D rotation, applied equally to UI and hardware.
    if angle:
        frame = frame.rotate(angle, Image.Resampling.BICUBIC, expand=True)
    # Transparent padding contains every tilted corner within the layout box.
    canvas = Image.new('RGBA', (frame.width+round(16*density), frame.height+round(16*density)))
    canvas.alpha_composite(frame, (round(8*density), round(8*density)))
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
        'screen_policy': 'Full 3x Flutter marketing export pasted without retouching into a uniformly scaled device; screen background fills spare opening rows. Final geometric resampling and AVIF encoding only.',
    }
    for name, angle in ANGLES.items():
        source = manifest['sources'][name]
        export = ROOT / 'build/marketing' / f'{name}.png'
        raw = export.read_bytes()
        screen = Image.open(io.BytesIO(raw)).convert('RGBA')
        assert screen.size == (1170, 2532), 'Run the 3x marketing export first'
        source['marketing'] = {'path': str(export.relative_to(ROOT)),
            'sha256': hashlib.sha256(raw).hexdigest(), 'size': list(screen.size),
            'device_pixel_ratio': 3, 'fixture': source['path'],
            'exporter': 'app/test/marketing_export.dart'}
        composed = compose(screen, angle)
        # One output scale for every angle: expansion adds canvas, not shrinkage.
        upright = compose(screen, 0)
        output_scale = 390 / upright.width
        width, height = round(composed.width * output_scale), round(composed.height * output_scale)
        quality = 56 if name == 'home_main' else 48
        outputs = []
        for density in (1, 2, 3):
            file = f'{name}-phone' + (f'@{density}x' if density > 1 else '') + '.avif'
            base = composed.resize((width*density, height*density), Image.Resampling.LANCZOS)
            base.save(OUT / file, quality=quality, speed=6, subsampling='4:4:4')
            outputs.append(file)
        manifest['sources'][name]['phone'] = {
            'angle_degrees': angle, 'size_1x': [width, height],
            'outputs': outputs, 'screen_crop_rows': None,
            'encoding': {'format': 'AVIF', 'quality': quality, 'subsampling': '4:4:4'},
            'output_scale': output_scale,
        }
    # Whole UI controls/cards only. Coordinates are logical pixels in the same
    # export; never reconstructed type or model-generated interface pixels.
    crops = {
        'upi': ('settle_pay', (12, 636, 378, 764)),
        'remind': ('loans_detail', (20, 484, 370, 614)),
        'balance': ('home_main', (20, 128, 370, 352)),
        'instalments': ('loans_detail', (44, 336, 346, 452)),
    }
    manifest['details'] = {}
    for name, (screen_name, box) in crops.items():
        screen = Image.open(ROOT / 'build/marketing' / f'{screen_name}.png')
        detail = screen.crop(tuple(value*3 for value in box))
        file = f'detail-{name}.avif'
        detail.save(OUT / file, quality=70, speed=6, subsampling='4:4:4')
        manifest['details'][name] = {'source': screen_name, 'logical_crop': box,
            'output': file, 'size': list(detail.size)}
    (OUT / 'sources.json').write_text(json.dumps(manifest, indent=2)+'\n')


if __name__ == '__main__':
    main()
