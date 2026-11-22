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

To leave, choose QUIT on the main menu (or press B there) and answer YES to
"Return to the dashboard?". The title stops its sound and ends; the console
goes to its default dashboard (Aurora or FreeStyle if DashLaunch makes it
the default).

To leave to a particular dashboard or program instead, put its .xex path in
dashboard.txt (next to raptua.xex), e.g.  Usb0:\Aurora\default.xex  or
Hdd:\Aurora\default.xex . Drives: Usb0:, Usb1:, Usb2:, Hdd:, game: (the
raptua folder) or a full \Device\... path. "default" (as shipped), an empty
file or no file means the default dashboard; so does a path whose file
isn't there (the log says so).

Settings (volumes, game speed) are saved next to raptua.xex.

Aurora art
----------
The aurora/ folder has Raptua's own pictures at Aurora's asset sizes:
icon.png (64x64), banner.png (420x96), boxart.png (900x600) and
background.png (1280x720). Raptua has its own title ID (52415054), so in
Aurora you can give it these as its assets (from the game's asset options,
loading the images from the USB stick) without them showing on other
homebrew titles.

If something goes wrong
-----------------------
If the data files aren't found, the screen says so and shows the folder it
looked in. A script error is shown on screen too (START exits). Both, and the
folders used, are written to raptua.log next to raptua.xex.
