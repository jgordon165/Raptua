Raptua for the Wii U (Aroma)
============================

Raptua runs as homebrew under Aroma. It needs no game data of its own: you
supply FILE0000.GLB and FILE0001.GLB from your own copy of Raptor: Call of
the Shadows v1.2 (the shareware episode works).

Setting up
----------
1. Your Wii U needs the Aroma homebrew environment. Its guide is at
   https://wiiu.hacks.guide (it walks through setting it up from scratch).
2. Copy the "wiiu" folder from this zip to the root of the SD card, merging
   it with the wiiu folder Aroma made. You end up with
       SD:/wiiu/apps/raptua/raptua.wuhb
       SD:/wiiu/apps/raptua/data/
3. Put FILE0000.GLB and FILE0001.GLB in SD:/wiiu/apps/raptua/data/.
4. Put the card back and start Raptua from the HOME Menu.

If the data files aren't found, the screen says so and shows the folder it
looked in. Settings, pilots and raptua.log are kept in SD:/wiiu/apps/raptua/.

raptua.rpx is the same game without the bundle, for loaders that start .rpx
files; it reads its scripts from SD:/wiiu/apps/raptua/scripts/.

Controls (GamePad or Pro Controller)
------------------------------------
Left stick / D-pad   fly, move through menus
A / ZR               fire, choose
B                    next special weapon (in a mission), back (in menus)
Y                    megabomb
+                    main menu over the game
-                    pause
HOME                 back to the Wii U Menu
The game shows on the TV and the GamePad.
