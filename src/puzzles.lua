-- puzzles.lua - the puzzle collection, your puzzle rating and progress
--
-- Puzzles come from assets/puzzles/puzzles.txt (the Lichess puzzle database,
-- CC0). Each line: id,FEN,moves,rating. The moves are in UCI form (e2e4,
-- e7e8q); the FIRST move is the opponent's, played to set up the puzzle,
-- then the solver and opponent alternate. The solver's moves are the answer.
--
-- Progress is saved to ux0:data/VitaChess/puzzles.txt.

local P = require("platform")
local Chess = require("chess")
local config = require("config")

local Puzzles = {}

Puzzles.BANDS = {                      -- difficulty choices on the puzzle screen
  { name = "Adaptive" },               -- picks puzzles near your rating
  { name = "Easy",   min = 400,  max = 999 },
  { name = "Medium", min = 1000, max = 1499 },
  { name = "Hard",   min = 1500, max = 1999 },
  { name = "Expert", min = 2000, max = 3000 },
}

local list = {}                        -- every puzzle: { id, fen, moves = {...}, rating }
Puzzles.progress = { rating = 1000, solved = 0, attempts = 0, streak = 0, best = 0, seen = {} }

---------------------------------------------------------------------------
-- Loading and saving
---------------------------------------------------------------------------
function Puzzles.load()
  list = {}
  local data = P.readFile(config.PUZZLE_DATA)
  if data then
    for line in data:gmatch("[^\r\n]+") do
      local id, fen, moves, rating = line:match("^([^#,][^,]*),([^,]+),([^,]+),(%d+)$")
      if id then
        local mv = {}
        for u in moves:gmatch("%S+") do mv[#mv + 1] = u end
        list[#list + 1] = { id = id, fen = fen, moves = mv, rating = tonumber(rating) }
      end
    end
  end
  local pr = Puzzles.progress
  local saved = P.readFile(config.PUZZLE_PROGRESS)
  if saved then
    for k, v in saved:gmatch("(%a+)=([%w,]*)") do
      if k == "seen" then
        for id in v:gmatch("[^,]+") do pr.seen[id] = true end
      elseif pr[k] ~= nil then
        pr[k] = tonumber(v) or pr[k]
      end
    end
  end
end

function Puzzles.save()
  local pr = Puzzles.progress
  local seen = {}
  for id in pairs(pr.seen) do seen[#seen + 1] = id end
  table.sort(seen)
  P.writeFile(config.PUZZLE_PROGRESS, string.format(
    "rating=%d\nsolved=%d\nattempts=%d\nstreak=%d\nbest=%d\nseen=%s",
    pr.rating, pr.solved, pr.attempts, pr.streak, pr.best, table.concat(seen, ",")))
end

function Puzzles.count() return #list end

function Puzzles.seenCount()
  local n = 0
  for _ in pairs(Puzzles.progress.seen) do n = n + 1 end
  return n
end

---------------------------------------------------------------------------
-- Choosing a puzzle
---------------------------------------------------------------------------
-- band = index into Puzzles.BANDS. Prefers puzzles you haven't seen yet.
function Puzzles.pick(band)
  if #list == 0 then return nil end
  local b = Puzzles.BANDS[band] or Puzzles.BANDS[1]
  local lo, hi
  if b.min then
    lo, hi = b.min, b.max
  else
    local r = Puzzles.progress.rating
    lo, hi = r - 100, r + 100
  end
  local seen = Puzzles.progress.seen
  local maxWiden = b.min and 0 or 3000   -- fixed bands stay in range; adaptive widens
  for _, unseenOnly in ipairs({ true, false }) do
    for widen = 0, maxWiden, 100 do
      local pool = {}
      for _, p in ipairs(list) do
        if p.rating >= lo - widen and p.rating <= hi + widen and (not unseenOnly or not seen[p.id]) then
          pool[#pool + 1] = p
        end
      end
      if #pool > 0 then return pool[math.random(#pool)] end
    end
  end
  return list[math.random(#list)]
end

---------------------------------------------------------------------------
-- Moves and results
---------------------------------------------------------------------------
local PROMO = { n = 2, b = 3, r = 4, q = 5 }

-- Turn a UCI move like "e7e8q" into a legal move of game g (or nil)
function Puzzles.toMove(g, uci)
  local function square(s) return Chess.sq(s:byte(1) - 97, s:byte(2) - 49) end
  return Chess.findMove(g, square(uci:sub(1, 2)), square(uci:sub(3, 4)), PROMO[uci:sub(5, 5)] or 0)
end

-- Record a finished puzzle. success = solved without mistakes;
-- rated = false for puzzles solved with a hint (no rating change).
-- Returns the rating change.
function Puzzles.finish(p, success, rated)
  local pr = Puzzles.progress
  pr.seen[p.id] = true
  pr.attempts = pr.attempts + 1
  local delta = 0
  if success then
    pr.solved = pr.solved + 1
    pr.streak = pr.streak + 1
    if pr.streak > pr.best then pr.best = pr.streak end
  else
    pr.streak = 0
  end
  if rated ~= false then
    local k = (pr.attempts <= 20) and 40 or 24      -- move faster while you're new
    local expected = 1 / (1 + 10 ^ ((p.rating - pr.rating) / 400))
    delta = math.floor(k * ((success and 1 or 0) - expected) + 0.5)
    pr.rating = math.max(100, pr.rating + delta)
  end
  Puzzles.save()
  return delta
end

return Puzzles
