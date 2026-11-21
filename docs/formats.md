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

## Sprite library `SPRITEn_ITM` (known)

There are 131 records of 528 bytes in the shareware data.

| Bytes | Field |
|---|---|
| 0–15 | name of the first frame (`SHIP01G1_PIC`) |
| 16–119 | 26 × i32, Lua `f[1..26]`: item, bonus, explosion type, shot spacing, (ground, unused), suck, frame rate, frame count, countdown, rewind, anim type, shadow, boss flag, hit points, bounty, shoot start, volleys per burst, burst rest, move speed, flight point count, repeat-from point, flight type, gun count, engine count, (sfx, unused), song |
| 120–407 | six `i16[24]` per-gun tables: shot type, engine flame x, y, width, shot origin x, y |
| 408–467 | `i16[30]` flight path x |
| 468–527 | `i16[30]` flight path y |

`item` is a GLB handle in the original build (it doesn't match v1.2's handles), so frames are looked up by name. `bonus` is an object number (see `scripts/game/weapons.lua`). Flight types: 0 repeat, 1 linear, 2 kamikaze, 3 ground, 4 ground moving left, 5 ground moving right. Air paths are offsets from the spawn column and the screen's middle line (y = 100). The game logic runs once every 3 vertical blanks (70/3 ≈ 23.3 Hz), and the map scrolls 1 pixel per frame. An actor spawns when its row is 3 rows above the top of the screen.

## Tile damage `FLATSGn_ITM` (known)

8 bytes per tile of the set (672 for G1): `i16 linkflat, i16 unused (0), i16 hits, i16 bounty`. `hits == -1` means the tile is indestructible, and its `linkflat` is itself. Otherwise, when its hit points run out, the tile becomes `linkflat`, its wrecked version (rubble, a broken bridge), and pays `bounty`. 156 of the 672 G1 tiles are destructible.

## Sounds `*_FX` (known)

Each `NAME_FX` is an empty marker. It is followed by unnamed items, one per sound device, each starting with a `u16` format: 0 = PC speaker, 1 and 2 = the FM/AdLib versions, 3 = digitized. The digitized one is a DMX sound: `u16 3, u16 rate (11025), u32 samples`, then unsigned 8-bit mono PCM. All 26 effects have a digitized version. Raptua uses only those.

## Music `*_MUS` (known)

DMX MUS: `"MUS\x1A", u16 score_len, u16 score_start, u16 channels, u16 secondary, u16 instrument_count, u16 reserved, u16 instruments[]`, then the score. Each event byte holds: bit 7 = a delay follows, bits 4–6 = type (release, play, pitch bend, system, controller, measure end, score end), bits 0–3 = channel. The delay is a variable-length run of 7-bit groups, in 140 Hz ticks. Channel 15 is percussion. v1.2 has 16 songs: `APOGEE`, `RINTRO`, `MAINMENU`, `HANGAR`, `RAP1`–`RAP8` and `BOSS1`–`BOSS4`.

`GENMIDI_OP2` is the OPL bank: `"#OPL_II#"`, then 175 instruments of 36 bytes (`u16 flags` (1 = fixed pitch, 4 = double voice), `u8 finetune`, `u8 fixed_note`, then two 16-byte voices of modulator/feedback/carrier registers and an `i16` note offset), then 175 names of 32 bytes. Instruments 0–127 are melodic; 128–174 are percussion for keys 35–81.

Raptua plays them on an emulated OPL3 (ymfm's YMF262), 18 voices, with left/right from the MUS pan controller.

## Open questions

- Enemy movement and firing rules (sprite library tables and paths).
- AGX cutscene frames, SWD window layouts, REC demo macros.
