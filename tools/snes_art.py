#!/usr/bin/env python3
"""The SNES build's art and wave data (snes/build.sh runs it).

  python3 -I tools/snes_art.py --out <work dir> [--data <folder with FILE0000.GLB, FILE0001.GLB>]

Without --data it draws Raptua's own wave: terrain tiles, a map, aircraft
and a boss, all made here (no game content), so CI builds and releases can
share that ROM. With --data it converts sector 1 wave 1 from your own
Raptor v1.2 files instead: the map, its tiles, the enemies' pictures and
sprite-library records, the player's ship. That ROM is for you only.

Writes art.inc (WLA-DX), art.h and the .bin files it includes:
  BG    4bpp 8x8 characters (deduplicated); per map tile 16 (char, palette)
        words; the 9 x 150 map; 8 BG palettes. The game streams characters
        into VRAM as the map scrolls (snes/src/main.c).
  OBJ   4bpp sprite characters for VRAM; the player's 3 frames as 32x32
        objects, everything else as 16x16 units; 8 sprite palettes.
  Wave  enemy types (hit points, flight, speed, path, guns, ...) and the
        actors (row, column, type, difficulty gate), bottom row first.
"""

import argparse
import warnings
import math
import os
import random
import struct
import sys

from PIL import Image, ImageDraw

warnings.filterwarnings("ignore", category=DeprecationWarning)
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

MAP_W, MAP_H, TILE = 9, 150, 32
TRANSPARENT = (255, 0, 255, 0)


# ---- the player's own files (--data) ---------------------------------------

def glb_items(path):
    """(name, bytes) for each item of a GLB archive."""
    key = b"32768GLB"
    raw = open(path, "rb").read()

    def decrypt(data, length=None):
        out = bytearray()
        pos = 25 % len(key)
        prev = key[pos]
        for c in data[:length]:
            out.append((c - key[pos] - prev) & 0xFF)
            prev = c
            pos = (pos + 1) % len(key)
        return bytes(out)

    head = decrypt(raw[:28])
    count = struct.unpack_from("<I", head, 4)[0]
    items = []
    for i in range(count):
        e = decrypt(raw[28 + i * 28:56 + i * 28])
        flags, offset, length = struct.unpack_from("<III", e, 0)
        name = e[12:28].split(b"\0")[0].decode("latin-1")
        data = raw[offset:offset + length]
        items.append((name, decrypt(data) if flags & 1 else data))
    return items


def decode_pic(data, pal):
    """A *_PIC / *_BLK / tile as an RGBA image (pixels not in a run: clear)."""
    _a, _b, spans, w, h = struct.unpack_from("<5I", data, 0)
    img = Image.new("RGBA", (w, h), TRANSPARENT)
    px = img.load()
    if spans == 0:
        for i in range(w * h):
            px[i % w, i // w] = pal[data[20 + i]] + (255,)
        return img
    p = 20
    while p + 16 <= len(data):
        x, y, linear, n = struct.unpack_from("<4i", data, p)
        p += 16
        if linear == -1 and n == -1:
            break
        for i in range(n):
            if 0 <= x + i < w and 0 <= y < h:
                px[x + i, y] = pal[data[p + i]] + (255,)
        p += n
    return img


def from_data(folder):
    def find(name):
        for n in os.listdir(folder):
            if n.lower() == name.lower():
                return os.path.join(folder, n)
        raise SystemExit(f"{name} not found in {folder}")
    items = glb_items(find("FILE0000.GLB")) + glb_items(find("FILE0001.GLB"))
    by_name = {}
    for i, (n, d) in enumerate(items):
        by_name.setdefault(n, i)
    get = lambda n: items[by_name[n]][1]
    pal = [tuple(min(255, c * 4 + c // 16) for c in get("PALETTE_DAT")[i * 3:i * 3 + 3]) for i in range(256)]

    mp = get("MAP1G1_MAP")
    _size, aoff, acount = struct.unpack_from("<III", mp, 0)
    cells = [struct.unpack_from("<HH", mp, 12 + i * 4) for i in range(MAP_W * MAP_H)]
    start = by_name["STARTG1TILES"]
    tile_ids, tiles, cell_tiles = {}, [], []
    for t, s in cells:
        if (t, s) not in tile_ids:
            tile_ids[(t, s)] = len(tiles)
            tiles.append(decode_pic(items[by_name["STARTG%dTILES" % (s + 1)] + 1 + t][1], pal).convert("RGB"))
        cell_tiles.append(tile_ids[(t, s)])

    lib = get("SPRITE1_ITM")
    types, type_of, pics, pic_of = [], {}, [], {}
    actors = []
    for i in range(acount):
        _link, slib, x, y, _game, lvl = struct.unpack_from("<6i", mp, aoff + i * 24)
        if slib not in type_of:
            r = lib[slib * 528:(slib + 1) * 528]
            name = r[:16].split(b"\0")[0].decode("latin-1")
            f = struct.unpack_from("<26i", r, 16)
            tab = [struct.unpack_from("<24h", r, 120 + k * 48) for k in range(6)]
            px_ = struct.unpack_from("<30h", r, 408)
            py_ = struct.unpack_from("<30h", r, 468)
            if name not in pic_of:
                pic_of[name] = len(pics)
                pics.append(decode_pic(get(name), pal))
            n = max(0, min(30, f[19]))
            guns = max(0, min(4, f[22]))
            type_of[slib] = len(types)
            types.append(dict(pic=pic_of[name], hp=max(1, f[13]), bounty=f[14], flight=f[21], speed=max(1, f[18]),
                              path=list(zip(px_[:n], py_[:n])), repos=max(0, f[20]), boss=1 if f[12] else 0,
                              countdown=f[8], shootstart=f[15], shootcnt=f[16], shootframe=f[17],
                              shootspace=f[3], guns=[(tab[4][g], tab[5][g]) for g in range(guns)]))
        actors.append((y, x, type_of[slib], lvl))

    player = decode_pic(get("LPLAYER_PIC"), pal)
    frames = [player.crop((k * 32, 0, k * 32 + 32, 32)) if player.width >= 224 else player for k in (0, 3, 6)]
    if player.width < 224:   # stacked vertically
        frames = [player.crop((0, k * 32, 32, k * 32 + 32)) for k in (0, 3, 6)]
    shot = decode_pic(get("NMSHOT_BLK"), pal)
    eshot = decode_pic(get("ESHOT_BLK"), pal)
    return dict(tiles=tiles, cells=cell_tiles, actors=actors, types=types, pics=pics,
                player=frames, shot=shot, eshot=eshot, explosion=own_explosion(), source="your Raptor files")


# ---- Raptua's own wave (the default) -----------------------------------------

def own_tiles():
    """Terrain tiles drawn here: sea, coast, grass, forest, roads, a base."""
    rnd = random.Random(1)
    sea, sea2 = (24, 64, 120), (32, 84, 150)
    sand, grass, grass2 = (196, 176, 120), (60, 120, 52), (44, 98, 40)
    road, line, roof, roof2 = (86, 86, 90), (220, 210, 120), (150, 70, 52), (120, 120, 128)

    def base(color, noise=12, seed=0):
        im = Image.new("RGB", (TILE, TILE), color)
        px = im.load()
        r = random.Random(seed)
        for y in range(TILE):
            for x in range(TILE):
                d = r.randint(-noise, noise)
                c = px[x, y]
                px[x, y] = tuple(max(0, min(255, v + d)) for v in c)
        return im

    tiles = []
    water = base(sea, 6, 1)
    d = ImageDraw.Draw(water)
    for k in range(3):
        y = 6 + k * 10
        d.arc((4 + k * 7, y, 16 + k * 7, y + 6), 200, 340, fill=sea2)
    tiles.append(water)                                  # 0 sea
    tiles.append(base(grass, 14, 2))                     # 1 grass
    forest = base(grass2, 10, 3)
    d = ImageDraw.Draw(forest)
    for _ in range(6):
        x, y = rnd.randint(2, 24), rnd.randint(2, 24)
        d.ellipse((x, y, x + 8, y + 8), fill=(30, 76, 30), outline=(20, 56, 22))
    tiles.append(forest)                                 # 2 forest
    for side in ("left", "right"):                       # 3, 4 coast (land on that side)
        im = base(sea, 6, 4)
        d = ImageDraw.Draw(im)
        if side == "left":
            d.polygon([(0, 0), (18, 0), (14, 10), (20, 22), (15, 32), (0, 32)], fill=sand)
            d.polygon([(0, 0), (12, 0), (9, 12), (13, 24), (9, 32), (0, 32)], fill=grass)
        else:
            d.polygon([(32, 0), (14, 0), (18, 10), (12, 22), (17, 32), (32, 32)], fill=sand)
            d.polygon([(32, 0), (20, 0), (23, 12), (19, 24), (23, 32), (32, 32)], fill=grass)
        tiles.append(im)
    rd = base(grass, 14, 5)                              # 5 road (vertical)
    d = ImageDraw.Draw(rd)
    d.rectangle((10, 0, 21, 31), fill=road)
    for y in (2, 18):
        d.rectangle((15, y, 16, y + 8), fill=line)
    tiles.append(rd)
    pad = base(roof2, 6, 6)                              # 6 concrete
    d = ImageDraw.Draw(pad)
    d.line((0, 15, 31, 15), fill=(100, 100, 108))
    d.line((15, 0, 15, 31), fill=(100, 100, 108))
    tiles.append(pad)
    bld = base(grass, 14, 7)                             # 7 building
    d = ImageDraw.Draw(bld)
    d.rectangle((5, 6, 26, 25), fill=roof, outline=(90, 40, 30))
    d.line((5, 15, 26, 15), fill=(110, 50, 40))
    tiles.append(bld)
    return tiles


def own_map():
    """A coastline that winds up the map, with roads, forest and a base."""
    rnd = random.Random(7)
    cells = []
    for row in range(MAP_H):
        coast = 4 + int(2.5 * math.sin(row / 9.0))
        line = []
        for col in range(MAP_W):
            if col < coast - 1:
                line.append(0)
            elif col == coast - 1:
                line.append(4)
            else:
                v = rnd.random()
                if col == coast + 2 and row % 40 < 30:
                    line.append(5)
                elif row < 20 and col > coast:
                    line.append(6 if (row + col) % 3 else 7)
                else:
                    line.append(2 if v < 0.35 else 7 if v > 0.93 else 1)
        cells.extend(line)
    return cells


def own_ship(color, size, shape=0):
    """An aircraft seen from above, nose down (an enemy), drawn here."""
    s = size * 4
    im = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    P = lambda pts: [(x * s / 32, y * s / 32) for x, y in pts]
    dark = tuple(max(0, c - 60) for c in color)
    if shape == 0:      # swept wings
        d.polygon(P([(16, 30), (2, 8), (6, 6), (16, 14), (26, 6), (30, 8)]), fill=color)
    elif shape == 1:    # straight wings
        d.polygon(P([(1, 12), (31, 12), (31, 17), (1, 17)]), fill=color)
    else:               # delta
        d.polygon(P([(16, 31), (3, 4), (29, 4)]), fill=color)
    d.polygon(P([(14, 2), (18, 2), (19, 26), (16, 31), (13, 26)]), fill=dark)
    d.ellipse(P([(14, 18), (18, 24)]), fill=(150, 220, 255))
    return im.resize((size, size), Image.LANCZOS)


def own_boss():
    s = 4
    im = Image.new("RGBA", (80 * s, 40 * s), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    P = lambda pts: [(x * s, y * s) for x, y in pts]
    d.polygon(P([(40, 39), (0, 10), (6, 2), (40, 12), (74, 2), (80, 10)]), fill=(120, 120, 136))
    d.polygon(P([(32, 0), (48, 0), (50, 34), (40, 39), (30, 34)]), fill=(80, 80, 96))
    for x in (14, 26, 54, 66):
        d.rectangle(P([(x - 2, 8), (x + 2, 18)]), fill=(200, 60, 40))
    d.ellipse(P([(36, 22), (44, 30)]), fill=(255, 200, 60))
    return im.resize((80, 40), Image.LANCZOS)


def own_explosion():
    frames = []
    for k in range(4):
        im = Image.new("RGBA", (16 * 4, 16 * 4), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        r = 10 + k * 7
        c = [(255, 240, 120), (255, 170, 40), (220, 90, 30), (110, 90, 90)][k]
        d.ellipse((32 - r, 32 - r, 32 + r, 32 + r), fill=c + (255,))
        if k < 3:
            d.ellipse((32 - r // 2, 32 - r // 2, 32 + r // 2, 32 + r // 2), fill=(255, 255, 220, 255))
        frames.append(im.resize((16, 16), Image.LANCZOS))
    return frames


def own_wave():
    from make_aurora_art import jet_layer
    jet = jet_layer(32)
    player = [jet.rotate(a, resample=Image.BICUBIC) for a in (8, 0, -8)]
    pics = [own_ship((176, 64, 56), 24, 0), own_ship((90, 140, 70), 32, 1),
            own_ship((150, 150, 170), 24, 2), own_ship((200, 160, 60), 32, 0), own_boss()]
    sweep = [(-60, -120), (-60, 0), (60, 60), (60, 400)]
    straight = [(0, 400)]
    zig = [(40, -60), (-40, 0), (40, 60), (-40, 120), (0, 400)]
    types = [
        dict(pic=0, hp=3, bounty=100, flight=1, speed=4, path=straight, repos=0, boss=0, countdown=40,
             shootstart=10, shootcnt=1, shootframe=40, shootspace=10, guns=[(12, 22)]),
        dict(pic=1, hp=8, bounty=250, flight=1, speed=3, path=sweep, repos=0, boss=0, countdown=20,
             shootstart=5, shootcnt=2, shootframe=30, shootspace=6, guns=[(16, 28)]),
        dict(pic=2, hp=4, bounty=150, flight=1, speed=5, path=zig, repos=0, boss=0, countdown=60,
             shootstart=10, shootcnt=1, shootframe=50, shootspace=10, guns=[(12, 22)]),
        dict(pic=3, hp=10, bounty=300, flight=2, speed=3, path=[(0, -40)], repos=0, boss=0, countdown=30,
             shootstart=5, shootcnt=3, shootframe=40, shootspace=5, guns=[(16, 28)]),
        dict(pic=4, hp=300, bounty=5000, flight=0, speed=2, path=[(0, -130), (-70, -110), (70, -110)], repos=1,
             boss=1, countdown=0, shootstart=10, shootcnt=6, shootframe=30, shootspace=4,
             guns=[(14, 36), (40, 38), (66, 36)]),
    ]
    rnd = random.Random(3)
    actors = []
    for row in range(MAP_H - 8, 12, -3):
        kind = rnd.choice((0, 0, 1, 2, 2, 3))
        col = rnd.randint(1, 7)
        for k in range(2 if kind in (0, 2) else 1):
            actors.append((row - k, max(0, min(8, col + k * 2 - 1)), kind, 3))
    actors.append((8, 4, 4, 3))
    return dict(tiles=own_tiles(), cells=own_map(), actors=actors, types=types, pics=pics, player=player,
                shot=own_shot((255, 240, 160)), eshot=own_shot((255, 90, 60)), explosion=own_explosion(),
                source="Raptua's own art")


def own_shot(color):
    im = Image.new("RGBA", (8, 8), (0, 0, 0, 0))
    ImageDraw.Draw(im).ellipse((2, 1, 5, 6), fill=color + (255,))
    return im


# ---- SNES encoding -------------------------------------------------------------

def snes_rgb(c):
    r, g, b = c[:3]
    return (r >> 3) | ((g >> 3) << 5) | ((b >> 3) << 10)


def nearest(c, pal):
    return min(range(len(pal)), key=lambda i: (pal[i][0] - c[0]) ** 2 * 2 + (pal[i][1] - c[1]) ** 2 * 4 + (pal[i][2] - c[2]) ** 2 * 3)


def reduce_colors(images, n):
    """A shared palette of n colours for a list of RGB(A) images (opaque pixels)."""
    pixels = [p[:3] for im in images for p in im.convert("RGBA").getdata() if p[3] >= 128]
    if not pixels:
        return [(0, 0, 0)]
    strip = Image.new("RGB", (len(pixels), 1))
    strip.putdata(pixels)
    q = strip.quantize(colors=min(n, 256), method=Image.Quantize.MEDIANCUT)
    p = q.getpalette()[:3 * n]
    used = sorted(set(q.getdata()))
    return [tuple(p[i * 3:i * 3 + 3]) for i in used]


def pack_palettes(sets, slots):
    """Puts colour sets (each <= 15) into at most `slots` palettes; None if they won't fit."""
    pals = []
    where = [None] * len(sets)
    for i in sorted(range(len(sets)), key=lambda i: -len(sets[i])):
        s = sets[i]
        best, grow = None, None
        for k, p in enumerate(pals):
            g = len(s - p)
            if len(p | s) <= 15 and (grow is None or g < grow):
                best, grow = k, g
        if best is None:
            if len(pals) == slots:
                return None
            pals.append(set(s))
            best = len(pals) - 1
        pals[best] |= s
        where[i] = best
    return [sorted(p) for p in pals], where


def fit(blocks, slots, start=96):
    """Quantises blocks (RGBA images) so each uses <= 15 colours and they all
    fit in `slots` palettes. Returns (palettes as RGB lists, per block palette
    number, per block index image with 0 = clear)."""
    n = start
    while True:
        shared = reduce_colors(blocks, n)
        idx_sets, mapped = [], []
        for b in blocks:
            px = list(b.convert("RGBA").getdata())
            m = [None if p[3] < 128 else nearest(p, shared) for p in px]
            counts = {}
            for v in m:
                if v is not None:
                    counts[v] = counts.get(v, 0) + 1
            keep = sorted(counts, key=lambda v: -counts[v])[:15]
            ks = [shared[k] for k in keep]
            m = [None if v is None else (v if v in keep else keep[nearest(shared[v], ks)]) for v in m]
            idx_sets.append(set(v for v in m if v is not None))
            mapped.append(m)
        packed = pack_palettes(idx_sets, slots)
        if packed:
            pals, where = packed
            out_pals = [[shared[k] for k in p] for p in pals]
            images = []
            for m, k in zip(mapped, where):
                order = pals[k]
                images.append([0 if v is None else order.index(v) + 1 for v in m])
            return out_pals, where, images
        n = int(n * 0.8)


def char4(indices, w, x0, y0):
    """One 8x8 4bpp SNES character from an index image (row width w)."""
    out = bytearray(32)
    for y in range(8):
        for x in range(8):
            v = indices[(y0 + y) * w + x0 + x]
            bit = 7 - x
            for plane in range(4):
                if v >> plane & 1:
                    off = (plane // 2) * 16 + y * 2 + (plane & 1)
                    out[off] |= 1 << bit
    return bytes(out)


def encode_bg(tiles):
    blocks = []
    for t in tiles:
        for cy in range(4):
            for cx in range(4):
                blocks.append(t.crop((cx * 8, cy * 8, cx * 8 + 8, cy * 8 + 8)).convert("RGBA"))
    pals, where, images = fit(blocks, 8)
    chars, char_id, entries = [], {}, []
    for img, pal in zip(images, where):
        c = char4([v for v in img], 8, 0, 0)
        if c not in char_id:
            char_id[c] = len(chars)
            chars.append(c)
        entries.append((char_id[c], pal))
    return pals, chars, entries


def sprite_units(img, unit=16):
    """Pads an RGBA picture to whole 16x16 units: (units across, down, image)."""
    w, h = img.size
    ux, uy = (w + unit - 1) // unit, (h + unit - 1) // unit
    canvas = Image.new("RGBA", (ux * unit, uy * unit), (0, 0, 0, 0))
    canvas.paste(img, ((ux * unit - w) // 2, (uy * unit - h) // 2), img)
    return ux, uy, canvas


def encode_sprites(d):
    """OBJ characters for a 16-character-wide sheet (512 characters: two
    pages of 16 x 16). The player's three 32x32 frames take the first three
    32x32 blocks; everything else is placed as 16x16 units."""
    pictures = [("player%d" % k, f, 0) for k, f in enumerate(d["player"])]
    pictures += [("shot", d["shot"], 1), ("eshot", d["eshot"], 1)]
    pictures += [("explo%d" % k, f, 1) for k, f in enumerate(d["explosion"])]
    pictures += [("pic%d" % k, p, None) for k, p in enumerate(d["pics"])]
    # Palettes: 0 the player, 1 shots and explosions, 2..7 the enemies.
    fixed = {0: [p[1] for p in pictures if p[2] == 0], 1: [p[1] for p in pictures if p[2] == 1]}
    out_pals = [None] * 8
    pic_pal, pic_idx = {}, {}
    for slot, imgs in fixed.items():
        pals, _, idx = fit(imgs, 1, 15)
        out_pals[slot] = pals[0]
        for (name, _img, s), ix in zip([p for p in pictures if p[2] == slot], idx):
            pic_pal[name], pic_idx[name] = slot, ix
    enemies = [p for p in pictures if p[2] is None]
    if enemies:
        pals, where, idx = fit([p[1] for p in enemies], 6, 90)
        for k, pal in enumerate(pals):
            out_pals[2 + k] = pal
        for (name, _img, _s), w, ix in zip(enemies, where, idx):
            pic_pal[name], pic_idx[name] = 2 + w, ix
    sheet = bytearray(512 * 32)
    used_units = set()
    for b in range(3):   # the player's 32x32 blocks: characters b*4 .. +3, rows 0..3
        for u in (0, 1, 8, 9):
            used_units.add(b * 2 + u)
    def unit_char(u):
        return (u % 8) * 2 + (u // 8) * 32
    def put(img_idx, w, x0, y0, char):
        sheet[char * 32:char * 32 + 32] = char4(img_idx, w, x0, y0)
    # Player frames.
    for k in range(3):
        name = "player%d" % k
        ix, w = pic_idx[name], 32
        for cy in range(4):
            for cx in range(4):
                put(ix, w, cx * 8, cy * 8, k * 4 + cx + cy * 16)
    table = []
    free = [u for u in range(128) if u not in used_units]
    for name, img, _s in pictures[3:]:
        ux, uy, canvas = sprite_units(img)
        # Re-index the padded picture with this picture's palette.
        pal = out_pals[pic_pal[name]]
        base = list(img.getdata())
        src = pic_idx[name]
        idx = [0] * (canvas.width * canvas.height)
        ox, oy = (canvas.width - img.width) // 2, (canvas.height - img.height) // 2
        for y in range(img.height):
            for x in range(img.width):
                idx[(y + oy) * canvas.width + x + ox] = src[y * img.width + x]
        units = []
        for vy in range(uy):
            for vx in range(ux):
                if all(idx[(vy * 16 + y) * canvas.width + vx * 16 + x] == 0 for y in range(16) for x in range(16)):
                    units.append(0xFF)
                    continue
                if not free:
                    raise SystemExit("sprites don't fit in 512 characters")
                u = free.pop(0)
                c = unit_char(u)
                for cy in range(2):
                    for cx in range(2):
                        put(idx, canvas.width, vx * 16 + cx * 8, vy * 16 + cy * 8, c + cx + cy * 16)
                units.append(c)
        table.append((name, ux, uy, canvas.width, canvas.height, pic_pal[name], units))
    pals = [p or [(0, 0, 0)] for p in out_pals]
    return pals, bytes(sheet), table


# ---- output --------------------------------------------------------------------

def emit(out, d):
    pals_bg, chars, entries = encode_bg(d["tiles"])
    pals_obj, sheet, table = encode_sprites(d)
    os.makedirs(out, exist_ok=True)

    def wpal(pals):
        b = bytearray()
        for p in pals:
            row = [(0, 0, 0)] + list(p) + [(0, 0, 0)] * (15 - len(p))
            b += b"".join(struct.pack("<H", snes_rgb(c)) for c in row[:16])
        b += b"\0" * (256 - len(b))
        return bytes(b)

    files = {
        "art_bgpal.bin": wpal(pals_bg),
        "art_objpal.bin": wpal(pals_obj),
        "art_bgchars.bin": b"".join(chars),
        "art_tiles.bin": b"".join(struct.pack("<HB", c, p) + b"\0" for c, p in entries),   # 4 bytes per char
        "art_map.bin": b"".join(struct.pack("<B", t) for t in d["cells"]),
        "art_objchars.bin": sheet,
    }
    if len(chars) > 3072:
        raise SystemExit("more than 3072 BG characters (3 banks)")
    if len(d["tiles"]) > 255:
        raise SystemExit("more than 255 distinct map tiles")
    # Pictures: w_units, h_units, palette, then up to 16 unit characters (0xFFFF none).
    pics = bytearray()
    names = [t[0] for t in table]
    for name, ux, uy, w, h, pal, units in table:
        if len(units) > 16:
            raise SystemExit(f"{name}: bigger than 4 x 4 units")
        u = units + [0xFF] * (16 - len(units))
        pics += struct.pack("<BBBB", ux, uy, pal, 0) + b"".join(struct.pack("<H", 0xFFFF if v == 0xFF else v) for v in u)
    files["art_pics.bin"] = bytes(pics)
    # Enemy types: 32 x i16 header + path 30 x (x, y) i16.
    first_enemy_pic = names.index("pic0") if "pic0" in names else 0
    types = bytearray()
    for t in d["types"]:
        guns = (t["guns"] + [(0, 0)] * 4)[:4]
        hdr = [t["pic"] + first_enemy_pic, t["hp"], t["bounty"] // 10, t["flight"], t["speed"], len(t["path"]),
               t["repos"], t["boss"], t["countdown"], t["shootstart"], t["shootcnt"], t["shootframe"],
               t["shootspace"], len(t["guns"])] + [v for g in guns for v in g]
        hdr += [0] * (32 - len(hdr))
        path = (list(t["path"]) + [(0, 0)] * 30)[:30]
        types += struct.pack("<32h", *[max(-32768, min(32767, v)) for v in hdr])
        types += b"".join(struct.pack("<hh", x, y) for x, y in path)
    files["art_types.bin"] = bytes(types)
    acts = sorted(d["actors"], key=lambda a: -a[0])
    files["art_actors.bin"] = b"".join(struct.pack("<hBBBB", r, c, k, lv, 0) for r, c, k, lv in acts) + struct.pack("<hBBBB", -32768, 0, 0, 0, 0)
    for n, b in files.items():
        open(os.path.join(out, n), "wb").write(b)

    inc = ["; Generated by tools/snes_art.py (%s)." % d["source"]]
    for n, b in files.items():
        label = n[:-4]
        # One bank (32 KB) at most per section; the BG characters can be bigger.
        if len(b) <= 0x8000 and label != "art_bgchars":
            inc += ['.section "%s" superfree' % label, "%s: .incbin \"%s\"" % (label, n), "%s_end:" % label, ".ends"]
        else:
            parts = (len(b) + 0x7FFF) // 0x8000
            for k in range(parts):
                inc += ['.section "%s%d" superfree' % (label, k),
                        "%s%d: .incbin \"%s\" skip %d read %d" % (label, k, n, k * 0x8000, min(0x8000, len(b) - k * 0x8000)),
                        ".ends"]
    open(os.path.join(out, "art.inc"), "w").write("\n".join(inc) + "\n")
    bg_parts = (len(files["art_bgchars.bin"]) + 0x7FFF) // 0x8000
    h = ["/* Generated by tools/snes_art.py (%s). */" % d["source"], "#ifndef RAPTUA_ART_H", "#define RAPTUA_ART_H",
         "#define ART_BG_CHARS %d" % len(chars), "#define ART_BG_PARTS %d" % bg_parts,
         "#define ART_TILES %d" % len(d["tiles"]), "#define ART_TYPES %d" % len(d["types"]),
         "#define ART_ACTORS %d" % len(d["actors"]), "#define ART_PICS %d" % len(names)]
    for i, n in enumerate(names):
        h.append("#define PIC_%s %d" % (n.upper(), i))
    for n in files:
        label = n[:-4]
        if len(files[n]) <= 0x8000 and label != "art_bgchars":
            h.append("extern char %s, %s_end;" % (label, label))
    for k in range(bg_parts):
        h.append("extern char art_bgchars%d;" % k)
    h.append("#define ART_BG_PART_LIST " + ", ".join("&art_bgchars%d" % k for k in range(bg_parts)))
    h.append("#endif")
    open(os.path.join(out, "art.h"), "w").write("\n".join(h) + "\n")
    print("%s: %d tiles, %d BG characters (%d KB), %d pictures, %d enemy types, %d actors" % (
        d["source"], len(d["tiles"]), len(chars), len(chars) * 32 // 1024, len(names), len(d["types"]), len(d["actors"])))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--data")
    a = ap.parse_args()
    emit(a.out, from_data(a.data) if a.data else own_wave())


if __name__ == "__main__":
    main()
