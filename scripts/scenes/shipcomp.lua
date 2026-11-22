-- The ship computer (SHIPCOMP_SWD): pick a sector to fly (each needs its
-- own data file: FILE0001.GLB for sector 1, FILE0002/3 for 2 and 3), or
-- AUTO for the first sector not yet cleared. The three buttons under the
-- screen switch the secret enemies on and off (their lights show which).
-- CLOSE goes back to the hangar.
local scenes = require("core.scenes")
local swd = require("ui.swd")
local dialogs = require("ui.dialogs")
local pilot = require("game.pilot")

local M = {}

local function have_sector(n) return rap.file_count() > n end

function M.enter(arg)
  M.pilot = arg.pilot
  M.win = swd.open("SHIPCOMP_SWD")
  M.stack = {}
  M.secret = { false, false, false }
  M.snd = rap.sound("SWEP_FX")
  if not M.win then return end
  M.win:hide("SECRET")
  for n = 1, 3 do
    local label
    if not have_sector(n) then label = ("SECTOR %d (NOT INSTALLED)"):format(n)
    elseif pilot.sector_done(M.pilot, n) then label = ("SECTOR %d CLEARED"):format(n)
    else label = ("SECTOR %d  WAVE %d"):format(n, M.pilot.wave[n] or 1) end
    M.win:set_text("GAME" .. n, label)
  end
  M.win:set_text("AUTO", "AUTO SELECT")
  M.win:select("AUTO")
end

local function fly(sector)
  if not have_sector(sector) then
    M.stack[#M.stack + 1] = dialogs.message(("SECTOR %d NEEDS FILE000%d.GLB"):format(sector, sector), 3)
    return
  end
  if pilot.sector_done(M.pilot, sector) then
    M.stack[#M.stack + 1] = dialogs.message("SECTOR ALREADY CLEARED", 2)
    return
  end
  M.pilot.sector = sector
  scenes.switch(require("scenes.loadcomp"), { pilot = M.pilot, sector = sector,
    wave = M.pilot.wave[sector] or 1, secret = M.secret })
end

function M.update()
  local top = M.stack[#M.stack]
  if top then if top:update() then table.remove(M.stack) end; return end
  if rap.pressed("F1") then
    local h = dialogs.help("COMPHLP1_TXT")
    if h then M.stack[#M.stack + 1] = h end
    return
  end
  if not M.win then scenes.switch(require("scenes.hangar"), { pilot = M.pilot }); return end
  local r = M.win:update()
  if M.win.moved then rap.play(M.snd, 0.4) end
  local n = r and tonumber(r:match("^GAME(%d)$"))
  if n then fly(n)
  elseif r == "AUTO" then
    for s = 1, 3 do if have_sector(s) and not pilot.sector_done(M.pilot, s) then fly(s); return end end
    M.stack[#M.stack + 1] = dialogs.message("EVERY INSTALLED SECTOR IS CLEARED", 3)
  elseif r and r:match("^B%d$") then
    local b = tonumber(r:sub(2))
    M.secret[b] = not M.secret[b]
    M.win:set_item("LITE" .. b, M.secret[b] and "LIGHTON_PIC" or "LIGHTOFF_PIC")
    rap.play(M.snd, 0.6)
  elseif r == "CLOSE" or r == "cancel" then
    scenes.switch(require("scenes.hangar"), { pilot = M.pilot })
  end
end

function M.draw()
  rap.clear(0)
  if M.win then M.win:draw() end
  for _, d in ipairs(M.stack) do d:draw() end
end

return M
