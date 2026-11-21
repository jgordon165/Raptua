# Raptor v1.2 data formats

Everything is little-endian. Status: **known** = checked against the v1.2 shareware data by the decoders and tests. **guess** = consistent with the data but not yet confirmed against `RAP.EXE`.

## Distribution (shareware `1rap12.zip`)

`RAPSW12.SHR` is a PKZIP archive with a PKLITE-packed self-extractor stub in front, so `unzip` reads it directly. It holds `RAP.EXE`, `SETUP.EXE`, `RAPHELP.EXE`, `FILE0000.GLB` (text, sounds, music) and `FILE0001.GLB` (graphics, levels).

## GLB archive (known)

- A table of 28-byte entries at offset 0: `u32 flags, u32 offset, u32 length, char name[16]`.
- Entry 0 is a header. Its `offset` field holds the item count.
- Each table entry is encrypted on its own. Item data is encrypted when `flags & 1`, as one stream.
- Cipher: key `32768GLB`, starting at position `25 % 8`. "Previous" starts as that key byte. `plain = cipher - key[pos] - previous_cipher` (mod 256), then the position advances and wraps. Encrypting an all-zero header gives the signature `64 9B D1 09`.
- Names are not unique. Animation frames share one name and sit next to each other, so frame *n* of `NAME` is `find(NAME) + n`. Some items have no name (tiles, sound variants).
- Item handle = `(file_number << 16) | index`.

## Images: `*_PIC`, `*_BLK`, tiles (known)

The header is five `u32`: `a, b, spans, width, height`.

- `spans == 0`: `width*height` raw palette indices follow (full screens, tiles).
- otherwise: runs `{i32 x, i32 y, i32 linear, i32 n, u8 pixels[n]}` (`linear = x + 320*y`), ending with a run where `linear == n == -1`. Pixels not in a run are transparent.
- `a`/`b` (guess): full screens have `1, 1`. On sprites they vary and may be a hotspot or a draw mode.

## Player ship `LPLAYER_PIC` (known)

Seven 32×32 sprite frames: banked hard left (0), level (3), banked hard right (6). `SHIPGLOW_BLK` (4 frames, 56×56) is an expanding ring around the ship, probably the shield flash (guess).

## Palettes `*_DAT` (known)

768 bytes of 6-bit VGA RGB. `PALETTE_DAT` is the game palette. `POGPAL`, `CYGPAL` and `TAIPAL` are for the Apogee, Cygnus and warning screens.

## Fonts `*_FNT` (known)

`i32 height, i16 offset[256] (-1 = missing), u8 width[256]`, then glyph bitmaps (`width*height` bytes each, 0 = transparent).

## Tiles (known)

Tiles are the unnamed items between `STARTGnTILES` and `ENDGnTILES`, each a raw 32×32 image. Map cell (tile *t*, set *s*) draws item `STARTG{s+1}TILES + 1 + t`.

## Levels `MAPnGn_MAP` (known)

- `u32 file_size, u32 actor_offset (0x1524), u32 actor_count`
- `9 × 150` cells of `u16 tile, u16 tileset`, top row first. Play starts at the bottom and scrolls up.
- Actors: 24 bytes each: `link, slib, x (column 0–8), y (row), game (sprite bank), level (difficulty gate: 3/4/5 = easy/medium/hard; other values are special)`.

## Sprite library `SPRITEn_ITM` (partly known)

There are 131 records of 528 bytes in the shareware data.

| Bytes | Field | Status |
|---|---|---|
| 0–15 | name of the first frame (`SHIP01G1_PIC`) | known |
| 16–119 | 26 × i32, Lua `f[1..26]` | see below |
| 120–407 | six `i16[24]` tables | guess: per-shot timing / kind / x / y |
| 408–465 | `i16[29]` path x | guess |
| 466–523 | `i16[29]` path y | guess |
| 524–527 | i32, always 0 | known |

In the `f[]` ints: `f[1]` = item handle in the build the library was made for (it does not match v1.2's handles, so the engine looks frames up by name), `f[8]` = frame count, `f[14]` = hit points, `f[15]` = bounty, `f[24]` = number of shot-table entries. All of these are guesses that fit every record. The rest are unnamed.

## Tile damage `FLATSGn_ITM` (known)

8 bytes per tile of the set (672 for G1): `i16 linkflat, i16 unused (0), i16 hits, i16 bounty`. `hits == -1` means the tile is indestructible, and its `linkflat` is itself. Otherwise, when its hit points run out, the tile becomes `linkflat`, its wrecked version (rubble, a broken bridge), and pays `bounty`. 156 of the 672 G1 tiles are destructible.

## Sounds `*_FX` (known)

Each `NAME_FX` is an empty marker. It is followed by unnamed items, one per sound device. The digitized one is a DMX sound: `u16 3, u16 rate (11025), u32 samples`, then unsigned 8-bit mono PCM. The other variants (PC speaker and the rest) are not decoded yet.

## Music `*_MUS` (known container)

DMX MUS (`MUS\x1A`), played through `GENMIDI_OP2` OPL patches. Not played yet.

## Open questions

- Enemy movement and firing rules (sprite library tables and paths).
- AGX cutscene frames, SWD window layouts, REC demo macros.
