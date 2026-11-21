-- When each song plays, as in the original:
--   Apogee logo            APOGEE
--   intro                  RINTRO
--   main menu              MAINMENU, or RINTRO when a game is in progress
--   hangar / sector pick   HANGAR
--   each wave              the sector's table below (not RAP1..8 in order)
--   death                  RAP5
--   credits                BOSS4, BOSS2, BOSS3 in turn, one per visit
local M = {}

M.WAVES = {
  [1] = { "RAP8", "RAP2", "RAP4", "RAP7", "RAP6", "RAP2", "RAP3", "RAP4", "RAP6" },
  [2] = { "RAP3", "RAP2", "RAP4", "RAP8", "RAP6", "RAP2", "RAP8", "RAP1", "RAP6" },
  [3] = { "RAP8", "RAP4", "RAP1", "RAP7", "RAP6", "RAP2", "RAP3", "RAP4", "RAP6" },
}

local function play(name) rap.music(name .. "_MUS") end

function M.wave(sector, wave)
  local t = M.WAVES[sector] or M.WAVES[1]
  play(t[(wave - 1) % #t + 1])
end

function M.menu(in_game) play(in_game and "RINTRO" or "MAINMENU") end
function M.hangar() play("HANGAR") end
function M.death() play("RAP5") end
function M.intro() play("RINTRO") end
function M.apogee() rap.music("APOGEE_MUS", false) end

local credit_song = 2      -- so the first visit plays BOSS4, as the original does
function M.credits()
  local songs = { "BOSS2", "BOSS3", "BOSS4" }
  credit_song = credit_song % #songs + 1
  play(songs[credit_song])
end

return M
