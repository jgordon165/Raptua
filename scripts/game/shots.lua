-- Bullets (player and enemy) and short-lived effects (explosions).
local util = require("core.util")

local M = {}
M.__index = M

function M.new()
  local self = setmetatable({}, M)
  self.player, self.enemy, self.fx = {}, {}, {}
  self.boom = util.frames("BOOM_PIC")
  self.airboom = util.frames("AIRBOOM_PIC")
  self.gexplo = util.frames("GEXPLO_BLK")
  self.sparks = util.frames("BSPARK_BLK")
  self.snd_gexplo = rap.sound("GEXPLO_FX")
  self.eshot = util.frames("ESHOT_BLK")
  self.snd_gun = rap.sound("GUN_FX")
  self.snd_boom = rap.sound("EXPLO_FX")
  self.snd_hit = rap.sound("HIT_FX")
  self.snd_eshot = rap.sound("ESHOT_FX")
  return self
end

function M:player_gun(x, y)
  for _, dx in ipairs({ -5, 5 }) do
    self.player[#self.player + 1] = { x = x + dx, y = y + 4, vx = 0, vy = -8, dmg = 1 }
  end
  rap.play(self.snd_gun, 0.5)
end

function M:enemy_shot(x, y, tx, ty, speed)
  local dx, dy = tx - x, ty - y
  local len = math.max(1, math.sqrt(dx * dx + dy * dy))
  speed = speed or 2.5
  self.enemy[#self.enemy + 1] = { x = x, y = y, vx = dx / len * speed, vy = dy / len * speed, t = 0 }
  rap.play(self.snd_eshot, 0.4)
end

function M:explode(x, y, air)
  local frames = air and self.airboom or self.boom
  if #frames == 0 then return end
  local w, h = rap.pic_info(frames[1])
  self.fx[#self.fx + 1] = { frames = frames, x = x - (w or 0) / 2, y = y - (h or 0) / 2, t = 0, scroll = not air }
  rap.play(self.snd_boom, 0.8, (x - rap.W / 2) / (rap.W / 2))
end

-- A destroyed map tile: the big ground explosion, riding the map.
function M:ground_explode(x, y)
  local frames = #self.gexplo > 0 and self.gexplo or self.boom
  if #frames == 0 then return end
  local w, h = rap.pic_info(frames[1])
  self.fx[#self.fx + 1] = { frames = frames, x = x - (w or 0) / 2, y = y - (h or 0) / 2, t = 0, scroll = true, rate = 1 }
  rap.play(self.snd_gexplo or self.snd_boom, 0.8, (x - rap.W / 2) / (rap.W / 2))
end

-- A bullet striking something it didn't destroy.
function M:spark(x, y)
  if #self.sparks == 0 then return end
  local w, h = rap.pic_info(self.sparks[1])
  self.fx[#self.fx + 1] = { frames = self.sparks, x = x - (w or 0) / 2, y = y - (h or 0) / 2, t = 0, scroll = true, rate = 1 }
end

local function move(list, keep)
  local j = 1
  for i = 1, #list do
    local s = list[i]
    if keep(s) then list[j] = s; j = j + 1 end
  end
  for i = j, #list do list[i] = nil end
end

function M:update(scroll)
  local function onscreen(s) return s.y > -16 and s.y < rap.H + 16 and s.x > -16 and s.x < rap.W + 16 end
  move(self.player, function(s) s.x = s.x + s.vx; s.y = s.y + s.vy; return not s.dead and onscreen(s) end)
  move(self.enemy, function(s) s.x = s.x + s.vx; s.y = s.y + s.vy; s.t = s.t + 1; return not s.dead and onscreen(s) end)
  move(self.fx, function(f)
    f.t = f.t + 1
    if f.scroll then f.y = f.y + scroll end
    return f.t // (f.rate or 2) < #f.frames
  end)
end

function M:draw_ground_fx()
  for _, f in ipairs(self.fx) do if f.scroll then rap.pic(f.frames[f.t // (f.rate or 2) + 1], f.x, f.y) end end
end

function M:draw()
  local yellow = util.color(255, 240, 120)
  for _, s in ipairs(self.player) do rap.rect(math.floor(s.x), math.floor(s.y), 2, 6, yellow) end
  for _, s in ipairs(self.enemy) do
    if #self.eshot > 0 then
      rap.pic(self.eshot[(s.t // 4) % #self.eshot + 1], math.floor(s.x) - 3, math.floor(s.y) - 3)
    else
      rap.rect(math.floor(s.x) - 1, math.floor(s.y) - 1, 3, 3, util.color(255, 80, 40))
    end
  end
  for _, f in ipairs(self.fx) do if not f.scroll then rap.pic(f.frames[f.t // (f.rate or 2) + 1], f.x, f.y) end end
end

return M
