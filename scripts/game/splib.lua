-- The sprite library (SPRITEn_ITM): one 528-byte record per enemy/object
-- type. The engine hands the raw fields over; this file names them.
-- f[] is 1-based here (f[1] = the first int after the name).
local M = {}

-- Flight types (f[22]).
M.F_REPEAT, M.F_LINEAR, M.F_KAMI = 0, 1, 2
M.F_GROUND, M.F_GROUNDLEFT, M.F_GROUNDRIGHT = 3, 4, 5

function M.wrap(raw)
  local f, t = raw.f, raw.table or {}
  local d = {
    raw = raw,
    name = raw.name,
    item = f[1] or 0,            -- GLB handle in the original build (frames are found by name instead)
    bonus = f[2] or -1,          -- pickup dropped when destroyed: an object number, -1 none
    exptype = f[3] or 0,         -- explosion kind
    shootspace = f[4] or 0,      -- frames between volleys
    frame_rate = f[7] or 0,
    frames = math.max(1, f[8] or 1),
    countdown = f[9] or 0,       -- distance before it may start shooting
    bossflag = f[13] or 0,       -- treated as a boss (weaker on the two easiest difficulties)
    hits = math.max(1, f[14] or 1),
    bounty = f[15] or 0,
    shootstart = f[16] or 0,     -- frames before the first volley
    shootcnt = f[17] or 0,       -- volleys per burst
    shootframe = f[18] or 0,     -- rest between bursts
    movespeed = f[19] or 1,      -- pixels per game frame
    numflight = f[20] or 0,      -- entries used in the flight path
    repos = f[21] or 0,          -- REPEAT flights bounce back to this entry
    flighttype = f[22] or 0,
    numguns = f[23] or 0,
    numengs = f[24] or 0,
    song = f[26] or -1,          -- not -1: a boss (keeps the boss sound going while it's on screen)
    shoot_type = t[1] or {},     -- per gun
    shootx = t[5] or {},         -- per gun: where shots leave the sprite
    shooty = t[6] or {},
  }
  d.ground = d.flighttype >= M.F_GROUND
  return d
end

-- The flight path's first `numflight` points, as offsets in pixels.
function M.path_points(d)
  local xs, ys = d.raw.path_x or {}, d.raw.path_y or {}
  local out = {}
  for i = 1, d.numflight or 0 do out[i] = { xs[i] or 0, ys[i] or 0 } end
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
