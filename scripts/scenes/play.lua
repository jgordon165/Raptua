-- One mission: scrolling map, player, enemies, HUD.
local scenes = require("core.scenes")
local util = require("core.util")
local Level = require("game.level")
local Player = require("game.player")
local Shots = require("game.shots")
local Enemies = require("game.enemies")
local Bonus = require("game.bonus")
local Weapons = require("game.weapons")

local settings = require("core.settings")
local music = require("game.music")
local dialogs = require("ui.dialogs")
local pilot = require("game.pilot")

-- The world, enemies, shots and scrolling run on game frames: one every
-- `settings.cadence` vertical blanks (3 = the original's ceiling of
-- 23.3 fps, 4 = 17.5, 5 = 14; see core/settings.lua). Input and drawing
-- run every 70 Hz tick.

local M = {}

function M.enter(arg)
  arg = arg or {}
  M.sector = arg.sector or 1
  M.map = arg.map or 1
  M.difficulty = arg.difficulty or 1   -- 0 training, 1 rookie, 2 veteran, 3 elite
  M.pilot = arg.pilot
  M.demo = arg.demo          -- a game/demo.lua recording to replay
  M.demo_i = 0
  M.secret = arg.secret or {}
  M.player = arg.player or Player.new()
  if M.pilot then pilot.equip(M.pilot, M.player) end
  M.player.shield, M.player.dead = math.max(M.player.shield, 100), false
  local lv, err = Level.new(("MAP%dG%d_MAP"):format(M.map, M.sector), M.secret)
  if not lv then io.stderr:write(err, "\n"); scenes.switch(require("scenes.mainmenu")); return end
  M.level = lv
  M.shots = Shots.new()
  M.enemies = Enemies.new("SPRITE1_ITM", M.difficulty)
  M.bonus = Bonus.new()
  M.weapons = Weapons.new()
  M.tick = 0
  M.font = rap.find("GAME_FNT")
  M.pause = nil
  M.autofire = arg.autofire
  if M.demo then M.player.autofire = true; M.player.demo = true end
  music.wave(M.sector, M.map)
  M.snd_warn = rap.sound("WARN_FX")
  M.snd_crash = rap.sound("CRASH_FX")
  M.snd_bomb = rap.sound("EXPLO2_FX")
  M.snd_swep = rap.sound("SWEP_FX")
  M.snd_boss = rap.sound("BOSS_FX")
  M.snd_flyby = rap.sound("FLYBY_FX")
  M.warn_t = 0
  M.end_t = nil
  M.wave_over = nil   -- game frames left once the wave is won (the original's 60)
  M.fade = 0
  rap.grab_mouse(not rap.headless())
end

function M.leave() rap.grab_mouse(false); rap.fade(1) end

-- Called by the main menu's RETURN: back to the wave where it was.
function M.resumed()
  rap.palette("PALETTE_DAT")
  util.reset_colors()
  rap.grab_mouse(not rap.headless())
  music.wave(M.sector, M.map)
end

function M.update()
  if M.pause then
    if M.pause:update() then M.pause = nil; rap.grab_mouse(not rap.headless()) end
    return
  end
  if M.demo and (rap.pressed("Escape") or rap.pressed("Return") or rap.pressed("Space") or rap.pressed("mouse_left")
      or rap.pressed("pad_a") or rap.pressed("pad_start") or rap.pressed("Left Alt")) then
    scenes.switch(require("scenes.mainmenu"))
    return
  end
  -- Esc (START on a pad / the Xbox 360) opens the main menu over the game,
  -- with RETURN, as in the original.
  if rap.pressed("Escape") or rap.pressed("pad_start") then
    scenes.push(require("scenes.mainmenu"), { resume = M })
    return
  end
  if rap.pressed("P") or rap.pressed("Pause") or rap.pressed("pad_back") then
    M.pause = dialogs.message("PAUSED - PRESS ANY KEY")
    return
  end
  if rap.pressed("F1") then
    rap.grab_mouse(false)
    M.pause = dialogs.help("GAMEHLP1_TXT")
    return
  end
  M.fade = math.min(1, M.fade + 1 / 35)
  local lv, pl = M.level, M.player
  pl.autofire = M.autofire or M.demo ~= nil
  if M.autofire and not M.demo and not pl.autopilot then
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
  if M.tick % settings.cadence == 0 then
    -- ---- one game frame -------------------------------------------------
    local before = lv.cam
    lv:update()                                   -- 1 pixel per frame
    local scroll = before - lv.cam
    for _, a in ipairs(lv:take_spawns(M.difficulty)) do M.enemies:spawn(a, a.y * 32 - lv.cam) end
    if M.demo then
      -- Replay: the recorded ship position, bank and buttons for this frame.
      M.demo_i = M.demo_i + 1
      local r = M.demo.frames[M.demo_i]
      if not r then scenes.switch(require("scenes.mainmenu")); return end
      pl.x, pl.y = r.x, r.y
      pl.bank = r.bank - 3
      if r.special and not M.demo_special then pl:next_special(Weapons.FIRST_SPECIAL, Weapons.LAST_SPECIAL) end
      M.demo_special = r.special
      if r.bomb and not M.demo_bomb and pl:bombs() > 0 then
        pl.items[Weapons.MEGABOMB] = pl:bombs() - 1
        M.enemies:megabomb(M.shots, pl, M.bonus)
      end
      M.demo_bomb = r.bomb
      if r.fire then M.weapons:fire_all(pl, M.enemies) end
    elseif not pl.dead and not pl.flyoff and (util.held("fire") or pl.autofire) then M.weapons:fire_all(pl, M.enemies) end
    M.enemies:step(scroll, pl, M.shots)
    -- The wave is won, as in the original, once the map's last enemy has
    -- appeared and every enemy is gone (the boss included): reaching the top
    -- of the map isn't enough. Then 60 game frames: for the last 40 the
    -- controls are taken away and the ship lines up with the middle and
    -- flies off the top of the screen.
    if not M.wave_over and not pl.dead and lv:all_spawned() and #M.enemies.list == 0 then M.wave_over = 60 end
    if M.wave_over and not pl.dead then
      M.wave_over = M.wave_over - 1
      if M.wave_over < 40 then
        if not pl.flyoff then pl.flyoff = true; rap.play(M.snd_flyby, 1.0) end
        local cx = pl.x + pl.w / 2
        pl.x = pl.x + (cx < 152 and 8 or cx > 168 and -8 or 0)
        pl.y = pl.y - 4
      end
    end
    -- A boss on screen (an enemy whose record names a song) keeps the boss
    -- sound going, as the original does.
    if M.enemies:boss_present() and not rap.sound_playing(M.snd_boss) then rap.play(M.snd_boss, 0.8) end
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

  if (pl.dead or (M.wave_over and M.wave_over <= 0)) and not M.end_t then
    M.end_t = 0
    if pl.dead then
      music.death()
      rap.play(M.snd_crash, 1.0)
      M.shots:explode(pl.x + pl.w / 2, pl.y + pl.h / 2, true)
    end
  end
  if M.end_t then
    M.end_t = M.end_t + 1
    M.fade = math.max(0, 1 - M.end_t / 140)
    if M.end_t > 160 then
      if pl.dead then
        -- The death movie, then the main menu (the last save stands).
        local menu = function() scenes.switch(require("scenes.mainmenu")) end
        if M.autofire then menu() else scenes.switch(require("scenes.movie"), { sequence = "death", done = menu }) end
      elseif M.pilot then
        -- Wave flown: the pilot keeps what the ship has, moves on a wave,
        -- and lands at the hangar (the landing movie first; the sector's
        -- end movie too after its last wave), as in the original.
        pilot.collect(M.pilot, pl)
        pilot.wave_done(M.pilot, M.sector)
        local p, sector = M.pilot, M.sector
        local hangar = function() scenes.switch(require("scenes.hangar"), { pilot = p }) end
        local land = function() scenes.switch(require("scenes.movie"), { sequence = "landing", done = hangar }) end
        if pilot.sector_done(p, sector) then
          scenes.switch(require("scenes.movie"), { sequence = "sector_end", done = land })
        else
          land()
        end
      else
        local nxt = M.map + 1
        if rap.find(("MAP%dG1_MAP"):format(nxt)) then
          scenes.switch(M, { sector = M.sector, map = nxt, difficulty = M.difficulty, player = pl, autofire = M.autofire })
        else
          scenes.switch(require("scenes.mainmenu"))
        end
      end
      return   -- the next scene owns the screen (and its fade) now
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
    rap.text(M.font, name, (rap.W - w) // 2, rap.H - 20, util.color(140, 200, 255))   -- above WAVE / BOMBS
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
  local msg = M.end_t and (M.player.dead and "SHIP DESTROYED" or "SECTOR CLEARED")
  if msg then
    -- One centred line per "\n", so long messages fit the 288-pixel playfield.
    local y = 88
    for line in msg:gmatch("[^\n]+") do
      local w = rap.text_size(M.font, line)
      rap.text(M.font, line, (rap.W - w) // 2, y, util.color(255, 255, 255))
      y = y + 10
    end
  end

  if M.pause then M.pause:draw() end
end

return M
