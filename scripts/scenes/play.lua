-- One mission: scrolling map, player, enemies, HUD.
local scenes = require("core.scenes")
local util = require("core.util")
local Level = require("game.level")
local Player = require("game.player")
local Shots = require("game.shots")
local Enemies = require("game.enemies")
local Bonus = require("game.bonus")
local Weapons = require("game.weapons")

-- The original steps its world once every 3 vertical blanks: 70 / 3 Hz.
-- Input and drawing run every 70 Hz tick; the world, enemies, shots and
-- scrolling run on game frames.
local TICKS_PER_FRAME = 3

local M = {}

function M.enter(arg)
  arg = arg or {}
  M.map = arg.map or 1
  M.difficulty = arg.difficulty or 1
  M.player = arg.player or Player.new()
  M.player.shield, M.player.dead = math.max(M.player.shield, 100), false
  local lv, err = Level.new(("MAP%dG1_MAP"):format(M.map))
  if not lv then io.stderr:write(err, "\n"); scenes.switch(require("scenes.title")); return end
  M.level = lv
  M.shots = Shots.new()
  M.enemies = Enemies.new("SPRITE1_ITM")
  M.bonus = Bonus.new()
  M.weapons = Weapons.new()
  M.tick = 0
  M.font = rap.find("GAME_FNT")
  M.paused = false
  M.autofire = arg.autofire
  -- Eight flight songs for the sector's waves, in order, then round again.
  -- (Which wave gets which song in the original is still to be checked
  -- against RAP.EXE.)
  rap.music(("RAP%d_MUS"):format((M.map - 1) % 8 + 1))
  M.snd_warn = rap.sound("WARN_FX")
  M.snd_crash = rap.sound("CRASH_FX")
  M.snd_bomb = rap.sound("EXPLO2_FX")
  M.snd_swep = rap.sound("SWEP_FX")
  M.warn_t = 0
  M.end_t = nil
  M.fade = 0
  rap.grab_mouse(not rap.headless())
end

function M.leave() rap.grab_mouse(false); rap.fade(1) end

function M.update()
  if rap.pressed("Escape") or rap.pressed("pad_start") then
    if M.paused then scenes.switch(require("scenes.title")); return end
    M.paused = true
  end
  if M.paused then
    if rap.pressed("Return") or rap.pressed("pad_a") or rap.pressed("mouse_left") then M.paused = false end
    return
  end
  M.fade = math.min(1, M.fade + 1 / 35)
  local lv, pl = M.level, M.player
  pl.autofire = M.autofire
  if M.autofire and not pl.autopilot then
    pl.autopilot = function()
      local best, by
      for _, b in ipairs(M.bonus.list) do return b.x + b.w / 2 end   -- pickups first
      for _, e in ipairs(M.enemies.list) do
        if not e.dead and e.y > 0 and e.y < pl.y and (not by or e.y > by) then best, by = e.x + e.w / 2, e.y end
      end
      return best
    end
  end
  pl:update()
  -- Edge-triggered controls are read every tick so presses aren't lost.
  if not pl.dead and util.pressed("special") then
    if pl:next_special(Weapons.FIRST_SPECIAL, Weapons.LAST_SPECIAL) then
      rap.play(M.snd_swep, 0.7)
      M.bonus.message, M.bonus.message_t = Weapons.LIB[pl.special].name, 50
    end
  end
  if not pl.dead and util.pressed("bomb") and pl:bombs() > 0 then
    pl.items[Weapons.MEGABOMB] = pl:bombs() - 1
    M.enemies:megabomb(M.shots, pl, M.bonus)
    rap.play(M.snd_bomb, 1.0)
  end

  M.tick = M.tick + 1
  if M.tick % TICKS_PER_FRAME == 0 then
    -- ---- one game frame -------------------------------------------------
    local before = lv.cam
    lv:update()                                   -- 1 pixel per frame
    local scroll = before - lv.cam
    for _, a in ipairs(lv:take_spawns(M.difficulty)) do M.enemies:spawn(a, a.y * 32 - lv.cam) end
    if not pl.dead and (util.held("fire") or pl.autofire) then M.weapons:fire_all(pl, M.enemies) end
    M.enemies:step(scroll, pl, M.shots)
    M.weapons:step(pl, M.enemies, M.shots, lv, M.bonus)
    M.shots:update(scroll)
    M.bonus:update(scroll, pl)
    M.enemies:collide_player(pl, M.shots)
    if M.autofire and rap.headless() and math.floor(lv.cam) % 400 == 0 and scroll > 0 then
      rap.screenshot(("autoplay_%05d.bmp"):format(math.floor(lv.cam)))
    end
  end
  -- Low shield: the warning beep, once a second.
  M.warn_t = math.max(0, M.warn_t - 1)
  if not pl.dead and pl.shield > 0 and pl.shield <= 25 and M.warn_t == 0 then
    rap.play(M.snd_warn, 0.8)
    M.warn_t = 70
  end

  if (pl.dead or lv:done()) and not M.end_t then
    M.end_t = 0
    if pl.dead then
      rap.play(M.snd_crash, 1.0)
      M.shots:explode(pl.x + pl.w / 2, pl.y + pl.h / 2, true)
    end
  end
  if M.end_t then
    M.end_t = M.end_t + 1
    M.fade = math.max(0, 1 - M.end_t / 140)
    if M.end_t > 160 then
      if pl.dead then
        scenes.switch(require("scenes.title"))
      else
        local nxt = M.map + 1
        if rap.find(("MAP%dG1_MAP"):format(nxt)) then
          scenes.switch(M, { map = nxt, difficulty = M.difficulty, player = pl, autofire = M.autofire })
        else
          scenes.switch(require("scenes.title"))
        end
      end
    end
  end
  rap.fade(M.fade)
end

local function hud()
  local pl = M.player
  -- Shield bar along the right edge, money top-left (as in the original HUD).
  local h = math.floor(pl.shield * 0.9)
  rap.rect(rap.W - 9, 10, 6, 92, util.color(30, 30, 30))
  rap.rect(rap.W - 8, 11 + 90 - h, 4, h, pl.shield > 25 and util.color(60, 200, 80) or util.color(230, 50, 40))
  rap.text(M.font, ("$%d"):format(pl.money), 4, 2, util.color(255, 230, 90))
  rap.text(M.font, ("WAVE %d"):format(M.map), 4, rap.H - 10, util.color(150, 150, 150))
  if pl.super > 0 then
    local sh = math.floor(pl.super * 0.9)
    rap.rect(rap.W - 15, 10, 4, 92, util.color(30, 30, 30))
    rap.rect(rap.W - 14, 11 + 90 - sh, 2, sh, util.color(90, 160, 255))
  end
  if pl:bombs() > 0 then
    rap.text(M.font, ("BOMBS %d"):format(pl:bombs()), rap.W - 60, rap.H - 10, util.color(255, 150, 40))
  end
  if pl.special then
    local name = Weapons.LIB[pl.special].name
    local w = rap.text_size(M.font, name)
    rap.text(M.font, name, (rap.W - w) // 2, rap.H - 10, util.color(140, 200, 255))
  end
  M.bonus:draw_message(M.font)
end

function M.draw()
  if not M.level then return end
  rap.clear(0)
  M.level:draw()
  rap.clip(Level.X0, 0, 288, rap.H)
  M.enemies:draw(true)
  M.shots:draw_ground_fx()
  M.bonus:draw()
  M.enemies:draw(false)
  M.player:draw()
  M.weapons:draw(M.player)
  M.shots:draw()
  rap.clip()
  hud()
  local msg = M.paused and "PAUSED - ENTER TO RESUME, ESC TO QUIT"
    or (M.end_t and (M.player.dead and "SHIP DESTROYED" or "SECTOR CLEARED"))
  if msg then
    local w = rap.text_size(M.font, msg)
    rap.text(M.font, msg, (rap.W - w) // 2, 92, util.color(255, 255, 255))
  end
end

return M
