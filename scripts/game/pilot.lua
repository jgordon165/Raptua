-- Pilots: who's flying, what they own and how far they've got. Saved as
-- pilotN.lua in the user's preferences folder (Raptua's own format), with
-- pilots.lua listing the slots in use. The original's own saves
-- (CHARnnnn.FIL in the data folder, game/original_pilot.lua) are listed too;
-- once one is loaded it carries on here, and its .FIL file is left alone.
local weapons = require("game.weapons")

local M = {}

M.PHOTOS = { "WMALE_PIC", "BMALE_PIC", "WFEMALE_PIC", "BFEMALE_PIC" }
M.ID_PHOTOS = { "WMALEID_PIC", "BMALEID_PIC", "WFMALEID_PIC", "BFMALEID_PIC" }
M.SECTORS = 3
M.WAVES = 9

function M.new(name, callsign, photo, difficulty)
  return {
    name = name, callsign = callsign, photo = photo or 1, difficulty = difficulty or 1,
    money = 10000,                 -- starting cash (Raptua's choice)
    items = { [0] = 1, [16] = 1 }, -- machine guns, and the shield energy
    special = nil,
    shield = 100,
    super = 0,
    wave = { 1, 1, 1 },            -- next wave to fly in each sector
    sector = 1,
    slot = nil,
  }
end

-- ---- saving ------------------------------------------------------------------------

local function serialize(v, indent)
  indent = indent or ""
  local t = type(v)
  if t == "number" or t == "boolean" then return tostring(v) end
  if t == "string" then return ("%q"):format(v) end
  if t ~= "table" then return "nil" end
  local parts, inner = {}, indent .. "  "
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  for _, k in ipairs(keys) do
    local key = type(k) == "number" and ("[%d]"):format(k) or ("[%q]"):format(k)
    parts[#parts + 1] = inner .. key .. " = " .. serialize(v[k], inner)
  end
  return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
end

local function read_table(file)
  local src = rap.load_file(file)
  if not src then return nil end
  local chunk = load(src, file, "t", {})
  if not chunk then return nil end
  local ok, t = pcall(chunk)
  return ok and type(t) == "table" and t or nil
end

local function slots() return read_table("pilots.lua") or {} end
local function save_slots(s) rap.save_file("pilots.lua", "return " .. serialize(s) .. "\n") end

-- Saves p (giving it a slot if it has none). Returns true on success.
function M.save(p)
  local s = slots()
  if not p.slot then
    local n = 1
    while s[n] do n = n + 1 end
    p.slot = n
  end
  s[p.slot] = p.callsign ~= "" and p.callsign or p.name
  if p.original then
    s.originals = s.originals or {}
    s.originals[p.original] = true
    p.original = nil
  end
  local data = {}
  for k, v in pairs(p) do if type(v) ~= "function" then data[k] = v end end
  local ok = rap.save_file(("pilot%d.lua"):format(p.slot), "return " .. serialize(data) .. "\n")
  save_slots(s)
  return ok
end

-- All saved pilots, in slot order.
function M.list()
  local out = {}
  local s = slots()
  local nums = {}
  for n in pairs(s) do if type(n) == "number" then nums[#nums + 1] = n end end
  table.sort(nums)
  for _, n in ipairs(nums) do
    local p = read_table(("pilot%d.lua"):format(n))
    if p then p.slot = n; out[#out + 1] = p end
  end
  local done = s.originals or {}
  for _, p in ipairs(require("game.original_pilot").list()) do
    if not done[p.original] then out[#out + 1] = p end
  end
  return out
end

function M.delete(p)
  local s = slots()
  if p.original then   -- hide it here; the original's file isn't touched
    s.originals = s.originals or {}
    s.originals[p.original] = true
    save_slots(s)
    return
  end
  if not p.slot then return end
  s[p.slot] = nil
  save_slots(s)
  rap.save_file(("pilot%d.lua"):format(p.slot), "return nil\n")
end

-- ---- play ---------------------------------------------------------------------------

-- Copies what the pilot owns onto a fresh player ship.
function M.equip(p, player)
  player.money = p.money
  player.items = {}
  for k, v in pairs(p.items) do player.items[tonumber(k)] = v end
  player.items[0] = player.items[0] or 1
  player.special = p.special
  player.shield = math.max(1, p.shield or 100)
  player.super = p.super or 0
end

-- Takes the ship's state back after a wave.
function M.collect(p, player)
  p.money = player.money
  p.items = {}
  for k, v in pairs(player.items) do p.items[k] = v end
  p.special = player.special
  p.shield = player.shield
  p.super = player.super
end

-- A wave flown to the end: on to the next (sector cleared after the last).
function M.wave_done(p, sector)
  p.wave[sector] = math.min(M.WAVES + 1, (p.wave[sector] or 1) + 1)
end

function M.sector_done(p, sector) return (p.wave[sector] or 1) > M.WAVES end

-- What the store sells in the shareware sector (object numbers).
M.STORE = { 0, 1, 2, 3, 4, 6, 7, 8, 11, 12, 15, 16, 17 }

function M.cost(n) return weapons.COST[n] or 0 end

return M
