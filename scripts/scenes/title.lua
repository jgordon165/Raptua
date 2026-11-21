-- Title / main menu. Uses the original menu art where it exists.
local scenes = require("core.scenes")
local util = require("core.util")
local settings = require("core.settings")

local M = {}
-- Labels are functions so the volume rows show their current value.
local items = {
  { label = function() return "START MISSION (TANGO SECTOR)" end, ok = "start" },
  { label = function() return ("MUSIC VOLUME  %d"):format(settings.music) end, adjust = "music" },
  { label = function() return ("SOUND VOLUME  %d"):format(settings.sound) end, adjust = "sound" },
  { label = function() return "ASSET EXPLORER" end, ok = "explorer" },
  { label = function() return "QUIT" end, ok = "quit" },
}

function M.enter()
  rap.palette("PALETTE_DAT")
  util.reset_colors()
  rap.grab_mouse(false)
  M.sel, M.t = 1, 0
  M.font = rap.find("GAME_FNT")
  M.bg = rap.find("HANGER_PIC")
  M.logo = rap.find("RAPLOG_PIC")
  M.difficulty = 1
  M.snd_move = rap.sound("SWEP_FX")
  rap.music("MAINMENU_MUS")
end

function M.update()
  M.t = M.t + 1
  local moved = false
  if util.pressed("up") then M.sel = (M.sel - 2) % #items + 1; moved = true end
  if util.pressed("down") then M.sel = M.sel % #items + 1; moved = true end
  local it = items[M.sel]
  if it.adjust then
    local d = (rap.pressed("repeat_Left") or rap.pressed("pad_dpleft")) and -1
      or (rap.pressed("repeat_Right") or rap.pressed("pad_dpright") or util.pressed("ok")) and 1 or 0
    if util.pressed("ok") and settings[it.adjust] == 10 then d = -10 end   -- Enter wraps 10 -> 0
    if d ~= 0 then settings.step(it.adjust, d); moved = true end
  end
  if moved then rap.play(M.snd_move, 0.5) end
  if util.pressed("back") then rap.quit() end
  if util.pressed("ok") and it.ok then
    if it.ok == "start" then scenes.switch(require("scenes.play"), { map = 1, difficulty = M.difficulty })
    elseif it.ok == "explorer" then scenes.push(require("scenes.explorer"))
    else rap.quit() end
  end
end

function M.draw()
  rap.clear(0)
  if M.bg then rap.pic(M.bg, 0, 0) end
  if M.logo then
    local w = rap.pic_info(M.logo)
    rap.pic(M.logo, (rap.W - w) // 2, 8)
  end
  local panel = util.color(0, 0, 0)
  rap.rect(60, 104, 200, 14 * #items + 10, panel)
  for i, item in ipairs(items) do
    local s = item.label()
    local w = rap.text_size(M.font, s)
    local col = i == M.sel and ((M.t // 8) % 2 == 0 and util.color(255, 230, 90) or util.color(255, 150, 40)) or util.color(170, 170, 170)
    rap.text(M.font, s, (rap.W - w) // 2, 110 + (i - 1) * 14, col)
  end
  rap.text(M.font, "RAPTUA " .. rap.version, 4, rap.H - 10, util.color(120, 120, 120))
end

return M
