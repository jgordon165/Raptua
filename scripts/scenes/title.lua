-- Title / main menu. Uses the original menu art where it exists.
local scenes = require("core.scenes")
local util = require("core.util")

local M = {}
local items = { "START MISSION (TANGO SECTOR)", "ASSET EXPLORER", "QUIT" }

function M.enter()
  rap.palette("PALETTE_DAT")
  util.reset_colors()
  rap.grab_mouse(false)
  M.sel, M.t = 1, 0
  M.font = rap.find("GAME_FNT")
  M.bg = rap.find("HANGER_PIC")
  M.logo = rap.find("RAPLOG_PIC")
  M.difficulty = 1
end

function M.update()
  M.t = M.t + 1
  if util.pressed("up") then M.sel = (M.sel - 2) % #items + 1 end
  if util.pressed("down") then M.sel = M.sel % #items + 1 end
  if util.pressed("back") then rap.quit() end
  if util.pressed("ok") then
    if M.sel == 1 then scenes.switch(require("scenes.play"), { map = 1, difficulty = M.difficulty })
    elseif M.sel == 2 then scenes.push(require("scenes.explorer"))
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
  rap.rect(60, 120, 200, 14 * #items + 10, panel)
  for i, s in ipairs(items) do
    local w = rap.text_size(M.font, s)
    local col = i == M.sel and ((M.t // 8) % 2 == 0 and util.color(255, 230, 90) or util.color(255, 150, 40)) or util.color(170, 170, 170)
    rap.text(M.font, s, (rap.W - w) // 2, 126 + (i - 1) * 14, col)
  end
  rap.text(M.font, "RAPTUA " .. rap.version, 4, rap.H - 10, util.color(120, 120, 120))
end

return M
