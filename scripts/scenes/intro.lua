-- Start-up: the Apogee logo (APOGEE_PIC in its own palette, POGPAL_DAT)
-- with its jingle, then the Cygnus logo (CYGNUS_PIC, CYGPAL_DAT), fading in
-- and out, then the intro movie (game/movies.lua) under the intro theme,
-- then the main menu. Any key skips the logos; any key skips the movie.
local scenes = require("core.scenes")
local music = require("game.music")

local M = {}

local SHOW = 3 * 70          -- each logo's time on screen, in 70 Hz ticks
local FADE = 35

function M.enter()
  M.steps = {}
  if rap.find("APOGEE_PIC") then M.steps[#M.steps + 1] = { pic = "APOGEE_PIC", pal = "POGPAL_DAT", song = true } end
  if rap.find("CYGNUS_PIC") then M.steps[#M.steps + 1] = { pic = "CYGNUS_PIC", pal = "CYGPAL_DAT" } end
  M.i, M.t = 0, 0
  M.next_step()
end

function M.next_step()
  M.i, M.t = M.i + 1, 0
  local s = M.steps[M.i]
  if not s then
    rap.fade(1)
    music.intro()
    scenes.switch(require("scenes.movie"), { sequence = "intro", done = function()
      scenes.switch(require("scenes.mainmenu"))
    end })
    return
  end
  if not rap.palette(s.pal) then rap.palette("PALETTE_DAT") end
  if s.song then music.apogee() end
end

function M.update()
  local s = M.steps[M.i]
  if not s then return end
  M.t = M.t + 1
  if rap.pressed("Return") or rap.pressed("Space") or rap.pressed("Escape") or rap.pressed("mouse_left")
     or rap.pressed("pad_a") or rap.pressed("pad_start") then
    M.i = #M.steps
    M.next_step()
    return
  end
  rap.fade(math.min(1, M.t / FADE, (SHOW - M.t) / FADE))
  if M.t >= SHOW then M.next_step() end
end

function M.draw()
  rap.clear(0)
  local s = M.steps[M.i]
  if s then
    local w, h = rap.pic_info(s.pic)
    if w then rap.pic(s.pic, (rap.W - w) // 2, (rap.H - h) // 2) end
  end
end

function M.leave() rap.fade(1) end

return M
