-- The main menu: the original MAIN_SWD window from the player's data, its
-- buttons and dialogs (options, difficulty, quit), and its music.
local scenes = require("core.scenes")
local util = require("core.util")
local settings = require("core.settings")
local swd = require("ui.swd")
local dialogs = require("ui.dialogs")
local music = require("game.music")

local M = {}

-- arg.resume: a play scene to go back to (RETURN), when called from a game.
function M.enter(arg)
  arg = arg or {}
  rap.palette("PALETTE_DAT")
  util.reset_colors()
  rap.grab_mouse(false)
  rap.fade(1)
  M.resume = arg.resume
  M.win = swd.open("MAIN_SWD")
  M.stack = {}
  M.snd_move = rap.sound("SWEP_FX")
  M.font = rap.find("SYSTEM_FNT")
  if M.win then
    if not M.resume then M.win:hide("RETURN") end
    if rap.platform == "xenon" then M.win:hide("QUIT") end

  end
  music.menu(M.resume ~= nil)
  M.idle = 0
end

-- A demo: the next recording, replayed in its sector and wave.
local function play_demo()
  local d = require("game.demo").next()
  if d then scenes.switch(require("scenes.play"), { sector = d.sector, map = d.wave, difficulty = 2, demo = d }) end
end

local function push(d) if d then M.stack[#M.stack + 1] = d end end

local function activate(name)
  if name == "NEW" then
    scenes.switch(require("scenes.register"))
  elseif name == "LOAD" then
    local d = dialogs.load_pilot(function(p) if p then M.load_with = p end end)
    push(d or dialogs.message("NO PILOTS TO LOAD", 3))
  elseif name == "OPTS" then
    push(dialogs.options())
  elseif name == "ORDER" then
    scenes.push(require("scenes.textscreen"), { window = "ORDER_SWD" })
  elseif name == "CREDITS" then
    scenes.push(require("scenes.textscreen"), { window = "CREDIT_SWD", credits = true, in_game = M.resume ~= nil })
  elseif name == "QUIT" then
    push(dialogs.ask("QUIT RAPTUA?", function(yes) if yes then rap.quit() end end))
  elseif name == "RETURN" and M.resume then
    local p = M.resume
    M.resume = nil
    scenes.pop()          -- back to the paused game underneath
    if p.resumed then p.resumed() end
  end
end

function M.update()
  if M.load_with then local p = M.load_with; M.load_with = nil; scenes.switch(require("scenes.hangar"), { pilot = p }); return end
  -- Raptua extra (not in the original's window): F5 cycles the game speed.
  if rap.pressed("F5") then
    settings.cycle_cadence(1)
    push(dialogs.message(settings.cadence_label(), 2))
  end
  local top = M.stack[#M.stack]
  if top then
    if top:update() then table.remove(M.stack) end
    return
  end
  if rap.pressed("F1") then push(dialogs.help("HELP1_TXT")); return end
  -- D (as the menu's label says), or half a minute untouched: a demo.
  local _, _, _, _, moved = rap.mouse()
  if rap.typed() ~= "" or moved or rap.pressed("Return") or rap.pressed("Up") or rap.pressed("Down") then M.idle = 0 end
  M.idle = M.idle + 1
  if not M.resume and (rap.pressed("D") or M.idle > 30 * 70) then play_demo(); return end
  if not M.win then
    if util.pressed("ok") then scenes.switch(require("scenes.register")) end
    return
  end
  local r = M.win:update()
  if M.win.moved then rap.play(M.snd_move, 0.5) end
  if r == "cancel" then
    if M.resume then activate("RETURN")
    elseif rap.platform ~= "xenon" then activate("QUIT") end
  elseif r then
    rap.play(M.snd_move, 0.7)
    activate(r)
  end
end

function M.draw()
  rap.clear(0)
  if M.win then M.win:draw() end
  for _, d in ipairs(M.stack) do d:draw() end
end

return M
