-- Player settings, kept in settings.lua in the user's preferences folder
-- (SDL's pref path for Raptua).
-- Volumes 0..10, and `cadence`: vertical retraces (70 Hz) per game frame.
-- The original waits for at least 3 (23.3 fps, its ceiling on a fast PC);
-- on slower PCs a frame took 4 or 5 (17.5 / 14 fps) and the whole game ran
-- slower, as nothing scales movement by frame time.
local M = { music = 7, sound = 8, cadence = 4 }
M.CADENCES = { 3, 4, 5 }

local FILE = "settings.lua"

function M.apply()
  rap.music_volume(M.music / 10)
  rap.volume(M.sound / 10)
end

function M.load()
  local src = rap.load_file(FILE)
  if src then
    local chunk = load(src, FILE, "t", {})
    local ok, t = pcall(chunk or function() end)
    if ok and type(t) == "table" then
      for k, v in pairs(t) do if type(v) == type(M[k]) then M[k] = v end end
      if M.cadence ~= 3 and M.cadence ~= 4 and M.cadence ~= 5 then M.cadence = 4 end
    end
  end
  M.apply()
end

function M.save()
  rap.save_file(FILE, ("return { music = %d, sound = %d, cadence = %d }\n"):format(M.music, M.sound, M.cadence))
end

-- Cycle the game speed through 3/4/5 retraces per frame and save.
function M.cycle_cadence(d)
  local i = 1
  for k, v in ipairs(M.CADENCES) do if v == M.cadence then i = k end end
  M.cadence = M.CADENCES[(i - 1 + d) % #M.CADENCES + 1]
  M.save()
end

function M.cadence_label()
  local fps = 70 / M.cadence
  local tag = ({ [3] = "FAST PC", [4] = "486", [5] = "386" })[M.cadence] or ""
  return ("GAME SPEED  %.1f FPS %s"):format(fps, tag)
end

-- Step a volume by `d` (clamped 0..10), apply and save.
function M.step(key, d)
  M[key] = math.max(0, math.min(10, M[key] + d))
  M.apply()
  M.save()
end

return M
