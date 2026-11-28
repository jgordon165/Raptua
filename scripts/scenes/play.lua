-- One mission: scrolling map, player, enemies, HUD.
local scenes = require("core.scenes")
local util = require("core.util")
local smooth = require("game.smooth")
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
  util.take_pad(true)   -- the 360's bound buttons are the controls only (game/controls.lua)
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
  M.p2, M.weapons2 = nil, nil
  -- Co-op (Options > ADVANCED > TWO PLAYERS): a second ship on the same
  -- pilot. It shares the ship's stores (the same items table: weapons,
  -- specials and megabombs) and the pilot's money; each ship has its own
  -- shield and its own guns. Player shots only ever hit enemies, so the
  -- ships can't hurt each other, and they are kept from overlapping.
  -- A pilot flies two ships if its campaign was started for two players
  -- (scenes/register.lua), each in the colour picked then.
  local shipcolors = require("game.shipcolors")
  shipcolors.reset()
  M.player.color, M.player.tag = nil, nil
  local two = settings.coop and not M.demo
  if M.pilot then two = two and M.pilot.players == 2 end
  if two then
    local colors = (M.pilot and M.pilot.colors) or shipcolors.DEFAULT
    local pl, p2 = M.player, Player.new()
    p2.input = util.p2
    p2.items, p2.special, p2.money = pl.items, pl.special, 0
    pl.color, p2.color = colors[1], colors[2]
    pl.tag, p2.tag = shipcolors.swatch(colors[1]), shipcolors.swatch(colors[2])
    pl.x, p2.x = pl.x - 28, pl.x + 28
    p2.autofire = arg.autofire   -- --autoplay: both ships fire and can't die
    M.p2, M.weapons2 = p2, Weapons.new()
    rap.pad_keys_first_only(true)   -- the 360: player two's pad is only player two's
  end
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

function M.leave() rap.grab_mouse(false); rap.fade(1); util.take_pad(false); rap.pad_keys_first_only(false) end

-- The ships in play (one, or two in co-op).
local function ships()
  if M.p2 then return { M.player, M.p2 } end
  return { M.player }
end

-- Every ship is down.
local function lost()
  return M.player.dead and (not M.p2 or M.p2.dead)
end

-- A ship's own controls, read every tick: special-weapon select and megabomb.
local function buttons(pl)
  if pl.dead then return end
  if pl.input.pressed("special") and pl:next_special(Weapons.FIRST_SPECIAL, Weapons.LAST_SPECIAL) then
    rap.play(M.snd_swep, 0.7)
    M.bonus.message, M.bonus.message_t = Weapons.LIB[pl.special].name, 50
  end
  if pl.input.pressed("bomb") and pl:bombs() > 0 then
    pl.items[Weapons.MEGABOMB] = pl:bombs() - 1
    M.enemies:megabomb(M.shots, pl, M.bonus)
    rap.play(M.snd_bomb, 1.0)
  end
end

-- Called by the main menu's RETURN: back to the wave where it was.
function M.resumed()
  rap.palette("PALETTE_DAT")
  require("game.shipcolors").reset()
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
  local p2 = M.p2
  for _, s in ipairs(ships()) do
    s._px, s._py = s.x, s.y     -- for smooth motion: the ships move every tick
    s:update()
  end
  if p2 then Player.separate(pl, p2) end
  -- Edge-triggered controls are read every tick so presses aren't lost.
  for _, s in ipairs(ships()) do buttons(s) end

  M.tick = M.tick + 1
  if M.tick % settings.cadence == 0 then
    -- ---- one game frame -------------------------------------------------
    if settings.smooth then smooth.mark(M.moving()); lv._pcam = lv.cam end
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
    else
      if not pl.dead and not pl.flyoff and (util.held("fire") or pl.autofire) then M.weapons:fire_all(pl, M.enemies) end
      if p2 and not p2.dead and not p2.flyoff and (p2.input.held("fire") or p2.autofire) then M.weapons2:fire_all(p2, M.enemies) end
    end
    M.enemies:step(scroll, pl, M.shots, p2)
    -- The wave is won, as in the original, once the map's last enemy has
    -- appeared and every enemy is gone (the boss included): reaching the top
    -- of the map isn't enough. Then 60 game frames: for the last 40 the
    -- controls are taken away and the ship lines up with the middle and
    -- flies off the top of the screen.
    -- In co-op the wave goes on while either ship flies.
    if not M.wave_over and not lost() and lv:all_spawned() and #M.enemies.list == 0 then M.wave_over = 60 end
    if M.wave_over and not lost() then
      M.wave_over = M.wave_over - 1
      if M.wave_over < 40 then
        for i, s in ipairs(ships()) do
          if not s.dead then
            if not s.flyoff then s.flyoff = true; if i == 1 or pl.dead then rap.play(M.snd_flyby, 1.0) end end
            -- Two ships line up side by side either side of the middle.
            local mid = not p2 and 160 or (i == 1 and 160 - 20 or 160 + 20)
            if p2 and (pl.dead or p2.dead) then mid = 160 end
            local cx = s.x + s.w / 2
            s.x = s.x + (cx < mid - 8 and 8 or cx > mid + 8 and -8 or 0)
            s.y = s.y - 4
          end
        end
      end
    end
    -- A boss on screen (an enemy whose record names a song) keeps the boss
    -- sound going, as the original does.
    if M.enemies:boss_present() and not rap.sound_playing(M.snd_boss) then rap.play(M.snd_boss, 0.8) end
    M.weapons:step(pl, M.enemies, M.shots, lv, M.bonus)
    if p2 then M.weapons2:step(p2, M.enemies, M.shots, lv, M.bonus) end
    M.shots:update(scroll)
    M.bonus:update(scroll, pl, p2)
    for _, s in ipairs(ships()) do M.enemies:collide_player(s, M.shots) end
    if p2 then
      -- One purse: what player two earns goes to the pilot's (player one's) money.
      pl.money, p2.money = pl.money + p2.money, 0
      -- The first special picked up is selected on both ships.
      if not pl.special then pl.special = p2.special end
      if not p2.special then p2.special = pl.special end
    end
    if M.autofire and rap.headless() and math.floor(lv.cam) % 400 == 0 and scroll > 0 then
      rap.screenshot(("autoplay_%05d.bmp"):format(math.floor(lv.cam)))
    end
  end
  -- Low shield: the warning beep, once a second.
  M.warn_t = math.max(0, M.warn_t - 1)
  for _, s in ipairs(ships()) do
    if not s.dead and s.shield > 0 and s.shield <= 25 and M.warn_t == 0 then
      rap.play(M.snd_warn, 0.8)
      M.warn_t = 70
    end
  end
  -- A ship going down explodes (in co-op the other flies on).
  for _, s in ipairs(ships()) do
    if s.dead and not s.boomed then
      s.boomed = true
      if os.getenv("RAPTUA_TRACE") then io.stderr:write(("ship %d down\n"):format(s == M.player and 1 or 2)) end
      rap.play(M.snd_crash, 1.0)
      M.shots:explode(s.x + s.w / 2, s.y + s.h / 2, true)
    end
  end

  if (lost() or (M.wave_over and M.wave_over <= 0)) and not M.end_t then
    M.end_t = 0
    if lost() then music.death() end
    if os.getenv("RAPTUA_TRACE") then
      io.stderr:write(("wave %d %s (%d ship%s)\n"):format(M.map, lost() and "lost" or "won", #ships(), M.p2 and "s" or ""))
    end
  end
  if M.end_t then
    M.end_t = M.end_t + 1
    M.fade = math.max(0, 1 - M.end_t / 140)
    if M.end_t > 160 then
      if lost() then
        -- The death movie, then the main menu (the last save stands).
        local menu = function() scenes.switch(require("scenes.mainmenu")) end
        if M.autofire then menu() else scenes.switch(require("scenes.movie"), { sequence = "death", done = menu }) end
      elseif M.pilot then
        -- Wave flown: the pilot keeps what the ship has, moves on a wave,
        -- and lands at the hangar (the landing movie first; the sector's
        -- end movie too after its last wave), as in the original.
        pilot.collect(M.pilot, pl)
        if p2 and pl.dead then   -- co-op: player two brought the ship home
          M.pilot.shield, M.pilot.super = p2.shield, p2.super
        end
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
          if p2 and pl.dead then pl.shield, pl.super = p2.shield, p2.super end
          pl.boomed = nil
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
  if M.p2 then rap.rect(rap.W - 9, 104, 6, 2, pl.tag) end   -- co-op: player one's colour
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
  local p2 = M.p2
  if p2 then
    -- Player two's shield along the left edge (its colour under it).
    local h2 = math.floor(p2.shield * 0.9)
    rap.rect(3, 12, 6, 92, util.color(30, 30, 30))
    rap.rect(4, 13 + 90 - h2, 4, h2, p2.shield > 25 and util.color(60, 200, 80) or util.color(230, 50, 40))
    rap.rect(3, 106, 6, 2, p2.tag)
    if p2.super > 0 then
      local sh = math.floor(p2.super * 0.9)
      rap.rect(9, 12, 4, 92, util.color(30, 30, 30))
      rap.rect(10, 13 + 90 - sh, 2, sh, util.color(90, 160, 255))
    end
    if p2.special and p2.special ~= pl.special then
      local name = Weapons.LIB[p2.special].name
      local w = rap.text_size(M.font, name)
      rap.text(M.font, name, (rap.W - w) // 2, rap.H - 30, p2.tag)
    end
  end
  M.bonus:draw_message(M.font)
end

-- What moves on game frames (smooth motion places these between frames).
function M.moving()
  local w = M.weapons
  local t = { M.enemies.list, M.shots.player, M.shots.enemy, M.shots.fx, M.bonus.list,
              w.shots or {}, w.puffs or {}, w.smoke or {} }
  local w2 = M.weapons2
  if w2 then
    t[#t + 1] = w2.shots or {}; t[#t + 1] = w2.puffs or {}; t[#t + 1] = w2.smoke or {}
  end
  return t
end

function M.draw()
  if not M.level then return end
  -- Smooth motion: draw everything part-way from the last game frame to
  -- this one (game/smooth.lua); the game state is put back afterwards.
  local lists, cam, sx, sy
  if settings.smooth and not M.pause then
    local a = smooth.fraction(M.tick, settings.cadence, rap.alpha())
    lists = M.moving()
    smooth.place(lists, a)
    cam = M.level.cam
    if M.level._pcam and math.abs(cam - M.level._pcam) <= smooth.JUMP then
      M.level.cam = M.level._pcam + (cam - M.level._pcam) * a
    end
    sx, sy = {}, {}
    for i, pl in ipairs(ships()) do
      sx[i], sy[i] = pl.x, pl.y
      if pl._px and math.abs(pl.x - pl._px) <= smooth.JUMP and math.abs(pl.y - pl._py) <= smooth.JUMP then
        local t = rap.alpha()
        pl.x, pl.y = pl._px + (pl.x - pl._px) * t, pl._py + (pl.y - pl._py) * t
      end
    end
  end
  M.draw_scene()
  if lists then
    smooth.restore(lists)
    M.level.cam = cam
    for i, pl in ipairs(ships()) do pl.x, pl.y = sx[i], sy[i] end
  end
end

function M.draw_scene()
  rap.clear(0)
  M.level:draw()
  rap.clip(Level.X0, 0, 288, rap.H)
  M.enemies:draw(true)
  M.shots:draw_ground_fx()
  M.bonus:draw()
  M.enemies:draw(false)
  M.player:draw()
  M.weapons:draw(M.player)
  if M.p2 then M.p2:draw(); M.weapons2:draw(M.p2) end
  M.shots:draw()
  rap.clip()
  hud()
  local msg = M.end_t and (lost() and (M.p2 and "SHIPS DESTROYED" or "SHIP DESTROYED") or "SECTOR CLEARED")
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
