-- A level: the 9x150 tile map scrolling from the bottom row up, and the
-- actor list that spawns enemies as their row comes into view.
local M = {}
M.__index = M

local TILE, W, H = 32, 9, 150
M.X0 = (rap.W - W * TILE) // 2        -- the 288-pixel map, centred
M.VIEW_H = rap.H

function M.new(map_name, tileset)
  local data = rap.level(map_name)
  if not data then return nil, "missing " .. map_name end
  local self = setmetatable({}, M)
  self.cells = data.cells
  self.actors = data.actors
  -- Tile n of set s is the item after STARTG{s+1}TILES, plus n.
  self.tile_base = {}
  for s = 0, 3 do self.tile_base[s] = rap.find(("STARTG%dTILES"):format(s + 1)) end
  self.tileset = tileset or 1
  self.cam = H * TILE - M.VIEW_H      -- world y of the screen's top line
  self.speed = 0.5                    -- pixels per tick
  self.next_actor = 1
  table.sort(self.actors, function(a, b) return a.y > b.y end)   -- bottom rows first
  return self
end

function M:done() return self.cam <= 0 end

function M:update()
  self.cam = math.max(0, self.cam - self.speed)
end

-- Actors whose row has reached the top of the screen (minus a margin).
function M:take_spawns(difficulty)
  local out = {}
  while self.next_actor <= #self.actors do
    local a = self.actors[self.next_actor]
    if a.y * TILE + TILE < self.cam - 8 then break end
    self.next_actor = self.next_actor + 1
    -- level 3/4/5 = easy/medium/hard and up; other values are special tiers.
    if a.level <= 2 + difficulty or a.level > 5 then out[#out + 1] = a end
  end
  return out
end

-- World y -> screen y.
function M:sy(wy) return wy - self.cam end

function M:draw()
  local first = math.floor(self.cam / TILE)
  local last = math.min(H - 1, math.floor((self.cam + M.VIEW_H) / TILE))
  rap.clip(M.X0, 0, W * TILE, M.VIEW_H)
  for row = first, last do
    local y = math.floor(row * TILE - self.cam)
    for col = 0, W - 1 do
      local c = self.cells[row * W + col + 1]
      local base = self.tile_base[c[2]]
      if base then rap.pic(base + 1 + c[1], M.X0 + col * TILE, y) end
    end
  end
  rap.clip()
end

return M
