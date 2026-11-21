-- Player settings, kept in settings.lua in the user's preferences folder
-- (SDL's pref path for Raptua).
local M = { music = 7, sound = 8 }   -- volumes 0..10

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
    end
  end
  M.apply()
end

function M.save()
  rap.save_file(FILE, ("return { music = %d, sound = %d }\n"):format(M.music, M.sound))
end

-- Step a volume by `d` (clamped 0..10), apply and save.
function M.step(key, d)
  M[key] = math.max(0, math.min(10, M[key] + d))
  M.apply()
  M.save()
end

return M
