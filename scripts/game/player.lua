-- The player's ship.
local util = require("core.util")
local level = require("game.level")

local M = {}
M.__index = M

-- The in-game Raptor sprite has not been identified in the archives yet
-- (see docs/formats.md, "Open questions"). Until then the first of these
-- names that exists is used, else a drawn placeholder.
M.SPRITE_NAMES = { "PLAYER_PIC", "RAPTOR_PIC", "MINSHIP_PIC" }

function M.new()
  local self = setmetatable({}, M)
  self.w, self.h = 32, 32
  for _, n in ipairs(M.SPRITE_NAMES) do
    if rap.find(n) then
      self.pic = n
      self.w, self.h = rap.pic_info(n)
      break
    end
  end
  self.x = rap.W / 2 - self.w / 2
  self.y = rap.H - self.h - 16
  self.shield = 100
  self.money = 0
  self.cool = 0
  self.flash = 0
  self.dead = false
  return self
end

function M:update(shots)
  if self.dead then return end
  local sp = 3
  local mx, my, dx, dy, moved = rap.mouse()
  if moved then self.x, self.y = self.x + dx * 0.75, self.y + dy * 0.75 end
  if self.autofire then self.x = rap.W / 2 - self.w / 2 + math.sin(rap.millis() / 700) * 100 end
  if util.held("left") then self.x = self.x - sp end
  if util.held("right") then self.x = self.x + sp end
  if util.held("up") then self.y = self.y - sp end
  if util.held("down") then self.y = self.y + sp end
  self.x = util.clamp(self.x, level.X0 - self.w / 3, level.X0 + 288 - self.w * 2 / 3)
  self.y = util.clamp(self.y, 8, rap.H - self.h)
  self.cool = math.max(0, self.cool - 1)
  self.flash = math.max(0, self.flash - 1)
  if (util.held("fire") or self.autofire) and self.cool == 0 then
    self.cool = 7
    shots:player_gun(self.x + self.w / 2, self.y)
  end
end

function M:hurt(n)
  if self.dead then return end
  self.shield = self.shield - n
  self.flash = 6
  if self.shield <= 0 then self.shield = 0; self.dead = true end
end

function M:box() return self.x + 6, self.y + 6, self.w - 12, self.h - 12 end

function M:draw()
  if self.dead then return end
  local remap = self.flash % 2 == 1 and util.color(255, 255, 255) or -1
  if self.pic then
    rap.pic(self.pic, math.floor(self.x), math.floor(self.y), 0, remap)
    return
  end
  -- Placeholder: an original delta-wing shape.
  local body = remap >= 0 and remap or util.color(170, 180, 200)
  local dark = util.color(80, 90, 110)
  local glow = util.color(255, 160, 40)
  local cx, top = math.floor(self.x + self.w / 2), math.floor(self.y)
  for i = 0, 27 do
    local half = i < 8 and 1 or math.min(15, (i - 6) * 3 // 4)
    rap.rect(cx - half, top + i, half * 2 + 1, 1, i > 22 and dark or body)
  end
  rap.rect(cx - 1, top + 10, 3, 6, dark)
  rap.rect(cx - 6, top + 28, 3, 3, glow)
  rap.rect(cx + 4, top + 28, 3, 3, glow)
end

return M
