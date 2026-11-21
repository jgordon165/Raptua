-- The player's ship.
--
-- Drawn from LPLAYER_PIC in the player's own FILE0001.GLB: seven 32x32
-- frames, banked hard left (0) through level (3) to banked hard right (6).
-- The bank eases toward the direction of horizontal movement and back to
-- level when the ship stops.
local util = require("core.util")
local level = require("game.level")

local M = {}
M.__index = M

M.SPRITE = "LPLAYER_PIC"
local LEVEL_FRAME = 3      -- frames run 0..6; 3 is wings level
local BANK_RATE = 0.25     -- frames per tick toward the target bank

function M.new()
  local self = setmetatable({}, M)
  self.frames = util.frames(M.SPRITE)
  self.w, self.h = 32, 32
  if #self.frames > 0 then self.w, self.h = rap.pic_info(self.frames[1]) end
  self.bank = 0             -- -3 (left) .. +3 (right), fractional while easing
  self.x = rap.W / 2 - self.w / 2
  self.y = rap.H - self.h - 16
  self.shield, self.max_shield = 100, 100
  self.super = 0            -- phase shield: absorbs damage before the shield
  self.money = 0
  self.items = { [0] = 1 }  -- owned objects by number (weapons.lua); start with the machine guns
  self.special = nil        -- selected special weapon (3..14)
  self.cool = 0
  self.flash = 0
  self.dead = false
  return self
end

function M:update()
  if self.dead then return end
  local sp = 3
  local x0 = self.x
  local mx, my, dx, dy, moved = rap.mouse()
  if moved then self.x, self.y = self.x + dx * 0.75, self.y + dy * 0.75 end
  if self.autofire and self.autopilot then
    -- Autoplay: drift toward the target play.lua picked (lowest on screen).
    local tx = self.autopilot() or rap.W / 2
    local cx = self.x + self.w / 2
    self.x = self.x + util.clamp(tx - cx, -2, 2)
  end
  if util.held("left") then self.x = self.x - sp end
  if util.held("right") then self.x = self.x + sp end
  if util.held("up") then self.y = self.y - sp end
  if util.held("down") then self.y = self.y + sp end
  self.x = util.clamp(self.x, level.X0 - self.w / 3, level.X0 + 288 - self.w * 2 / 3)
  self.y = util.clamp(self.y, 8, rap.H - self.h)

  -- Bank toward this tick's movement: faster movement banks harder.
  local vx = self.x - x0
  local target = util.clamp(vx, -LEVEL_FRAME, LEVEL_FRAME)
  if math.abs(vx) < 0.5 then target = 0 end
  if self.bank < target then self.bank = math.min(target, self.bank + BANK_RATE)
  elseif self.bank > target then self.bank = math.max(target, self.bank - BANK_RATE) end

  self.flash = math.max(0, self.flash - 1)
end

-- Megabombs carried (object 11).
function M:bombs() return self.items[11] or 0 end

-- Select the next owned special weapon after the current one.
function M:next_special(first, last)
  local start = self.special or (first - 1)
  for i = 1, last - first + 1 do
    local n = first + (start - first + i) % (last - first + 1)
    if self.items[n] and n ~= 11 then self.special = n; return true end
  end
  return false
end

function M:hurt(n)
  if self.dead then return end
  if self.autofire then self.flash = 6; return end   -- autoplay/demo: can't die
  local absorbed = math.min(self.super, n)
  self.super, n = self.super - absorbed, n - absorbed
  self.shield = self.shield - n
  self.flash = 6
  if self.shield <= 0 then self.shield = 0; self.dead = true end
end

function M:box() return self.x + 6, self.y + 6, self.w - 12, self.h - 12 end

function M:frame()
  local i = LEVEL_FRAME + math.floor(self.bank + 0.5)
  return self.frames[util.clamp(i, 0, #self.frames - 1) + 1]
end

function M:draw()
  if self.dead or #self.frames == 0 then return end
  local remap = self.flash % 2 == 1 and util.color(255, 255, 255) or -1
  rap.pic(self:frame(), math.floor(self.x), math.floor(self.y), 0, remap)
end

return M
