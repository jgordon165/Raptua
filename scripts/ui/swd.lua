-- The original's windows (*_SWD), drawn from the layouts in the player's
-- own FILE0001.GLB: fills, shadows, bevels, pictures, text, sliders.
--
--   local w = swd.open("OPTS_SWD")
--   w:set_text("DETAIL", "HIGH DETAIL"); w:hide("PIC1"); w.values.VMUSIC = 100
--   w:update() -> "DETAIL" | "cancel" | nil   (the name of an activated button)
--   w:draw()
--
-- Buttons are selected with the arrows / D-pad (nearest in that direction),
-- the mouse, or their position in the list; Enter / Space / A / click
-- activates; Esc / B cancels. Sliders take Left/Right when focused, or a
-- mouse drag. How the selection is highlighted is Raptua's own (the original
-- moved a mouse pointer over the buttons).
local util = require("core.util")

local M = {}
M.__index = M

-- Type 11 is a "view area": an invisible region the program gives meaning
-- to (the hangar's doors, the store's buttons). Raptua draws a slider knob
-- on one only when a value is set for it (the options window's volumes).
local T_TEXT, T_BUTTON, T_INPUT, T_DRAGBAR, T_BUMPIN, T_BUMPOUT, T_ICON, T_AREA = 1, 2, 3, 6, 7, 8, 9, 11
local F_COLOR, F_TEXTURE, F_PICTURE = 0, 1, 2

function M.open(name)
  local def = rap.swd(name)
  if not def then return nil end
  local self = setmetatable({ def = def, name = name, texts = {}, hidden = {}, values = {}, items = {} }, M)
  self.x, self.y = def.x, def.y
  -- Focusable fields: buttons, input boxes, and selectable view areas.
  -- (M:focus_area() adds others, e.g. the options sliders.)
  self.focus = {}
  for i, f in ipairs(def.fields) do
    if f.type == T_BUTTON or f.type == T_INPUT or (f.type == T_AREA and f.selectable ~= 0) then
      self.focus[#self.focus + 1] = i
    end
  end
  self.sel = 1
  for k, i in ipairs(self.focus) do if i - 1 == def.first then self.sel = k end end
  self.t = 0
  return self
end

function M:field(name)
  for _, f in ipairs(self.def.fields) do if f.name == name then return f end end
end

function M:set_text(name, text) self.texts[name] = text end

-- A button of the port's own (not in the window's data), styled like the
-- window's button `like`: added to the fields and the focus order.
function M:add_button(name, label, x, y, w, h, like)
  local f = { type = T_BUTTON, name = name, text = label, x = x, y = y, w = w, h = h, item = "",
              font = "FONT2_FNT", base = 0, fill = 0, color = 0, lite = 0, shadow = 0, selectable = 1, id = -1, hotkey = 0, max = 0 }
  for _, g in ipairs(self.def.fields) do
    if g.name == like then
      for _, k in ipairs({ "font", "base", "fill", "color", "lite", "shadow", "item" }) do f[k] = g[k] end
    end
  end
  self.def.fields[#self.def.fields + 1] = f
  self.focus[#self.focus + 1] = #self.def.fields
end
function M:text(name)
  local f = self:field(name)
  return self.texts[name] or (f and f.text) or ""
end

-- Make a view area focusable (e.g. a slider, or a region with no
-- selectable flag that Raptua still wants a pad to reach).
function M:focus_area(name)
  for i, f in ipairs(self.def.fields) do
    if f.name == name then
      for _, k in ipairs(self.focus) do if k == i then return end end
      self.focus[#self.focus + 1] = i
    end
  end
end

-- Select a field by name.
function M:select(name)
  for k, i in ipairs(self.focus) do if self.def.fields[i].name == name then self.sel = k end end
end
function M:hide(name) self.hidden[name] = true end
function M:show(name) self.hidden[name] = nil end
function M:set_item(name, item) self.items[name] = item end

function M:selected()
  local i = self.focus[self.sel]
  return i and self.def.fields[i]
end

local function usable(self, f) return not self.hidden[f.name] end

-- Move the selection to the nearest usable focus field in direction (dx, dy).
function M:move(dx, dy)
  local cur = self:selected()
  if not cur then return end
  local cx, cy = cur.x + cur.w / 2, cur.y + cur.h / 2
  local best, bd
  for k, i in ipairs(self.focus) do
    local f = self.def.fields[i]
    if k ~= self.sel and usable(self, f) then
      local fx, fy = f.x + f.w / 2 - cx, f.y + f.h / 2 - cy
      local along = fx * dx + fy * dy
      if along > 0 then
        local across = math.abs(fx * dy) + math.abs(fy * dx)
        local d = along + across * 3
        if not bd or d < bd then best, bd = k, d end
      end
    end
  end
  if best then self.sel = best; return true end
  -- Nothing that way: step through the list (wraps), so lists still work.
  local n = #self.focus
  for step = 1, n - 1 do
    local k = (self.sel - 1 + (dx + dy > 0 and step or -step)) % n + 1
    if usable(self, self.def.fields[self.focus[k]]) then self.sel = k; return true end
  end
end

local function inside(f, ox, oy, mx, my)
  return mx >= ox + f.x and mx < ox + f.x + f.w and my >= oy + f.y and my < oy + f.y + f.h
end

-- Handles input; returns the activated button's name, "cancel", or nil.
function M:update()
  self.t = self.t + 1
  if not usable(self, self:selected() or {}) then self:move(0, 1) end
  local mx, my, _, _, moved = rap.mouse()
  if moved or rap.pressed("mouse_left") or rap.held("mouse_left") then
    -- The smallest field under the pointer wins: some windows put input
    -- boxes inside a larger clickable area (REGISTER_SWD's name and callsign
    -- lie on the sign-in clipboard), and taking the last match picked the
    -- area, so clicking a box signed in instead of selecting it.
    local best, best_size
    for k, i in ipairs(self.focus) do
      local f = self.def.fields[i]
      if usable(self, f) and inside(f, self.x, self.y, mx, my) and (not best_size or f.w * f.h < best_size) then
        best, best_size = k, f.w * f.h
      end
    end
    if best then self.sel = best end
  end
  local moved_sel
  if rap.pressed("repeat_Up") or rap.pressed("pad_dpup") then moved_sel = self:move(0, -1) end
  if rap.pressed("repeat_Down") or rap.pressed("pad_dpdown") then moved_sel = self:move(0, 1) end
  local f = self:selected()
  -- Typing into an input box.
  if f and f.type == T_INPUT and usable(self, f) then
    local cur = self:text(f.name)
    local typed = rap.typed():upper():gsub("[^%w %-%.']", "")
    if typed ~= "" then cur = (cur .. typed):sub(1, math.max(1, f.max - 1)) end
    if rap.pressed("repeat_Backspace") then cur = cur:sub(1, -2) end
    if cur ~= self:text(f.name) then self.texts[f.name] = cur; self.changed = f.name end
  end
  if f and f.type == T_AREA and self.values[f.name] ~= nil then
    local v = self.values[f.name] or 0
    if rap.held("Left") or rap.held("pad_dpleft") then v = v - 2 end
    if rap.held("Right") or rap.held("pad_dpright") then v = v + 2 end
    if rap.held("mouse_left") and inside(f, self.x, self.y, mx, my) then v = mx - self.x - f.x end
    v = util.clamp(v, 0, f.w)
    if v ~= self.values[f.name] then self.values[f.name] = v; self.changed = f.name end
  else
    if rap.pressed("repeat_Left") or rap.pressed("pad_dpleft") then moved_sel = self:move(-1, 0) end
    if rap.pressed("repeat_Right") or rap.pressed("pad_dpright") then moved_sel = self:move(1, 0) end
  end
  self.moved = moved_sel
  -- Cancel: Esc, pad B, right click; on the Xbox 360, B arrives as Left Alt.
  if rap.pressed("Escape") or rap.pressed("pad_b") or rap.pressed("mouse_right")
     or (rap.platform == "xenon" and rap.pressed("Left Alt")) then return "cancel" end
  f = self:selected()
  if f and usable(self, f) and (f.type == T_BUTTON or (f.type == T_AREA and self.values[f.name] == nil)) then
    local click = rap.pressed("mouse_left") and inside(f, self.x, self.y, mx, my)
    if click or rap.pressed("Return") or rap.pressed("Space") or rap.pressed("pad_a") or rap.pressed("pad_start") then
      return f.name
    end
  end
  -- Enter in an input box moves on to the next field.
  if f and f.type == T_INPUT and (rap.pressed("Return") or rap.pressed("pad_a")
      or (rap.platform == "xenon" and rap.pressed("Space"))) then
    self.entered = f.name
    self:move(0, 1)
  end
end

-- ---- drawing -------------------------------------------------------------------

local function tile(item, x, y, w, h)
  local tw, th = rap.pic_info(item)
  if not tw then return end
  rap.clip(x, y, w, h)
  for ty = y, y + h - 1, th do
    for tx = x, x + w - 1, tw do rap.pic(item, tx, ty) end
  end
  rap.clip()
end

-- Raised (up) or sunken bevel around a rectangle, by shading what's there.
local function bevel(x, y, w, h, up)
  local lite, dark = up and 1 or -1, up and -1 or 1
  rap.shade(x, y, w, 1, lite)
  rap.shade(x, y + 1, 1, h - 1, lite)
  rap.shade(x + 1, y + h - 1, w - 1, 1, dark)
  rap.shade(x + w - 1, y + 1, 1, h - 2, dark)
end

local function font_of(f)
  return (f.font ~= "" and rap.find(f.font)) or rap.find("SYSTEM_FNT")
end

-- Text in a field: glyph shade + the field's base colour, or (no base
-- colour) the font's own pixels. (The field's colour is its box's colour,
-- not the text's: using it hid the help window's button labels.)
local function draw_text(f, text, x, y, base)
  local font = font_of(f)
  if base and base > 0 then return rap.text(font, text, x, y, base, true) end
  return rap.text(font, text, x, y, -1)
end

-- Text fields that name a _TXT item run that item's layout script: lines are
-- printed down the field (font height + 3 apart); TEXT_POS x y, TEXT_RIGHT
-- dx, TEXT_DOWN dy move the pen (inside the field), TEXT_COLOR c sets the
-- colour, TEXT_IMAGE name x y draws a picture. A 0x1A byte ends it.
local function draw_script(f, ox, oy, item)
  local src = rap.read(item or f.item)
  if not src then return end
  local font = font_of(f)
  local _, fh = rap.text_size(font, "A")
  local x0, y0 = ox + f.x, oy + f.y
  local px, py, color = x0, y0, f.base > 0 and f.base or f.color
  rap.clip(x0, y0, f.w, f.h)
  for line in src:gmatch("([^\r\n]*)\r?\n?") do
    if line:find("\26") then break end
    local cmd, a, b, c = line:match("^%s*(TEXT_%u+)%s*(%S*)%s*(%S*)%s*(%S*)")
    if cmd == "TEXT_POS" then px, py = x0 + (tonumber(a) or 0), y0 + (tonumber(b) or 0)
    elseif cmd == "TEXT_RIGHT" then px = px + (tonumber(a) or 0)
    elseif cmd == "TEXT_DOWN" then py = py + (tonumber(a) or 0)
    elseif cmd == "TEXT_COLOR" then color = tonumber(a) or color
    elseif cmd == "TEXT_IMAGE" then
      local item = a:gsub(",", "")
      rap.pic(item, x0 + (tonumber((b:gsub(",", ""))) or 0), y0 + (tonumber(c) or 0))
    elseif cmd then
      -- unknown command: skip
    else
      if line ~= "" then rap.text(font, line, px, py, color, true) end
      py = py + fh + 3
    end
  end
  rap.clip()
end

function M:draw()
  local d, ox, oy = self.def, self.x, self.y
  if d.shadow ~= 0 and d.fill ~= F_PICTURE then rap.shade(ox + 4, oy + 4, d.w, d.h, -2) end
  if d.fill == F_PICTURE and d.item ~= "" then rap.pic(d.item, ox, oy)
  elseif d.fill == F_TEXTURE and d.item ~= "" then tile(d.item, ox, oy, d.w, d.h)
  elseif d.fill == F_COLOR then rap.rect(ox, oy, d.w, d.h, d.color) end
  if d.fill ~= F_PICTURE then bevel(ox, oy, d.w, d.h, true) end

  local sel = self:selected()
  for _, f in ipairs(d.fields) do
    if not self.hidden[f.name] then
      local x, y = ox + f.x, oy + f.y
      local text = self.texts[f.name] or f.text
      local item = self.items[f.name] or f.item
      if f.type == T_BUMPIN or f.type == T_BUMPOUT then
        bevel(x, y, f.w, f.h, f.type == T_BUMPOUT)
      elseif f.type == T_ICON then
        if item ~= "" then rap.pic(item, x, y) end
      elseif f.type == T_TEXT or f.type == T_DRAGBAR then
        if type(item) == "number" or item:match("_TXT$") then draw_script(f, ox, oy, item)
        elseif text ~= "" then draw_text(f, text, x, y, f.base) end
      elseif f.type == T_BUTTON then
        local down = f == sel and (rap.held("mouse_left") or rap.held("Return"))
        if f.fill == F_PICTURE and item ~= "" then
          rap.pic(item, x, y)
        else
          if f.fill == F_TEXTURE and item ~= "" then tile(item, x, y, f.w, f.h)
          else rap.rect(x, y, f.w, f.h, f.color) end
          bevel(x, y, f.w, f.h, not down)
          if text ~= "" then
            local tw, th = rap.text_size(font_of(f), text)
            draw_text(f, text, x + (f.w - tw) // 2, y + (f.h - th) // 2 + (down and 1 or 0), f.base)
          end
        end
        if f == sel then
          -- Selection: a light frame that pulses.
          local lvl = (self.t // 8) % 2 == 0 and 2 or 1
          rap.shade(x - 1, y - 1, f.w + 2, 1, lvl); rap.shade(x - 1, y + f.h, f.w + 2, 1, lvl)
          rap.shade(x - 1, y, 1, f.h, lvl); rap.shade(x + f.w, y, 1, f.h, lvl)
        end
      elseif f.type == T_AREA then
        local v = self.values[f.name]
        if v ~= nil then
          rap.pic("SLIDE_PIC", x + v - 2, y)
          if f == sel then rap.shade(x, y + f.h, f.w, 1, (self.t // 8) % 2 == 0 and 2 or 1) end
        elseif f == sel and not self.no_area_frame then
          -- A view area under the pointer / pad: a soft frame round it.
          local lvl = (self.t // 8) % 2 == 0 and 1 or 2
          rap.shade(x, y, f.w, 1, lvl); rap.shade(x, y + f.h - 1, f.w, 1, lvl)
          rap.shade(x, y + 1, 1, f.h - 2, lvl); rap.shade(x + f.w - 1, y + 1, 1, f.h - 2, lvl)
        end
      elseif f.type == T_INPUT then
        local text = self:text(f.name)
        local caret = (f == sel and (self.t // 16) % 2 == 0) and "_" or ""
        draw_text(f, text .. caret, x, y, f.base)
      end
    end
  end
end

return M
