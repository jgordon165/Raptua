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

-- Shared bindings: the keyboard's from Options > KEYBOARD (game/controls.lua),
-- the mouse's and a PC game controller's fixed; on the Xbox 360 the
-- controller's fire, special and megabomb from Options > CONTROLLER (its
-- stick and D-pad arrive as the arrow keys).
local controls = require("game.controls")
local settings = require("core.settings")
local XENON = rap.platform == "xenon"

local function key(action) return controls.of(settings, "keys")[action] end
local function button(action) return controls.of(settings, "pad")[action] end

function M.held(action)
  if action == "left" then return rap.held(key("left")) or rap.held("pad_dpleft") or rap.held("pad_stick_left") end
  if action == "right" then return rap.held(key("right")) or rap.held("pad_dpright") or rap.held("pad_stick_right") end
  if action == "up" then return rap.held(key("up")) or rap.held("pad_dpup") or rap.held("pad_stick_up") end
  if action == "down" then return rap.held(key("down")) or rap.held("pad_dpdown") or rap.held("pad_stick_down") end
  if XENON and (action == "fire" or action == "special") then return rap.pad_held(button(action)) end
  if action == "fire" then return rap.held(key("fire")) or rap.held("mouse_left") or rap.held("pad_a") or rap.held("pad_trigger_right") end
  if action == "special" then return rap.held(key("special")) or rap.held("mouse_right") or rap.held("pad_b") end
  return false
end

function M.pressed(action)
  if action == "ok" then return rap.pressed("Return") or rap.pressed("Space") or rap.pressed("pad_a") or rap.pressed("pad_start") end
  if action == "back" then return rap.pressed("Escape") or rap.pressed("pad_back") or rap.pressed("pad_b") end
  if action == "up" then return rap.pressed("repeat_Up") or rap.pressed("pad_dpup") end
  if action == "down" then return rap.pressed("repeat_Down") or rap.pressed("pad_dpdown") end
  if XENON and (action == "special" or action == "bomb") then return rap.pad_pressed(button(action)) end
  if action == "special" then return rap.pressed(key("special")) or rap.pressed("mouse_right") or rap.pressed("pad_b") end
  if action == "bomb" then return rap.pressed(key("bomb")) or rap.pressed("mouse_middle") or rap.pressed("pad_y") end
  return false
end

-- Co-op's second player (Options > ADVANCED > TWO PLAYERS): the second
-- controller, with the same button mapping as player one's. On the Xbox 360
-- its own pad's buttons (port 2); elsewhere SDL's second game controller
-- ("pad2_...", with the first controller's fixed buttons).
local P2_SDL = {
  left = { "pad2_dpleft", "pad2_stick_left" }, right = { "pad2_dpright", "pad2_stick_right" },
  up = { "pad2_dpup", "pad2_stick_up" }, down = { "pad2_dpdown", "pad2_stick_down" },
  fire = { "pad2_a", "pad2_trigger_right" }, special = { "pad2_b" }, bomb = { "pad2_y" },
}
local P2_DIR = { left = "LEFT", right = "RIGHT", up = "UP", down = "DOWN" }

M.p2 = {}
function M.p2.held(action)
  if XENON then
    if P2_DIR[action] then return rap.pad_held(P2_DIR[action], 2) end
    return rap.pad_held(button(action), 2)
  end
  for _, n in ipairs(P2_SDL[action] or {}) do if rap.held(n) then return true end end
  return false
end
function M.p2.pressed(action)
  if XENON then
    if P2_DIR[action] then return rap.pad_pressed(P2_DIR[action], 2) end
    return rap.pad_pressed(button(action), 2)
  end
  for _, n in ipairs(P2_SDL[action] or {}) do if rap.pressed(n) then return true end end
  return false
end

-- Player one's input, as an object like M.p2 (game/player.lua takes either).
M.p1 = { held = function(a) return M.held(a) end, pressed = function(a) return M.pressed(a) end }

-- In a mission (scenes/play.lua): the 360's bound buttons stop also being
-- the keys they stand for in menus. take(false) gives them back.
function M.take_pad(on)
  if XENON then rap.pad_take(on and controls.used(controls.of(settings, "pad")) or {}) end
end

return M
