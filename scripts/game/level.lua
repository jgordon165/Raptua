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
  -- Per-tile damage rules (FLATSG1_ITM): hits = -1 means indestructible;
  -- otherwise the tile becomes `linkflat` (its wreck: rubble, a broken
  -- bridge) when its hit points run out, paying `bounty`.
  self.flats = rap.flats("FLATSG1_ITM") or {}
  self.hp = {}                        -- cell index -> remaining hit points
  self.cam = H * TILE - M.VIEW_H      -- world y of the screen's top line
  self.speed = 1                      -- pixels per game frame
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
    -- An actor appears when its row is 3 rows above the top of the screen.
    if a.y * TILE < self.cam - 3 * TILE then break end
    self.next_actor = self.next_actor + 1
    -- Actor levels: 3 easy, 4 medium, 5 hard, 0..2 secret (not unlocked
    -- yet). Training and rookie see easy only; veteran easy and medium;
    -- elite all three.
    local ok = a.level == 3 or (a.level == 4 and difficulty >= 2) or (a.level == 5 and difficulty >= 3)
    if ok then out[#out + 1] = a end
  end
  return out
end

-- Damage the map at screen point (sx, sy). Returns nil if the tile there
-- can't be hurt, else { destroyed, bounty, x, y } with the tile's centre in
-- screen coordinates.
function M:hit_tile(sx, sy, dmg)
  local col = math.floor((sx - M.X0) / TILE)
  local row = math.floor((sy + self.cam) / TILE)
  if col < 0 or col >= W or row < 0 or row >= H then return nil end
  local i = row * W + col + 1
  local cell = self.cells[i]
  if cell[2] ~= 0 then return nil end          -- only set 0 has flats in v1.2
  local fl = self.flats[cell[1] + 1]
  if not fl or fl.hits < 0 then return nil end
  self.hp[i] = (self.hp[i] or fl.hits) - dmg
  local cx, cy = M.X0 + col * TILE + TILE / 2, row * TILE + TILE / 2 - self.cam
  if self.hp[i] > 0 then return { destroyed = false, bounty = 0, x = cx, y = cy } end
  self.hp[i] = nil
  cell[1] = fl.linkflat
  if os.getenv("RAPTUA_TRACE") then io.stderr:write(("tile %d,%d destroyed -> %d (+$%d)\n"):format(col, row, fl.linkflat, fl.bounty)) end
  return { destroyed = true, bounty = fl.bounty, x = cx, y = cy }
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
