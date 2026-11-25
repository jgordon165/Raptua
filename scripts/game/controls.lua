-- The player's controls: which key (Options > KEYBOARD on a PC) or which
-- controller button (Options > CONTROLLER on the Xbox 360) does what, kept
-- in settings (settings.keys, settings.pad). As in Meguarace's controller
-- setup. Pure Lua; tested in the self-test.
--
-- Keyboard: the four directions, fire, next special weapon and megabomb.
-- The mouse (left fire, right special, middle megabomb) and a PC game
-- controller keep their fixed buttons. Escape (the menu), P (pause), F1 and
-- the other function keys can't be bound.
--
-- Controller (the Xbox 360): fire, special and megabomb on any of A, B, X,
-- Y, LB, RB, LT, RT and the sticks pressed in (LS, RS). The left stick and
-- D-pad fly, START is the menu and BACK is OK, so those can't be bound.
-- In a mission the bound buttons are the controls only (rap.pad_take), not
-- also the keys they stand for in menus.
local M = {}

M.KEY_ACTIONS = { "up", "down", "left", "right", "fire", "special", "bomb" }
M.PAD_ACTIONS = { "fire", "special", "bomb" }
M.LABELS = { up = "UP", down = "DOWN", left = "LEFT", right = "RIGHT",
             fire = "FIRE", special = "NEXT SPECIAL", bomb = "MEGABOMB" }
M.KEY_DEFAULT = { up = "Up", down = "Down", left = "Left", right = "Right",
                  fire = "Left Ctrl", special = "Left Alt", bomb = "Left Shift" }
M.PAD_DEFAULT = { fire = "A", special = "B", bomb = "Y" }
M.PAD_BUTTONS = { "A", "B", "X", "Y", "LB", "RB", "LT", "RT", "LS", "RS" }

local RESERVED_KEYS = { Escape = true, P = true, Return = true }
local PAD_OK = {}
for _, b in ipairs(M.PAD_BUTTONS) do PAD_OK[b] = true end

-- Which setup this machine has: "pad" (the Xbox 360) or "keys".
function M.kind() return rap.platform == "xenon" and "pad" or "keys" end

function M.accepts_key(k)
  return type(k) == "string" and k ~= "" and not RESERVED_KEYS[k] and not k:match("^F%d+$")
end

function M.accepts_button(b) return type(b) == "string" and PAD_OK[b] == true end

-- The bindings of a kind, filled in where missing or not allowed.
function M.of(settings, kind)
  local field, default, ok = "keys", M.KEY_DEFAULT, M.accepts_key
  if kind == "pad" then field, default, ok = "pad", M.PAD_DEFAULT, M.accepts_button end
  if type(settings[field]) ~= "table" then settings[field] = {} end
  local t = settings[field]
  for a, v in pairs(default) do if not ok(t[a]) then t[a] = v end end
  return t
end

-- The actions a setup asks for, in order.
function M.actions(kind) return kind == "pad" and M.PAD_ACTIONS or M.KEY_ACTIONS end

-- The buttons the bindings use (for rap.pad_take), once each.
function M.used(binds)
  local out, seen = {}, {}
  for _, a in ipairs(M.PAD_ACTIONS) do
    local b = binds[a]
    if b and not seen[b] then seen[b] = true; out[#out + 1] = b end
  end
  return out
end

-- A key or button as shown on the setup screen.
function M.display(v)
  if not v then return "..." end
  return v:upper()
end

return M
