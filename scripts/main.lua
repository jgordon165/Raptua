-- Raptua entry point. The engine calls init(), then update() at
-- rap.tick_rate() Hz and draw() once per displayed frame.
local scenes = require("core.scenes")

function init()
  rap.tick_rate(70)            -- mode 13h refresh rate; game logic runs per tick
  if RAPTUA_SELFTEST then return end
  require("core.settings").load()
  if not rap.have_data() then
    scenes.switch(require("scenes.nodata"))
  else
    rap.palette("PALETTE_DAT")
    if RAPTUA_AUTOPLAY then
      -- Demo / test mode: straight into the first mission, firing constantly.
      scenes.switch(require("scenes.play"), { map = 1, difficulty = 1, autofire = true })
    else
      scenes.switch(require("scenes.intro"))
    end
  end
end

function update()
  if rap.pressed("F11") then rap.fullscreen() end
  if rap.pressed("F12") then
    local name = ("raptua_%d.bmp"):format(rap.millis())
    if rap.screenshot(name) then io.stderr:write("saved ", name, "\n") end
  end
  -- F9: the asset explorer (F1 is help, as in the original).
  if rap.pressed("F9") and rap.have_data() and not scenes.is(require("scenes.explorer")) then
    scenes.push(require("scenes.explorer"))
  end
  scenes.update()
end

function draw()
  scenes.draw()
end

-- `raptua --selftest`: pure-Lua checks that need no game data.
function selftest()
  local util = require("core.util")
  assert(util.clamp(5, 0, 3) == 3)
  assert(util.overlap(0, 0, 10, 10, 5, 5, 10, 10))
  assert(not util.overlap(0, 0, 4, 4, 5, 5, 2, 2))
  local splib = require("game.splib")
  local def = splib.wrap({ name = "SHIP01G1_PIC", f = { [8] = 2, [14] = 7, [15] = 350, [20] = 2, [22] = 1 },
                           path_x = { 0, 10 }, path_y = { 0, -5 }, table = {} })
  assert(def.frames == 2 and def.hits == 7 and def.bounty == 350 and not def.ground)
  local path = splib.path_points(def)
  assert(#path == 2 and path[2][1] == 10)
  local s = require("core.scenes")
  local log = {}
  s.switch({ enter = function() log[#log + 1] = "a" end })
  s.push({ enter = function() log[#log + 1] = "b" end, leave = function() log[#log + 1] = "-b" end })
  s.pop()
  assert(table.concat(log, ",") == "a,b,-b")
  -- Pilots: a new pilot, a wave flown, the ship's state taken back.
  local pilot = require("game.pilot")
  local pl = pilot.new("ANN", "ACE", 2, 1)
  assert(pl.wave[1] == 1 and pl.items[0] == 1 and pl.money > 0)
  local ship = { items = {}, money = 0, shield = 0, super = 0 }
  pilot.equip(pl, ship)
  assert(ship.items[0] == 1 and ship.money == pl.money)
  ship.money, ship.items[7], ship.special = ship.money + 500, 1, 7
  pilot.collect(pl, ship)
  assert(pl.money == ship.money and pl.items[7] == 1 and pl.special == 7)
  for _ = 1, pilot.WAVES do pilot.wave_done(pl, 1) end
  assert(pilot.sector_done(pl, 1) and not pilot.sector_done(pl, 2))
  -- Smooth motion (game/smooth.lua): drawn part-way, then put back exactly.
  -- Co-op: two ships pushed apart never overlap, and stay on the playfield.
  local Player = require("game.player")
  local a = setmetatable({ x = 140, y = 150, w = 32, h = 32 }, Player)
  local b = setmetatable({ x = 150, y = 155, w = 32, h = 32 }, Player)
  Player.separate(a, b)
  assert(not util.overlap(a.x, a.y, a.w, a.h, b.x, b.y, b.w, b.h) and a.x < b.x)
  local level = require("game.level")
  a.x, b.x = level.X0 - 10, level.X0 - 6   -- against the left wall
  Player.separate(a, b)
  assert(not util.overlap(a.x, a.y, a.w, a.h, b.x, b.y, b.w, b.h))
  assert(util.p2 and util.p2.held and util.p1.pressed)
  -- Ship colours: the two players' never match; red paint is recognised.
  local shipcolors = require("game.shipcolors")
  assert(shipcolors.step(1, 1, 2) == 3 and shipcolors.step(2, -1, 1) == #shipcolors.LIST)
  assert(shipcolors.is_red(shipcolors.hsv(200, 30, 30)) and not shipcolors.is_red(shipcolors.hsv(40, 60, 200)))
  local r, g, b = shipcolors.rgb(shipcolors.hsv(40, 120, 220))
  assert(math.abs(r - 40) <= 1 and math.abs(g - 120) <= 1 and math.abs(b - 220) <= 1)
  local smooth = require("game.smooth")
  local objs = { { x = 10, y = 20 }, { x = 0, y = 0 } }
  smooth.mark({ objs }); objs[1].x, objs[1].y = 18, 24; objs[2].x = 200
  smooth.place({ objs }, 0.5)
  assert(objs[1].x == 14 and objs[1].y == 22 and objs[2].x == 200)   -- a jump is drawn where it is
  smooth.restore({ objs })
  assert(objs[1].x == 18 and objs[1].y == 24 and objs[1]._cx == nil)
  assert(smooth.fraction(8, 4, 0) == 0 and smooth.fraction(9, 4, 0.5) == 0.375 and smooth.fraction(11, 4, 1) == 1)
  -- Controls (game/controls.lua) and the on-screen keyboard (ui/osk.lua).
  local controls = require("game.controls")
  local st = { keys = { fire = "Escape", up = "W" }, pad = { fire = "START", bomb = "LB" } }
  local kb, pd = controls.of(st, "keys"), controls.of(st, "pad")
  assert(kb.fire == "Left Ctrl" and kb.up == "W" and kb.special == "Left Alt")   -- Escape can't be bound
  assert(pd.fire == "A" and pd.bomb == "LB" and pd.special == "B")              -- nor START
  assert(not controls.accepts_key("F1") and controls.accepts_key("Space") and not controls.accepts_button("BACK"))
  local used = controls.used(pd)
  assert(#used == 3)
  local osk = require("ui.osk")
  local rows = osk.layout(osk.LETTERS)
  assert(#rows == 5 and rows[5][1] == "SPACE" and rows[5][3] == "DONE")
  local k = { rows = rows, row = 1, col = 1, max = 3 }
  osk.move(k, 0, -1); assert(k.col == 10)
  osk.move(k, 4, 0); assert(k.row == 5 and k.col == 3)
  assert(osk.press(k, "", "SPACE") == "" and osk.press(k, "AB", "C") == "ABC" and osk.press(k, "ABC", "D") == "ABC")
  assert(osk.press(k, "AB", "DEL") == "A" and select(2, osk.press(k, "AB", "DONE")) == "done")
  -- An original CHARnnnn.FIL pilot: build one, encipher it, read it back.
  local orig = require("game.original_pilot")
  local head = string.pack("<c20c12i4I4i4i4i4i4i4i4i4i4i4i4i4i4", ("BOB" .. ("\0"):rep(17)), ("RED" .. ("\0"):rep(9)),
    2, 54321, 6, 0, 4, 0, 0, 3, 2, 0, 0, 0, 0, 0)
  local objs = string.pack("<i4i4i4i4i4i4", 0, 0, 1, 0, 0, 1) .. string.pack("<i4i4i4i4i4i4", 0, 0, 75, 16, 0, 1)
    .. string.pack("<i4i4i4i4i4i4", 0, 0, 1, 6, 0, 1)
  assert(#head == 88 and orig.decipher(orig.encipher(head)) == head)
  local op = assert(orig.parse(orig.encipher(head) .. orig.encipher(objs)))
  assert(op.name == "BOB" and op.callsign == "RED" and op.photo == 3 and op.money == 54321)
  assert(op.sector == 1 and op.wave[1] == 5 and op.difficulty == 2 and op.shield == 75 and op.special == 6 and op.items[6] == 1)
  local music = require("game.music")
  assert(music.WAVES[1][1] == "RAP8" and #music.WAVES[1] == 9)
  return true
end
