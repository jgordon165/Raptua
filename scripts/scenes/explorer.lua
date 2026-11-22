-- Asset explorer (F9): walk every item in the GLB archives and preview it.
-- Up/Down: item, PgUp/PgDn: 20 items, Left/Right: archive, P: cycle
-- palette, Esc: back.
local scenes = require("core.scenes")
local util = require("core.util")

local M = {}
local PALETTES = { "PALETTE_DAT", "POGPAL_DAT", "CYGPAL_DAT", "TAIPAL_DAT" }

function M.enter()
  M.file = M.file or 1
  M.index = M.index or 0
  M.pal = M.pal or 1
  M.font = rap.find("SYSTEM_FNT") or rap.find("GAME_FNT")
  rap.palette(PALETTES[M.pal])
  util.reset_colors()
end

function M.leave()
  rap.palette("PALETTE_DAT")
  util.reset_colors()
end

local function kind(name)
  local ext = name:match("_(%u+)$") or ""
  if name == "" then return "data" end
  return ext
end

function M.update()
  local n = rap.item_count(M.file)
  if util.pressed("back") or rap.pressed("F9") then scenes.pop(); return end
  if util.pressed("down") then M.index = (M.index + 1) % n end
  if util.pressed("up") then M.index = (M.index - 1) % n end
  if rap.pressed("repeat_Page Down") then M.index = math.min(n - 1, M.index + 20) end
  if rap.pressed("repeat_Page Up") then M.index = math.max(0, M.index - 20) end
  if rap.pressed("Left") or rap.pressed("Right") then
    M.file = (M.file + (rap.pressed("Left") and -1 or 1)) % rap.file_count()
    M.index = 0
  end
  if rap.pressed("P") then
    M.pal = M.pal % #PALETTES + 1
    rap.palette(PALETTES[M.pal])
    util.reset_colors()
  end
end

function M.draw()
  rap.clear(0)
  local h = (M.file << 16) | M.index
  local it = rap.item(h) or { name = "?", length = 0, flags = 0 }
  local w, ph, spr = rap.pic_info(h)
  if w and (it.name:match("_PIC$") or it.name:match("_BLK$") or it.name == "" ) then
    rap.pic(h, math.max(0, (rap.W - w) // 2), math.max(12, (rap.H - ph) // 2))
  end
  local white, grey = util.color(255, 255, 255), util.color(140, 140, 140)
  rap.rect(0, 0, rap.W, 11, util.color(0, 0, 60))
  rap.text(M.font, ("FILE%04d %d/%d  %s"):format(M.file, M.index, rap.item_count(M.file) - 1,
           it.name ~= "" and it.name or "(unnamed)"), 2, 2, white)
  local info = ("%s  %d bytes%s"):format(kind(it.name), it.length, it.flags & 1 == 1 and "  encrypted" or "")
  if w then info = info .. ("  %dx%d%s"):format(w, ph, spr and " sprite" or "") end
  rap.rect(0, rap.H - 11, rap.W, 11, util.color(0, 0, 60))
  rap.text(M.font, info .. "   [" .. PALETTES[M.pal] .. "]", 2, rap.H - 9, grey)
end

return M
