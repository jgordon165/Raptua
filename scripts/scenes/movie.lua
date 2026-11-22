-- Plays one of game/movies.lua's sequences, then calls arg.done(). Any key
-- or click skips the rest (as in the original). Drawn in the game palette.
local scenes = require("core.scenes")
local movies = require("game.movies")

local M = {}

local FADE_TICKS = 35

local function start_clip()
  local c = M.clips[M.ci]
  while c and (#movies.frames(c.movie) == 0) do   -- missing (e.g. BASE in the shareware)
    M.ci = M.ci + 1
    c = M.clips[M.ci]
  end
  if not c then return false end
  M.frames = movies.frames(c.movie)
  M.fi, M.play, M.wait = 0, 1, 0
  M.loop = c.loop and rap.sound(c.loop) or nil
  M.fade = c.fade_in and 0 or nil
  M.first_drawn = false
  return true
end

function M.enter(arg)
  M.arg = arg or {}
  M.clips = movies.SEQUENCES[M.arg.sequence] or {}
  rap.palette("PALETTE_DAT")
  rap.grab_mouse(false)
  rap.clear(0)
  M.ci = 1
  M.t = 0
  M.fx_cache = {}
  M.ending = nil
  if not start_clip() then M.finish() end
end

function M.finish()
  if M.done_called then return end
  M.done_called = true
  rap.stop_sounds()
  rap.fade(1)
  local done = M.arg.done
  if done then done() else scenes.pop() end
end

local function sound(name)
  if not M.fx_cache[name] then M.fx_cache[name] = rap.sound(name) or false end
  return M.fx_cache[name] or nil
end

-- Shows frame M.fi of the clip (the first of each play clears the screen).
local function show_frame()
  local c = M.clips[M.ci]
  local first = M.fi == 0
  rap.agx(M.frames[M.fi + 1], first and M.play == 1)
  if c.fx then
    local name, pan = c.fx(M.fi, #M.frames - 1)
    if name then rap.play(sound(name), 0.9, pan or 0) end
  end
end

function M.update()
  M.t = M.t + 1
  if M.done_called then return end
  if M.t > 10 and (rap.pressed("Return") or rap.pressed("Space") or rap.pressed("Escape") or rap.pressed("mouse_left")
      or rap.pressed("pad_a") or rap.pressed("pad_b") or rap.pressed("pad_start")) then
    M.finish()
    return
  end
  local c = M.clips[M.ci]
  if not c then M.finish(); return end
  if M.ending then
    -- Fading out at the end of the sequence.
    M.ending = M.ending - 1
    rap.fade(math.max(0, M.ending / FADE_TICKS))
    if M.ending <= 0 then M.finish() end
    return
  end
  if M.loop and not rap.sound_playing(M.loop) then rap.play(M.loop, 0.5) end
  if M.fade then M.fade = math.min(1, M.fade + 1 / FADE_TICKS); rap.fade(M.fade); if M.fade >= 1 then M.fade = nil end end
  if not M.first_drawn then show_frame(); M.first_drawn = true; M.wait = c.rate; return end
  M.wait = M.wait - 1
  if M.wait > 0 then return end
  M.wait = c.rate
  M.fi = M.fi + 1
  if M.fi >= #M.frames then
    M.play = M.play + 1
    if M.play <= (c.plays or 1) then
      M.fi = 0
    else
      local last_clip = M.ci == #M.clips
      if c.fade_out and last_clip then M.ending = FADE_TICKS; return end
      M.ci = M.ci + 1
      if not start_clip() then M.finish() end
      return
    end
  end
  show_frame()
end

function M.draw()
  -- Movie frames paint over the screen buffer, so nothing is cleared here.
end

function M.leave() rap.fade(1) end

return M
