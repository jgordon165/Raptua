-- One mission: scrolling map, player, enemies, HUD.
local scenes = require("core.scenes")
local util = require("core.util")
local Level = require("game.level")
local Player = require("game.player")
local Shots = require("game.shots")
local Enemies = require("game.enemies")

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
  M.font = rap.find("GAME_FNT")
  M.paused = false
  M.autofire = arg.autofire
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
  local before = lv.cam
  lv:update()
  for _, a in ipairs(lv:take_spawns(M.difficulty)) do M.enemies:spawn(a, lv) end
  pl.autofire = M.autofire
  pl:update(M.shots)
  if M.autofire and rap.headless() and lv.cam % 400 < lv.speed then
    rap.screenshot(("autoplay_%05d.bmp"):format(math.floor(lv.cam)))
  end
  M.enemies:update(lv, pl, M.shots)
  M.shots:update(before - lv.cam)
  M.enemies:collide(pl, M.shots)

  if (pl.dead or lv:done()) and not M.end_t then M.end_t = 0 end
  if M.end_t then
    M.end_t = M.end_t + 1
    M.fade = math.max(0, 1 - M.end_t / 140)
    if M.end_t > 160 then
      if pl.dead then
        scenes.switch(require("scenes.title"))
      else
        local nxt = M.map + 1
        if rap.find(("MAP%dG1_MAP"):format(nxt)) then
          scenes.switch(M, { map = nxt, difficulty = M.difficulty, player = pl })
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
end

function M.draw()
  if not M.level then return end
  rap.clear(0)
  M.level:draw()
  rap.clip(Level.X0, 0, 288, rap.H)
  M.enemies:draw(true)
  M.shots:draw_ground_fx()
  M.enemies:draw(false)
  M.player:draw()
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
