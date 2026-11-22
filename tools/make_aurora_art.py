#!/usr/bin/env python3
"""Raptua's own art for the Aurora dashboard on the Xbox 360, drawn from
scratch (no game art): a delta-wing jet seen from above over a night sky,
and the name. Writes assets/aurora/ at Aurora's asset sizes:

  icon.png        64 x 64     the title's icon
  banner.png     420 x 96     the banner in the game list
  boxart.png     900 x 600    the cover (back, spine, front)
  background.png 1280 x 720   the background behind the game's details

  python3 tools/make_aurora_art.py [--font PATH]

The lettering uses a bold sans font (default: Inter ExtraBold, SIL Open
Font License); only the rendered pictures are kept, not the font.
"""
import argparse
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = Path(__file__).resolve().parent.parent / "assets" / "aurora"
SS = 4  # drawn at 4x, then scaled down for smooth edges

SKY_TOP = (6, 10, 28)
SKY_BOTTOM = (18, 44, 78)
HULL = (196, 208, 222)
HULL_DARK = (98, 112, 134)
ACCENT = (255, 168, 40)
GLOW = (90, 210, 255)


def sky(w, h, seed=7, stars=True):
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        t = y / max(1, h - 1)
        c = tuple(int(SKY_TOP[i] + (SKY_BOTTOM[i] - SKY_TOP[i]) * t) for i in range(3))
        for x in range(w):
            px[x, y] = c
    if stars:
        rnd = random.Random(seed)
        d = ImageDraw.Draw(img)
        for _ in range(w * h // 1800):
            x, y = rnd.randrange(w), rnd.randrange(h)
            b = rnd.randint(110, 255)
            r = rnd.choice((0, 0, 0, 1))
            d.ellipse((x - r, y - r, x + r, y + r), fill=(b, b, min(255, b + 20)))
    return img


def jet_layer(size, angle=0.0):
    """An RGBA picture of the jet, nose up, about `size` pixels tall."""
    s = size * SS
    layer = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    def P(pts):  # points in a 100 x 100 design square
        return [(x * s / 100, y * s / 100) for x, y in pts]

    # Engine glow behind the twin nozzles.
    glow = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    for cx in (44, 56):
        gd.ellipse(P([(cx - 5, 84), (cx + 5, 99)]), fill=GLOW + (220,))
    glow = glow.filter(ImageFilter.GaussianBlur(s / 40))
    layer.alpha_composite(glow)

    wing = [(50, 30), (94, 74), (93, 79), (60, 72), (40, 72), (7, 79), (6, 74)]
    tail = [(44, 70), (30, 88), (31, 91), (46, 84), (54, 84), (69, 91), (70, 88), (56, 70)]
    body = [(50, 4), (55, 18), (57, 40), (58, 70), (57, 86), (43, 86), (42, 70), (43, 40), (45, 18)]
    d.polygon(P(wing), fill=HULL_DARK)
    d.polygon(P(tail), fill=HULL_DARK)
    # Lighter upper wing panels.
    d.polygon(P([(50, 34), (88, 73), (60, 69), (50, 60)]), fill=HULL)
    d.polygon(P([(50, 34), (12, 73), (40, 69), (50, 60)]), fill=HULL)
    d.polygon(P(body), fill=HULL)
    # Canopy and accent stripes.
    d.polygon(P([(50, 12), (53, 20), (52, 30), (48, 30), (47, 20)]), fill=(40, 120, 190))
    d.polygon(P([(50, 13), (51.5, 19), (50, 24)]), fill=(150, 220, 255))
    for side in (-1, 1):
        d.polygon(P([(50 + side * 14, 52), (50 + side * 30, 68), (50 + side * 26, 69), (50 + side * 12, 55)]), fill=ACCENT)
    d.line(P([(50, 34), (50, 82)]), fill=HULL_DARK, width=max(1, s // 160))
    if angle:
        layer = layer.rotate(angle, resample=Image.BICUBIC)
    return layer.resize((size, size), Image.LANCZOS)


def title(text, height, font_path, fill=(240, 244, 250), skew=0.18):
    """The name, slanted, with an orange underline and a soft shadow."""
    font = ImageFont.truetype(font_path, int(height * SS))
    bbox = font.getbbox(text)
    w, h = bbox[2] - bbox[0], bbox[3] - bbox[1]
    pad = int(h * 0.6)
    img = Image.new("RGBA", (w + pad * 2, h + pad * 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.text((pad - bbox[0], pad - bbox[1]), text, font=font, fill=fill + (255,))
    bar = int(h * 0.09)
    d.rectangle((pad, pad + h + bar, pad + w, pad + h + bar * 2), fill=ACCENT + (255,))
    img = img.transform(img.size, Image.AFFINE, (1, skew, -skew * img.height / 2, 0, 1, 0), resample=Image.BICUBIC)
    shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    shadow.putalpha(img.getchannel("A").point(lambda a: a * 0.7))
    shadow = shadow.filter(ImageFilter.GaussianBlur(h / 14))
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.alpha_composite(shadow, (int(h * 0.04), int(h * 0.06)))
    out.alpha_composite(img)
    out = out.crop(out.getbbox())
    return out.resize((max(1, out.width // SS), max(1, out.height // SS)), Image.LANCZOS)


def paste(base, layer, x, y):
    base.paste(layer, (int(x), int(y)), layer)


def make_icon(font):
    img = sky(64, 64, seed=3, stars=False)
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, 63, 63), outline=ACCENT)
    paste(img, jet_layer(58, angle=-20), 3, 2)
    return img


def make_banner(font):
    img = sky(420, 96, seed=5)
    paste(img, jet_layer(104, angle=-62), 300, -6)
    t = title("RAPTUA", 46, font)
    paste(img, t, 20, (96 - t.height) // 2)
    return img


def make_boxart(font):
    img = sky(900, 600, seed=11)
    d = ImageDraw.Draw(img)
    # Back (left 420), spine (60), front (right 420).
    d.rectangle((420, 0, 479, 599), fill=(10, 18, 40))
    d.line((420, 0, 420, 599), fill=ACCENT, width=2)
    d.line((479, 0, 479, 599), fill=ACCENT, width=2)
    spine = title("RAPTUA", 30, font, skew=0.0).rotate(90, expand=True)
    paste(img, spine, 450 - spine.width // 2, 300 - spine.height // 2)
    paste(img, jet_layer(330, angle=-18), 530, 210)
    paste(img, jet_layer(120, angle=-24), 760, 120)
    t = title("RAPTUA", 82, font)
    paste(img, t, 690 - t.width // 2, 50)
    paste(img, jet_layer(260, angle=-30), 80, 170)
    return img


def make_background(font):
    img = sky(1280, 720, seed=17)
    paste(img, jet_layer(520, angle=-28), 690, 140)
    paste(img, jet_layer(170, angle=-34), 520, 60)
    t = title("RAPTUA", 96, font)
    paste(img, t, 70, 70)
    return img


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--font", default="/usr/share/fonts/opentype/inter/Inter-ExtraBold.otf")
    args = ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    for name, fn in (("icon", make_icon), ("banner", make_banner), ("boxart", make_boxart), ("background", make_background)):
        fn(args.font).save(OUT / f"{name}.png", optimize=True)
        print("wrote", OUT / f"{name}.png")


if __name__ == "__main__":
    main()
