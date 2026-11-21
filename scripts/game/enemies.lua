-- Enemies and ground objects spawned from the level's actor list.
--
-- Everything here runs once per game frame (play.lua calls step() at the
-- original's ~23.3 Hz: every third 70 Hz tick), in screen pixels.
--
-- Flight (sprite library f[22]):
--   REPEAT  fly the path, then bounce back and forth between entry `repos`
--           and the last entry for as long as it lives
--   LINEAR  fly the path once, then leave
--   KAMI    fly the path, then dive at where the player is
--   GROUND  sits on the map and scrolls with it
--   GROUNDLEFT/RIGHT  scrolls with the map and drives sideways once on screen
-- Air paths are offsets from (spawn x, screen centre); ground paths unused.
--
-- Firing: once the countdown has run out, a burst of `shootcnt` volleys,
-- `shootspace` frames apart (the first after `shootstart`), from every gun,
-- then a rest of `shootframe` frames, and again.
local util = require("core.util")
local splib = require("game.splib")
local level = require("game.level")

local M = {}
M.__index = M

local SCREEN_MID = 100     -- air paths are measured from the screen's middle line

function M.new(lib_name, difficulty)
  local self = setmetatable({}, M)
  self.difficulty = difficulty or 1
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

-- Moves e toward (tx, ty) by up to `budget` pixels; returns what's left of
-- the budget if it arrived, else 0.
local function travel(e, tx, ty, budget)
  local dx, dy = tx - e.x, ty - e.y
  local dist = math.sqrt(dx * dx + dy * dy)
  if dist <= budget then e.x, e.y = tx, ty; return budget - dist end
  e.x, e.y = e.x + dx / dist * budget, e.y + dy / dist * budget
  return 0
end

-- `sy_screen`: the screen y of the actor's map row (top of the tile).
function M:spawn(actor, sy_screen)
  local def = self.lib[actor.slib]
  if not def then return end
  local frames = self:frames_of(def)
  if #frames == 0 then return end
  local w, h = rap.pic_info(frames[1])
  local e = {
    def = def, frames = frames, w = w, h = h,
    hp = def.hits, t = 0, flash = 0, boss = def.bossflag ~= 0, song = def.song ~= -1,
    x = level.X0 + actor.x * 32 + 16 - w / 2,
    y = sy_screen + 16 - h / 2,
  }
  e.countdown = def.countdown - e.y
  e.shoot_on = false
  e.volleys = def.shootcnt
  -- Bosses on training and rookie: half the hit points, a quarter fewer volleys.
  if e.boss and self.difficulty <= 1 then
    e.hp = e.hp - e.hp // 2
    e.volleys = e.volleys - e.volleys // 4
  end
  e.wait = def.shootstart
  e.resting = 0
  local ft = def.flighttype
  if ft == splib.F_GROUNDRIGHT then e.x = e.x - w
  elseif ft == splib.F_GROUNDLEFT then e.x = e.x + w end
  if not def.ground then
    e.sx, e.sy = e.x, SCREEN_MID - h / 2
    e.path = splib.path_points(def)
    e.leg = 1            -- index of the path entry being flown to
    e.dir = 1
    if #e.path == 0 then e.path = { { 0, rap.H } } end
  end
  self.list[#self.list + 1] = e
end

local function fly(e, player)
  local d = e.def
  local budget = d.movespeed
  for _ = 1, 32 do                     -- a fast ship can pass several points in a frame
    if e.dive then
      -- KAMI end: keep going along the dive line (past the player's old
      -- spot) until off screen. (A choice made here: where the original
      -- leaves a diving ship after it arrives is not settled yet.)
      e.x, e.y = e.x + e.dive[1] * budget, e.y + e.dive[2] * budget
      return
    end
    local p = e.path[e.leg]
    budget = travel(e, e.sx + p[1], e.sy + p[2], budget)
    if budget <= 0 then return end
    -- Arrived: pick the next point.
    if d.flighttype == splib.F_REPEAT then
      local n = #e.path
      if n <= 1 then return end
      e.leg = e.leg + e.dir
      if e.leg > n then e.dir, e.leg = -1, n - 1 end
      if e.leg < d.repos + 1 then e.dir, e.leg = 1, d.repos + 2 end
      e.leg = util.clamp(e.leg, 1, n)
    elseif d.flighttype == splib.F_KAMI then
      if e.leg < #e.path then
        e.leg = e.leg + 1
      else
        local tx, ty = player.x + player.w / 2 - e.w / 2, player.y + player.h / 2 - e.h / 2
        local dx, dy = tx - e.x, ty - e.y
        local len = math.max(1, math.sqrt(dx * dx + dy * dy))
        e.dive = { dx / len, dy / len }
      end
    else   -- LINEAR
      e.leg = e.leg + 1
      if e.leg > #e.path then e.gone = true; return end
    end
  end
end

local function fire(e, player, shots)
  local d = e.def
  if not e.shoot_on or player.dead or d.numguns <= 0 then return end
  if e.resting > 0 then
    e.resting = e.resting - 1
    if e.resting == 0 then e.volleys, e.wait = d.shootcnt, d.shootspace end
    return
  end
  e.wait = e.wait - 1
  if e.wait >= 0 then return end
  e.wait = d.shootspace
  if e.y + e.h < 0 or e.y > rap.H then return end
  for g = 1, math.min(d.numguns, 24) do
    local gx = e.x + (d.shootx[g] or e.w // 2)
    local gy = e.y + (d.shooty[g] or e.h)
    shots:enemy_shot(gx, gy, player.x + player.w / 2, player.y + player.h / 2, d.shoot_type[g] or 0)
  end
  e.volleys = e.volleys - 1
  if e.volleys < 1 then e.resting = math.max(1, d.shootframe) end
end

-- Is an enemy with a song in its record (a boss) alive on screen?
function M:boss_present()
  for _, e in ipairs(self.list) do
    if e.song and not e.dead and e.y + e.h > 0 then return true end
  end
  return false
end

-- One game frame. `scroll` is how far the map moved this frame (0 or 1).
function M:step(scroll, player, shots)
  local j = 1
  for i = 1, #self.list do
    local e = self.list[i]
    local d = e.def
    e.t = e.t + 1
    e.flash = math.max(0, e.flash - 1)
    if e.countdown < 1 then e.shoot_on = true else e.countdown = e.countdown - d.movespeed end

    local ft = d.flighttype
    if ft == splib.F_GROUND then
      e.y = e.y + scroll
    elseif ft == splib.F_GROUNDLEFT or ft == splib.F_GROUNDRIGHT then
      e.y = e.y + scroll
      if e.y >= 0 then e.x = e.x + (ft == splib.F_GROUNDRIGHT and d.movespeed or -d.movespeed) end
    else
      fly(e, player)
    end
    fire(e, player, shots)

    local off = e.y > rap.H + 12 or e.x > rap.W + e.w or e.x + e.w < -e.w
      or (e.dive and e.y + e.h < -40)
    local keep = not e.dead and not e.gone and not off
    if keep then self.list[j] = e; j = j + 1 end
  end
  for i = j, #self.list do self.list[i] = nil end
end

local function kill(e, player, shots, bonus)
  e.dead = true
  player.money = player.money + e.def.bounty
  shots:explode(e.x + e.w / 2, e.y + e.h / 2, not e.def.ground)
  if e.def.bonus >= 0 and bonus then bonus:drop(e.def.bonus, e.x + e.w / 2, e.y + e.h / 2) end
  if os.getenv("RAPTUA_TRACE") then io.stderr:write(("killed %s bonus=%d\n"):format(e.def.name, e.def.bonus)) end
end

-- Damage e; returns true if it died.
function M:damage(e, dmg, player, shots, bonus)
  if e.dead then return false end
  e.hp = e.hp - dmg
  e.flash = 2
  if e.hp <= 0 then kill(e, player, shots, bonus); return true end
  return false
end

-- Does point (x, y) touch e? Ground objects use their box (buildings and
-- crates have gaps), aircraft their pixels.
function M.touches(e, x, y)
  if e.dead or x < e.x or x >= e.x + e.w or y < e.y or y >= e.y + e.h then return false end
  return e.def.ground or rap.pic_hit(e.frames[1], x - e.x, y - e.y)
end

-- Enemy bullets and bodies vs the player. (Player shots are resolved in
-- weapons.lua, which knows what each shot can hit.)
function M:collide_player(player, shots)
  if player.dead then return end
  local px, py, pw, ph = player:box()
  for _, s in ipairs(shots.enemy) do
    if util.overlap(px, py, pw, ph, s.x - 2, s.y - 2, 4, 4) then
      s.dead = true
      player:hurt(s.dmg or 4)
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

-- Megabomb: heavy damage to everything in the air on screen, and clears
-- enemy shots.
function M:megabomb(shots, player, bonus)
  for _, e in ipairs(self.list) do
    if not e.dead and not e.def.ground and e.y + e.h > 0 then self:damage(e, 50, player, shots, bonus) end
  end
  for _, s in ipairs(shots.enemy) do s.dead = true end
end

function M:draw(ground)
  local white = util.color(255, 255, 255)
  for _, e in ipairs(self.list) do
    if e.def.ground == ground and not e.dead then
      local rate = math.max(1, e.def.frame_rate)
      local f = e.frames[(e.t // rate) % math.min(#e.frames, e.def.frames) + 1]
      rap.pic(f, math.floor(e.x), math.floor(e.y), 0, e.flash > 0 and white or -1)
    end
  end
end

return M
