-- learn.lua - runs the Learn courses: judging moves and saving progress
-- The course content lives in lessons.lua.

local P = require("platform")
local Chess = require("chess")
local config = require("config")

local Learn = {}
Learn.COURSES = require("lessons")
Learn.done = {}             -- [ "basics/rook" ] = true for finished lessons

local PROMO = { n = 2, b = 3, r = 4, q = 5 }
local PROMO_CHAR = { [2] = "n", [3] = "b", [4] = "r", [5] = "q" }

function Learn.uci(m)
  return Chess.sqName(m.from) .. Chess.sqName(m.to) .. (PROMO_CHAR[m.promo] or "")
end

-- A legal move of game g from UCI text like "e7e8q", or nil
function Learn.toMove(g, u)
  local function square(s) return Chess.sq(s:byte(1) - 97, s:byte(2) - 49) end
  return Chess.findMove(g, square(u:sub(1, 2)), square(u:sub(3, 4)), PROMO[u:sub(5, 5)] or 0)
end

local function words(s)
  local t = {}
  if s then for w in s:gmatch("%S+") do t[#t + 1] = w end end
  return t
end
Learn.words = words

-- Square names "e4:g d5:r" -> list of { sq = square, color = "g" }
function Learn.parseMarks(s)
  local out = {}
  for name, c in (s or ""):gmatch("(%a%d):(%a)") do
    out[#out + 1] = { sq = Chess.sq(name:byte(1) - 97, name:byte(2) - 49), color = c }
  end
  return out
end

function Learn.parseSquares(s)
  local out = {}
  for _, name in ipairs(words(s)) do
    out[Chess.sq(name:byte(1) - 97, name:byte(2) - 49)] = true
  end
  return out
end

-- Does the opponent (now to move in g) have a move that checkmates?
local function opponentCanMate(g)
  for _, m in ipairs(g.legal) do
    Chess.makeMove(g, m)
    local legal = Chess.legalMoves(g)
    local mate = #legal == 0 and Chess.inCheck(g)
    Chess.unmakeMove(g)
    if mate then return true end
  end
  return false
end

-- Was the player's move right? Called after the move was played on g.
-- k = which of the player's moves this is (1 for the first).
function Learn.isCorrect(step, k, g)
  local rec = g.played[#g.played]
  local m = rec.m
  if g.result == "checkmate" then return true end         -- a checkmate is always right
  local line = words(step.line)
  if #line > 0 then return Learn.uci(m) == line[2 * k - 1] end
  local accept = words(step.accept)
  if #accept > 0 then
    for _, u in ipairs(accept) do if u == Learn.uci(m) then return true end end
    return false
  end
  local moved = math.abs(g.board[m.to])
  local rule = step.rule
  if rule == "mate" then return false end
  if rule == "check" then return g.check end
  if rule == "capture" then return rec.cap ~= 0 end
  if rule == "king" then return moved == 6 end
  if rule == "block" then return moved ~= 6 and rec.cap == 0 end
  if rule == "castle" then return m.flag == 3 end
  if rule == "stopmate" then return not opponentCanMate(g) end
  return true
end

-- How many moves the player has to make in a find step
function Learn.playerMoves(step)
  local n = #words(step.line)
  if n == 0 then return 1 end
  return math.floor((n + 1) / 2)
end

---------------------------------------------------------------------------
-- Progress
---------------------------------------------------------------------------
function Learn.key(course, lesson) return course.id .. "/" .. lesson.id end

function Learn.load()
  local data = P.readFile(config.LEARN_FILE)
  if not data then return end
  for k in data:gmatch("[%w%-]+/[%w%-]+") do Learn.done[k] = true end
end

function Learn.save()
  local out = {}
  for k in pairs(Learn.done) do out[#out + 1] = k end
  table.sort(out)
  P.writeFile(config.LEARN_FILE, table.concat(out, "\n"))
end

function Learn.complete(course, lesson)
  Learn.done[Learn.key(course, lesson)] = true
  Learn.save()
end

function Learn.count(course)
  local n = 0
  for _, lesson in ipairs(course.lessons) do
    if Learn.done[Learn.key(course, lesson)] then n = n + 1 end
  end
  return n
end

return Learn
