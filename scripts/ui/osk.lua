-- An on-screen keyboard, for typing a name with a controller (the Xbox 360
-- and the Wii U have no keyboard): the pilot's name and callsign. As in
-- Meguarace's on-screen keyboard.
--
--   D-pad / stick   move between the keys
--   A               type the key (SPACE, DEL and DONE do what they say)
--   B               rub out a letter; with nothing typed, leave unchanged
--   X               a space
--   START           done
--
-- The keys are in rows of ten, then SPACE, DEL and DONE. M.new returns a
-- dialog (update, draw) that edits one text field of a window; the field
-- shows the name as it's typed. Pure Lua apart from draw and the buttons.

local M = {}

M.COLS = 10
M.LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-. "

-- Whether this machine types with a controller.
function M.active() return rap.platform == "xenon" or rap.platform == "wiiu" end

-- A button went down this tick: the 360's own buttons (rap.pad_pressed),
-- else an SDL game controller's (the Wii U).
local SDL_NAME = { UP = { "pad_dpup", "pad_stick_up" }, DOWN = { "pad_dpdown", "pad_stick_down" },
                   LEFT = { "pad_dpleft", "pad_stick_left" }, RIGHT = { "pad_dpright", "pad_stick_right" },
                   A = { "pad_a" }, B = { "pad_b" }, X = { "pad_x" }, START = { "pad_start" } }
local function button(b)
  if rap.platform == "xenon" then return rap.pad_pressed(b) end
  for _, n in ipairs(SDL_NAME[b] or {}) do if rap.pressed(n) then return true end end
  return false
end

-- The keys for `chars`: rows of up to COLS characters, then the special row.
function M.layout(chars)
  local rows, row, space = {}, {}, false
  for i = 1, #chars do
    local c = chars:sub(i, i)
    if c == " " then space = true
    else
      row[#row + 1] = c
      if #row == M.COLS then rows[#rows + 1] = row; row = {} end
    end
  end
  if #row > 0 then rows[#rows + 1] = row end
  local special = {}
  if space then special[#special + 1] = "SPACE" end
  special[#special + 1] = "DEL"
  special[#special + 1] = "DONE"
  rows[#rows + 1] = special
  return rows
end

-- Moves the cursor (dr, dc of -1, 0, 1), wrapping; between rows of
-- different lengths it keeps its place across the width.
function M.move(k, dr, dc)
  if dc ~= 0 then
    local n = #k.rows[k.row]
    k.col = (k.col - 1 + dc) % n + 1
    k.x = (k.col - 0.5) / n
  end
  if dr ~= 0 then
    k.x = k.x or (k.col - 0.5) / #k.rows[k.row]
    k.row = (k.row - 1 + dr) % #k.rows + 1
    local to = k.rows[k.row]
    k.col = math.min(#to, math.max(1, math.floor(k.x * #to) + 1))
  end
end

-- What a key does to `name`: the new name, and "done" or nil.
function M.press(k, name, key)
  if key == "DONE" then return name, "done" end
  if key == "DEL" then return name:sub(1, -2) end
  local c = key == "SPACE" and " " or key
  if #name >= k.max then return name end
  if c == " " and #name == 0 then return name end
  return name .. c
end

-- A keyboard editing field `field` of window `win`, up to `max` characters.
-- on_done(text) is called when it closes with DONE or START.
function M.new(win, field, max, on_done)
  local k = { win = win, field = field, max = max or 12, chars = M.LETTERS, row = 1, col = 1, t = 0,
              old = win:text(field), on_done = on_done }
  k.rows = M.layout(k.chars)

  function k:update()
    self.t = self.t + 1
    if self.t < 4 then return false end            -- the press that opened it
    local name = self.win:text(self.field)
    local done
    if button("START") then done = "done"
    else
      if button("UP") then M.move(self, -1, 0) end
      if button("DOWN") then M.move(self, 1, 0) end
      if button("LEFT") then M.move(self, 0, -1) end
      if button("RIGHT") then M.move(self, 0, 1) end
      if button("A") then name, done = M.press(self, name, self.rows[self.row][self.col]) end
      if button("X") then name = M.press(self, name, "SPACE") end
      if button("B") then
        if #name > 0 then name = name:sub(1, -2)
        else self.win:set_text(self.field, self.old); return true end
      end
    end
    name = name:gsub("%s+$", function(s) return done and "" or s end)
    self.win:set_text(self.field, name)
    if done then
      if self.on_done then self.on_done(name) end
      return true
    end
    return false
  end

  -- The keyboard in the lower part of the screen, the cursor's key lit.
  function k:draw()
    local CW, RH = 26, 13
    local w = M.COLS * CW
    local x0, y0 = 160 - w // 2, 200 - (#self.rows * RH + 20)
    local h = #self.rows * RH + 34
    rap.shade(x0 - 6, y0 - 21, w + 12, h, -3)
    rap.shade(x0 - 6, y0 - 21, w + 12, 1, 2); rap.shade(x0 - 6, y0 - 22 + h, w + 12, 1, 2)
    -- The name as it stands (the window's box is under the keyboard).
    local caret = (self.t // 16) % 2 == 0 and "_" or ""
    rap.text("FONT2_FNT", self.field .. ":  " .. self.win:text(self.field) .. caret, x0, y0 - 16, -1)
    for r, row in ipairs(self.rows) do
      local cw = w // #row
      for c, key in ipairs(row) do
        local x, y = x0 + (c - 1) * cw, y0 + (r - 1) * RH
        local on = r == self.row and c == self.col
        rap.shade(x + 1, y, cw - 2, RH - 2, on and 2 or -1)
        local tw = rap.text_size("FONT2_FNT", key)
        rap.text("FONT2_FNT", key, x + (cw - tw) // 2, y + 2, -1)
      end
    end
    local hint = "A TYPE  B DELETE  X SPACE  START DONE"
    local hw = rap.text_size("FONT2_FNT", hint)
    rap.text("FONT2_FNT", hint, 160 - hw // 2, y0 + #self.rows * RH + 1, -1)
  end

  return k
end

return M
