#!/usr/bin/env python3
"""Compose real iOS 26 simulator captures into a deterministic, illustrative phone frame.

The display is 430 x 932 logical pixels, including native system chrome.
Hardware and display share concentric rounded rectangles; no inferred opening
from generated artwork, stretching, cropped controls, or spare display rows.
"""
import hashlib
import json
import io
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'site/images'
DISPLAY = (430, 932)
BEZEL = 8
RADIUS = 52
PADDING = 16
ANGLES = {'home_main': 0, 'settle_pay': 3, 'spaces_balances': -3,
          'loans_detail': 3, 'confirm_repayment': 0}


def compose(screen, angle):
    density = screen.width / DISPLAY[0]
    assert screen.size == (1290, 2796), 'Run the 430 x 932 phone export first'
    def px(value):
        return round(value * density)
    w, h = (px(v) for v in DISPLAY)
    bezel, padding, radius = map(px, (BEZEL, PADDING, RADIUS))
    frame = Image.new('RGBA', (w + 2*bezel, h + 2*bezel))
    draw = ImageDraw.Draw(frame)
    # One geometry controls the metal rim, black bezel and display mask.
    draw.rounded_rectangle((0, 0, frame.width-1, frame.height-1),
                           radius=radius+bezel, fill='#929597')
    draw.rounded_rectangle((px(2), px(2), frame.width-1-px(2), frame.height-1-px(2)),
                           radius=radius+bezel-px(2), fill='#17191b')
    panel = screen.copy()
    mask = Image.new('L', panel.size)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, w-1, h-1), radius=radius, fill=255)
    frame.paste(panel, (bezel, bezel), mask)
    if angle:
        frame = frame.rotate(angle, Image.Resampling.BICUBIC, expand=True)
    canvas = Image.new('RGBA', (frame.width+2*padding, frame.height+2*padding))
    canvas.alpha_composite(frame, (padding, padding))
    return canvas


# Original iOS 26 simulator captures are pinned in the repository.
CAPTURES = ROOT / 'docs/evidence/204/captures'
SCREENS = {'home_main': 'home', 'settle_pay': 'spaces',
           'spaces_balances': 'balances', 'loans_detail': 'loans',
           'confirm_repayment': 'activity'}


def main():
    manifest = json.loads((OUT / 'sources.json').read_text())
    manifest['device'] = {
        'generator': 'deterministic Pillow geometry',
        'display_logical_size': list(DISPLAY),
        'bezel_width': BEZEL, 'display_radius': RADIUS,
        'recipe': 'scripts/site-phones.py',
        'screen_policy': 'Full unaltered iOS 26 SabkiJeb simulator captures, including native system chrome. Light captures serve both site themes. Uniform resampling inside a concentric illustrative frame.',
    }
    manifest['sources'] = {}
    for name, angle in ANGLES.items():
        export = CAPTURES / f'{SCREENS[name]}-light-phone.png'
        raw = export.read_bytes()
        screen = Image.open(io.BytesIO(raw)).convert('RGBA')
        composed = compose(screen, angle)
        output_scale = 390 / compose(screen, 0).width
        width, height = round(composed.width * output_scale), round(composed.height * output_scale)
        outputs = []
        for density in (1, 2, 3):
            file = f'{name}-phone' + (f'@{density}x' if density > 1 else '') + '.avif'
            base = composed.resize((width*density, height*density), Image.Resampling.LANCZOS)
            base.save(OUT / file, quality=48, speed=6, subsampling='4:4:4')
            outputs.append(file)
            if density == 1:
                base.save(OUT / f'{name}-phone.png', optimize=True)
        manifest['sources'][name] = {
            'marketing': {'path': str(export.relative_to(ROOT)),
                          'sha256': hashlib.sha256(raw).hexdigest(),
                          'size': list(screen.size), 'platform': 'iOS 26 simulator'},
            'phone': {'angle_degrees': angle, 'size_1x': [width, height],
                      'outputs': outputs + [f'{name}-phone.png'], 'screen_crop_rows': None,
                      'encoding': {'format': 'AVIF', 'quality': 48, 'subsampling': '4:4:4'},
                      'output_scale': output_scale}}
    # Whole cards from native captures, in logical 430 x 932 coordinates.
    crops = {
        'upi': ('profile', (20, 282, 410, 372)),
        'remind': ('profile', (20, 428, 410, 512)),
        'balance': ('home', (20, 142, 410, 364)),
        'instalments': ('loans', (20, 166, 410, 312)),
    }
    manifest['details'] = {}
    for name, (screen_name, box) in crops.items():
        export = CAPTURES / f'{screen_name}-light-phone.png'
        screen = Image.open(export)
        detail = screen.crop(tuple(value*3 for value in box))
        file = f'detail-{name}.avif'
        detail.save(OUT / file, quality=65, speed=6, subsampling='4:4:4')
        detail.resize((box[2]-box[0], box[3]-box[1]), Image.Resampling.LANCZOS).save(OUT / f'detail-{name}.png', optimize=True)
        manifest['details'][name] = {'source': str(export.relative_to(ROOT)),
            'sha256': hashlib.sha256(export.read_bytes()).hexdigest(), 'logical_crop': box,
            'output': file, 'size': list(detail.size)}
    (OUT / 'sources.json').write_text(json.dumps(manifest, indent=2)+'\n')


if __name__ == '__main__':
    main()
