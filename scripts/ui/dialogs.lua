-- The original's small windows, opened over a scene. Each dialog is
-- { win = swd window, update = fn -> done?, draw = fn }; the owning scene
-- keeps a stack and passes input only to the top one.
--
-- Labels come from the window layouts in the player's data. Where the
-- original filled a label in from its program (the detail button, the
-- question in a yes/no box, a message), Raptua writes its own short text.
local swd = require("ui.swd")
local settings = require("core.settings")

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
  local function detail_label() w:set_text("DETAIL", settings.detail and "HIGH DETAIL" or "LOW DETAIL") end
  detail_label()
  w.values.VMUSIC, w.values.VFX = settings.music, settings.sound
  w:focus_area("VMUSIC"); w:focus_area("VFX")
  local d = simple(w, function(r)
    if r == "DETAIL" then
      settings.detail = not settings.detail
      detail_label()
      settings.save()
    elseif r == "EXIT" or r == "cancel" then
      return true
    end
  end)
  local base_update = d.update
  d.update = function(self)
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

return M
