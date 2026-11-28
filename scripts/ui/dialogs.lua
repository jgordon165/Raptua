-- The original's small windows, opened over a scene. Each dialog is
-- { win = swd window, update = fn -> done?, draw = fn }; the owning scene
-- keeps a stack and passes input only to the top one.
--
-- Labels come from the window layouts in the player's data. Where the
-- original filled a label in from its program (the detail button, the
-- question in a yes/no box, a message), Raptua writes its own short text.
local swd = require("ui.swd")
local settings = require("core.settings")
local util = require("core.util")

local M = {}

local function simple(win, on_button)
  return {
    win = win,
    update = function(self)
      local r = win:update()
      if r then return on_button(r) end
    end,
    draw = function(self) win:draw() end,
  }
end

-- OPTIONS: detail toggle, music and sound effect sliders (0..127), exit.
function M.options()
  local w = swd.open("OPTS_SWD")
  if not w then return nil end
  for _, n in ipairs({ "PIC1", "PIC2", "PIC3" }) do w:hide(n) end
  -- The port's own: ADVANCED (smooth motion, game speed, the keyboard or
  -- controller setup) beside EXIT, in the space the original leaves there.
  w:add_button("ADVANCED", "ADVANCED", 7, 136, 98, 12, "EXIT")
  local function detail_label() w:set_text("DETAIL", settings.detail and "HIGH DETAIL" or "LOW DETAIL") end
  detail_label()
  w.values.VMUSIC, w.values.VFX = settings.music, settings.sound
  w:focus_area("VMUSIC"); w:focus_area("VFX")
  local d
  d = simple(w, function(r)
    if r == "DETAIL" then
      settings.detail = not settings.detail
      detail_label()
      settings.save()
    elseif r == "ADVANCED" then
      d.sub = M.advanced()
    elseif r == "EXIT" or r == "cancel" then
      return true
    end
  end)
  local base_update, base_draw = d.update, d.draw
  d.update = function(self)
    if self.sub then
      if self.sub:update() then self.sub = nil end
      return false
    end
    local done = base_update(self)
    if w.changed then
      settings.music = math.floor(w.values.VMUSIC or settings.music)
      settings.sound = math.floor(w.values.VFX or settings.sound)
      settings.apply()
      settings.save()
      w.changed = nil
    end
    return done
  end
  d.draw = function(self)
    base_draw(self)
    if self.sub then self.sub:draw() end
  end
  return d
end

-- Options > ADVANCED (the port's own, as in Meguarace): settings the
-- original doesn't have.
--   SMOOTH MOTION  draw every displayed frame (60 on the Xbox 360), moving
--                  things placed between game frames (game/smooth.lua); the
--                  game itself is unchanged
--   GAME SPEED     game frames a second (the original's 3, 4 or 5 vertical
--                  blanks per frame; also F5 on the main menu)
--   KEYBOARD / CONTROLLER  the key or button setup
-- Up and down pick a row; A / Enter (or left and right) changes it; B / Esc
-- or DONE closes.
function M.advanced()
  local controls = require("game.controls")
  local XENON = rap.platform == "xenon"
  local rows = { "smooth", "speed", "controls", "done" }
  local d = { row = 1, t = 0 }
  local W, RH = 236, 13
  local H = (#rows + 2) * RH + 10
  local X, Y = (320 - W) // 2, (200 - H) // 2

  local function label(r)
    if r == "smooth" then return "SMOOTH MOTION", settings.smooth and "ON (60 FPS)" or "OFF" end
    if r == "speed" then return settings.cadence_label(), "" end
    if r == "controls" then return controls.kind() == "pad" and "CONTROLLER SETUP" or "KEYBOARD SETUP", "" end
    return "DONE", ""
  end

  local function back()
    return util.pressed("back") or (XENON and rap.pad_pressed("B"))
  end

  local function change(r, dir)
    if r == "smooth" then
      settings.smooth = not settings.smooth
      settings.apply(); settings.save()
    elseif r == "speed" then
      settings.cycle_cadence(dir)
    elseif r == "controls" then
      d.sub = M.controls()
    else
      return true
    end
  end

  function d:update()
    self.t = self.t + 1
    if self.sub then
      if self.sub:update() then self.sub = nil; self.t = 0 end
      return false
    end
    if self.t < 6 then return false end            -- the press that opened this
    if back() then return true end
    if util.pressed("up") then self.row = (self.row - 2) % #rows + 1 end
    if util.pressed("down") then self.row = self.row % #rows + 1 end
    local r = rows[self.row]
    if rap.pressed("repeat_Left") or rap.pressed("pad_dpleft") then if r ~= "controls" and r ~= "done" then change(r, -1) end end
    if rap.pressed("repeat_Right") or rap.pressed("pad_dpright") then if r ~= "controls" and r ~= "done" then change(r, 1) end end
    if util.pressed("ok") or rap.pressed("mouse_left") then
      if change(r, 1) then return true end
    end
    return false
  end

  function d:draw()
    rap.shade(X, Y, W, H, -3); rap.shade(X, Y, W, H, -3)   -- twice: the menu behind stays out of the way
    rap.shade(X, Y, W, 1, 2); rap.shade(X, Y + H - 1, W, 1, 2)
    rap.shade(X, Y, 1, H, 2); rap.shade(X + W - 1, Y, 1, H, 2)
    local tw = rap.text_size("FONT2_FNT", "ADVANCED")
    rap.text("FONT2_FNT", "ADVANCED", X + (W - tw) // 2, Y + 5, -1)
    for i, r in ipairs(rows) do
      local y = Y + 6 + i * RH + 2
      if i == self.row then rap.shade(X + 4, y - 2, W - 8, RH - 1, 1) end
      local name, value = label(r)
      rap.text("FONT2_FNT", name, X + 10, y, -1)
      if value ~= "" then
        local vw = rap.text_size("FONT2_FNT", value)
        rap.text("FONT2_FNT", value, X + W - 10 - vw, y, -1)
      end
    end
    if self.sub then self.sub:draw() end
  end

  return d
end

-- The key or controller setup (the port's own; game/controls.lua): asks
-- for a key (or a controller button) for each control in turn. On the last
-- row any key or button keeps them; Escape (BACK on the 360) at any point
-- puts the old ones back. A key or button already given to an earlier row
-- is refused.
function M.controls()
  local controls = require("game.controls")
  local kind = controls.kind()
  local cur = controls.of(settings, kind)
  local acts = controls.actions(kind)
  local d = { row = 1, new = {}, t = 0 }
  local W, RH = 200, 11
  local H = (#acts + 4) * RH + 8
  local X, Y = (320 - W) // 2, (200 - H) // 2

  local function taken(v)
    for i = 1, d.row - 1 do if d.new[acts[i]] == v then return true end end
    return false
  end

  function d:update()
    self.t = self.t + 1
    if self.t < 6 then return false end            -- the press that opened this
    local v
    if kind == "pad" then
      v = rap.pad_button()
      if v == "BACK" then return true end          -- the old buttons stay
    else
      v = rap.key_down()
      if v == "Escape" then return true end
    end
    if not v then return false end
    if self.row > #acts then                       -- the last row: keep them
      for a, b in pairs(self.new) do cur[a] = b end
      settings.save()
      return true
    end
    local ok = kind == "pad" and controls.accepts_button(v) or (kind ~= "pad" and controls.accepts_key(v))
    if ok and not taken(v) then
      self.new[acts[self.row]] = v
      self.row = self.row + 1
    end
    return false
  end

  function d:draw()
    rap.shade(X, Y, W, H, -3); rap.shade(X, Y, W, H, -3)   -- twice: the menu behind stays out of the way
    rap.shade(X, Y, W, 1, 2); rap.shade(X, Y + H - 1, W, 1, 2)
    rap.shade(X, Y, 1, H, 2); rap.shade(X + W - 1, Y, 1, H, 2)
    local title = kind == "pad" and "CONTROLLER" or "KEYBOARD"
    local tw = rap.text_size("FONT2_FNT", title)
    rap.text("FONT2_FNT", title, X + (W - tw) // 2, Y + 4, -1)
    for i, a in ipairs(acts) do
      local y = Y + 4 + (i + 1) * RH
      local v = self.new[a] or (i >= self.row and cur[a]) or nil
      if i == self.row then rap.shade(X + 4, y - 2, W - 8, RH, 1) end
      rap.text("FONT2_FNT", controls.LABELS[a], X + 10, y, -1)
      local shown = i < self.row and controls.display(self.new[a]) or (i == self.row and ((self.t // 16) % 2 == 0 and "..." or "")) or controls.display(v)
      rap.text("FONT2_FNT", shown, X + 110, y, -1)
    end
    local last = Y + 4 + (#acts + 2) * RH
    local hint
    if self.row > #acts then
      rap.shade(X + 4, last - 2, W - 8, RH, 1)
      hint = kind == "pad" and "ANY BUTTON KEEPS, BACK UNDOES" or "ANY KEY KEEPS, ESC UNDOES"
    else
      hint = kind == "pad" and "PRESS A BUTTON  (BACK UNDOES)" or "PRESS A KEY  (ESC UNDOES)"
    end
    local hw = rap.text_size("FONT2_FNT", hint)
    rap.text("FONT2_FNT", hint, X + (W - hw) // 2, last, -1)
  end

  return d
end

-- CHOOSE DIFFICULTY: calls pick(0..3) for training/rookie/veteran/elite,
-- or pick(nil) for abort.
function M.difficulty(pick)
  local w = swd.open("ASKDIFF_SWD")
  if not w then pick(1); return nil end
  local map = { TRAIN = 0, EASY = 1, MED = 2, HARD = 3 }
  return simple(w, function(r)
    if map[r] then pick(map[r]); return true end
    if r == "ABORT" or r == "cancel" then pick(nil); return true end
  end)
end

-- A yes/no question; answer(true|false).
function M.ask(question, answer)
  local w = swd.open("ASK_SWD")
  if not w then answer(false); return nil end
  w:set_text("DRAGBAR", question)
  -- Start on NO, so a stray press doesn't confirm.
  for k, i in ipairs(w.focus) do if w.def.fields[i].name == "NO" then w.sel = k end end
  return simple(w, function(r)
    if r == "YES" then answer(true); return true end
    if r == "NO" or r == "cancel" then answer(false); return true end
  end)
end

-- A message; closes on any key or click (or after `seconds`, if given).
function M.message(text, seconds)
  local w = swd.open("MSG_SWD")
  if not w then return nil end
  w:set_text("MSG", text)
  local t = 0
  return {
    win = w,
    update = function(self)
      t = t + 1
      if t > 10 and (rap.pressed("Return") or rap.pressed("Space") or rap.pressed("Escape") or rap.pressed("pad_a")
          or rap.pressed("pad_b") or rap.pressed("pad_start") or rap.pressed("mouse_left")) then return true end
      if seconds and t > seconds * 70 then return true end
    end,
    draw = function(self) w:draw() end,
  }
end

-- LOAD MISSION: browse saved pilots; pick(p) with the chosen pilot, or
-- pick(nil) on cancel. Returns nil (and calls none) if there are none, so
-- the caller can say so.
function M.load_pilot(pick)
  local pilot = require("game.pilot")
  local list = pilot.list()
  if #list == 0 then return nil end
  local w = swd.open("LOAD_SWD")
  if not w then return nil end
  local pos = 1
  local confirm
  local function show()
    local p = list[pos]
    w:set_item("IDPIC", pilot.PHOTOS[p.photo] or pilot.PHOTOS[1])
    w:set_text("NAME", p.name or "")
    w:set_text("CALL", p.callsign or "")
    w:set_text("CREDITS", tostring(p.money or 0))
  end
  show()
  w:select("LOAD")
  return {
    win = w,
    update = function(self)
      if confirm then
        if confirm:update() then confirm = nil end
        return self.done
      end
      local r = w:update()
      if r == "NEXT" then pos = pos % #list + 1; show()
      elseif r == "PREV" then pos = (pos - 2) % #list + 1; show()
      elseif r == "LOAD" then pick(list[pos]); return true
      elseif r == "DEL" then
        confirm = M.ask("DELETE THIS PILOT?", function(yes)
          if not yes then return end
          pilot.delete(list[pos])
          table.remove(list, pos)
          if #list == 0 then pick(nil); self.done = true; return end
          pos = math.min(pos, #list)
          show()
        end)
      elseif r == "CANCEL" or r == "cancel" then pick(nil); return true end
    end,
    draw = function(self)
      w:draw()
      if confirm then confirm:draw() end
    end,
  }
end

-- HELP: the pages between the STARTHELP and ENDHELP markers in the
-- player's FILE0000.GLB, shown in HELP_SWD. Opens at `page` (an item name
-- such as "HANGHLP1_TXT"); UP / DOWN (and the arrows, Page Up / Down, Home,
-- End) go through every page, wrapping; DONE / Esc closes.
function M.help(page)
  local first, last = rap.find("STARTHELP"), rap.find("ENDHELP")
  if not first or not last or last - first < 2 then return nil end
  local count = last - first - 1
  local w = swd.open("HELP_SWD")
  if not w then return nil end
  local cur = 0
  local start = page and rap.find(page)
  if start and start > first and start < last then cur = start - first - 1 end
  local function show()
    w:set_item("TEXT", first + 1 + cur)
    w:set_text("HEADER", ("PAGE : %02d"):format(cur + 1))
  end
  show()
  w:select("DONE")
  return {
    win = w,
    update = function(self)
      local r = w:update()
      local step = 0
      if r == "DOWN" or rap.pressed("repeat_Page Down") then step = 1 end
      if r == "UP" or rap.pressed("repeat_Page Up") then step = -1 end
      if rap.pressed("Home") then cur = 0; show() end
      if rap.pressed("End") then cur = count - 1; show() end
      if step ~= 0 then cur = (cur + step) % count; show() end
      if r == "DONE" or r == "cancel" or rap.pressed("F1") then return true end
    end,
    draw = function(self) w:draw() end,
  }
end

return M
