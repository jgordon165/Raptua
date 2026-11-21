RAPTUA FOR THE XBOX 360 (XELL / LIBXENON)
=========================================

Raptua (a Lua recompilation of Raptor: Call of the Shadows) built with
LibXenon, for an Xbox 360 that boots XeLL (RGH/JTAG, or BadUpdate +
FreeMyXe launching XeLL).

No game data is included. You need your own copy of Raptor v1.2 (shareware
or registered).

1. Copy this whole "raptua" folder to the root of a FAT32 USB stick, so it
   holds  raptua.elf32  and  scripts/ ...
2. Copy FILE0000.GLB and FILE0001.GLB from your Raptor into  raptua/data/
   (in the shareware zip they're inside RAPSW12.SHR, which unzips like a
   normal .zip).
3. Start XeLL with the stick plugged in and load raptua.elf32.

Controls
--------
  Left stick / D-pad     fly, move in menus
  A, X or right trigger  fire (A also chooses in menus)
  B                      next special weapon
  Y                      megabomb
  START                  pause / continue
  RB                     help
  BACK                   choose in menus
