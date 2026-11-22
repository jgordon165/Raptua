-- The ship computer while the mission loads (LOADCOMP_SWD): the sector and
-- wave on its screen for a moment, then into the mission.
local scenes = require("core.scenes")
local swd = require("ui.swd")

local M = {}

function M.enter(arg)
  M.arg = arg
  M.win = swd.open("LOADCOMP_SWD")
  M.t = 0
  if M.win then
    M.win:hide("SECRET")
    M.win:set_text("SECTOR", ("SECTOR %d"):format(arg.sector))
    M.win:set_text("WAVE", ("WAVE %d"):format(arg.wave))
    for b = 1, 3 do M.win:set_item("LITE" .. b, arg.secret and arg.secret[b] and "LIGHTON_PIC" or "LIGHTOFF_PIC") end
    M.win.no_area_frame = true
  end
end

function M.update()
  M.t = M.t + 1
  if M.t > 140 or (M.t > 20 and (rap.pressed("Return") or rap.pressed("Space") or rap.pressed("pad_a"))) then
    local a = M.arg
    scenes.switch(require("scenes.play"), { pilot = a.pilot, sector = a.sector, map = a.wave,
      difficulty = a.pilot.difficulty, secret = a.secret })
  end
end

function M.draw()
  rap.clear(0)
  if M.win then M.win:draw() end
end

return M
