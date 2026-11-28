-- Smooth motion (Options > ADVANCED > SMOOTH MOTION): every displayed frame
-- is drawn (60 a second on the Xbox 360 and most screens), with everything
-- that moves placed between where it was at the last game frame and where
-- it is now. The game itself doesn't change: enemies, shots and the map
-- still move only on game frames, by the same amounts, so paths, speeds,
-- timing and hits are the original's. Only what's shown between game
-- frames is new, and it trails the game by up to one game frame (about
-- 43 ms), the usual cost of this kind of smoothing.
--
-- Objects need x and y; mark() notes where each is at the start of a game
-- frame, place() moves them to the in-between spot for drawing and
-- restore() puts them back. Something that moved further than JUMP in a
-- game frame (it was just placed, or wrapped) is drawn where it is.
local M = {}

M.JUMP = 64

function M.mark(lists)
  for _, list in ipairs(lists) do
    for _, o in ipairs(list) do
      if type(o) == "table" and type(o.x) == "number" and type(o.y) == "number" then o._px, o._py = o.x, o.y end
    end
  end
end

-- a: 0 = where things were at the last game frame, 1 = where they are now.
function M.place(lists, a)
  for _, list in ipairs(lists) do
    for _, o in ipairs(list) do
      local px, py
      if type(o) == "table" then px, py = o._px, o._py end
      if px and py then
        local dx, dy = o.x - px, o.y - py
        o._cx, o._cy = o.x, o.y
        if math.abs(dx) <= M.JUMP and math.abs(dy) <= M.JUMP then
          o.x, o.y = px + dx * a, py + dy * a
        end
      end
    end
  end
end

function M.restore(lists)
  for _, list in ipairs(lists) do
    for _, o in ipairs(list) do
      if type(o) == "table" and o._cx then o.x, o.y, o._cx, o._cy = o._cx, o._cy, nil, nil end
    end
  end
end

-- How far into the game frame the screen is: ticks since the last game
-- frame plus the part of a tick, over the ticks in a game frame.
function M.fraction(tick, cadence, alpha)
  local a = ((tick % cadence) + (alpha or 0)) / cadence
  return a < 0 and 0 or a > 1 and 1 or a
end

return M
