"""Compose the fixture captures; requires Pillow already installed locally."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

root = Path(__file__).resolve().parent
views = ["390x844", "375x667", "375x667_text200"]
font = ImageFont.load_default(size=15)
cell_width, cell_height = 200, 470
sheet = Image.new("RGB", (cell_width * 8, cell_height * 6), "#dddddd")
draw = ImageDraw.Draw(sheet)
for row, (view, theme) in enumerate((v, t) for v in views for t in ["light", "dark"]):
    for tab_index, tab in enumerate(["home", "spaces", "loans", "activity"]):
        for state_index, state in enumerate(["before", "after"]):
            col = tab_index * 2 + state_index
            name = f"tab_{tab}_{view}_{theme}.png"
            capture = Image.open(root / state / name).convert("RGB")
            capture.thumbnail((195, 422), Image.Resampling.LANCZOS)
            x, y = col * cell_width, row * cell_height
            draw.text((x + 4, y + 3), f"{tab.title()} - {state}", fill="black", font=font)
            draw.text((x + 4, y + 22), f"{view} {theme}", fill="black", font=font)
            sheet.paste(capture, (x + 2, y + 44))
sheet.save(root / "contact-sheet.png")
