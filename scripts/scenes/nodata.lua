-- Shown when FILE0000.GLB / FILE0001.GLB are missing. There are no game
-- fonts without the data, so the explanation is drawn in the built-in 5x8
-- font (and goes to a native dialog where there is one, and stderr). On the
-- Xbox 360 the screen is the only place it can be read.
local M = {}

function M.enter()
  local msg = "Raptua needs the data files from your own copy of Raptor: Call of the Shadows v1.2 "
    .. "(FILE0000.GLB and FILE0001.GLB).\n\n"
    .. (rap.platform == "xenon" and "Copy them into the data folder inside the raptua folder on your USB stick.\n\n"
        or "Copy them next to raptua, or start it with --data <folder>.\n\n")
    .. rap.data_error()
  io.stderr:write(msg, "\n")
  if not rap.headless() then rap.message("Raptua: game data not found", msg) end
  for i = 0, 255 do rap.palette_rgb(i, i, i // 2, 0) end
  M.t = 0
  -- Word-wrapped to the screen (50 characters of the 5x8 font a line).
  M.lines = {}
  for para in (msg .. "\n"):gmatch("(.-)\n") do
    local line = ""
    for word in para:gmatch("%S+") do
      if #line + #word + 1 > 50 and line ~= "" then M.lines[#M.lines + 1] = line; line = word
      else line = line == "" and word or line .. " " .. word end
    end
    M.lines[#M.lines + 1] = line
  end
end

function M.update()
  M.t = M.t + 1
  if rap.pressed("Escape") or rap.pressed("Return") then rap.quit() end
end

function M.draw()
  rap.clear(0)
  -- A slow amber sweep, so the window is visibly alive.
  local y = (M.t // 2) % (rap.H + 20) - 10
  rap.rect(0, y, rap.W, 2, 60)
  for i, line in ipairs(M.lines) do rap.sys_text(line, 10, 10 + (i - 1) * 10, 255) end
end

return M
