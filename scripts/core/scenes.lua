-- A stack of scenes. Each scene is a table with optional
-- enter(arg), leave(), update(), draw(). Only the top scene updates; draw()
-- runs for the top scene (a scene can draw the one below via scenes.below()).
local M = { stack = {} }

local function top() return M.stack[#M.stack] end

function M.switch(scene, arg)
  while #M.stack > 0 do
    local s = table.remove(M.stack)
    if s.leave then s.leave() end
  end
  M.push(scene, arg)
end

function M.push(scene, arg)
  M.stack[#M.stack + 1] = scene
  if scene.enter then scene.enter(arg) end
end

function M.pop()
  local s = table.remove(M.stack)
  if s and s.leave then s.leave() end
end

function M.is(scene) return top() == scene end

function M.below()
  local s = M.stack[#M.stack - 1]
  if s and s.draw then s.draw() end
end

function M.update() local s = top(); if s and s.update then s.update() end end
function M.draw() local s = top(); if s and s.draw then s.draw() end end

return M
