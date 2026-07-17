from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
GREEN = "#24523A"
GREEN_LIGHT = "#2F6849"
IVORY = "#FFF9EA"
PAGE_EDGE = "#E4D7B6"
GOLD = "#C99A2E"


def logo(size: int, adaptive: bool = False) -> Image.Image:
    scale = 4
    n = size * scale
    im = Image.new("RGBA", (n, n), GREEN)
    d = ImageDraw.Draw(im)
    def p(points): return [(int(x*n/1024), int(y*n/1024)) for x, y in points]
    def w(value): return max(1, int(value*n/1024))

    radius = int((0 if adaptive else 224) * n / 1024)
    if radius:
        im = Image.new("RGBA", (n, n), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        d.rounded_rectangle((0, 0, n-1, n-1), radius=radius, fill=GREEN)
    d.ellipse((164*n/1024, 148*n/1024, 860*n/1024, 844*n/1024), fill=GREEN_LIGHT)
    left = p([(176,322),(270,280),(390,300),(512,380),(512,800),(390,724),(270,710),(176,742)])
    right = p([(848,322),(754,280),(634,300),(512,380),(512,800),(634,724),(754,710),(848,742)])
    d.polygon(left, fill=IVORY)
    d.line(left + [left[0]], fill=PAGE_EDGE, width=w(20), joint="curve")
    d.polygon(right, fill=IVORY)
    d.line(right + [right[0]], fill=PAGE_EDGE, width=w(20), joint="curve")
    d.line(p([(512,380),(512,800)]), fill="#C9B988", width=w(18))
    for points in [[(282,438),(350,425),(414,442),(466,476)],[(282,522),(350,509),(414,526),(466,560)],[(742,438),(674,425),(610,442),(558,476)],[(742,522),(674,509),(610,526),(558,560)]]:
        d.line(p(points), fill="#AEBDAF", width=w(18), joint="curve")
    bookmark = p([(610,352),(680,330),(750,326),(750,694),(680,642),(610,694)])
    d.polygon(bookmark, fill=GOLD)
    d.line(p([(680,414),(680,546)]), fill="#FFF7DB", width=w(18))
    d.line(p([(634,480),(726,480)]), fill="#FFF7DB", width=w(18))
    return im.resize((size, size), Image.Resampling.LANCZOS)


def adaptive_foreground(size: int) -> Image.Image:
    scale = 4
    n = size * scale
    im = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    def p(points): return [(int(x*n/1024), int(y*n/1024)) for x, y in points]
    def w(value): return max(1, int(value*n/1024))

    left = p([(176,322),(270,280),(390,300),(512,380),(512,800),(390,724),(270,710),(176,742)])
    right = p([(848,322),(754,280),(634,300),(512,380),(512,800),(634,724),(754,710),(848,742)])
    d.polygon(left, fill=IVORY)
    d.line(left + [left[0]], fill=PAGE_EDGE, width=w(20), joint="curve")
    d.polygon(right, fill=IVORY)
    d.line(right + [right[0]], fill=PAGE_EDGE, width=w(20), joint="curve")
    d.line(p([(512,380),(512,800)]), fill="#C9B988", width=w(18))
    for points in [[(282,438),(350,425),(414,442),(466,476)],[(282,522),(350,509),(414,526),(466,560)],[(742,438),(674,425),(610,442),(558,476)],[(742,522),(674,509),(610,526),(558,560)]]:
        d.line(p(points), fill="#AEBDAF", width=w(18), joint="curve")
    bookmark = p([(610,352),(680,330),(750,326),(750,694),(680,642),(610,694)])
    d.polygon(bookmark, fill=GOLD)
    d.line(p([(680,414),(680,546)]), fill="#FFF7DB", width=w(18))
    d.line(p([(634,480),(726,480)]), fill="#FFF7DB", width=w(18))
    return im.resize((size, size), Image.Resampling.LANCZOS)


android_sizes = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
for density, size in android_sizes.items():
    target = ROOT / "android" / "app" / "src" / "main" / "res" / f"mipmap-{density}" / "ic_launcher.png"
    logo(size).save(target)
    logo(size).save(target.with_name("ic_launcher_bible.png"))

adaptive_target = ROOT / "android" / "app" / "src" / "main" / "res" / "drawable-nodpi" / "ic_launcher_foreground.png"
adaptive_target.parent.mkdir(parents=True, exist_ok=True)
logo(432, adaptive=True).save(adaptive_target)
adaptive_bible_target = adaptive_target.with_name("ic_launcher_bible_foreground.png")
adaptive_foreground(432).save(adaptive_bible_target)

contents = ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
for path in contents.glob("*.png"):
    name = path.stem
    if "1024x1024" in name:
        pixels = 1024
    else:
        base = float(name.split("-")[-1].split("x")[0])
        scale_factor = int(name.split("@")[-1][0]) if "@" in name else 1
        pixels = round(base * scale_factor)
    logo(pixels).convert("RGB").save(path)

preview = ROOT / "assets" / "branding" / "app_logo_1024.png"
logo(1024).save(preview)
