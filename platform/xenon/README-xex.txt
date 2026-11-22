RAPTUA FOR THE XBOX 360 (.XEX)
==============================

Raptua (a Lua recompilation of Raptor: Call of the Shadows) built as an
Xbox 360 title (raptua.xex) with xsdk (openpak/x360-sdk). It runs on a
console that runs unsigned code: BadUpdate with FreeMyXe (or XeUnshackle),
an RGH or a JTAG. Launch it from the dashboard, Aurora or a file manager.

No game data is included. You need your own copy of Raptor v1.2 (shareware
or registered).

1. Copy this whole "raptua" folder to a USB stick (FAT32) or the hard
   drive, so it holds  raptua.xex  and  scripts/ ...
2. Copy FILE0000.GLB and FILE0001.GLB from your Raptor into  raptua/data/
   (in the shareware zip they're inside RAPSW12.SHR, which unzips like a
   normal .zip).
3. Launch raptua.xex.

Controls
--------
  Left stick / D-pad     fly, move in menus
  A, X or right trigger  fire (A also chooses in menus)
  B                      next special weapon
  Y                      megabomb
  START                  pause / continue
  RB                     help
  BACK                   choose in menus

Settings (volumes, game speed) are saved next to raptua.xex.

Aurora art
----------
The aurora/ folder has Raptua's own pictures at Aurora's asset sizes:
icon.png (64x64), banner.png (420x96), boxart.png (900x600) and
background.png (1280x720). Raptua has its own title ID (52415054), so in
Aurora you can give it these as its assets (from the game's asset options,
loading the images from the USB stick) without them showing on other
homebrew titles.
