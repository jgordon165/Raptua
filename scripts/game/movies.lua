-- The original's movie sequences (frames are the *_AGX items in the
-- player's FILE0001.GLB). Each sequence is a list of clips; a clip plays a
-- movie's frames `rate` vertical blanks (70 Hz) apart, `plays` times, with
-- an optional background loop and sound effects on given frames
-- (fx(frame) -> sound name, pan -1..1 | nil). Frame numbers count from 0.
local M = {}

M.SEQUENCES = {
  intro = {
    { movie = "CHASE_AGX", rate = 8, fade_in = true,
      fx = function(i) if i == 4 then return "FLYBY_FX", 0.65 elseif i == 9 then return "FLYBY_FX", -0.2 end end },
    { movie = "SHIPSD1_AGX", rate = 18, plays = 2, loop = "JETSND_FX" },
    { movie = "PILOT_AGX", rate = 10, loop = "JETSND_FX" },
    { movie = "SHIPSD1_AGX", rate = 18, loop = "JETSND_FX" },
    { movie = "SHIPSD2_AGX", rate = 18, loop = "JETSND_FX",
      fx = function(i) if i > 1 then return "GUN_FX", 0 end end },
    { movie = "EXPLO_AGX", rate = 12, loop = "JETSND_FX", fade_out = true,
      fx = function(i, last)
        if i == last then return "EXPLO_FX", 0 end
        if i >= 8 and i % 2 == 1 then return "EXPLO_FX", 0 end
        if i >= 2 and i < 10 then return "GUN_FX", (math.random(0, 40) - 20) / 128 end
      end },
  },
  landing = {
    { movie = "BASE_AGX", rate = 10, fade_in = true, optional = true },   -- not in the shareware
    { movie = "LANDING_AGX", rate = 10, fade_in = true, fade_out = true },
  },
  death = {
    { movie = "DOWN_AGX", rate = 11, fade_in = true },
    { movie = "SDEATH_AGX", rate = 3, plays = 8, fade_out = true },
  },
  sector_end = {
    { movie = "GAME1END_AGX", rate = 4, plays = 8, fade_in = true, fade_out = true },
  },
}

-- The frame items of a movie (consecutive items sharing its name).
function M.frames(movie)
  local h = rap.find(movie)
  if not h then return {} end
  local out = { h }
  while true do
    local it = rap.item(h + #out)
    if not it or it.name ~= movie then break end
    out[#out + 1] = h + #out
  end
  return out
end

return M
