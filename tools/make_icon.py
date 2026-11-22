#!/usr/bin/env python3
"""Draws Raptua's icon, assets/raptua.ico (and a 256 px PNG): the jet from
the Aurora art (tools/make_aurora_art.py, drawn from scratch, no game art)
banking over a night-sky square.

The .ico is built for Windows 3.1-style hosts as well as modern Windows:
  32 x 32 and 16 x 16 in 16 colours (4-bit BMP, the standard VGA palette),
    as Windows 3.1 and Progman31lua's Program Manager read icons
  48 x 48 and 32 x 32 / 16 x 16 in 32-bit colour (BMP), for Explorer
  256 x 256 (PNG), for Explorer's large views

    python3 tools/make_icon.py [out_dir]       (needs Pillow)
"""
import io
import os
import struct
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_aurora_art import ACCENT, jet_layer, sky  # noqa: E402

# The 16 colours of a VGA / Windows 3.1 display, in palette order.
VGA16 = [
    (0, 0, 0), (128, 0, 0), (0, 128, 0), (128, 128, 0), (0, 0, 128), (128, 0, 128), (0, 128, 128), (192, 192, 192),
    (128, 128, 128), (255, 0, 0), (0, 255, 0), (255, 255, 0), (0, 0, 255), (255, 0, 255), (0, 255, 255), (255, 255, 255),
]


def draw(size):
    """The icon in full colour, with transparency."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    m = max(1, size // 16)
    tile = sky(size - 2 * m, size - 2 * m, seed=3, stars=size >= 48).convert("RGBA")
    mask = Image.new("L", tile.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, tile.width - 1, tile.height - 1), radius=max(1, size // 8), fill=255)
    img.paste(tile, (m, m), mask)
    if size >= 32:
        ImageDraw.Draw(img).rounded_rectangle((m, m, size - m - 1, size - m - 1), radius=max(1, size // 8),
                                              outline=ACCENT, width=max(1, size // 32))
    jet = jet_layer(int(size * 0.96), angle=-20)
    img.alpha_composite(jet, ((size - jet.width) // 2, (size - jet.height) // 2))
    return img


# The colours the 16-colour icon keeps to (all in VGA16), so the jet reads
# cleanly at 32 px: navy sky, white and silver hull, grey shading, yellow
# accents and border, cyan canopy and engine glow.
SMALL = [(0, 0, 128), (0, 0, 0), (192, 192, 192), (255, 255, 255), (128, 128, 128),
         (255, 255, 0), (0, 255, 255), (0, 128, 128)]


def draw16(size):
    """A 16-colour version on the VGA palette: the jet nose-up (straight
    edges stay clean at 32 px), nearest colours, no dithering, hard
    transparency, as a Windows 3.1 icon is."""
    big = size * 8
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    m = big // 16
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((m, m, big - m - 1, big - m - 1), radius=big // 8, fill=(0, 0, 128, 255),
                        outline=(255, 255, 0, 255), width=big // 32)
    jet = jet_layer(int(big * 0.9))
    img.alpha_composite(jet, ((big - jet.width) // 2, (big - jet.height) // 2 + big // 40))
    full = img.resize((size, size), Image.BOX)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    src, dst = full.load(), out.load()
    for y in range(size):
        for x in range(size):
            r, g, b, a = src[x, y]
            if a < 128:
                continue
            c = min(SMALL, key=lambda p: 2 * (p[0] - r) ** 2 + 4 * (p[1] - g) ** 2 + 3 * (p[2] - b) ** 2)
            dst[x, y] = c + (255,)
    return out


def bmp_entry(img, bpp):
    """An icon image as a DIB: BITMAPINFOHEADER, palette (4-bit), XOR bits, AND mask."""
    w, h = img.size
    px = img.load()
    head = struct.pack("<IiiHHIIiiII", 40, w, h * 2, 1, bpp, 0, 0, 0, 0, 16 if bpp == 4 else 0, 0)
    pal = b"".join(struct.pack("<BBBB", b, g, r, 0) for r, g, b in VGA16) if bpp == 4 else b""
    rows = []
    for y in range(h - 1, -1, -1):  # bottom-up
        if bpp == 4:
            row = bytearray()
            for x in range(0, w, 2):
                def idx(xx):
                    r, g, b, a = px[xx, y]
                    return VGA16.index((r, g, b)) if a else 0
                row.append(idx(x) << 4 | (idx(x + 1) if x + 1 < w else 0))
        else:
            row = bytearray()
            for x in range(w):
                r, g, b, a = px[x, y]
                row += bytes((b, g, r, a))
        row += b"\0" * (-len(row) % 4)
        rows.append(bytes(row))
    mask = []
    for y in range(h - 1, -1, -1):
        bits = bytearray((w + 7) // 8)
        for x in range(w):
            if px[x, y][3] < 128:
                bits[x // 8] |= 0x80 >> (x % 8)
        bits += b"\0" * (-len(bits) % 4)
        mask.append(bytes(bits))
    return head + pal + b"".join(rows) + b"".join(mask)


def write_ico(path, entries):
    """entries: (size, bpp, bytes)."""
    out = struct.pack("<HHH", 0, 1, len(entries))
    off = 6 + 16 * len(entries)
    for size, bpp, data in entries:
        colors = 16 if bpp == 4 else 0
        out += struct.pack("<BBBBHHII", size % 256, size % 256, colors, 0, 1, bpp, len(data), off)
        off += len(data)
    with open(path, "wb") as f:
        f.write(out + b"".join(d for _, _, d in entries))


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "assets")
    os.makedirs(out, exist_ok=True)
    big = draw(256)
    png = io.BytesIO()
    big.save(png, "PNG")
    entries = [
        (32, 4, bmp_entry(draw16(32), 4)),   # first: what Windows 3.1-style readers pick
        (16, 4, bmp_entry(draw16(16), 4)),
        (48, 32, bmp_entry(draw(48), 32)),
        (32, 32, bmp_entry(draw(32), 32)),
        (16, 32, bmp_entry(draw(16), 32)),
        (256, 32, png.getvalue()),
    ]
    write_ico(os.path.join(out, "raptua.ico"), entries)
    big.save(os.path.join(out, "raptua.png"))
    print("wrote", os.path.join(out, "raptua.ico"))


if __name__ == "__main__":
    main()
