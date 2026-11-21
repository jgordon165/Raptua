-- The original's demo recordings (DEMOnG1_REC in the player's data): 12
-- bytes per game frame, i8 buttons 1..4, i16 x, y (the ship's top-left in
-- screen pixels), i16 bank frame (0..6, 3 = level), i16 unused. Record 0 is
-- a header: frame count in the bank field, sector (from 0) in x, wave
-- (from 0) in y.
--
-- Replaying moves the ship and presses its buttons exactly as recorded.
-- The enemies are Raptua's own, so it is the original pilot's flight in
-- Raptua's world rather than a frame-exact copy of the original demo.
local M = {}

M.NAMES = { "DEMO1G1_REC", "DEMO2G1_REC", "DEMO3G1_REC" }

function M.load(name)
  local raw = rap.read(name)
  if not raw or #raw < 24 then return nil end
  local n = #raw // 12
  local _, _, _, _, sector, wave, count = string.unpack("<i1i1i1i1i2i2i2", raw, 1)
  local d = { name = name, sector = sector + 1, wave = wave + 1, frames = {} }
  for i = 1, math.min(n - 1, count > 0 and count or n) do
    local b1, b2, b3, b4, x, y, bank = string.unpack("<i1i1i1i1i2i2i2", raw, i * 12 + 1)
    d.frames[i] = { fire = b1 ~= 0, special = b2 ~= 0, bomb = b3 ~= 0, b4 = b4 ~= 0, x = x, y = y, bank = bank }
  end
  return d
end

local next_demo = 0
-- The next recording in turn, or nil if none load.
function M.next()
  for _ = 1, #M.NAMES do
    next_demo = next_demo % #M.NAMES + 1
    local d = M.load(M.NAMES[next_demo])
    if d and #d.frames > 0 then return d end
  end
end

return M
