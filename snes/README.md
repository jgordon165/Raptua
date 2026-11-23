# Raptua for the Super Nintendo

Sector 1, wave 1 of Raptor as a SNES cartridge ROM, built with
[PVSnesLib](https://github.com/alekmaul/pvsneslib) (zlib licence) in mode 1.
This is the first milestone: one playable wave.

- **Map:** the wave's 9 × 150 map of 32-pixel tiles scrolls up one pixel per game frame, as in the original. The 288-pixel-wide map is shown 256 pixels wide and pans with the ship. Its tiles are 4bpp characters (8 palettes of 15 colours), streamed into a 1024-character VRAM cache as rows come into view.
- **Timing:** the game runs in the original's game frames, about 23.3 a second (7 of every 18 SNES frames). Enemies fly their sprite-library paths, by flight type, speed and repeat point, and fire bursts at the ship by their countdown, burst and rest timings. The ship itself moves every frame.
- **The wave:** ground targets scroll with the map, and boss and enemy hit points come from the records. The wave is won when the last enemy has appeared and every enemy is gone; the ship then flies off the top and the wave starts again. If the shield runs out, the wave restarts.
- **Not yet:** music and sound, the HUD, weapon upgrades and the other waves.

| Pad | |
|---|---|
| D-pad | Fly |
| B or Y | Fire (hold) |
| Start | Pause |

Leave the pad alone for five seconds and the ship flies itself and fires (the demo the smoke test watches).

## Art and your Raptor files

The art and the wave are built into the ROM by `tools/snes_art.py`.

- **By default:** the wave is Raptua's own. The terrain, map, aircraft, boss and enemy waves are all drawn by the tool, with no game content, so CI builds that ROM and releases share it.
- **`--data`:** builds sector 1 wave 1 from your own Raptor v1.2 files (`FILE0000.GLB`, `FILE0001.GLB`): the map, its tiles, the enemies and their sprite-library records, and your ship. That ROM is for you only; don't share it.

## Building

On Linux x64 with Python 3 and Pillow:

```
eval "$(snes/setup-pvsneslib.sh .pvsneslib)"         # PVSnesLib 4.7.1, checksum-verified
snes/build.sh build-snes                              # -> build-snes/raptua-snes.sfc (Raptua's own wave)
snes/build.sh build-snes-mine --data ~/RAPTOR         # your own files' wave, private
```

Run the ROM in any SNES emulator (bsnes, Snes9x, Mesen), or on the console from a flash cartridge.

## Tests

- **Smoke test:** CI runs the ROM headless for 4000 frames in the snes9x libretro core (`apt install libretro-snes9x`) through `snes/tests/libretro_run.py`, with no input, so the demo plays.
- **What it checks:** `snes/tests/snes_smoke.sh` reads the game's state from work RAM. It fails unless the map has scrolled, enemies have appeared and some have been shot down.
- **Artifacts:** the job keeps the ROM, the snapshots and the result.
