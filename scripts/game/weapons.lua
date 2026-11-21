-- The player's weapons and the shots they fire.
--
-- Objects are numbered as in the original (the same numbers pickups carry):
--   0 machine guns, 1 plasma guns, 2 micro missiles    fire with the guns
--   3 dumbfire, 4 mini gun, 5 laser turret, 6 missile pods, 7 air-to-air,
--   8 air-to-ground, 9 bomb, 10 energy grab, 12 pulse cannon,
--   13 forward laser, 14 death ray                     the "special" weapon
--   11 megabomb (up to 5), 15 phase shield, 16 energy, 17 damage detector,
--   18-23 cash items
--
-- Per weapon: damage, start/top speed, fire rate (game frames) and what it
-- can hit come from the original's weapon table. How each one spreads its
-- shots is Raptua's own approximation until it's checked in RAP.EXE.
local util = require("core.util")

local M = {}
M.__index = M

-- hit: "air", "ground", "all"; ground-capable shots also damage map tiles.
local LIB = {
  [0]  = { name = "MACHINE GUNS", pic = "NMSHOT_BLK", dmg = 1, speed = 8, top = 16, rate = 2, hit = "all", snd = "GUN_FX" },
  [1]  = { name = "PLASMA GUNS", pic = "PLASMA_BLK", dmg = 2, speed = 4, top = 8, rate = 10, hit = "air", snd = "LASER_FX" },
  [2]  = { name = "MICRO MISSILES", pic = "MICROM_BLK", dmg = 2, speed = 2, top = 8, rate = 4, hit = "all", snd = "MISSLE_FX" },
  [3]  = { name = "DUMBFIRE MISSILES", pic = "MISDUM_BLK", dmg = 4, speed = 2, top = 12, rate = 10, hit = "all", snd = "MISSLE_FX" },
  [4]  = { name = "MINI GUN", pic = "NMSHOT_BLK", dmg = 1, speed = 8, top = 10, rate = 1, hit = "all", aim = true, snd = "GUN_FX" },
  [5]  = { name = "LASER TURRET", dmg = 5, rate = 6, hit = "all", beam = "turret", snd = "TURRET_FX" },
  [6]  = { name = "MISSILE PODS", pic = "MISRAT_BLK", dmg = 4, speed = 1, top = 16, rate = 5, hit = "air", snd = "MISSLE_FX" },
  [7]  = { name = "AIR-TO-AIR MISSILES", pic = "MISRAT_BLK", dmg = 4, speed = 1, top = 12, rate = 10, hit = "air", home = true, snd = "MISSLE_FX" },
  [8]  = { name = "AIR-TO-GROUND MISSILES", pic = "MISGRD_BLK", dmg = 20, speed = 1, top = 6, rate = 20, hit = "ground", home = true, snd = "MISSLE_FX" },
  [9]  = { name = "BOMB", pic = "BLDGBOMB_PIC", dmg = 50, speed = 1, top = 4, rate = 30, hit = "ground", bomb = true, snd = "MISSLE_FX" },
  [10] = { name = "ENERGY GRAB", pic = "POWDIS_BLK", dmg = 3, speed = 4, top = 8, rate = 2, hit = "air", grab = true, snd = "EGRAB_FX" },
  [12] = { name = "PULSE CANNON", pic = "SHOKWV_BLK", dmg = 5, speed = 8, top = 8, rate = 3, hit = "all", snd = "LASER_FX" },
  [13] = { name = "FORWARD LASER", pic = "FRNTLAS_BLK", dmg = 10, rate = 7, hit = "air", beam = "forward", snd = "LASER_FX" },
  [14] = { name = "DEATH RAY", pic = "DETHRY_BLK", dmg = 6, rate = 7, hit = "all", beam = "forward", snd = "LASER_FX" },
}
M.LIB = LIB
M.MEGABOMB, M.SUPER_SHIELD, M.ENERGY = 11, 15, 16
M.FIRST_SPECIAL, M.LAST_SPECIAL = 3, 14
M.CASH = { [18] = 93800, [19] = 76000, [20] = 55700, [21] = 35200, [22] = 122500, [23] = 50 }

function M.new()
  local self = setmetatable({}, M)
  self.shots = {}
  self.beams = {}
  self.cool = {}
  self.pics, self.snds = {}, {}
  for n, w in pairs(LIB) do
    if w.pic then self.pics[n] = util.frames(w.pic) end
    if w.snd then self.snds[n] = rap.sound(w.snd) end
  end
  return self
end

local function can_hit(hit, ground) return hit == "all" or (hit == "air") ~= ground end

-- The nearest live enemy above (x, y) that `hit` can strike.
local function nearest(enemies, x, y, hit)
  local best, bd
  for _, e in ipairs(enemies.list) do
    if not e.dead and can_hit(hit, e.def.ground) and e.y + e.h > 0 and e.y < y then
      local dx, dy = e.x + e.w / 2 - x, e.y + e.h / 2 - y
      local d = dx * dx + dy * dy
      if not bd or d < bd then best, bd = e, d end
    end
  end
  return best
end

function M:add(n, x, y, vx, vy, extra)
  local w = LIB[n]
  local s = { n = n, x = x, y = y, vx = vx or 0, vy = vy or -w.speed, speed = w.speed, t = 0 }
  if extra then for k, v in pairs(extra) do s[k] = v end end
  self.shots[#self.shots + 1] = s
end

-- Fire weapon n from the player's ship this game frame, if it's ready.
function M:fire(n, pl, enemies)
  local w = LIB[n]
  if not w then return end
  if (self.cool[n] or 0) > 0 then return end
  self.cool[n] = w.rate
  local cx, top = pl.x + pl.w / 2, pl.y
  if n == 0 then
    self:add(n, cx - 7, top + 6); self:add(n, cx + 7, top + 6)
  elseif n == 1 then
    self:add(n, cx, top)
  elseif n == 2 or n == 6 then
    pl.alt = not pl.alt
    local side = pl.alt and -1 or 1
    self:add(n, cx + side * 12, top + 12, side * 0.5)
  elseif n == 4 then
    local e = nearest(enemies, cx, top, w.hit)
    local vx, vy = 0, -w.speed
    if e then
      local dx, dy = e.x + e.w / 2 - cx, e.y + e.h / 2 - top
      local len = math.max(1, math.sqrt(dx * dx + dy * dy))
      vx, vy = dx / len * w.speed, dy / len * w.speed
    end
    self:add(n, cx, top, vx, vy)
  elseif w.beam == "turret" then
    local e = nearest(enemies, cx, top, w.hit)
    if not e then self.cool[n] = 1; return end
    self.beams[#self.beams + 1] = { x1 = cx, y1 = top + 8, target = e, t = 4, n = n }
    e._beam_hit = (e._beam_hit or 0) + w.dmg
  elseif w.beam == "forward" then
    self.beams[#self.beams + 1] = { x1 = cx, y1 = top, t = 4, n = n, column = true }
  elseif n == 12 then
    self:add(n, cx - 8, top - 8)
  elseif n == 7 or n == 8 then
    pl.alt = not pl.alt
    self:add(n, cx + (pl.alt and -10 or 10), top + 8)
  elseif w.bomb then
    self:add(n, cx - 4, top + 8, 0, -w.speed, { target_y = math.max(20, top - 100) })
  else
    self:add(n, cx, top)
  end
  if self.snds[n] then rap.play(self.snds[n], n == 0 and 0.45 or 0.6) end
end

-- What the player has: the always-on guns, plus the selected special.
function M:fire_all(pl, enemies)
  for n = 0, 2 do if pl.items[n] then self:fire(n, pl, enemies) end end
  if pl.special and pl.items[pl.special] then self:fire(pl.special, pl, enemies) end
end

local function hit_enemy(self, s, w, enemies, pl, shots, bonus)
  for _, e in ipairs(enemies.list) do
    if can_hit(w.hit, e.def.ground) and enemies.touches(e, s.x, s.y) then
      enemies:damage(e, w.dmg, pl, shots, bonus)
      if w.grab then pl.shield = math.min(pl.max_shield, pl.shield + 1) end
      if not e.dead then shots:spark(s.x, s.y) end
      return true
    end
  end
  return false
end

-- One game frame: move shots, resolve hits.
function M:step(pl, enemies, shots, lv, bonus)
  for n, c in pairs(self.cool) do if c > 0 then self.cool[n] = c - 1 end end
  local j = 1
  for i = 1, #self.shots do
    local s = self.shots[i]
    local w = LIB[s.n]
    s.t = s.t + 1
    if w.home and s.t > 3 then
      local e = nearest(enemies, s.x, s.y + 40, w.hit)
      if e then
        local dx, dy = e.x + e.w / 2 - s.x, e.y + e.h / 2 - s.y
        local len = math.max(1, math.sqrt(dx * dx + dy * dy))
        s.vx, s.vy = dx / len * s.speed, dy / len * s.speed
      end
    end
    -- Speed builds up to the weapon's top speed.
    if w.top and s.speed < w.top then
      local f = (s.speed + 1) / math.max(1, s.speed)
      s.speed = s.speed + 1
      s.vx, s.vy = s.vx * f, s.vy * f
    end
    s.x, s.y = s.x + s.vx, s.y + s.vy
    local done = s.y < -24 or s.y > rap.H + 8 or s.x < -16 or s.x > rap.W + 16
    if not done then
      if w.bomb then
        if s.y <= s.target_y then
          -- A bomb strikes the ground where it lands: tiles and ground targets nearby.
          for _, e in ipairs(enemies.list) do
            if e.def.ground and util.overlap(s.x - 12, s.y - 12, 24, 24, e.x, e.y, e.w, e.h) then
              enemies:damage(e, w.dmg, pl, shots, bonus)
            end
          end
          local t = lv:hit_tile(s.x, s.y, w.dmg)
          if t and t.destroyed then pl.money = pl.money + t.bounty end
          shots:ground_explode(s.x, s.y)
          done = true
        end
      elseif hit_enemy(self, s, w, enemies, pl, shots, bonus) then
        done = true
      elseif w.hit ~= "air" then
        local t = lv:hit_tile(s.x, s.y, w.dmg)
        if t then
          done = true
          if t.destroyed then pl.money = pl.money + t.bounty; shots:ground_explode(t.x, t.y)
          else shots:spark(s.x, s.y) end
        end
      end
    end
    if not done then self.shots[j] = s; j = j + 1 end
  end
  for i = j, #self.shots do self.shots[i] = nil end

  -- Beams hit on the frame they're fired, then fade.
  local k = 1
  for i = 1, #self.beams do
    local b = self.beams[i]
    local w = LIB[b.n]
    if b.t == 4 then
      if b.column then
        for _, e in ipairs(enemies.list) do
          if not e.dead and can_hit(w.hit, e.def.ground) and e.y < b.y1 and e.y + e.h > 0
             and b.x1 >= e.x and b.x1 < e.x + e.w then
            enemies:damage(e, w.dmg, pl, shots, bonus)
          end
        end
      elseif b.target and not b.target.dead then
        enemies:damage(b.target, w.dmg, pl, shots, bonus)
      end
    end
    b.t = b.t - 1
    if b.t > 0 then self.beams[k] = b; k = k + 1 end
  end
  for i = k, #self.beams do self.beams[i] = nil end
end

function M:draw(pl)
  for _, s in ipairs(self.shots) do
    local fr = self.pics[s.n]
    if fr and #fr > 0 then
      local w, h = rap.pic_info(fr[1])
      rap.pic(fr[(s.t // 2) % #fr + 1], math.floor(s.x - w / 2), math.floor(s.y - h / 2))
    else
      rap.rect(math.floor(s.x), math.floor(s.y), 2, 5, util.color(255, 240, 120))
    end
  end
  local red, cyan = util.color(255, 60, 40), util.color(120, 230, 255)
  for _, b in ipairs(self.beams) do
    local col = b.n == 14 and red or cyan
    if b.column then
      local x = math.floor(pl.x + pl.w / 2)
      rap.rect(x - 1, 0, 3, math.floor(pl.y), col)
    elseif b.target then
      local e = b.target
      local x1, y1, x2, y2 = pl.x + pl.w / 2, pl.y + 8, e.x + e.w / 2, e.y + e.h / 2
      local n = math.max(1, math.floor(math.max(math.abs(x2 - x1), math.abs(y2 - y1))))
      for i = 0, n, 2 do rap.pixel(math.floor(x1 + (x2 - x1) * i / n), math.floor(y1 + (y2 - y1) * i / n), col) end
    end
  end
end

return M
