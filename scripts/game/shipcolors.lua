-- Co-op ship colours (the port's own): picked for each player when a
-- two-player campaign starts (scenes/register.lua), kept on the pilot as
-- `colors = { player one's, player two's }`.
--
-- The ship picture is left as it is; drawing it through a colour table
-- turns its red paint (the palette's saturated reds) to the chosen hue at
-- the same brightness, matched to the nearest palette colours. RED is the
-- original paint, drawn untouched.
local M = {}

M.LIST = {
  { name = "RED" },                 -- the original
  { name = "BLUE", hue = 215 },
  { name = "GREEN", hue = 120 },
  { name = "GOLD", hue = 45 },
  { name = "PURPLE", hue = 280 },
  { name = "CYAN", hue = 185 },
  { name = "SILVER", grey = true },
}
M.DEFAULT = { 1, 2 }   -- red and blue

local function hsv(r, g, b)
  r, g, b = r / 255, g / 255, b / 255
  local mx, mn = math.max(r, g, b), math.min(r, g, b)
  local d = mx - mn
  local h = 0
  if d > 0 then
    if mx == r then h = 60 * (((g - b) / d) % 6)
    elseif mx == g then h = 60 * ((b - r) / d + 2)
    else h = 60 * ((r - g) / d + 4) end
  end
  return h, mx > 0 and d / mx or 0, mx
end

local function rgb(h, s, v)
  local c = v * s
  local x = c * (1 - math.abs((h / 60) % 2 - 1))
  local m = v - c
  local r, g, b
  if h < 60 then r, g, b = c, x, 0 elseif h < 120 then r, g, b = x, c, 0
  elseif h < 180 then r, g, b = 0, c, x elseif h < 240 then r, g, b = 0, x, c
  elseif h < 300 then r, g, b = x, 0, c else r, g, b = c, 0, x end
  return math.floor((r + m) * 255 + 0.5), math.floor((g + m) * 255 + 0.5), math.floor((b + m) * 255 + 0.5)
end
M.hsv, M.rgb = hsv, rgb

local function nearest(pal, r, g, b)
  local best, bd = 0, math.huge
  for i = 0, 255 do
    local p = pal[i]
    local d = (p[1] - r) ^ 2 + (p[2] - g) ^ 2 + (p[3] - b) ^ 2
    if d < bd then best, bd = i, d end
  end
  return best
end

-- Is this palette colour part of the ship's red paint?
local function red(h, s, v) return (h >= 340 or h <= 20) and s >= 0.35 and v >= 0.12 end
M.is_red = red

local cache = {}
-- Forget the tables (after a palette change).
function M.reset() cache = {} end

-- The colour table for LIST[n] in the current palette (a 256-byte string
-- for rap.pic), or nil for the original paint.
function M.lut(n)
  local c = M.LIST[n]
  if not c or (not c.hue and not c.grey) then return nil end
  if cache[n] then return cache[n] end
  local pal = {}
  for i = 0, 255 do pal[i] = { rap.palette_rgb(i) } end
  local out = {}
  for i = 0, 255 do
    local p = pal[i]
    local h, s, v = hsv(p[1], p[2], p[3])
    local j = i
    if red(h, s, v) then
      if c.grey then j = nearest(pal, rgb(0, 0, math.min(1, v * 1.1)))
      else j = nearest(pal, rgb(c.hue, s, v)) end
    end
    out[#out + 1] = string.char(j)
  end
  cache[n] = table.concat(out)
  return cache[n]
end

-- A swatch colour for LIST[n] (a palette index), for menus and the HUD.
function M.swatch(n)
  local util = require("core.util")
  local c = M.LIST[n] or M.LIST[1]
  if c.grey then return util.color(200, 200, 210) end
  return util.color(rgb(c.hue or 0, 0.85, 0.95))
end

-- Step a player's colour, skipping the other player's.
function M.step(n, dir, other)
  local k = #M.LIST
  repeat n = (n - 1 + dir) % k + 1 until n ~= other
  return n
end

return M
