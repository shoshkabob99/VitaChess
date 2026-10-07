-- stats.lua - your record and milestones, saved to stats.txt
--
-- File format: one "key=value" per line. "3=2,1,0" lines are the
-- won,lost,drawn record against computer level 3 (the original format).

local P = require("platform")
local config = require("config")

local stats = {
  levels = {},          -- [level] = { w, l, d }
  data = {              -- everything else
    games = 0, aiGames = 0, twoPlayer = 0, winStreak = 0, bestStreak = 0,
    longest = 0, fastestWin = 0, bestLevelBeaten = 0, timedWins = 0,
    quickWin = 0, cleanWin = 0, drawLv5 = 0, queens = 0, knights = 0,
    styleTheme = 0, stylePieces = 0,
  },
  openingsWhite = {},   -- [ "e4" ] = games where you opened with it as White
  openingsBlack = {},   -- your first reply as Black
  unlocked = {},        -- [ trophy id ] = true
}

local function entry(level)
  stats.levels[level] = stats.levels[level] or { w = 0, l = 0, d = 0 }
  return stats.levels[level]
end

local function pairs_to_text(t)
  local out = {}
  for k, v in pairs(t) do out[#out + 1] = k .. ":" .. v end
  table.sort(out)
  return table.concat(out, ",")
end

local function text_to_pairs(s, t)
  for k, v in s:gmatch("([^,:]+):(%d+)") do t[k] = tonumber(v) end
end

function stats.load()
  local data = P.readFile(config.STATS_FILE)
  if not data then return end
  for line in data:gmatch("[^\n]+") do
    local lvl, w, l, d = line:match("^(%d+)=(%d+),(%d+),(%d+)$")
    if lvl then
      local e = entry(tonumber(lvl))
      e.w, e.l, e.d = tonumber(w), tonumber(l), tonumber(d)
    else
      local k, v = line:match("^(%a+)=(.*)$")
      if k == "ow" then text_to_pairs(v, stats.openingsWhite)
      elseif k == "ob" then text_to_pairs(v, stats.openingsBlack)
      elseif k == "unlocked" then for id in v:gmatch("[^,]+") do stats.unlocked[id] = true end
      elseif k and stats.data[k] ~= nil then stats.data[k] = tonumber(v) or 0 end
    end
  end
  -- Records from before the game counters existed (v0.9 and earlier) only kept the
  -- per-level results, so make the totals agree with them.
  local w, l, d = stats.totals()
  stats.data.aiGames = math.max(stats.data.aiGames, w + l + d)
  stats.data.games = math.max(stats.data.games, stats.data.aiGames + stats.data.twoPlayer)
end

function stats.save()
  local out = {}
  for lvl, e in pairs(stats.levels) do out[#out + 1] = lvl .. "=" .. e.w .. "," .. e.l .. "," .. e.d end
  for k, v in pairs(stats.data) do out[#out + 1] = k .. "=" .. v end
  out[#out + 1] = "ow=" .. pairs_to_text(stats.openingsWhite)
  out[#out + 1] = "ob=" .. pairs_to_text(stats.openingsBlack)
  local ids = {}
  for id in pairs(stats.unlocked) do ids[#ids + 1] = id end
  table.sort(ids)
  out[#out + 1] = "unlocked=" .. table.concat(ids, ",")
  table.sort(out)
  P.writeFile(config.STATS_FILE, table.concat(out, "\n"))
end

function stats.get(level) return entry(level) end

function stats.totals()
  local w, l, d = 0, 0, 0
  for _, e in pairs(stats.levels) do w, l, d = w + e.w, l + e.l, d + e.d end
  return w, l, d
end

-- Record a finished game.
-- g = { mode = "ai"/"2p", outcome = "w"/"l"/"d" (ai), level, moves (full moves),
--       assisted (used undo or hint), timed, firstMove, firstReply }
function stats.recordGame(g)
  local s = stats.data
  s.games = s.games + 1
  s.longest = math.max(s.longest, g.moves)
  if g.mode == "2p" then
    s.twoPlayer = s.twoPlayer + 1
  else
    s.aiGames = s.aiGames + 1
    local e = entry(g.level)
    e[g.outcome] = e[g.outcome] + 1
    if g.outcome == "w" then
      s.winStreak = s.winStreak + 1
      s.bestStreak = math.max(s.bestStreak, s.winStreak)
      s.bestLevelBeaten = math.max(s.bestLevelBeaten, g.level)
      if s.fastestWin == 0 or g.moves < s.fastestWin then s.fastestWin = g.moves end
      if g.moves <= 20 then s.quickWin = 1 end
      if g.level >= 4 and not g.assisted then s.cleanWin = 1 end
      if g.timed then s.timedWins = s.timedWins + 1 end
    else
      s.winStreak = 0
      if g.outcome == "d" and g.level >= 5 then s.drawLv5 = 1 end
    end
    if g.firstMove then stats.openingsWhite[g.firstMove] = (stats.openingsWhite[g.firstMove] or 0) + 1 end
    if g.firstReply then stats.openingsBlack[g.firstReply] = (stats.openingsBlack[g.firstReply] or 0) + 1 end
  end
  stats.save()
end

-- Bump a counter like "queens" and save
function stats.bump(key)
  stats.data[key] = (stats.data[key] or 0) + 1
  stats.save()
end

-- Most-played entry of an openings table: name, count
function stats.favourite(t)
  local best, n = nil, 0
  for k, v in pairs(t) do if v > n or (v == n and best and k < best) then best, n = k, v end end
  return best, n
end

return stats
