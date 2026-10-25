from pathlib import Path
from PIL import Image

root = Path(__file__).resolve().parent
src = root / "icon.png"
dst = root / "icon.ico"
sizes = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]

img = Image.open(src).convert("RGBA")
bbox = img.getbbox()
if not bbox:
    raise SystemExit("icon.png is fully transparent")

content = img.crop(bbox)
w, h = content.size
side = int(round(max(w, h) * 1.08))
master = Image.new("RGBA", (side, side), (0, 0, 0, 0))
master.paste(content, ((side - w) // 2, (side - h) // 2), content)
master.save(dst, format="ICO", sizes=sizes)

print(f"source {img.width}x{img.height}, content {w}x{h} {bbox}, square {side}x{side}")
with Image.open(dst) as out:
    print("icon.ico sizes:", sorted(out.info.get("sizes", [])))
print("wrote", dst)
