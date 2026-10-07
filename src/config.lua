-- config.lua - easy-to-edit game data
--
-- Add a board theme by copying one of the THEMES lines and changing the
-- name and colours (red, green, blue values from 0 to 255).
-- Add a piece set by making a folder of 12 PNGs in assets/pieces/<dir>/
-- (wK.png ... bP.png, 64x64) and adding a line to PIECE_SETS.

local P = require("platform")
local config = {}

config.VERSION = "v1.0"
config.AUTHOR  = "shoshkabob"

config.DATA_DIR      = P.DATA_DIR or "ux0:data/VitaChess"   -- the platform can override these
config.SAVE_FILE     = config.DATA_DIR .. "/save.txt"
config.SETTINGS_FILE = config.DATA_DIR .. "/settings.txt"
config.STATS_FILE    = config.DATA_DIR .. "/stats.txt"
config.GAMES_DIR     = config.DATA_DIR .. "/games"      -- finished games, as PGN files
config.PUZZLE_PROGRESS = config.DATA_DIR .. "/puzzles.txt"
config.LEARN_FILE    = config.DATA_DIR .. "/learn.txt"
config.ASSET_DIR     = P.ASSET_DIR or "app0:/"  -- where pieces/, sounds/ and fonts/ live

-- Text uses the Inter font, pre-rendered into bitmaps by tools/make_fonts.py
config.FONT_DIR  = config.ASSET_DIR .. "fonts/bitmap/"
config.FONT      = config.ASSET_DIR .. "fonts/Inter-Regular.ttf"   -- (desktop preview)
config.FONT_BOLD = config.ASSET_DIR .. "fonts/Inter-Bold.ttf"
config.FONT_SIZES = { 14, 15, 16, 17, 18, 20, 21, 22, 23, 26, 31, 32, 47, 54 }

-- Pixel size for a text scale (1 = normal body text). Never smaller than 14.
function config.fontPx(scale)
  return math.max(14, math.floor(17 * (scale or 1) * 1.06 + 0.5))
end
config.PUZZLE_DATA = config.ASSET_DIR .. "puzzles/puzzles.txt"

config.THEMES = {
  { name = "Wood",       light = { 238, 216, 181 }, dark = { 181, 136, 99 } },
  { name = "Tournament", light = { 238, 238, 210 }, dark = { 118, 150, 86 } },
  { name = "Ice Blue",   light = { 222, 227, 230 }, dark = { 140, 162, 173 } },
  { name = "Midnight",   light = { 150, 160, 178 }, dark = { 72, 82, 102 } },
  { name = "Lavender",   light = { 232, 226, 245 }, dark = { 148, 124, 186 } },
  { name = "Coral",      light = { 246, 226, 214 }, dark = { 214, 128, 108 } },
  { name = "Marble",     light = { 226, 226, 226 }, dark = { 128, 128, 134 } },
}

config.PIECE_SETS = {
  { name = "Classic",  dir = "classic" },
  { name = "Staunton", dir = "staunton" },
  { name = "Flat",     dir = "flat" },
  { name = "Neon",     dir = "neon" },
  { name = "Pixel",    dir = "pixel" },
}

config.COLOR_NAMES = { "White", "Black", "Random" }

-- Chess clocks: base time and increment per move, in seconds
config.TIME_CONTROLS = {
  { name = "No clock" },
  { name = "3 min + 2", base = 180, inc = 2 },
  { name = "5 min",     base = 300, inc = 0 },
  { name = "10 min",    base = 600, inc = 0 },
  { name = "15 min + 10", base = 900, inc = 10 },
  { name = "30 min",    base = 1800, inc = 0 },
}

-- How long a piece takes to slide to its new square (milliseconds)
config.ANIM_MS = 180

-- Minimum time (ms) the computer appears to think, so its moves don't feel instant
config.MIN_THINK = 600

return config
