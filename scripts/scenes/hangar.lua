-- The hangar: the original HANGAR_SWD picture with its four doors. Fly a
-- mission (the ship computer), the supply room (the store), back to the
-- main menu, or save the pilot. Plays the hangar music.
local scenes = require("core.scenes")
local swd = require("ui.swd")
local dialogs = require("ui.dialogs")
local pilot = require("game.pilot")
local music = require("game.music")

local M = {}

local HINTS = { MISSION = "FLY MISSION", SUPPLIES = "SUPPLY ROOM", MAIN_MENU = "MAIN MENU", QSAVE = "SAVE PILOT" }

function M.enter(arg)
  M.pilot = (arg and arg.pilot) or M.pilot
  rap.palette("PALETTE_DAT")
  rap.grab_mouse(false)
  rap.fade(1)
  M.win = swd.open("HANGAR_SWD")
  M.stack = {}
  M.snd = rap.sound("SWEP_FX")
  if M.win then
    M.win:hide("PIC")          -- (an item this version of the game doesn't have)
    M.win:select("SUPPLIES")   -- the original starts on the supply room
  end
  music.hangar()
end

function M.update()
  local top = M.stack[#M.stack]
  if top then if top:update() then table.remove(M.stack) end; return end
  if rap.pressed("F1") then
    local h = dialogs.help("HANGHLP1_TXT")
    if h then M.stack[#M.stack + 1] = h end
    return
  end
  if not M.win or not M.pilot then scenes.switch(require("scenes.mainmenu")); return end
  local r = M.win:update()
  if M.win.moved then rap.play(M.snd, 0.4) end
  local f = M.win:selected()
  M.win:set_text("TEXT", f and HINTS[f.name] or "")
  if r == "MISSION" then
    scenes.switch(require("scenes.shipcomp"), { pilot = M.pilot })
  elseif r == "SUPPLIES" then
    scenes.push(require("scenes.store"), { pilot = M.pilot })
  elseif r == "QSAVE" then
    local ok = pilot.save(M.pilot)
    M.stack[#M.stack + 1] = dialogs.message(ok and "PILOT SAVED" or "COULDN'T SAVE THE PILOT", 2)
  elseif r == "MAIN_MENU" or r == "cancel" then
    M.stack[#M.stack + 1] = dialogs.ask("LEAVE THE HANGAR? (UNSAVED PROGRESS IS LOST)", function(yes)
      if yes then M.leave_to_menu = true end
    end)
  end
  if M.leave_to_menu then M.leave_to_menu = nil; scenes.switch(require("scenes.mainmenu")) end
end

function M.draw()
  rap.clear(0)
  if M.win then M.win:draw() end
  for _, d in ipairs(M.stack) do d:draw() end
end

return M
