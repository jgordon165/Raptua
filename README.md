# Raptua

A Lua recompilation of the DOS game **Raptor: Call of the Shadows** (Cygnus Studios / Apogee, 1994).

The engine is C++20 on SDL2. It reads the original GLB archives, draws the 320×200 VGA screen, mixes sound and handles input. The game itself (scenes, levels, player, enemies, HUD) is Lua in `scripts/`, so you can change it without rebuilding.

**No game data is included.** Raptua loads `FILE0000.GLB` and `FILE0001.GLB` from your own copy of Raptor v1.2 (shareware or registered).

## Status

Early. What works today:

- GLB archives: encrypted tables and items, lookup by name (`src/formats/glb.*`)
- Images, sprites, 32×32 tiles, palettes, fonts and digitized sound effects
- Levels: the 9×150 tile map scrolls, and enemies spawn from the map's actor list using the sprite library
- A playable first pass of Tango Sector: the original Raptor sprite banking with movement, keyboard/mouse/game pad, twin guns, enemy fire, bounties, explosions, shield, sector-to-sector progression
- Destructible map tiles (buildings, bridges and so on swap to their wrecked tiles and pay their bounty), ground targets, and crates that drop pickups (energy, megabombs, weapons kept for the store later)
- Music: the original MUS songs played on an emulated OPL3 (Sound Blaster 16) with the game's own GENMIDI instrument bank. The menu, the eight flight songs and the rest
- Digitized sound effects for guns, hits, explosions, pickups, the low-shield warning, the crash and menus. Music and sound volume and detail are in the original Options window; the game speed (23.3 / 17.5 / 14 fps: the original's cadence on a fast PC, a 486, a 386) cycles with F5 on the main menu. All are saved between runs
- The original menus, drawn from the window layouts in your data: main menu, options (detail, music and sound effect volume), difficulty (Training, Rookie, Veteran, Elite), quit confirmation, credits and order screens. Esc during a mission opens the main menu with Return to Game, as in the original
- The pilot side, from your data's windows: start-up logos, registration (name, callsign, photo, difficulty), pilot loading and saving, the hangar, the ship computer (sector pick, secret-enemy lights) and the supply room (buy and sell, with each item's description). After each wave you land back at the hangar
- The original movies from your data: the intro after the start-up logos, the landing after each wave, the death sequence and the end of a sector, with their sound effects. Any key skips
- Songs play where the original plays them: the main menu theme, the intro theme over a game in progress, each sector's own wave order, the death theme, and the credits songs in turn
- Help (F1) with the original help pages from your data, opening at the page for the screen you're on
- Your original pilots: any `CHAR000n.FIL` saves in your data folder show up in Load (read only; they carry on in Raptua's own save format)
- The demos: D on the main menu, or leaving it untouched for half a minute, replays one of the original's three recordings (the recorded flight and firing; Raptua's enemies)
- An asset explorer (F9) for browsing everything in the archives

Still to come (roughly in order): enemy shot types, the non-missile special weapons, then the SNES build. `docs/formats.md` lists what is known and what is still a guess.

## Running

1. Get Raptor v1.2. In the shareware zip (`1rap12.zip`), `RAPSW12.SHR` is a zip archive with a self-extractor in front. `unzip RAPSW12.SHR` (or running `INSTALL.EXE` in DOSBox) gives you the two GLB files.
2. Put `FILE0000.GLB` and `FILE0001.GLB` next to `raptua`, or run `raptua --data <folder>`.

| Key | Action |
|---|---|
| Arrows / mouse / left stick | Fly |
| Ctrl / Space / left mouse / A | Fire (guns plus the selected special weapon) |
| Alt / right mouse / B | Next special weapon |
| Left Shift / middle mouse / Y | Megabomb |
| Esc | Main menu (Return to Game goes back) |
| P | Pause |
| F5 (main menu) | Cycle game speed |
| F1 | Help (the page for where you are) |
| F9 | Asset explorer |
| F11, Alt+Enter | Fullscreen |
| F12 | Screenshot (BMP) |

Command line: `--data DIR`, `--scripts DIR`, `--scale N`, `--fullscreen`, `--autoplay` (straight into a mission: steers at targets, auto-fires, can't die), `--headless TICKS`, `--selftest`. Set `RAPTUA_TRACE=1` to log tile destruction, kills and pickups to stderr.

## Xbox 360

For a console that runs unsigned code. There are two builds, both from the `xbox360` workflow:

- `raptua-xbox360-xex.zip`: a normal title, `raptua.xex` (built with xsdk). Launch it from the dashboard, Aurora or a file manager on BadUpdate + FreeMyXe, RGH or JTAG.
- `raptua-xbox360-xell.zip`: `raptua.elf32` for XeLL (LibXenon).

Copy the `raptua` folder to a FAT32 USB stick (or the hard drive), then put `FILE0000.GLB` and `FILE0001.GLB` in `raptua/data/`. Controls: stick/D-pad fly; A, X or right trigger fire; B next special; Y megabomb; START pause (B quits to the title while paused). The README inside each package has the details.

To build: `cmake -DCMAKE_TOOLCHAIN_FILE=platform/xenon/toolchain.cmake` (LibXenon, in the `free60/libxenon` image) or `-DCMAKE_TOOLCHAIN_FILE=<xsdk>/cmake/xsdk.cmake`. `-DRAPTUA_XENON_SIM=ON` builds the same SDL and layout on a PC for testing (`XENON_SIM_*` variables in `platform/xenon/xenon_platform_sim.c`). The platform layer is shared with Meguarace.

## Advanced options

Options has an **ADVANCED** button of Raptua's own:

- **Smooth motion:** every displayed frame is drawn (60 a second on the Xbox 360), with the map, enemies, shots and pickups placed between the game's own frames (`game/smooth.lua`). The game itself is unchanged: enemies move, fire and get hit only on the original's game frames, by the same amounts. The in-between pictures trail by up to one game frame. Off by default.
- **Game speed:** the original's 3, 4 or 5 vertical blanks per game frame (also F5 on the main menu).
- **Keyboard / controller setup:** see Controls.

## Controls

Options > ADVANCED has a **KEYBOARD** setup on a PC: press a key for up, down, left, right, fire, next special and megabomb in turn (Esc undoes). On the Xbox 360 it's **CONTROLLER** instead, for the fire, special and megabomb buttons; the stick and D-pad always fly. The bindings are saved with the settings (`game/controls.lua`). On the Xbox 360 and the Wii U, the new pilot's name and callsign are typed on an on-screen keyboard (`ui/osk.lua`): A on the box opens it.

## Building

You need CMake 3.20+ and a C++20 compiler. CMake downloads SDL2, Lua and ymfm (the OPL3 emulator, BSD-3) itself.

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

`CI-build` builds and tests Linux (GCC and Clang), macOS and Windows on every push. `release-all` builds the release zips for all platforms, and pushing a `v*` tag publishes them as a GitHub release. `xbox360` builds both Xbox 360 packages and the Linux stand-in on every push and pull request, and attaches the two packages to the release on a `v*` tag.

## Legal

Raptor: Call of the Shadows is © Cygnus Studios / Mountain King Studios. Raptua contains none of its code or data. It is an independent reimplementation that reads files you supply.

## Icon

`assets/raptua.ico` is Raptua's own icon (the jet from the Aurora art, drawn from scratch by `tools/make_icon.py`). The Windows build carries it in `raptua.exe`, so a shortcut to Raptua shows it in Explorer and in [Progman31lua](https://github.com/jgordon165/Progman31lua)'s Games group, and the release zip has a copy beside the executable. Besides the modern sizes it has 16-colour 32×32 and 16×16 images on the standard VGA palette, which is what Windows 3.1, and Progman31lua's Program Manager, read.

## Aurora art (Xbox 360)

`assets/aurora/` holds Raptua's own icon, banner, box art and background for the Aurora dashboard, drawn from scratch by `tools/make_aurora_art.py` (no game art). The `.xex` package includes them in `aurora/`, and the title has its own title ID (`52415054`), so Aurora keeps these assets separate from other homebrew.
