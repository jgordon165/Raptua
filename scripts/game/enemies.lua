-- Enemies and ground targets spawned from the level's actor list.
--
-- Behaviour is a first pass: ground objects ride the map, air units follow
-- their sprite library flight path (interpreted as successive pixel offsets)
-- or fly straight down, and anything armed fires at the player now and then.
-- The real movement and shot rules are still to be read out of RAP.EXE.
local util = require("core.util")
local splib = require("game.splib")
local level = require("game.level")

local M = {}
M.__index = M

function M.new(lib_name)
  local self = setmetatable({}, M)
  self.lib = splib.load(lib_name) or {}
  self.list = {}
  self.frames = {}
  return self
end

function M:frames_of(def)
  local f = self.frames[def.name]
  if not f then f = util.frames(def.name); self.frames[def.name] = f end
  return f
end

function M:spawn(actor, lv)
  local def = self.lib[actor.slib]
  if not def then return end
  local frames = self:frames_of(def)
  if #frames == 0 then return end
  local w, h = rap.pic_info(frames[1])
  local e = {
    def = def, frames = frames, w = w, h = h,
    hp = def.hits, t = 0, flash = 0,
    x = level.X0 + actor.x * 32 + 16 - w / 2,
  }
  if def.ground then
    e.wy = actor.y * 32 + 16 - h / 2          -- world position: rides the map
  else
    e.y = -h
    e.path = splib.path_points(def)
    e.leg, e.legt = 1, 0
    e.vy = 1.5
  end
  e.fire_wait = 60 + (actor.x * 37 + actor.y * 11) % 90
  self.list[#self.list + 1] = e
end

local function step_path(e)
  local p = e.path[e.leg]
  if not p then e.y = e.y + e.vy; return end
  -- Each leg moves by its (dx, dy) over 32 ticks; dy is flipped so the
  -- mostly-negative values in the data read as "towards the bottom".
  e.x = e.x + p[1] / 32
  e.y = e.y + math.max(0.5, -p[2] / 32)
  e.legt = e.legt + 1
  if e.legt >= 32 then e.leg, e.legt = e.leg + 1, 0 end
end

function M:update(lv, player, shots)
  local j = 1
  for i = 1, #self.list do
    local e = self.list[i]
    e.t = e.t + 1
    e.flash = math.max(0, e.flash - 1)
    if e.def.ground then e.y = lv:sy(e.wy) else step_path(e) end
    local keep = not e.dead and e.y < rap.H + 8
    if keep and e.y > 0 and not player.dead and e.def.shots > 0 then
      e.fire_wait = e.fire_wait - 1
      if e.fire_wait <= 0 then
        e.fire_wait = 70 + (e.t * 13) % 80
        shots:enemy_shot(e.x + e.w / 2, e.y + e.h * 0.7, player.x + player.w / 2, player.y + player.h / 2)
      end
    end
    if keep then self.list[j] = e; j = j + 1 end
  end
  for i = j, #self.list do self.list[i] = nil end
end

-- Player bullets vs enemies; enemy bullets and bodies vs the player.
function M:collide(player, shots)
  for _, s in ipairs(shots.player) do
    for _, e in ipairs(self.list) do
      if not e.dead and s.x >= e.x and s.x < e.x + e.w and s.y >= e.y and s.y < e.y + e.h
         and rap.pic_hit(e.frames[1], s.x - e.x, s.y - e.y) then
        s.dead = true
        e.hp = e.hp - s.dmg
        e.flash = 3
        if e.hp <= 0 then
          e.dead = true
          player.money = player.money + e.def.bounty
          shots:explode(e.x + e.w / 2, e.y + e.h / 2, not e.def.ground)
        end
        break
      end
    end
  end
  if player.dead then return end
  local px, py, pw, ph = player:box()
  for _, s in ipairs(shots.enemy) do
    if util.overlap(px, py, pw, ph, s.x - 2, s.y - 2, 4, 4) then
      s.dead = true
      player:hurt(4)
      rap.play(shots.snd_hit, 0.7)
    end
  end
  for _, e in ipairs(self.list) do
    if not e.dead and not e.def.ground and util.overlap(px, py, pw, ph, e.x + 4, e.y + 4, e.w - 8, e.h - 8) then
      e.dead = true
      player:hurt(15)
      shots:explode(e.x + e.w / 2, e.y + e.h / 2, true)
    end
  end
end

function M:draw(ground)
  local white = util.color(255, 255, 255)
  for _, e in ipairs(self.list) do
    if e.def.ground == ground and not e.dead then
      local f = e.frames[(e.t // 6) % math.min(#e.frames, e.def.frames) + 1]
      rap.pic(f, math.floor(e.x), math.floor(e.y), 0, e.flash > 0 and white or -1)
    end
  end
end

return M
