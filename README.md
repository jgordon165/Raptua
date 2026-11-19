# Raptua

A Lua recompilation of the DOS game **Raptor: Call of the Shadows** (Cygnus Studios / Apogee, 1994).

The engine is C++20 on SDL2. It reads the original GLB archives, draws the 320×200 VGA screen, mixes sound and handles input. The game itself (scenes, levels, player, enemies, HUD) is Lua in `scripts/`, so you can change it without rebuilding.

**No game data is included.** Raptua loads `FILE0000.GLB` and `FILE0001.GLB` from your own copy of Raptor v1.2 (shareware or registered).

## Status

Early. What works today:

- GLB archives: encrypted tables and items, lookup by name (`src/formats/glb.*`)
- Images, sprites, 32×32 tiles, palettes, fonts and digitized sound effects
- Levels: the 9×150 tile map scrolls, and enemies spawn from the map's actor list using the sprite library
- A playable first pass of Tango Sector: movement (keyboard, mouse, game pad), twin guns, enemy fire, bounties, explosions, shield, sector-to-sector progression
- An asset explorer (F1) for browsing everything in the archives

Still to come (roughly in order): the real enemy flight and shot rules read out of `RAP.EXE`, the player's ship sprite, weapons and the store/hangar, MUS music through OPL (GENMIDI.OP2), cutscenes (AGX), menus and saves, then other platforms the same way as Meguarace and Tetrispack. `docs/formats.md` lists what is known and what is still a guess.

## Running

1. Get Raptor v1.2. In the shareware zip (`1rap12.zip`), `RAPSW12.SHR` is a zip archive with a self-extractor in front. `unzip RAPSW12.SHR` (or running `INSTALL.EXE` in DOSBox) gives you the two GLB files.
2. Put `FILE0000.GLB` and `FILE0001.GLB` next to `raptua`, or run `raptua --data <folder>`.

| Key | Action |
|---|---|
| Arrows / mouse / left stick | Fly |
| Ctrl / Space / left mouse / A | Fire |
| Esc | Pause (twice: quit to title) |
| F1 | Asset explorer |
| F11, Alt+Enter | Fullscreen |
| F12 | Screenshot (BMP) |

Command line: `--data DIR`, `--scripts DIR`, `--scale N`, `--fullscreen`, `--autoplay` (straight into a mission, auto-firing), `--headless TICKS`, `--selftest`.

## Building

You need CMake 3.20+ and a C++20 compiler. CMake downloads SDL2 and Lua itself.

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel
ctest --test-dir build --output-on-failure
```

On Linux, install the SDL2 build dependencies first (see `.github/actions/configure-linux`). To run the tests that need real data too, configure with `-DRAPTUA_DATA=<folder with the GLB files>`.

`raptua-glb` is built alongside the game: `raptua-glb list FILE0001.GLB`, `raptua-glb extract FILE0001.GLB out/`.

## Layout

| Path | What |
|---|---|
| `src/formats/` | Decoders with no SDL or Lua dependency (GLB, PIC, level, sprite library, font, sound) |
| `src/` | Engine: video, audio, input, the `rap` Lua API, main loop |
| `scripts/` | The game in Lua: `main.lua`, `scenes/`, `game/`, `core/` |
| `tests/` | Format tests (synthetic data in CI, real data with `RAPTUA_DATA`) |
| `docs/` | File formats and the Lua API |

## CI and releases

`CI-build` builds and tests Linux (GCC and Clang), macOS and Windows on every push. `release-all` builds the release zips for all platforms, and pushing a `v*` tag publishes them as a GitHub release.

## Legal

Raptor: Call of the Shadows is © Cygnus Studios / Mountain King Studios. Raptua contains none of its code or data. It is an independent reimplementation that reads files you supply.
