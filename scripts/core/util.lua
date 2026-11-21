local M = {}

function M.clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end

function M.overlap(ax, ay, aw, ah, bx, by, bw, bh)
  return ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah
end

-- Nearest palette index to an RGB colour (for UI colours that must work
-- with whatever palette is loaded).
local cache = {}
function M.color(r, g, b)
  local key = r * 65536 + g * 256 + b
  if cache[key] then return cache[key] end
  local best, bd = 0, math.huge
  for i = 0, 255 do
    local pr, pg, pb = rap.palette_rgb(i)
    local d = (pr - r) ^ 2 + (pg - g) ^ 2 + (pb - b) ^ 2
    if d < bd then best, bd = i, d end
  end
  cache[key] = best
  return best
end
function M.reset_colors() cache = {} end

-- Animation frames: items sharing one name sit next to each other in the
-- archive, so frame n of NAME is handle(NAME) + n.
function M.frames(name)
  local h = rap.find(name)
  if not h then return {} end
  local out = { h }
  while true do
    local it = rap.item(h + #out)
    if not it or it.name ~= name then break end
    out[#out + 1] = h + #out
  end
  return out
end

-- Shared key bindings: keyboard, game pad.
function M.held(action)
  if action == "left" then return rap.held("Left") or rap.held("pad_dpleft") or rap.held("pad_stick_left") end
  if action == "right" then return rap.held("Right") or rap.held("pad_dpright") or rap.held("pad_stick_right") end
  if action == "up" then return rap.held("Up") or rap.held("pad_dpup") or rap.held("pad_stick_up") end
  if action == "down" then return rap.held("Down") or rap.held("pad_dpdown") or rap.held("pad_stick_down") end
  if action == "fire" then return rap.held("Left Ctrl") or rap.held("Space") or rap.held("mouse_left") or rap.held("pad_a") or rap.held("pad_trigger_right") end
  if action == "special" then return rap.held("Left Alt") or rap.held("mouse_right") or rap.held("pad_b") end
  return false
end

function M.pressed(action)
  if action == "ok" then return rap.pressed("Return") or rap.pressed("Space") or rap.pressed("pad_a") or rap.pressed("pad_start") end
  if action == "back" then return rap.pressed("Escape") or rap.pressed("pad_back") or rap.pressed("pad_b") end
  if action == "up" then return rap.pressed("repeat_Up") or rap.pressed("pad_dpup") end
  if action == "down" then return rap.pressed("repeat_Down") or rap.pressed("pad_dpdown") end
  if action == "special" then return rap.pressed("Left Alt") or rap.pressed("mouse_right") or rap.pressed("pad_b") end
  if action == "bomb" then return rap.pressed("Left Shift") or rap.pressed("mouse_middle") or rap.pressed("pad_y") end
  return false
end

return M
