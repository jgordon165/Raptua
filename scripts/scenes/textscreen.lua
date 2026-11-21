-- Full-screen text windows from the player's data: CREDIT_SWD (credits,
-- with the credits music) and ORDER_SWD. Any key or click goes back.
local swd = require("ui.swd")
local scenes = require("core.scenes")
local music = require("game.music")

local M = {}

function M.enter(arg)
  M.win = swd.open(arg.window)
  M.credits = arg.credits
  M.in_game = arg.in_game
  M.t = 0
  if M.credits then music.credits() end
end

function M.leave()
  if M.credits then music.menu(M.in_game) end
end

function M.update()
  M.t = M.t + 1
  if not M.win or (M.t > 15 and (rap.pressed("Return") or rap.pressed("Space") or rap.pressed("Escape")
      or rap.pressed("mouse_left") or rap.pressed("pad_a") or rap.pressed("pad_b") or rap.pressed("pad_start"))) then
    scenes.pop()
  end
end

function M.draw()
  rap.clear(0)
  if M.win then M.win:draw() end
end

return M
