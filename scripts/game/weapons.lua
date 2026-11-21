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
-- Shots follow the original's rules (all per game frame):
--   * fired in pairs from the wings; how far out depends on the ship's bank
--     frame (widest when level), so turning pulls the pair together
--   * fly straight at their target point (the top of the screen for
--     missiles), `speed` pixels along the main axis per frame, the speed
--     going up by 1 a frame to the weapon's top speed
--   * animation steps every frame, looping back to `loop_from`
--   * dumbfire missiles first coast sideways out of the rack (no thrust, no
--     animation), then ignite with a puff of smoke and climb, drifting up to
--     16 pixels to one side
--   * missile pods and air-to-air / air-to-ground missiles leave a smoke
--     trail; nothing homes
--   * hits throw a blue or orange spark
-- Per weapon: damage, start/top speed, fire rate, frames and what it can hit
-- match the original's weapon table. The non-missile specials (mini gun,
-- turret, pulse cannon, lasers, bomb, energy grab) are still approximations.
local util = require("core.util")

local M = {}
M.__index = M

-- hit: "air" (aircraft only), "ground" (ground targets, then map tiles),
--      "all" (any enemy, then map tiles), "enemies" (any enemy, not tiles),
--      "tiles" (bombs).
local LIB = {
  [0]  = { name = "MACHINE GUNS", pic = "NMSHOT_BLK", dmg = 1, speed = 8, top = 16, rate = 2, hit = "all", snd = "GUN_FX" },
  [1]  = { name = "PLASMA GUNS", pic = "PLASMA_BLK", dmg = 2, speed = 4, top = 8, rate = 10, hit = "air", snd = "LASER_FX" },
  [2]  = { name = "MICRO MISSILES", pic = "MICROM_BLK", dmg = 2, speed = 2, top = 8, rate = 4, hit = "enemies", snd = "GUN_FX" },
  [3]  = { name = "DUMBFIRE MISSILES", pic = "MISDUM_BLK", dmg = 4, speed = 2, top = 12, rate = 10, hit = "all",
           loop_from = 1, coast = true, snd = "MISSLE_FX" },
  [4]  = { name = "MINI GUN", pic = "NMSHOT_BLK", dmg = 1, speed = 8, top = 10, rate = 1, hit = "enemies", loop_from = 1, aim = true, snd = "GUN_FX" },
  [5]  = { name = "LASER TURRET", dmg = 5, rate = 6, hit = "air", beam = "turret", snd = "TURRET_FX" },
  [6]  = { name = "MISSILE PODS", pic = "MISRAT_BLK", dmg = 4, speed = 1, top = 16, rate = 5, hit = "air", smoke = true, snd = "GUN_FX" },
  [7]  = { name = "AIR-TO-AIR MISSILES", pic = "MISRAT_BLK", dmg = 4, speed = 1, top = 12, rate = 10, hit = "air", smoke = true, snd = "MISSLE_FX" },
  [8]  = { name = "AIR-TO-GROUND MISSILES", pic = "MISGRD_BLK", dmg = 20, speed = 1, top = 6, rate = 20, hit = "ground", smoke = true, snd = "MISSLE_FX" },
  [9]  = { name = "BOMB", pic = "BLDGBOMB_PIC", dmg = 50, speed = 1, top = 4, rate = 30, hit = "tiles", bomb = true, snd = "MISSLE_FX" },
  [10] = { name = "ENERGY GRAB", pic = "POWDIS_BLK", dmg = 3, speed = 4, top = 8, rate = 2, hit = "air", grab = true, snd = "EGRAB_FX" },
  [12] = { name = "PULSE CANNON", pic = "SHOKWV_BLK", dmg = 5, speed = 8, top = 8, rate = 3, hit = "all", snd = "LASER_FX" },
  [13] = { name = "FORWARD LASER", pic = "FRNTLAS_BLK", dmg = 10, rate = 7, hit = "air", beam = "forward", snd = "LASER_FX" },
  [14] = { name = "DEATH RAY", pic = "DETHRY_BLK", dmg = 6, rate = 7, hit = "enemies", beam = "forward", snd = "LASER_FX" },
}
M.LIB = LIB
M.MEGABOMB, M.SUPER_SHIELD, M.ENERGY = 11, 15, 16
M.FIRST_SPECIAL, M.LAST_SPECIAL = 3, 14
M.CASH = { [18] = 93800, [19] = 76000, [20] = 55700, [21] = 35200, [22] = 122500, [23] = 50 }

-- Wing positions (pixels either side of the ship's centre) per bank frame
-- 0..6: machine guns, missile racks (pods, air-to-air, air-to-ground),
-- micro missile launchers.
local GUN_X   = { [0] = 1, 3, 5, 6, 5, 3, 1 }
local RACK_X  = { [0] = 1, 3, 6, 9, 6, 3, 2 }
local MICRO_X = { [0] = 2, 6, 8, 11, 8, 6, 2 }

local SMOKE_FIRST, SMOKE_FRAMES = 5, 5    -- the falling-smoke part of SSMOKE_BLK
local SMOKE_FALL = 2                      -- pixels per frame (Raptua's choice)

function M.new()
  local self = setmetatable({}, M)
  self.shots, self.beams, self.puffs = {}, {}, {}
  self.cool = {}
  self.pics, self.snds = {}, {}
  for n, w in pairs(LIB) do
    if w.pic then self.pics[n] = util.frames(w.pic) end
    if w.snd then self.snds[n] = rap.sound(w.snd) end
  end
  local smoke = util.frames("SSMOKE_BLK")
  self.smoke = {}
  for i = SMOKE_FIRST, math.min(#smoke, SMOKE_FIRST + SMOKE_FRAMES - 1) do self.smoke[#self.smoke + 1] = smoke[i] end
  self.spark_blue = util.frames("BSPARK_BLK")
  self.spark_orange = util.frames("OSPARK_BLK")
  return self
end

local function can_hit(hit, ground)
  if hit == "all" or hit == "enemies" then return true end
  if hit == "air" then return not ground end
  return ground   -- "ground", "tiles"
end

-- Starts a shot of weapon n at (x, y) heading for (tx, ty).
function M:add(n, x, y, tx, ty, extra)
  local w = LIB[n]
  local s = { n = n, x = x, y = y, tx = tx, ty = ty, speed = w.speed or 0, frame = 0 }
  if extra then for k, v in pairs(extra) do s[k] = v end end
  self.shots[#self.shots + 1] = s
  return s
end

-- A random live enemy that `hit` can strike (the mini gun and turret pick
-- one at random each shot).
local function random_target(enemies, hit)
  local pool = {}
  for _, e in ipairs(enemies.list) do
    if not e.dead and can_hit(hit, e.def.ground) and e.y + e.h > 0 and e.y < rap.H then pool[#pool + 1] = e end
  end
  return #pool > 0 and pool[math.random(#pool)] or nil
end

-- Fire weapon n from the player's ship this game frame, if it's ready.
function M:fire(n, pl, enemies)
  local w = LIB[n]
  if not w or (self.cool[n] or 0) > 0 then return end
  self.cool[n] = w.rate
  local cx, cy = pl.x + pl.w / 2, pl.y + pl.h / 2
  local b = pl:bank_index()
  if n == 0 then
    self:add(n, cx + GUN_X[b], cy, cx + GUN_X[b], -16)
    self:add(n, cx - GUN_X[b] - 1, cy, cx - GUN_X[b] - 1, -16)
  elseif n == 2 then
    self:add(n, cx + MICRO_X[b], cy, cx + MICRO_X[b], 0)
    self:add(n, cx - MICRO_X[b], cy, cx - MICRO_X[b], 0)
  elseif n == 6 or n == 7 or n == 8 then
    self:add(n, cx + RACK_X[b], cy, cx + RACK_X[b], 0)
    self:add(n, cx - RACK_X[b], cy, cx - RACK_X[b], 0)
  elseif n == 3 then
    -- Out of the rack sideways, a little behind the ship, then ignite.
    self:add(n, cx, cy, cx + math.random(10, 25), cy + 5, { coasting = true })
    self:add(n, cx, cy, cx - math.random(10, 25), cy + 5, { coasting = true })
  elseif n == 4 then
    local e = random_target(enemies, w.hit)
    if not e then self.cool[n] = 0; return end
    self:add(n, cx, cy, e.x + math.random(0, math.max(0, e.w - 1)), e.y + e.h / 2 + math.random(0, math.max(0, e.h // 2 - 1)),
             { frame = math.random(0, 3) })
  elseif w.beam == "turret" then
    local e = random_target(enemies, w.hit)
    if not e then self.cool[n] = 0; return end
    self.beams[#self.beams + 1] = { target = e, t = 4, n = n }
  elseif w.beam == "forward" then
    self.beams[#self.beams + 1] = { t = 4, n = n, column = true }
  elseif n == 9 then
    self:add(n, cx, cy - 24, cx, math.max(20, cy - 110))
  elseif n == 12 then
    self:add(n, cx, cy - 12, cx, -16)
  else
    self:add(n, cx, cy, cx, -16)
  end
  if self.snds[n] then rap.play(self.snds[n], n == 0 and 0.45 or 0.6) end
end

-- What the player has: the always-on guns, plus the selected special.
function M:fire_all(pl, enemies)
  for n = 0, 2 do if pl.items[n] then self:fire(n, pl, enemies) end end
  if pl.special and pl.items[pl.special] then self:fire(pl.special, pl, enemies) end
end

function M:spark(x, y, orange)
  local fr = (orange or math.random(2) == 1) and self.spark_orange or self.spark_blue
  if #fr == 0 then return end
  self.puffs[#self.puffs + 1] = { frames = fr, x = x, y = y, t = 0, fall = 0 }
end

function M:puff(x, y)
  if #self.smoke == 0 then return end
  self.puffs[#self.puffs + 1] = { frames = self.smoke, x = x, y = y, t = 0, fall = SMOKE_FALL }
end

-- Moves s toward its target by `speed` pixels along the main axis.
-- Returns true when it arrives.
local function travel(s)
  local dx, dy = s.tx - s.x, s.ty - s.y
  local major = math.max(math.abs(dx), math.abs(dy))
  if major <= s.speed then s.x, s.y = s.tx, s.ty; return true end
  local f = s.speed / major
  s.x, s.y = s.x + dx * f, s.y + dy * f
  return false
end

-- Damage what shot s touches; returns true if it struck something.
local function strike(self, s, w, enemies, pl, shots, lv, bonus)
  if w.hit ~= "tiles" then
    for _, e in ipairs(enemies.list) do
      if can_hit(w.hit, e.def.ground) and enemies.touches(e, s.x, s.y) then
        enemies:damage(e, w.dmg, pl, shots, bonus)
        if w.grab then pl.shield = math.min(pl.max_shield, pl.shield + 1) end
        self:spark(s.x, s.y, w.hit == "ground")
        return true
      end
    end
  end
  if w.hit == "all" or w.hit == "ground" or w.hit == "tiles" then
    local t = lv:hit_tile(s.x, s.y, w.dmg)
    if t then
      if t.destroyed then pl.money = pl.money + t.bounty; shots:ground_explode(t.x, t.y)
      else self:spark(s.x, s.y, true) end
      return true
    end
  end
  return false
end

-- One game frame: move shots, resolve hits, age smoke and sparks.
function M:step(pl, enemies, shots, lv, bonus)
  for n, c in pairs(self.cool) do if c > 0 then self.cool[n] = c - 1 end end
  local j = 1
  for i = 1, #self.shots do
    local s = self.shots[i]
    local w = LIB[s.n]
    local fr = self.pics[s.n] or {}
    if not s.coasting then
      if w.top and s.speed < w.top then s.speed = s.speed + 1 end
      s.frame = s.frame + 1
      if s.frame >= #fr then s.frame = w.loop_from or 0 end
    end
    local arrived = travel(s)
    if w.smoke then self:puff(s.x, s.y + 8) end
    local done = s.y < -16 or s.y > rap.H or s.x < 0 or s.x > rap.W
    if not done then done = strike(self, s, w, enemies, pl, shots, lv, bonus) end
    if not done and arrived then
      if s.coasting then
        -- Ignite: climb to the top, drifting up to 16 pixels to a side.
        s.coasting = false
        s.tx, s.ty = s.x + math.random(-16, 15), 0
        self:puff(s.x, s.y)
      elseif w.bomb then
        for _, e in ipairs(enemies.list) do
          if e.def.ground and util.overlap(s.x - 12, s.y - 12, 24, 24, e.x, e.y, e.w, e.h) then
            enemies:damage(e, 5, pl, shots, bonus)
          end
        end
        local t = lv:hit_tile(s.x, s.y, w.dmg)
        if t and t.destroyed then pl.money = pl.money + t.bounty end
        shots:ground_explode(s.x, s.y)
        done = true
      else
        done = true
      end
    end
    if not done then self.shots[j] = s; j = j + 1 end
  end
  for i = j, #self.shots do self.shots[i] = nil end

  -- Beams strike on the frame they're fired, then fade.
  local k = 1
  for i = 1, #self.beams do
    local b = self.beams[i]
    local w = LIB[b.n]
    if b.t == 4 then
      if b.column then
        local cx = pl.x + pl.w / 2
        for _, e in ipairs(enemies.list) do
          if not e.dead and can_hit(w.hit, e.def.ground) and e.y < pl.y and e.y > -30 and cx > e.x and cx < e.x + e.w then
            enemies:damage(e, w.dmg, pl, shots, bonus)
          end
        end
      elseif b.target and not b.target.dead then
        enemies:damage(b.target, w.dmg, pl, shots, bonus)
        self:spark(b.target.x + b.target.w / 2, b.target.y + b.target.h / 2)
      end
    end
    b.t = b.t - 1
    if b.t > 0 then self.beams[k] = b; k = k + 1 end
  end
  for i = k, #self.beams do self.beams[i] = nil end

  local m = 1
  for i = 1, #self.puffs do
    local p = self.puffs[i]
    p.t = p.t + 1
    p.y = p.y + p.fall
    if p.t < #p.frames then self.puffs[m] = p; m = m + 1 end
  end
  for i = m, #self.puffs do self.puffs[i] = nil end
end

local function centred(item, x, y)
  local w, h = rap.pic_info(item)
  if w then rap.pic(item, math.floor(x - w / 2), math.floor(y - h / 2)) end
end

function M:draw(pl)
  for _, p in ipairs(self.puffs) do
    if p.frames == self.smoke then centred(p.frames[p.t + 1], p.x, p.y) end
  end
  for _, s in ipairs(self.shots) do
    local fr = self.pics[s.n]
    if fr and #fr > 0 then centred(fr[math.min(s.frame, #fr - 1) + 1], s.x, s.y)
    else rap.rect(math.floor(s.x), math.floor(s.y), 2, 5, util.color(255, 240, 120)) end
  end
  for _, p in ipairs(self.puffs) do
    if p.frames ~= self.smoke then centred(p.frames[p.t + 1], p.x, p.y) end
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
