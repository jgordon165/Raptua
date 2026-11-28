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
  self.input = util.p1      -- whose controls fly it (util.p2: co-op's second player)
  return self
end

function M:update()
  if self.dead then return end
  if self.demo or self.flyoff then self.flash = math.max(0, self.flash - 1); return end   -- a demo replay places the ship
  local sp = 3
  local x0 = self.x
  if self.input == util.p1 then   -- the mouse flies player one
    local mx, my, dx, dy, moved = rap.mouse()
    if moved then self.x, self.y = self.x + dx * 0.75, self.y + dy * 0.75 end
  end
  if self.autofire and self.autopilot then
    -- Autoplay: drift toward the target play.lua picked (lowest on screen).
    local tx = self.autopilot() or rap.W / 2
    local cx = self.x + self.w / 2
    self.x = self.x + util.clamp(tx - cx, -2, 2)
  end
  local held = self.input.held
  if held("left") then self.x = self.x - sp end
  if held("right") then self.x = self.x + sp end
  if held("up") then self.y = self.y - sp end
  if held("down") then self.y = self.y + sp end
  self:clamp()

  -- Bank toward this tick's movement: faster movement banks harder.
  local vx = self.x - x0
  local target = util.clamp(vx, -LEVEL_FRAME, LEVEL_FRAME)
  if math.abs(vx) < 0.5 then target = 0 end
  if self.bank < target then self.bank = math.min(target, self.bank + BANK_RATE)
  elseif self.bank > target then self.bank = math.max(target, self.bank - BANK_RATE) end

  self.flash = math.max(0, self.flash - 1)
end

-- Keep the ship on the playfield.
function M:clamp()
  self.x = util.clamp(self.x, level.X0 - self.w / 3, level.X0 + 288 - self.w * 2 / 3)
  self.y = util.clamp(self.y, 8, rap.H - self.h)
end

-- Co-op: push two ships apart so they never overlap (they can't fly into
-- each other). Each moves half the overlap, along the shallower axis.
function M.separate(a, b)
  if a.dead or b.dead or a.flyoff or b.flyoff then return end
  local ox = math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x)
  local oy = math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y)
  if ox <= 0 or oy <= 0 then return end
  -- Half each first; if a wall stopped one, the other then takes the rest.
  for i = 1, 3 do
    local k = i == 1 and 0.5 or 1
    if ox <= oy then
      local s = (a.x + a.w / 2 <= b.x + b.w / 2) and -1 or 1
      a.x, b.x = a.x + s * ox * k, b.x - s * ox * k
    else
      local s = (a.y + a.h / 2 <= b.y + b.h / 2) and -1 or 1
      a.y, b.y = a.y + s * oy * k, b.y - s * oy * k
    end
    a:clamp(); b:clamp()
    ox = math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x)
    oy = math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y)
    if ox <= 0 or oy <= 0 then return end
  end
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

-- Bank frame 0..6 (3 = level): also picks the wing gun positions.
function M:bank_index()
  return util.clamp(LEVEL_FRAME + math.floor(self.bank + 0.5), 0, math.max(0, #self.frames - 1))
end

function M:frame()
  return self.frames[self:bank_index() + 1]
end

function M:draw()
  if self.dead or #self.frames == 0 then return end
  local remap = self.flash % 2 == 1 and util.color(255, 255, 255) or -1
  -- self.color: a co-op ship colour (game/shipcolors.lua; nil = the original).
  local lut = self.color and require("game.shipcolors").lut(self.color)
  rap.pic(self:frame(), math.floor(self.x), math.floor(self.y), 0, remap, lut)
  if self.tag then   -- co-op: a mark in the player's colour under each ship
    rap.rect(math.floor(self.x + self.w / 2) - 3, math.floor(self.y + self.h) + 1, 7, 2, self.tag)
  end
end

return M
