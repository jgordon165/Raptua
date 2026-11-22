-- Pickups. A destroyed enemy whose sprite library entry has a bonus number
-- (f[2] >= 0, an object number) drops that object, and an "energy" ship
-- (explosion type 8) drops the blue energy orb, object 23; each rides the
-- map until the player flies over it.
--
-- Each object has its own picture, BONUSnn_PIC by the original's object
-- table, not by object number: from the bomb (9, BONUS21) on, the two
-- differ (shield energy 16 is BONUS15, the orb 23 is BONUS22). The item's name comes from the
-- ITEMxx_TXT whose TEXT_IMAGE line names that icon, read from the player's
-- own FILE0000.GLB. What each pickup does is a first pass until the
-- original's rules are read out of RAP.EXE.
local util = require("core.util")

local M = {}
M.__index = M

local function item_names()
  local names = {}
  for i = 0, 40 do
    local txt = rap.read(("ITEM%02d_TXT"):format(i))
    if not txt then break end
    local icon = txt:match("TEXT_IMAGE%s+ICON(%d+)_PIC")
    -- The title is the first line after TEXT_POS that isn't a command.
    local title
    for line in txt:gmatch("[^\r\n]+") do
      line = line:match("^%s*(.-)%s*$")
      if line ~= "" and not line:match("^TEXT_") then title = line; break end
    end
    if icon and title then names[tonumber(icon)] = title end
  end
  return names
end

local weapons = require("game.weapons")

function M.new()
  local self = setmetatable({}, M)
  self.list = {}
  self.frames = {}
  self.names = item_names()
  self.snd = rap.sound("BONUS_FX")
  self.message, self.message_t = nil, 0
  return self
end

-- Object number -> its BONUSnn picture (the original's object table).
M.PIC = { [0] = 0, 1, 2, 3, 4, 5, 6, 7, 8, 21, 9, 10, 11, 12, 13, 14, 15, 16, 16, 17, 18, 19, 20, 22 }

-- The energy orb an energy ship leaves ($50), and how many may be about at
-- once (the original keeps 3 of its 12 pickup slots for other drops).
M.ORB, M.MAX_ORBS = 23, 9

function M:frames_of(n)
  if not self.frames[n] then
    local pic = M.PIC[n]
    self.frames[n] = pic and util.frames(("BONUS%02d_PIC"):format(pic)) or {}
  end
  return self.frames[n]
end

function M:drop(n, x, y)
  local fr = self:frames_of(n)
  if #fr == 0 then return end
  if n == M.ORB then
    local orbs = 0
    for _, b in ipairs(self.list) do if b.n == M.ORB then orbs = orbs + 1 end end
    if orbs >= M.MAX_ORBS then return end
  end
  local w, h = rap.pic_info(fr[1])
  if os.getenv("RAPTUA_TRACE") then io.stderr:write(("bonus %d dropped\n"):format(n)) end
  self.list[#self.list + 1] = { n = n, frames = fr, x = x - w / 2, y = y - h / 2, w = w, h = h, t = 0 }
end

-- Pickups carry object numbers (weapons.lua): weapons are added to the
-- ship (the first special picked up is selected), energy recharges a
-- quarter of the shield, the phase shield fills its own layer, megabombs
-- stack to 5, cash items pay out.
local function apply(self, player, n)
  local label
  if weapons.CASH[n] then
    player.money = player.money + weapons.CASH[n]
    label = ("$%d"):format(weapons.CASH[n])
  elseif n == weapons.ENERGY then
    player.shield = math.min(player.max_shield, player.shield + player.max_shield // 4)
  elseif n == weapons.SUPER_SHIELD then
    player.super = 100
  elseif n == weapons.MEGABOMB then
    player.items[n] = math.min(5, (player.items[n] or 0) + 1)
  else
    player.items[n] = 1
    if not player.special and n >= weapons.FIRST_SPECIAL and n <= weapons.LAST_SPECIAL then player.special = n end
  end
  if os.getenv("RAPTUA_TRACE") then io.stderr:write(("bonus %d collected: %s\n"):format(n, self.names[M.PIC[n] or n] or "?")) end
  self.message = label or self.names[M.PIC[n] or n] or (weapons.LIB[n] and weapons.LIB[n].name) or ("BONUS %d"):format(n)
  self.message_t = 70
end

function M:update(scroll, player)
  self.message_t = math.max(0, self.message_t - 1)
  local px, py, pw, ph = player:box()
  local j = 1
  for i = 1, #self.list do
    local b = self.list[i]
    b.t = b.t + 1
    b.y = b.y + scroll
    local keep = b.y < rap.H + 8
    if keep and not player.dead and util.overlap(px, py, pw, ph, b.x, b.y, b.w, b.h) then
      apply(self, player, b.n)
      rap.play(self.snd, 0.9)
      keep = false
    end
    if keep then self.list[j] = b; j = j + 1 end
  end
  for i = j, #self.list do self.list[i] = nil end
end

function M:draw()
  for _, b in ipairs(self.list) do
    rap.pic(b.frames[(b.t // 6) % #b.frames + 1], math.floor(b.x), math.floor(b.y))
  end
end

function M:draw_message(font)
  if self.message_t > 0 and self.message then
    local w = rap.text_size(font, self.message)
    rap.text(font, self.message, (rap.W - w) // 2, 20, util.color(120, 255, 120))
  end
end

return M
