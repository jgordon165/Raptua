-- The original's pilot saves, CHAR0000.FIL .. CHAR0009.FIL in the data
-- folder. Read only: an original pilot you load carries on in Raptua's own
-- save format (game/pilot.lua) and the .FIL file is left as it was.
--
-- Layout (all little-endian, the same cipher as the GLB archives but keyed
-- "CASTLE"; the 88-byte pilot record and the item records after it are
-- each enciphered on their own):
--   char name[20], char callsign[12], i32 photo (0..3), u32 money,
--   i32 special weapon (object number), i32 sector (from 0),
--   i32 wave[3] (next wave in each sector, from 0), i32 item count,
--   i32 difficulty[4] (per sector), i32 training flag, i32 training done
-- then per item 24 bytes: 2 unused pointers, i32 amount, i32 object number,
-- 1 unused pointer, i32 equipped.
local M = {}

M.SLOTS = 10
local KEY = "CASTLE"
local PLAYER_SIZE, OBJ_SIZE = 88, 24

function M.decipher(s)
  local n = #KEY
  local pos = 25 % n
  local prev = KEY:byte(pos + 1)
  local out = {}
  for i = 1, #s do
    local c = s:byte(i)
    out[i] = string.char((c - KEY:byte(pos + 1) - prev) % 256)
    prev = c
    pos = (pos + 1) % n
  end
  return table.concat(out)
end

-- The inverse (for tests, which build a save to read back).
function M.encipher(s)
  local n = #KEY
  local pos = 25 % n
  local prev = KEY:byte(pos + 1)
  local out = {}
  for i = 1, #s do
    prev = (s:byte(i) + KEY:byte(pos + 1) + prev) % 256
    out[i] = string.char(prev)
    pos = (pos + 1) % n
  end
  return table.concat(out)
end

local function cstr(s) return (s:match("^[^%z]*")) end

-- Parses an original save's bytes into a Raptua pilot table (nil if it isn't one).
function M.parse(raw)
  if not raw or #raw < PLAYER_SIZE then return nil end
  local head = M.decipher(raw:sub(1, PLAYER_SIZE))
  local objs = M.decipher(raw:sub(PLAYER_SIZE + 1))
  local name, call = head:sub(1, 20), head:sub(21, 32)
  local photo, money, special, sector, w1, w2, w3, count, d1, d2, d3, d4 =
    string.unpack("<i4I4i4i4i4i4i4i4i4i4i4i4", head, 33)
  if count < 0 or count > 64 or #objs < count * OBJ_SIZE then return nil end
  local p = require("game.pilot").new(cstr(name), cstr(call), photo + 1, 1)
  p.money = money
  p.sector = math.max(1, math.min(3, sector + 1))
  p.wave = { w1 + 1, w2 + 1, w3 + 1 }
  local diffs = { d1, d2, d3, d4 }
  p.difficulty = math.max(0, math.min(3, diffs[p.sector] or 1))
  p.items = {}
  for i = 0, count - 1 do
    local amount, kind = string.unpack("<i4i4", objs, i * OBJ_SIZE + 9)
    if kind >= 0 and kind < 64 then
      if kind == 16 then p.shield = amount; p.items[16] = 1
      elseif kind == 15 then p.super = amount; p.items[15] = 1
      else p.items[kind] = (p.items[kind] or 0) + amount end
    end
  end
  p.items[0] = p.items[0] or 1
  p.special = special > 0 and p.items[special] and special or nil
  if (p.shield or 0) <= 0 then return nil end   -- the original refuses dead pilots too
  return p
end

-- Every original pilot in the data folder, as { file = n, pilot = p }.
function M.list()
  local out = {}
  for n = 0, M.SLOTS - 1 do
    local p = M.parse(rap.data_file(("CHAR%04d.FIL"):format(n)))
    if p then p.original = n; out[#out + 1] = p end
  end
  return out
end

return M
