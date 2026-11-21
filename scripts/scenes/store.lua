-- The supply room (STORE_SWD). Buy or sell mode (the two small buttons),
-- PREV / NEXT through what's for sale or what you own, and the big button
-- to buy or sell the item shown. The screen shows the item's description
-- (ITEMnn_TXT for object nn, from the player's data); the walk-out strip
-- on the left goes back to the hangar. Selling pays half the price.
local scenes = require("core.scenes")
local swd = require("ui.swd")
local dialogs = require("ui.dialogs")
local pilot = require("game.pilot")
local weapons = require("game.weapons")

local M = {}

local HINTS = { BUY = "BUY MODE", SELL = "SELL MODE", PREV = "PREVIOUS ITEM", NEXT = "NEXT ITEM",
                BUYIT = "BUY / SELL THIS", VEXIT = "BACK TO THE HANGAR" }

local function owned(p, n) return p.items[n] or 0 end

-- How much one purchase adds, and the most you can hold.
local function lot(n) return n == 16 and 25 or 1 end
local function max_of(n) return n == 16 and 100 or weapons.MAX[n] or 1 end

local function can_buy(p, n)
  if n == 16 then return (p.shield or 100) < 100 end
  return owned(p, n) < max_of(n)
end

-- What the current mode lists.
local function listing(p, mode)
  local out = {}
  for _, n in ipairs(pilot.STORE) do
    if mode == "buy" and can_buy(p, n) then out[#out + 1] = n
    elseif mode == "sell" and n ~= 0 and n ~= 16 and owned(p, n) > 0 then out[#out + 1] = n end
  end
  return out
end

local function refresh()
  local w, p = M.win, M.pilot
  M.list = listing(p, M.mode)
  M.pos = math.max(1, math.min(M.pos, #M.list))
  local n = M.list[M.pos]
  w:set_item("BUY", M.mode == "buy" and "BUYLGT_PIC" or "BUYDRK_PIC")
  w:set_item("SELL", M.mode == "sell" and "SELLGT_PIC" or "SELLDRK_PIC")
  w:set_item("BUYIT", M.mode == "buy" and "BUYITEM_PIC" or "SELLITEM_PIC")
  w:set_item("ID", pilot.PHOTOS[p.photo] or pilot.PHOTOS[1])
  w:set_text("CALLSIGN", p.callsign or "")
  w:set_text("SCORE", tostring(p.money))
  if n then
    local price = pilot.cost(n)
    if M.mode == "sell" then price = price // 2 end
    w:set_item("COMP", ("ITEM%02d_TXT"):format(n))
    w:set_text("TEXTCOST", M.mode == "buy" and "COST" or "RESALE")
    w:set_text("COST", tostring(price))
    w:set_text("STATS", "OWNED")
    w:set_text("NUM", n == 16 and tostring(p.shield or 0) or tostring(owned(p, n)))
  else
    w:set_item("COMP", "")
    w:set_text("TEXTCOST", ""); w:set_text("COST", ""); w:set_text("STATS", ""); w:set_text("NUM", "")
  end
end

function M.enter(arg)
  M.pilot = arg.pilot
  M.win = swd.open("STORE_SWD")
  M.mode, M.pos = "buy", 1
  M.stack = {}
  M.snd = rap.sound("SWEP_FX")
  M.snd_buy = rap.sound("BONUS_FX")
  if not M.win then return end
  M.win:focus_area("VEXIT")
  M.win:select("NEXT")
  refresh()
end

local function say(text) M.stack[#M.stack + 1] = dialogs.message(text, 2) end

local function deal()
  local p, n = M.pilot, M.list[M.pos]
  if not n then say(M.mode == "buy" and "NOTHING LEFT TO BUY" or "NOTHING TO SELL"); return end
  local price = pilot.cost(n)
  if M.mode == "buy" then
    if p.money < price then say("NOT ENOUGH MONEY"); return end
    p.money = p.money - price
    if n == 16 then p.shield = math.min(100, (p.shield or 0) + lot(n))
    elseif n == weapons.SUPER_SHIELD then p.super = 100; p.items[n] = 1
    else p.items[n] = owned(p, n) + lot(n) end
    if not p.special and n >= weapons.FIRST_SPECIAL and n <= weapons.LAST_SPECIAL and n ~= weapons.MEGABOMB then
      p.special = n
    end
  else
    p.money = p.money + price // 2
    p.items[n] = owned(p, n) - 1
    if p.items[n] <= 0 then p.items[n] = nil end
    if n == weapons.SUPER_SHIELD then p.super = 0 end
    if p.special == n then p.special = nil end
  end
  rap.play(M.snd_buy, 0.8)
  refresh()
end

function M.update()
  local top = M.stack[#M.stack]
  if top then if top:update() then table.remove(M.stack) end; return end
  if rap.pressed("F1") then
    local h = dialogs.help("STORHLP1_TXT")
    if h then M.stack[#M.stack + 1] = h end
    return
  end
  if not M.win then scenes.pop(); return end
  local r = M.win:update()
  if M.win.moved then rap.play(M.snd, 0.4) end
  local f = M.win:selected()
  M.win:set_text("TEXT", f and HINTS[f.name] or "")
  if r == "BUY" or r == "VBUY" then M.mode = "buy"; M.pos = 1; refresh(); rap.play(M.snd, 0.6)
  elseif r == "SELL" or r == "VSELL" then M.mode = "sell"; M.pos = 1; refresh(); rap.play(M.snd, 0.6)
  elseif r == "PREV" or r == "VPREV" then if #M.list > 0 then M.pos = (M.pos - 2) % #M.list + 1 end; refresh()
  elseif r == "NEXT" or r == "VNEXT" then if #M.list > 0 then M.pos = M.pos % #M.list + 1 end; refresh()
  elseif r == "BUYIT" or r == "VACCEPT" then deal()
  elseif r == "VEXIT" or r == "cancel" then scenes.pop() end
end

function M.draw()
  rap.clear(0)
  if M.win then M.win:draw() end
  for _, d in ipairs(M.stack) do d:draw() end
end

return M
