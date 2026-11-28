-- New pilot: the original REGISTER_SWD window. Type a name and a callsign,
-- click the photo to change it, then sign in (the registration desk) to
-- pick a difficulty and go to the hangar. The exit strip goes back.
-- With co-op on (Options > ADVANCED > TWO PLAYERS), after the difficulty:
-- one player or two, and for two, each player's ship colour; the pilot
-- keeps both (`players`, `colors`).
local scenes = require("core.scenes")
local swd = require("ui.swd")
local dialogs = require("ui.dialogs")
local pilot = require("game.pilot")
local music = require("game.music")
local osk = require("ui.osk")
local util = require("core.util")

local M = {}

local HINTS = { NAME = osk.active() and "A: TYPE YOUR NAME" or "TYPE YOUR NAME",
                CALLSIGN = osk.active() and "A: TYPE YOUR CALLSIGN" or "TYPE YOUR CALLSIGN", VIEWID = "CHANGE PHOTO",
                VIEWREG = "SIGN IN", VIEWEXIT = "BACK TO MAIN MENU" }

function M.enter()
  rap.palette("PALETTE_DAT")
  M.win = swd.open("REGISTER_SWD")
  M.photo = 1
  M.stack = {}
  M.next = nil
  M.snd = rap.sound("SWEP_FX")
  if M.win then
    M.win:focus_area("VIEWID"); M.win:focus_area("VIEWREG"); M.win:focus_area("VIEWEXIT")
    M.win:set_item("IDPIC", pilot.ID_PHOTOS[M.photo])
    M.win:select("NAME")
    -- No keyboard on the Xbox 360: start with a name and callsign filled in.
    if rap.platform == "xenon" then
      M.win:set_text("NAME", "PILOT")
      M.win:set_text("CALLSIGN", ("RAPTOR %d"):format(#pilot.list() + 1))
    end
  end
  music.menu(false)
end

local function sign_in()
  local name, call = M.win:text("NAME"), M.win:text("CALLSIGN")
  if name == "" or call == "" then
    M.stack[#M.stack + 1] = dialogs.message("ENTER A NAME AND A CALLSIGN", 3)
    -- Back in the window, the box still to fill is selected, ready to type.
    M.win:select(name == "" and "NAME" or "CALLSIGN")
    return
  end
  local function create(d, players, colors)
    local p = pilot.new(name, call, M.photo, d)
    p.players, p.colors = players, colors
    pilot.save(p)
    M.go = p
  end
  M.stack[#M.stack + 1] = dialogs.difficulty(function(d)
    if d == nil then return end
    if not require("core.settings").coop then create(d); return end
    -- Each window opens once the one before has closed (the stack's top).
    M.next = dialogs.players(function(n)
      if n == nil then return end   -- back: the registration window again
      if n == 1 then create(d, 1); return end
      M.next = dialogs.ship_colors(function(c)
        if c then create(d, 2, c) end
      end)
    end)
  end)
end

function M.update()
  if M.go then local p = M.go; M.go = nil; scenes.switch(require("scenes.hangar"), { pilot = p }); return end
  local top = M.stack[#M.stack]
  if top then
    if top:update() then
      table.remove(M.stack)
      if M.next then M.stack[#M.stack + 1] = M.next; M.next = nil end
    end
    return
  end
  if not M.win then scenes.switch(require("scenes.mainmenu")); return end
  -- A controller: A on the name or callsign box opens the on-screen keyboard.
  local f0 = M.win:selected()
  if osk.active() and f0 and (f0.name == "NAME" or f0.name == "CALLSIGN") and util.pressed("ok") then
    M.stack[#M.stack + 1] = osk.new(M.win, f0.name, f0.max > 0 and f0.max or 12)
    return
  end
  local r = M.win:update()
  local f = M.win:selected()
  M.win:set_text("TEXT", f and HINTS[f.name] or "")
  if r == "VIEWID" then
    M.photo = M.photo % #pilot.ID_PHOTOS + 1
    M.win:set_item("IDPIC", pilot.ID_PHOTOS[M.photo])
    rap.play(M.snd, 0.6)
  elseif r == "VIEWREG" or M.win.entered == "CALLSIGN" then
    M.win.entered = nil
    sign_in()
  elseif r == "VIEWEXIT" or r == "cancel" then
    scenes.switch(require("scenes.mainmenu"))
  end
  M.win.entered = nil
end

function M.draw()
  rap.clear(0)
  if M.win then M.win:draw() end
  for _, d in ipairs(M.stack) do d:draw() end
end

return M
