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
end

local function push(d) if d then M.stack[#M.stack + 1] = d end end

local function start_game(diff)
  scenes.switch(require("scenes.play"), { sector = 1, map = 1, difficulty = diff })
end

local function activate(name)
  if name == "NEW" then
    push(dialogs.difficulty(function(d) if d then M.start_with = d end end))
  elseif name == "LOAD" then
    push(dialogs.message("NO SAVED GAMES YET", 3))   -- pilots and saves come with the hangar
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
  if M.start_with then local d = M.start_with; M.start_with = nil; start_game(d); return end
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
  if not M.win then
    if util.pressed("ok") then start_game(1) end
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
