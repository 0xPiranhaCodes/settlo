#!/usr/bin/env python3
"""Compose real Flutter exports into a deterministic, illustrative phone frame.

The display is 430 x 932 logical pixels: 54 status + 844 content + 34 home, rendered with real safe-area insets.
Hardware and display share concentric rounded rectangles; no inferred opening
from generated artwork, stretching, cropped controls, or spare display rows.
"""
import argparse
import hashlib
import json
import io
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'site/images'
DISPLAY = (430, 932)
STATUS = 54
HOME = 34
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
    chrome = ImageDraw.Draw(panel)
    # Illustrative system chrome only; app pixels remain untouched.
    chrome.rounded_rectangle((px(153), px(12), px(277), px(42)),
                             radius=px(15), fill='#000000')
    font = ImageFont.truetype(str(ROOT / 'packages/core/assets/fonts/Figtree-Medium.ttf'), px(15))
    chrome.text((px(38), px(18)), '9:41', font=font, fill='#f3f2ee')
    for i in range(4):
        chrome.rounded_rectangle((px(335+i*5), px(31-i*3), px(338+i*5), px(35)),
                                 radius=px(1), fill='#f3f2ee')
    chrome.rounded_rectangle((px(362), px(23), px(386), px(35)),
                             radius=px(3), outline='#f3f2ee', width=px(1))
    chrome.rectangle((px(365), px(26), px(381), px(32)), fill='#f3f2ee')
    chrome.rectangle((px(387), px(27), px(389), px(31)), fill='#f3f2ee')
    chrome.rounded_rectangle((px(145), h-px(13), px(285), h-px(8)),
                             radius=px(2.5), fill='#f3f2ee')
    mask = Image.new('L', panel.size)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, w-1, h-1), radius=radius, fill=255)
    frame.paste(panel, (bezel, bezel), mask)
    if angle:
        frame = frame.rotate(angle, Image.Resampling.BICUBIC, expand=True)
    canvas = Image.new('RGBA', (frame.width+2*padding, frame.height+2*padding))
    canvas.alpha_composite(frame, (padding, padding))
    return canvas


# SabkiJeb "Settle Check" dark palette (#202), for neutral placeholders only.
CARD, LINE, ACTION = '#14271c', '#30473c', '#febd11'


def skeleton(size, blocks):
    """Text-free wireframe at 3x: (x0, y0, x1, y1, fill) in logical pixels."""
    image = Image.new('RGBA', size, '#000000')
    draw = ImageDraw.Draw(image)
    for x0, y0, x1, y1, fill in blocks:
        draw.rounded_rectangle((x0*3, y0*3, x1*3, y1*3), radius=min(24, (y1-y0)/2)*3, fill=fill)
    return image


# shortcut: no SabkiJeb app captures yet (#202/#203), so phones and close-ups
# are neutral wireframes; rebuild without --placeholders once the app is rebranded.
PLACEHOLDER = skeleton((1290, 2796), [
    (20, 70, 56, 106, LINE), (334, 70, 370, 106, CARD), (374, 70, 410, 106, CARD),
    (20, 128, 410, 352, CARD), (44, 156, 160, 168, LINE), (44, 188, 300, 228, LINE),
    (44, 248, 240, 262, LINE), (44, 300, 150, 316, LINE), (280, 300, 386, 316, LINE),
    (20, 376, 212, 428, ACTION), (220, 376, 410, 428, CARD),
    (20, 452, 410, 676, CARD), (44, 480, 140, 492, LINE),
    (44, 520, 84, 560, LINE), (100, 524, 240, 538, LINE), (100, 546, 180, 556, LINE), (316, 530, 386, 544, LINE),
    (44, 600, 84, 640, LINE), (100, 604, 240, 618, LINE), (100, 626, 180, 636, LINE), (316, 610, 386, 624, LINE),
    (20, 700, 410, 820, CARD), (44, 728, 140, 740, LINE), (44, 760, 300, 774, LINE),
    (40, 836, 390, 892, CARD), (52, 842, 132, 886, LINE),
])
DETAILS = {
    'upi': [(0, 0, 366, 128, CARD), (40, 20, 326, 32, LINE), (16, 56, 350, 112, ACTION)],
    'remind': [(0, 0, 350, 130, CARD), (24, 24, 220, 38, LINE), (16, 64, 220, 114, ACTION), (232, 64, 334, 114, LINE)],
    'balance': [(0, 0, 350, 224, CARD), (24, 28, 140, 40, LINE), (24, 60, 280, 100, LINE),
                (24, 120, 220, 134, LINE), (24, 172, 130, 188, LINE), (220, 172, 326, 188, LINE)],
    'instalments': [(0, 0, 302, 116, CARD), (20, 24, 200, 38, LINE), (20, 56, 282, 66, LINE), (20, 84, 160, 96, LINE)],
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--placeholders', action='store_true',
                        help='Compose neutral wireframes instead of build/marketing exports')
    placeholders = parser.parse_args().placeholders
    manifest = json.loads((OUT / 'sources.json').read_text())
    manifest['device'] = {
        'generator': 'deterministic Pillow geometry',
        'display_logical_size': list(DISPLAY),
        'status_bar_height': STATUS, 'home_area_height': HOME,
        'bezel_width': BEZEL, 'display_radius': RADIUS,
        'recipe': 'scripts/site-phones.py',
        'screen_policy': 'Full 430 x 932 Flutter export at 3x with 54px top and 34px bottom safe-area insets. Illustrative system chrome is drawn only in those reserved areas. Shared concentric frame/mask geometry. Uniform resampling and AVIF encoding only.',
    }
    for name, angle in ANGLES.items():
        source = manifest['sources'][name]
        if placeholders:
            screen = PLACEHOLDER
            source['marketing'] = {'placeholder': 'scripts/site-phones.py --placeholders'}
        else:
            export = ROOT / 'build/marketing' / f'{name}-phone.png'
            raw = export.read_bytes()
            screen = Image.open(io.BytesIO(raw)).convert('RGBA')
            assert screen.size == (1290, 2796), 'Run the 3x marketing export first'
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
        if placeholders:
            detail = skeleton(((box[2]-box[0])*3, (box[3]-box[1])*3), DETAILS[name]).convert('RGB')
        else:
            screen = Image.open(ROOT / 'build/marketing' / f'{screen_name}.png')
            detail = screen.crop(tuple(value*3 for value in box))
        file = f'detail-{name}.avif'
        detail.save(OUT / file, quality=70, speed=6, subsampling='4:4:4')
        manifest['details'][name] = {'source': screen_name, 'logical_crop': box,
            'output': file, 'size': list(detail.size)}
    (OUT / 'sources.json').write_text(json.dumps(manifest, indent=2)+'\n')


if __name__ == '__main__':
    main()
