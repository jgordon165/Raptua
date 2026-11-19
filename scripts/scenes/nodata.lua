-- Shown when FILE0000.GLB / FILE0001.GLB are missing. There are no fonts
-- without the data, so the explanation goes to a native dialog (and stderr).
local M = {}

function M.enter()
  local msg = "Raptua needs the data files from your own copy of Raptor: Call of the Shadows v1.2 "
    .. "(FILE0000.GLB and FILE0001.GLB).\n\nCopy them next to raptua, or start it with --data <folder>.\n\n"
    .. rap.data_error()
  io.stderr:write(msg, "\n")
  if not rap.headless() then rap.message("Raptua: game data not found", msg) end
  for i = 0, 255 do rap.palette_rgb(i, i, i // 2, 0) end
  M.t = 0
end

function M.update()
  M.t = M.t + 1
  if rap.pressed("Escape") or rap.pressed("Return") then rap.quit() end
end

function M.draw()
  rap.clear(0)
  -- A slow amber sweep, so the window is visibly alive.
  local y = (M.t // 2) % (rap.H + 20) - 10
  rap.rect(0, y, rap.W, 2, 200)
end

return M
