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
  if rap.pressed("F1") and rap.have_data() and not scenes.is(require("scenes.explorer")) then
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
  local music = require("game.music")
  assert(music.WAVES[1][1] == "RAP8" and #music.WAVES[1] == 9)
  return true
end
