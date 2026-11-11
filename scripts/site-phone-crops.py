#!/usr/bin/env python3
"""Build exact 2x nearest-neighbour corner/bottom evidence from 1x phone AVIFs.

Usage: python3 scripts/site-phone-crops.py INPUT_DIR OUTPUT.png
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw

source, target = map(Path, sys.argv[1:])
names = ['home_main', 'settle_pay', 'spaces_balances', 'loans_detail', 'confirm_repayment']
sheet = Image.new('RGB', (1000, len(names)*500), '#303237')
draw = ImageDraw.Draw(sheet)
for row, name in enumerate(names):
    im = Image.open(source / f'{name}-phone.avif').convert('RGBA')
    w, h = im.size
    draw.text((10, row*500+5), name, fill='white')
    boxes = [(0, 0, 120, 120), (w-120, 0, w, 120),
             (0, h-120, 120, h), (w-120, h-120, w, h)]
    for i, box in enumerate(boxes):
        crop = im.crop(box).resize((240, 240), Image.Resampling.NEAREST)
        sheet.paste(crop, (i*250, row*500+25), crop)
    bottom = im.crop((0, h-110, w, h)).resize((w*2, 220), Image.Resampling.NEAREST)
    sheet.paste(bottom, (0, row*500+275), bottom)
sheet.save(target, optimize=True)
