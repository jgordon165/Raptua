-- The sprite library (SPRITEn_ITM): one 528-byte record per enemy/object
-- type. The engine hands the raw fields over; this file gives them names.
--
-- Status: names marked "?" are guesses from looking across all 131 records
-- of the shareware library and still need confirming against RAP.EXE
-- (see docs/formats.md). Fields are 1-based here (f[1] = first int).
local M = {}

-- Ground objects scroll with the map; everything else flies.
local GROUND_PREFIX = { "TARGT", "BONUS", "BOUY", "COW", "DINO", "MOLE", "APE" }

function M.wrap(raw)
  local f = raw.f
  local d = {
    raw = raw,
    name = raw.name,
    item = f[1] or 0,          -- GLB handle in the build it was made for (not this one)
    bonus = f[2] or -1,        -- BONUSnn pickup dropped when destroyed (-1 none)
    frames = math.max(1, f[8] or 1),
    hits = math.max(1, f[14] or 1),
    bounty = f[15] or 0,
    shots = f[24] or 0,        -- number of entries in the shot tables
    tables = raw.table,        -- ? six short[24] tables: shot timing, kind, x, y ...
  }
  d.ground = false
  for _, p in ipairs(GROUND_PREFIX) do
    if d.name:sub(1, #p) == p then d.ground = true end
  end
  return d
end

-- Flight path points (guess: offsets in pixels). Trailing zeros dropped.
function M.path_points(d)
  local xs, ys, n = d.raw.path_x or {}, d.raw.path_y or {}, 0
  for i = 1, math.max(#xs, #ys) do
    if (xs[i] or 0) ~= 0 or (ys[i] or 0) ~= 0 then n = i end
  end
  local out = {}
  for i = 1, n do out[i] = { xs[i] or 0, ys[i] or 0 } end
  return out
end

function M.load(name)
  local raw = rap.sprite_lib(name)
  if not raw then return nil end
  local out = {}
  for i, r in ipairs(raw) do out[i - 1] = M.wrap(r) end   -- actors index from 0
  return out
end

return M
