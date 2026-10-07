-- settings.lua - the player's settings, saved to settings.txt as key=value lines

local P = require("platform")
local config = require("config")
local AI = require("ai")
local Puzzles = require("puzzles")

local settings = {
  values = {
    theme = 2, pieces = 2,          -- Tournament board, Staunton pieces (index into config.THEMES / PIECE_SETS)
    legal = true, last = true, coords = true, autoflip = false,
    sfxvol = 5,                     -- sound volume: 1 Off, 2 25%, 3 50%, 4 75%, 5 100%
    level = 4,                      -- computer difficulty (index into AI.LEVELS)
    color = 1,                      -- 1 White, 2 Black, 3 Random
    tc = 1,                         -- time control (index into config.TIME_CONTROLS)
    anim = true,                    -- slide pieces when they move
    pband = 1,                      -- puzzle difficulty (index into Puzzles.BANDS)
    menubg = 1,                     -- menu background: 1 Floating pieces, 2 Waves, 3 Classic
  },
}

local LIMITS = { theme = #config.THEMES, pieces = #config.PIECE_SETS,
                 level = #AI.LEVELS, color = #config.COLOR_NAMES,
                 tc = #config.TIME_CONTROLS, pband = #Puzzles.BANDS, menubg = 3,
                 sfxvol = 5 }
settings.VOLUME_NAMES = { "Off", "25%", "50%", "75%", "100%" }
function settings.volume(step) return (step - 1) / 4 end

function settings.load()
  local data = P.readFile(config.SETTINGS_FILE)
  if not data then return end
  local v = settings.values
  if data:find("sound=0", 1, true) and not data:find("sfxvol", 1, true) then v.sfxvol = 1 end  -- old on/off setting
  for k, val in data:gmatch("(%w+)=(%w+)") do
    if type(v[k]) == "boolean" then
      v[k] = (val == "1")
    elseif type(v[k]) == "number" then
      local n = tonumber(val)
      if n and n >= 1 and n <= (LIMITS[k] or 1) then v[k] = math.floor(n) end
    end
  end
end

function settings.save()
  local out = {}
  for k, val in pairs(settings.values) do
    if type(val) == "boolean" then val = val and "1" or "0" end
    out[#out + 1] = k .. "=" .. val
  end
  table.sort(out)
  P.writeFile(config.SETTINGS_FILE, table.concat(out, "\n"))
end

return settings
