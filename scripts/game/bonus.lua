-- Pickups. A destroyed ground crate (sprite library entries with a bonus
-- number, f[2] >= 0) drops BONUSnn_PIC, which rides the map until the player
-- flies over it.
--
-- BONUSnn matches the store icon ICONnn. The item's name comes from the
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

-- Effects by bonus number. Anything not listed counts as an item kept for
-- later (store/hangar) and pays a small bonus.
local SHIELD_ENERGY = 15     -- energy module: shield recharge
local PHASE_SHIELD = 14
local MEGABOMB = 10

function M.new()
  local self = setmetatable({}, M)
  self.list = {}
  self.frames = {}
  self.names = item_names()
  self.snd = rap.sound("BONUS_FX")
  self.message, self.message_t = nil, 0
  return self
end

function M:frames_of(n)
  if not self.frames[n] then self.frames[n] = util.frames(("BONUS%02d_PIC"):format(n)) end
  return self.frames[n]
end

function M:drop(n, x, y)
  local fr = self:frames_of(n)
  if #fr == 0 then return end
  local w, h = rap.pic_info(fr[1])
  if os.getenv("RAPTUA_TRACE") then io.stderr:write(("bonus %d dropped\n"):format(n)) end
  self.list[#self.list + 1] = { n = n, frames = fr, x = x - w / 2, y = y - h / 2, w = w, h = h, t = 0 }
end

local function apply(self, player, n)
  player.items[n] = (player.items[n] or 0) + 1
  if n == SHIELD_ENERGY then
    player.shield = math.min(100, player.shield + 25)
  elseif n == PHASE_SHIELD then
    player.shield = 100
  elseif n == MEGABOMB then
    player.bombs = player.bombs + 1
  else
    player.money = player.money + 500
  end
  if os.getenv("RAPTUA_TRACE") then io.stderr:write(("bonus %d collected: %s\n"):format(n, self.names[n] or "?")) end
  self.message = self.names[n] or ("BONUS %d"):format(n)
  self.message_t = 120
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
