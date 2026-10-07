-- trophies.lua - in-game achievements
--
-- Each trophy has a test over your saved stats, puzzle progress and lessons.
-- Trophies.check() unlocks any newly earned ones and returns them.

local stats = require("stats")
local Puzzles = require("puzzles")
local Learn = require("learn")

local Trophies = {}
local S = stats.data

local function wonAt(level)
  for lvl = level, 8 do
    local e = stats.levels[lvl]
    if e and e.w > 0 then return true end
  end
  return false
end

local function lessonsDone()
  local n = 0
  for _ in pairs(Learn.done) do n = n + 1 end
  return n
end

local function anyCourseDone()
  for _, c in ipairs(Learn.COURSES) do
    if Learn.count(c) == #c.lessons then return true end
  end
  return false
end

local function totalLessons()
  local n = 0
  for _, c in ipairs(Learn.COURSES) do n = n + #c.lessons end
  return n
end

Trophies.LIST = {
  { id = "first_game", name = "First Steps",      desc = "Finish your first game.",                  test = function() return S.games >= 1 end },
  { id = "first_win",  name = "Checkmate!",       desc = "Beat the computer for the first time.",    test = function() return wonAt(1) end },
  { id = "lv4",        name = "Climbing Up",      desc = "Beat the computer at Lv4 Intermediate.",   test = function() return wonAt(4) end },
  { id = "lv5",        name = "Club Player",      desc = "Beat the computer at Lv5 Club.",           test = function() return wonAt(5) end },
  { id = "lv6",        name = "Strong Club",      desc = "Beat the computer at Lv6 Strong Club.",    test = function() return wonAt(6) end },
  { id = "lv7",        name = "Expert Slayer",    desc = "Beat the computer at Lv7 Expert.",         test = function() return wonAt(7) end },
  { id = "lv8",        name = "Master Class",     desc = "Beat the computer at Lv8 Master.",         test = function() return wonAt(8) end },
  { id = "quick",      name = "Lightning Strike", desc = "Beat the computer in 20 moves or fewer.",  test = function() return S.quickWin > 0 end },
  { id = "clean",      name = "No Takebacks",     desc = "Beat Lv4 or higher without Undo or Hint.", test = function() return S.cleanWin > 0 end },
  { id = "timed",      name = "Beat the Clock",   desc = "Win a timed game against the computer.",   test = function() return S.timedWins > 0 end },
  { id = "streak",     name = "Hat Trick",        desc = "Beat the computer 3 games in a row.",      test = function() return S.bestStreak >= 3 end },
  { id = "draw",       name = "Hold the Line",    desc = "Draw against Lv5 or higher.",              test = function() return S.drawLv5 > 0 end },
  { id = "marathon",   name = "Marathon",         desc = "Finish a game of 80 moves or more.",       test = function() return S.longest >= 80 end },
  { id = "twoplayer",  name = "Friendly Match",   desc = "Finish a two-player game.",                test = function() return S.twoPlayer >= 1 end },
  { id = "queen",      name = "Queen Me",         desc = "Promote a pawn to a queen.",               test = function() return S.queens > 0 end },
  { id = "knight",     name = "Sneaky Knight",    desc = "Promote a pawn to a knight.",              test = function() return S.knights > 0 end },
  { id = "puzzle10",   name = "Puzzle Solver",    desc = "Solve 10 puzzles.",                        test = function() return Puzzles.progress.solved >= 10 end },
  { id = "puzzle100",  name = "Puzzle Master",    desc = "Solve 100 puzzles.",                       test = function() return Puzzles.progress.solved >= 100 end },
  { id = "pstreak",    name = "On a Roll",        desc = "Solve 10 puzzles in a row.",               test = function() return Puzzles.progress.best >= 10 end },
  { id = "rating1500", name = "Sharp Eye",        desc = "Reach a puzzle rating of 1500.",           test = function() return Puzzles.progress.rating >= 1500 end },
  { id = "rating2000", name = "Tactician",        desc = "Reach a puzzle rating of 2000.",           test = function() return Puzzles.progress.rating >= 2000 end },
  { id = "lesson",     name = "Student",          desc = "Complete your first lesson.",              test = function() return lessonsDone() >= 1 end },
  { id = "course",     name = "Scholar",          desc = "Complete a whole Learn course.",           test = anyCourseDone },
  { id = "graduate",   name = "Graduate",         desc = "Complete every lesson in Learn.",          test = function() return lessonsDone() >= totalLessons() end },
  { id = "style",      name = "Style Points",     desc = "Change both the board theme and piece set.", test = function() return S.styleTheme > 0 and S.stylePieces > 0 end },
}

function Trophies.count()
  local n = 0
  for _, t in ipairs(Trophies.LIST) do if stats.unlocked[t.id] then n = n + 1 end end
  return n
end

-- Unlock anything newly earned. Returns the list of new trophies.
function Trophies.check()
  local new = {}
  for _, t in ipairs(Trophies.LIST) do
    if not stats.unlocked[t.id] and t.test() then
      stats.unlocked[t.id] = true
      new[#new + 1] = t
    end
  end
  if #new > 0 then stats.save() end
  return new
end

return Trophies
