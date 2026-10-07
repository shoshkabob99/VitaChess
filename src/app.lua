-- app.lua - the game itself: screens, menus, playing a game, the main loop
--
-- Screens: "title" -> "setup" (vs computer) / "setup2" (two players) /
--          "puzzles" (puzzle menu) / "learn" (courses) / "course" (lessons) /
--          "settings" / "game"
-- The game screen also runs puzzles (G.mode == "puzzle") and lessons (G.mode == "lesson").

local P = require("platform")
local Chess = require("chess")
local AI = require("ai")
local Book = require("book")
local Puzzles = require("puzzles")
local Learn = require("learn")
local PGN = require("pgn")
local config = require("config")
local settings = require("settings")
local stats = require("stats")
local Trophies = require("trophies")
local ui = require("ui")

local app = {}
local floor, abs = math.floor, math.abs
local sq, fileOf, rankOf = Chess.sq, Chess.fileOf, Chess.rankOf
local C = ui.C
local opt = settings.values

local SQ, BX, BY = 64, 16, 16     -- square size and board top-left
local BOARD_PX = 8 * SQ
local PX = 568                    -- side panel left edge
local FLAG_CASTLE = 3

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local G = {                       -- everything about the current game
  game = nil, mode = "2p", aiSide = -1, level = 4, tc = 1, flipped = false,
  clock = nil,                    -- { time = { [1] = ms, [-1] = ms }, inc = ms, hist = {} }
  selected = nil, targets = {}, promo = nil, pause = nil, over = nil, confirm = nil,
  overAt = nil, overShown = false, recorded = false, pgnName = nil,
  aiCo = nil, aiMove = nil, aiStart = 0,
  hintCo = nil, hintMove = nil, hintSan = nil,
  anims = nil, toast = nil,
  puzzle = nil,                   -- puzzle mode state, see startPuzzle
  lesson = nil,                   -- lesson mode state, see startStep
  view = nil, viewGame = nil,     -- looking back at an earlier position (ply number)
  listTop = 1, follow = true,     -- move list scroll position
  shake = nil, capFly = nil,      -- check shake and captured-piece flight animations
}
local listDrag = nil
local cursor = { f = 4, r = 1, visible = false }
local drag = { on = false, moved = false, from = nil, x = 0, y = 0 }
local touch = { on = false, x = 0, y = 0 }
local screen = "title"
local lists = {}
local settingsReturn = "title"
local sounds = {}

local function playSound(name)
  if opt.sfxvol > 1 then P.playSound(sounds[name], settings.volume(opt.sfxvol)) end
end

-- Trophies: unlock anything newly earned and queue a banner for each
local trophyToasts = {}
local function awardTrophies()
  for _, t in ipairs(Trophies.check()) do
    trophyToasts[#trophyToasts + 1] = { trophy = t }
  end
end

local function humanTurn()
  if G.mode == "lesson" then
    local L = G.lesson
    return L.state == "play" and L.step.kind ~= "explain" and G.game.side == L.solver
  end
  if G.mode == "puzzle" then
    return G.puzzle.state == "play" and G.game.side == G.puzzle.solver
  end
  return not (G.mode == "ai" and G.game.side == G.aiSide)
end

local function showToast(text) G.toast = { text = text, untilT = P.now() + 2500 } end

---------------------------------------------------------------------------
-- Results
---------------------------------------------------------------------------
local RESULT_TEXT = {
  stalemate    = "Draw by stalemate",
  fifty        = "Draw by 50-move rule",
  repetition   = "Draw by repetition",
  material     = "Draw: insufficient material",
  agreed       = "Draw by agreement",
  timeout_draw = "Draw: time out, no mating material",
}

local function sideName(side) return (side == 1) and "White" or "Black" end

local function resultText(g)
  local r, w = g.result, g.winner
  if G.mode == "ai" and w then
    local youWin = (w ~= G.aiSide)
    if r == "checkmate" then return youWin and "Checkmate - You win!" or "Checkmate - Computer wins" end
    if r == "timeout" then return youWin and "You win on time!" or "Computer wins on time" end
    if r == "resign" then return youWin and "Computer resigns - You win!" or "You resigned" end
  elseif w then
    if r == "checkmate" then return "Checkmate - " .. sideName(w) .. " wins!" end
    if r == "timeout" then return sideName(w) .. " wins on time" end
    if r == "resign" then return sideName(-w) .. " resigns - " .. sideName(w) .. " wins" end
  end
  return RESULT_TEXT[r] or ""
end

local function resultScore(g)
  if not g.result then return "*" end
  if g.winner == 1 then return "1-0" elseif g.winner == -1 then return "0-1" end
  return "1/2-1/2"
end

---------------------------------------------------------------------------
-- Save / load
-- "v3 mode=ai level=3 side=1 tc=3 wt=123000 bt=98000 [end=resign:1] from:to:promo ..."
---------------------------------------------------------------------------
local function saveGame()
  local g = G.game
  if not g or G.mode == "puzzle" or G.mode == "lesson" then return end
  local parts = { "v3", "mode=" .. G.mode, "level=" .. G.level, "side=" .. G.aiSide, "tc=" .. G.tc }
  if G.clock then
    parts[#parts + 1] = "wt=" .. floor(G.clock.time[1])
    parts[#parts + 1] = "bt=" .. floor(G.clock.time[-1])
  end
  if g.result == "resign" or g.result == "timeout" or g.result == "timeout_draw" or g.result == "agreed" then
    parts[#parts + 1] = "end=" .. g.result .. ":" .. (g.winner or 0)
  end
  for _, rec in ipairs(g.played) do
    parts[#parts + 1] = rec.m.from .. ":" .. rec.m.to .. ":" .. rec.m.promo
  end
  P.writeFile(config.SAVE_FILE, table.concat(parts, " "))
end

-- Returns { mode, level, aiSide, tc, wt, bt, game } or nil if there's no valid save.
-- Also reads the older v1 (moves only) and v2 formats.
local function readSave()
  local data = P.readFile(config.SAVE_FILE)
  if not data then return nil end
  local toks = {}
  for t in data:gmatch("%S+") do toks[#toks + 1] = t end
  local meta = { mode = "2p", level = 4, aiSide = -1, tc = 1 }
  local moves, kv = {}, {}
  if toks[1] == "v2" then
    kv.mode, kv.level, kv.side = toks[2], toks[3], toks[4]
    for j = 5, #toks do moves[#moves + 1] = toks[j] end
  else
    for _, t in ipairs(toks) do
      local k, v = t:match("^(%a+)=(%S+)$")
      if k then kv[k] = v elseif t ~= "v3" then moves[#moves + 1] = t end
    end
  end
  meta.mode = (kv.mode == "ai") and "ai" or "2p"
  meta.level = math.max(1, math.min(#AI.LEVELS, tonumber(kv.level) or 4))
  meta.aiSide = (tonumber(kv.side) == 1) and 1 or -1
  meta.tc = math.max(1, math.min(#config.TIME_CONTROLS, tonumber(kv.tc) or 1))
  meta.wt, meta.bt = tonumber(kv.wt), tonumber(kv.bt)
  local ok, g = pcall(function()
    local g = Chess.newGame()
    for _, tok in ipairs(moves) do
      local f, t, p = tok:match("^(%d+):(%d+):(%d+)$")
      local m = Chess.findMove(g, tonumber(f), tonumber(t), tonumber(p))
      if not m then error("bad save") end
      Chess.play(g, m)
    end
    return g
  end)
  if not ok then return nil end
  if kv["end"] then
    local reason, w = kv["end"]:match("^([%a_]+):(%-?%d)$")
    if reason then g.result = reason; g.winner = (tonumber(w) ~= 0) and tonumber(w) or nil end
  end
  meta.game = g
  return meta
end

---------------------------------------------------------------------------
-- Board geometry
---------------------------------------------------------------------------
local function squareXY(s)
  local f, r = fileOf(s), rankOf(s)
  if G.flipped then return BX + (7 - f) * SQ, BY + r * SQ end
  return BX + f * SQ, BY + (7 - r) * SQ
end

local function screenToSquare(x, y)
  if not ui.inside(x, y, BX, BY, BOARD_PX, BOARD_PX) then return nil end
  local col, row = floor((x - BX) / SQ), floor((y - BY) / SQ)
  if G.flipped then return sq(7 - col, row) end
  return sq(col, 7 - row)
end

---------------------------------------------------------------------------
-- Clock
---------------------------------------------------------------------------
local function newClock(tcIndex)
  local tc = config.TIME_CONTROLS[tcIndex]
  if not tc or not tc.base then return nil end
  return { time = { [1] = tc.base * 1000, [-1] = tc.base * 1000 }, inc = tc.inc * 1000, hist = {} }
end

local function fmtClock(ms)
  if ms < 10000 then return string.format("%.1f", math.max(0, ms) / 1000) end
  local s = math.ceil(ms / 1000)
  return string.format("%d:%02d", floor(s / 60), s % 60)
end

---------------------------------------------------------------------------
-- Game actions
---------------------------------------------------------------------------
local function clearSelection() G.selected, G.targets = nil, {} end

local function stopThinking()
  if G.aiCo or G.hintCo then AI.abort() end
  G.aiCo, G.aiMove, G.hintCo = nil, nil, nil
end

local function autoFlip()
  if G.mode == "2p" and opt.autoflip then G.flipped = (G.game.side == -1) end
end

local function exportPGN()
  local g = G.game
  local d = P.date()
  local names = { [1] = "White", [-1] = "Black" }
  if G.mode == "ai" then
    names[G.aiSide] = "Computer (Lv" .. G.level .. " " .. AI.LEVELS[G.level].name .. ")"
    names[-G.aiSide] = "Player"
  end
  local tc = config.TIME_CONTROLS[G.tc]
  local text = PGN.build(g, {
    white = names[1], black = names[-1],
    date = d and string.format("%04d.%02d.%02d", d.year, d.month, d.day),
    result = resultScore(g), termination = resultText(g),
    timeControl = tc.base and (tc.base .. "+" .. tc.inc) or nil,
  })
  local stamp = d and string.format("%04d%02d%02d-%02d%02d%02d", d.year, d.month, d.day, d.hour, d.min, d.sec)
                  or tostring(P.now())
  G.pgnName = "game-" .. stamp .. ".pgn"
  P.writeFile(config.GAMES_DIR .. "/" .. G.pgnName, text)
end

-- Called once whenever a game finishes, however it finished
local function onGameEnd()
  local g = G.game
  stopThinking()
  G.promo = nil
  clearSelection()
  playSound("end")
  G.overAt = P.now() + 900
  if not G.recorded then
    G.recorded = true
    local human = -G.aiSide
    stats.recordGame({
      mode = G.mode, level = G.level, moves = math.ceil(#g.played / 2),
      outcome = (g.winner == nil) and "d" or ((g.winner == G.aiSide) and "l" or "w"),
      assisted = G.assisted, timed = G.clock ~= nil,
      firstMove = (G.mode == "ai" and human == 1 and g.played[1]) and g.played[1].san or nil,
      firstReply = (G.mode == "ai" and human == -1 and g.played[2]) and g.played[2].san or nil,
    })
    awardTrophies()
    exportPGN()
  end
  saveGame()
end

-- End the game for a reason the rules engine doesn't detect itself
local function finishGame(reason, winner)
  G.game.result, G.game.winner = reason, winner
  onGameEnd()
end

local function selectSquare(s)
  clearSelection()
  local g = G.game
  local p = g.board[s]
  if (g.result and G.mode ~= "lesson") or not humanTurn() or p == 0 or (p > 0) ~= (g.side > 0) then
    return false
  end
  G.selected = s
  for _, m in ipairs(g.legal) do
    if m.from == s and abs(g.board[m.to]) ~= 6 then     -- (kings are never captured)
      G.targets[m.to] = G.targets[m.to] or {}
      table.insert(G.targets[m.to], m)
    end
  end
  return true
end

-- Slide the moved piece (and the rook, when castling) to its new square
local function startAnim(m)
  if not opt.anim then G.anims = nil; return end
  local t, b = P.now(), G.game.board
  local function slide(from, to)
    local fx, fy = squareXY(from)
    local tx, ty = squareXY(to)
    return { piece = b[to], fx = fx, fy = fy, tx = tx, ty = ty, sq = to, start = t }
  end
  G.anims = { slide(m.from, m.to) }
  if m.flag == FLAG_CASTLE then
    if m.to > m.from then G.anims[2] = slide(m.from + 3, m.from + 1)
    else G.anims[2] = slide(m.from - 4, m.from - 1) end
  end
end

---------------------------------------------------------------------------
-- Looking back through the game (tap a move, or L / R)
---------------------------------------------------------------------------
-- ply = number of moves played in the position to show; nil or the latest = live
local function setView(ply)
  local g = G.game
  if not ply or ply >= #g.played then
    G.view, G.viewGame = nil, nil
    return
  end
  ply = math.max(0, ply)
  local v = Chess.newGame()
  for i = 1, ply do Chess.play(v, Chess.findMove(v, g.played[i].m.from, g.played[i].m.to, g.played[i].m.promo)) end
  G.view, G.viewGame = ply, v
  G.selected, G.targets = nil, {}
  -- keep the viewed move visible in the list
  local pair = math.max(1, math.ceil(ply / 2))
  if pair < G.listTop then G.listTop = pair end
  if pair > G.listTop + 7 then G.listTop = pair - 7 end
  G.follow = false
end

local function goLive()
  G.view, G.viewGame, G.follow = nil, nil, true
end

local puzzleUserMoved   -- defined in the puzzle section below
local lessonUserMoved   -- defined in the lesson section below

-- scripted = a move played by the puzzle itself (not by the player)
local function commitMove(m, noAnim, scripted)
  local g = G.game
  G.promo = nil
  G.hintCo, G.hintMove, G.hintSan = nil, nil, nil
  local mover = g.side
  if G.clock then
    G.clock.hist[#G.clock.hist + 1] = { G.clock.time[1], G.clock.time[-1] }
  end
  Chess.play(g, m)
  if G.clock then G.clock.time[mover] = G.clock.time[mover] + G.clock.inc end
  if m.promo ~= 0 and not scripted and not (G.mode == "ai" and mover == G.aiSide) then
    if m.promo == 5 then stats.bump("queens") elseif m.promo == 2 then stats.bump("knights") end
    awardTrophies()
  end
  clearSelection()
  autoFlip()
  if noAnim then G.anims = nil else startAnim(m) end
  if g.check then G.shake = { sq = g.kingSq[g.side], start = P.now() } end
  local rec = g.played[#g.played]
  if rec.cap ~= 0 and (G.mode == "ai" or G.mode == "2p") then
    local x, y = squareXY(m.flag == 2 and (m.to + 10 * mover) or m.to)
    G.capFly = { piece = rec.cap, side = mover, x = x, y = y, start = P.now(), ply = #g.played }
  end
  if G.mode == "ai" or G.mode == "2p" then G.view, G.viewGame, G.follow = nil, nil, true end
  if G.mode == "puzzle" or G.mode == "lesson" then
    if g.check then playSound("check")
    elseif g.played[#g.played].cap ~= 0 then playSound("capture")
    else playSound("move") end
    if not scripted then
      if G.mode == "puzzle" then puzzleUserMoved(m) else lessonUserMoved(m) end
    end
    return
  end
  if g.result then
    onGameEnd()
    return
  end
  if g.check then playSound("check")
  elseif g.played[#g.played].cap ~= 0 then playSound("capture")
  else playSound("move") end
  saveGame()
end

local function tryMoveTo(s, noAnim)
  local ms = G.targets[s]
  if not ms then return false end
  if #ms > 1 then G.promo = { moves = ms, index = 1 }   -- promotion: Q, R, B, N
  else commitMove(ms[1], noAnim) end
  return true
end

local function activateSquare(s)
  if G.selected and G.targets[s] then tryMoveTo(s); return end
  if G.selected == s then clearSelection(); return end
  if not selectSquare(s) then clearSelection() end
end

local function undoOne()
  local g = G.game
  if #g.played == 0 then return false end
  Chess.undo(g)
  if G.clock and #G.clock.hist > 0 then
    local h = table.remove(G.clock.hist)
    G.clock.time[1], G.clock.time[-1] = h[1], h[2]
  end
  return true
end

local function doUndo()
  if G.view then goLive(); return end       -- in history view, the first button means "Live"
  G.assisted = true
  stopThinking()
  G.promo, G.over, G.hintMove, G.hintSan, G.anims = nil, nil, nil, nil, nil
  clearSelection()
  local g = G.game
  if not undoOne() then return end
  -- against the computer, take back its reply too
  if G.mode == "ai" and g.side == G.aiSide and #g.played > 0 then undoOne() end
  autoFlip()
  G.overShown = g.result ~= nil
  saveGame()
end

local function requestHint()
  local g = G.game
  if g.result or G.hintCo or G.aiCo or not humanTurn() then return end
  G.assisted = true
  G.hintMove, G.hintSan = nil, nil
  local snap = Chess.clone(g)
  G.hintCo = coroutine.create(function() return AI.think(snap, AI.HINT, true) end)
end

local function confirm(title, onYes)
  local L = ui.centerList({
    { label = "Yes", activate = function() G.confirm = nil; onYes() end },
    { label = "No", activate = function() G.confirm = nil end },
  }, 340, 46, 56)
  L.index = 2
  L.back = function() G.confirm = nil end
  G.confirm = { title = title, list = L }
end

local function offerDraw()
  local g = G.game
  G.pause = nil
  if g.result then return end
  if G.mode == "2p" then
    confirm("Both players agree to a draw?", function() finishGame("agreed", nil) end)
    return
  end
  -- the computer accepts if it isn't better, or if it's clearly losing
  local eval = g.score * G.aiSide
  if (#g.played >= 20 and eval <= 20) or eval <= -150 then
    finishGame("agreed", nil)
  else
    showToast("The computer declines the draw")
  end
end

local function resign()
  local g = G.game
  G.pause = nil
  if g.result then return end
  local loser = (G.mode == "ai") and -G.aiSide or g.side
  local q = (G.mode == "ai") and "Resign this game?" or (sideName(loser) .. " resigns?")
  confirm(q, function() finishGame("resign", -loser) end)
end

---------------------------------------------------------------------------
-- Puzzles
-- G.puzzle = { p = puzzle, idx = next move in p.moves, solver = side,
--   state = "intro" | "play" | "wrong" | "reply" | "solved" | "showing" | "done",
--   t = when the next automatic step happens, failed, assisted, recorded,
--   hintLevel, delta = rating change }
---------------------------------------------------------------------------
local PROMO_CHAR = { [2] = "n", [3] = "b", [4] = "r", [5] = "q" }
local function uci(m) return Chess.sqName(m.from) .. Chess.sqName(m.to) .. (PROMO_CHAR[m.promo] or "") end

local function recordPuzzle(success, rated)
  local Z = G.puzzle
  if Z.recorded then return end
  Z.recorded = true
  Z.delta = Puzzles.finish(Z.p, success, rated)
  awardTrophies()
end

puzzleUserMoved = function(m)
  local Z, g = G.puzzle, G.game
  local correct = uci(m) == Z.p.moves[Z.idx] or g.result == "checkmate"   -- any mate counts
  Z.hintLevel = 0
  if not correct then
    Z.state, Z.t = "wrong", P.now() + 700
    Z.failed = true
    recordPuzzle(false)
    return
  end
  Z.idx = Z.idx + 1
  if Z.idx > #Z.p.moves or g.result then
    Z.state = "solved"
    recordPuzzle(true, not Z.assisted)
    playSound("end")
  else
    Z.state, Z.t = "reply", P.now() + 450
  end
end

-- Runs every frame: plays the opponent's replies, takes back wrong moves,
-- and steps through the solution when it's being shown
local function updatePuzzle()
  local Z = G.puzzle
  if G.mode ~= "puzzle" or not Z or G.pause or G.confirm then return end
  local now = P.now()
  if now < (Z.t or 0) then return end
  if Z.state == "intro" or Z.state == "reply" or Z.state == "showing" then
    local m = Puzzles.toMove(G.game, Z.p.moves[Z.idx])
    Z.idx = Z.idx + 1
    if m then commitMove(m, false, true) end
    if Z.idx > #Z.p.moves then Z.state = "done"
    elseif Z.state == "showing" then Z.t = now + 900
    else Z.state = "play" end
  elseif Z.state == "wrong" then
    Chess.undo(G.game)
    G.anims = nil
    Z.state = "play"
  end
end

local function puzzleHint()
  local Z = G.puzzle
  if Z.state ~= "play" then return end
  local m = Puzzles.toMove(G.game, Z.p.moves[Z.idx])
  if not m then return end
  Z.assisted = true
  Z.hintLevel = math.min(2, (Z.hintLevel or 0) + 1)
  -- first press: the piece to move; second press: the whole move
  G.hintMove = (Z.hintLevel == 1) and { from = m.from, to = m.from } or { from = m.from, to = m.to }
end

local function puzzleSolution()
  local Z = G.puzzle
  if Z.state ~= "play" and Z.state ~= "wrong" then return end
  if Z.state == "wrong" then Chess.undo(G.game); G.anims = nil end
  Z.failed = true
  recordPuzzle(false)
  clearSelection()
  G.hintMove = nil
  Z.state, Z.t = "showing", P.now() + 300
end

local setupGame   -- defined just below

local function startPuzzle(p, retry)
  p = p or Puzzles.pick(opt.pband)
  if not p then showToast("No puzzles found"); return end
  local g = Chess.fromFEN(p.fen)
  setupGame({ mode = "puzzle", game = g, level = G.level, aiSide = -1, tc = 1 })
  G.puzzle = { p = p, idx = 1, solver = -g.side, state = "intro", t = P.now() + 700,
               failed = false, assisted = false, recorded = retry or false, hintLevel = 0 }
  G.flipped = (G.puzzle.solver == -1)
  cursor.f, cursor.r = 4, G.flipped and 6 or 1
end

-- Leaving a puzzle before it's finished counts as an unrated miss (resets the streak)
local function abandonPuzzle()
  local Z = G.puzzle
  if G.mode == "puzzle" and Z and not Z.recorded then recordPuzzle(false, false) end
end

local function nextPuzzle()
  abandonPuzzle()
  G.pause = nil
  startPuzzle()
end

---------------------------------------------------------------------------
-- Lessons (the Learn section; content in lessons.lua)
-- G.lesson = { ci, li, si = course/lesson/step numbers, course, lesson, step,
--   solver = the player's side, state = "intro" | "play" | "wrong" | "reply" | "done",
--   t = time of the next automatic step, k = which player move is next,
--   lineIdx = next move in step.line, intro = intro moves still to play,
--   stars = targets left, marks, msg = feedback text, wrongs }
---------------------------------------------------------------------------
local MARK_COLORS = { g = "markG", r = "markR", b = "markB", y = "markY" }
local openCourse    -- defined with the menus

local function lessonMsg(text, color) G.lesson.msg, G.lesson.msgColor = text, color end

-- The computer's strength when defending in endgame drills
local DRILL_AI = { depth = 6, q = true, noise = 0, random = 0, time = 700 }

-- Guided openings: show the next move. Yours is highlighted; the
-- opponent's is played automatically a moment later.
local function guideAdvance()
  local L, g = G.lesson, G.game
  local mv = L.step.moves[L.gi]
  G.hintMove, L.mySan, L.myText = nil, nil, nil
  if not mv then
    L.state = "done"
    lessonMsg(L.step.done or "Well played!", C.good)
    playSound("end")
    return
  end
  local m = Learn.toMove(g, mv[1])
  local san = m and Chess.san(g, m, g.legal) or mv[1]
  if g.side == L.solver then
    L.mySan, L.myText = san, mv[2]
    L.guideHint = m and { from = m.from, to = m.to }
    G.hintMove = L.guideHint
    L.state = "play"
  else
    L.pendingSan, L.pendingText = san, mv[2]
    L.state, L.t = "reply", P.now() + 900
  end
end

local function hasQueen(g, side)
  for s = 21, 98 do if g.board[s] == 5 * side then return true end end
  return false
end

local function drillFail(text)
  local L = G.lesson
  L.state = "failed"
  lessonMsg(text .. " Press Cross to try again.", C.red)
end

-- Endgame drills: has the goal been reached, or the attempt failed?
-- Returns true when the drill is over.
local function checkDrill()
  local L, g = G.lesson, G.game
  if g.result == "checkmate" and g.winner == L.solver then
    L.state = "done"
    lessonMsg(L.step.done or "Well done!", C.good)
    playSound("end")
    return true
  end
  if g.result == "stalemate" then drillFail("Stalemate! The king had no legal move, so it's a draw."); return true end
  if g.result then drillFail("The game was drawn."); return true end
  if g.side == L.solver then           -- after the computer's reply
    if L.step.goal == "promote" and L.promoted then
      if hasQueen(g, L.solver) then
        L.state = "done"
        lessonMsg(L.step.done or "Well done!", C.good)
        playSound("end")
      else
        drillFail("The new piece didn't survive (or wasn't a queen).")
      end
      return true
    end
    if L.k >= L.step.limit then drillFail("Out of moves!"); return true end
  end
  return false
end

local function startStep(ci, li, si)
  local course = Learn.COURSES[ci]
  local lesson = course.lessons[li]
  local step = lesson.steps[si]
  local g = Chess.fromFEN(step.fen)
  setupGame({ mode = "lesson", game = g, level = G.level, aiSide = -1, tc = 1 })
  local L = { ci = ci, li = li, si = si, course = course, lesson = lesson, step = step,
              k = 1, lineIdx = 1, wrongs = 0, intro = Learn.words(step.intro), marks = {},
              stars = Learn.parseSquares(step.stars) }
  G.lesson = L
  L.solver = (#L.intro % 2 == 0) and g.side or -g.side     -- whose turn after the intro
  for _, mk in ipairs(Learn.parseMarks(step.marks)) do
    L.marks[#L.marks + 1] = { sq = mk.sq, color = C[MARK_COLORS[mk.color] or "markY"] }
  end
  if step.kind == "explain" then
    L.state = "done"
    G.flipped = step.flip or false
  elseif step.kind == "guide" then
    L.solver = (step.side == "b") and -1 or 1
    G.flipped = (L.solver == -1)
    L.gi = 1
    guideAdvance()
  elseif step.kind == "play" then
    L.solver = g.side
    G.flipped = (L.solver == -1)
    L.state, L.k = "play", 0          -- k = moves made so far
  else
    G.flipped = (L.solver == -1)
    if #L.intro > 0 then L.state, L.t = "intro", P.now() + 700 else L.state = "play" end
  end
  cursor.f, cursor.r = 4, G.flipped and 6 or 1
end

lessonUserMoved = function(m)
  local L, g = G.lesson, G.game
  local step = L.step
  if step.kind == "guide" then
    if Learn.uci(m) == step.moves[L.gi][1] then
      L.gi = L.gi + 1
      L.msg = nil
      guideAdvance()
    else
      L.state, L.t = "wrong", P.now() + 900
      lessonMsg("Play the highlighted move: " .. (L.mySan or ""), C.red)
    end
    return
  end
  if step.kind == "play" then
    L.k = L.k + 1
    if m.promo ~= 0 then L.promoted = true end
    if not checkDrill() then L.state, L.t = "think", P.now() + 400 end
    return
  end
  if step.kind == "targets" then
    L.stars[m.to] = nil
    if next(L.stars) == nil then
      L.state = "done"
      lessonMsg(step.done or "Well done!", C.good)
      playSound("end")
    else
      -- hand the move straight back to the player for the next star
      G.game = Chess.fromFEN(Chess.toFEN(g, L.solver))
    end
    return
  end
  if Learn.isCorrect(step, L.k, g) then
    L.k, L.lineIdx = L.k + 1, L.lineIdx + 1
    if L.lineIdx <= #Learn.words(step.line) and not g.result then
      L.state, L.t = "reply", P.now() + 550
      lessonMsg("Good move!", C.good)
    else
      L.state = "done"
      lessonMsg(step.done or "Correct!", C.good)
      playSound("end")
    end
  else
    L.wrongs = L.wrongs + 1
    L.state, L.t = "wrong", P.now() + 900
    lessonMsg(step.wrong or "Not quite. Try again!", C.red)
  end
end

-- Every frame: intro moves, the opponent's scripted replies, taking back wrong moves
local function updateLesson()
  local L = G.lesson
  if G.mode ~= "lesson" or not L or G.pause then return end
  local now = P.now()
  if now < (L.t or 0) then return end
  if L.state == "intro" then
    local u = table.remove(L.intro, 1)
    local m = u and Learn.toMove(G.game, u)
    if m then commitMove(m, false, true) end
    if #L.intro > 0 then L.t = now + 700 else L.state = "play" end
  elseif L.state == "reply" and L.step.kind == "guide" then
    local m = Learn.toMove(G.game, L.step.moves[L.gi][1])
    if m then commitMove(m, false, true) end
    L.oppSan, L.oppText = L.pendingSan, L.pendingText
    L.gi = L.gi + 1
    guideAdvance()
  elseif L.state == "reply" then
    local m = Learn.toMove(G.game, Learn.words(L.step.line)[L.lineIdx])
    L.lineIdx = L.lineIdx + 1
    if m then commitMove(m, false, true) end
    L.state = "play"
  elseif L.state == "think" then
    -- the computer defends in an endgame drill (thinking a slice per frame)
    if not L.co then
      local snap = Chess.clone(G.game)
      L.co = coroutine.create(function() return AI.think(snap, DRILL_AI, true) end)
    end
    local ok, res = coroutine.resume(L.co)
    if not ok then error(res) end
    if coroutine.status(L.co) == "dead" then
      L.co = nil
      local m = res and Chess.findMove(G.game, res.from, res.to, res.promo)
      if m then commitMove(m, false, true) end
      if not checkDrill() then L.state = "play" end
    end
  elseif L.state == "wrong" then
    Chess.undo(G.game)
    G.anims = nil
    L.state = "play"
    if L.step.kind == "guide" then G.hintMove = L.guideHint end
    if L.wrongs >= 2 and L.step.hint then lessonMsg("Hint: " .. L.step.hint, C.accent) end
  end
end

local function lessonHint()
  local L = G.lesson
  if L.state ~= "play" then return end
  lessonMsg("Hint: " .. (L.step.hint or "Look at every check and capture first."), C.accent)
  local u = Learn.words(L.step.line)[L.lineIdx]
  local m = u and Learn.toMove(G.game, u)
  if m then G.hintMove = { from = m.from, to = m.from } end
end

local function lessonNext()
  local L = G.lesson
  if L.state == "failed" then startStep(L.ci, L.li, L.si); return end
  if L.state ~= "done" then return end
  if L.si < #L.lesson.steps then startStep(L.ci, L.li, L.si + 1); return end
  Learn.complete(L.course, L.lesson)
  awardTrophies()
  if L.li < #L.course.lessons then
    startStep(L.ci, L.li + 1, 1)
    lessonMsg("Lesson complete! Next up: " .. G.lesson.lesson.title, C.good)
  else
    openCourse(L.ci)
  end
end

local function lessonBack()
  local L = G.lesson
  if L.si > 1 then startStep(L.ci, L.li, L.si - 1) end
end

setupGame = function(meta)
  stopThinking()
  G.game, G.mode = meta.game, meta.mode
  G.level, G.aiSide, G.tc = meta.level or opt.level, meta.aiSide or -1, meta.tc or 1
  G.clock = newClock(G.tc)
  if G.clock and meta.wt and meta.bt then G.clock.time[1], G.clock.time[-1] = meta.wt, meta.bt end
  G.flipped = (G.mode == "ai" and G.aiSide == 1)
  autoFlip()
  G.promo, G.pause, G.over, G.confirm, G.overAt, G.anims, G.toast = nil, nil, nil, nil, nil, nil, nil
  G.overShown = G.game.result ~= nil
  G.recorded = G.game.result ~= nil
  G.hintMove, G.hintSan, G.pgnName = nil, nil, nil
  G.puzzle, G.lesson = nil, nil
  G.assisted = false
  G.view, G.viewGame, G.listTop, G.follow, G.shake, G.capFly = nil, nil, 1, true, nil, nil
  clearSelection()
  cursor.visible = false
  cursor.f, cursor.r = 4, G.flipped and 6 or 1
  screen = "game"
end

local function startGame(mode)
  local aiSide = -1
  if mode == "ai" then
    local c = opt.color
    if c == 3 then c = math.random(2) end
    aiSide = (c == 1) and -1 or 1      -- you play White -> computer plays Black
  end
  setupGame({ mode = mode, game = Chess.newGame(), level = opt.level, aiSide = aiSide, tc = opt.tc })
  saveGame()
end

---------------------------------------------------------------------------
-- Menus
---------------------------------------------------------------------------
local buildTitle   -- defined below (goTitle needs it)

local function goTitle()
  stopThinking()
  abandonPuzzle()
  saveGame()
  buildTitle()
  screen = "title"
end

local function openSettings(from)
  settingsReturn = from
  lists.settings.index = 1
  screen = "settings"
end

buildTitle = function()
  local rows = {}
  local sv = readSave()
  if sv and not sv.game.result and #sv.game.played > 0 then
    local what = (sv.mode == "ai") and ("vs Computer Lv" .. sv.level) or "Two Players"
    rows[#rows + 1] = { label = "Continue  (" .. what .. ")", activate = function() setupGame(sv) end }
  end
  rows[#rows + 1] = { label = "Play vs Computer", activate = function()
    lists.setup.index = 1; screen = "setup" end }
  rows[#rows + 1] = { label = "Two Players", activate = function()
    lists.setup2.index = 1; screen = "setup2" end }
  rows[#rows + 1] = { label = "Puzzles", activate = function()
    lists.puzzles.index = 1; screen = "puzzles" end }
  rows[#rows + 1] = { label = "Learn", activate = function() screen = "learn" end }
  rows[#rows + 1] = { label = "Stats & Trophies", activate = function()
    lists.trophies.index = 1; screen = "trophies" end }
  rows[#rows + 1] = { label = "Settings", activate = function() openSettings("title") end }
  rows[#rows + 1] = { label = "Exit", activate = function() P.exit() end }
  local step = (#rows > 7) and 45 or 50
  lists.title = ui.makeList(rows, 540, 150, 370, (#rows > 7) and 38 or 42, step)
end

local function toggleRow(label, key, onChange)
  return { label = label, value = function() return opt[key] and "On" or "Off" end,
           change = function() opt[key] = not opt[key]; if onChange then onChange() end end }
end

openCourse = function(ci)
  local course = Learn.COURSES[ci]
  local rows, first = {}, nil
  for li, lesson in ipairs(course.lessons) do
    local key = Learn.key(course, lesson)
    if not first and not Learn.done[key] then first = li end
    rows[#rows + 1] = { left = true, label = li .. ".  " .. lesson.title, rightColor = C.good,
      right = function() return Learn.done[key] and "Done" or "" end,
      activate = function() startStep(ci, li, 1) end }
  end
  rows[#rows + 1] = { label = "Back", activate = function() screen = "learn" end }
  lists.course = ui.makeList(rows, 150, 100, 660, 44, 52, 7)
  lists.course.index = first or 1
  lists.course.back = function() screen = "learn" end
  lists.course.course = course
  G.pause = nil
  screen = "course"
end

local function buildMenus()
  local function back() settings.save(); screen = "title" end
  local clockRow = { label = "Clock", value = function() return config.TIME_CONTROLS[opt.tc].name end,
    change = function(d) opt.tc = ui.wrap(opt.tc + d, #config.TIME_CONTROLS) end }

  lists.setup = ui.makeList({
    { label = "Difficulty", value = function() return "Lv" .. opt.level .. "  " .. AI.LEVELS[opt.level].name end,
      change = function(d) opt.level = ui.wrap(opt.level + d, #AI.LEVELS) end },
    { label = "Play as", value = function() return config.COLOR_NAMES[opt.color] end,
      change = function(d) opt.color = ui.wrap(opt.color + d, #config.COLOR_NAMES) end },
    clockRow,
    { label = "Start Game", activate = function() settings.save(); startGame("ai") end },
    { label = "Back", activate = back },
  }, 150, 112, 660, 46, 56)
  lists.setup.back = back

  lists.setup2 = ui.makeList({
    clockRow,
    toggleRow("Auto-flip board", "autoflip"),
    { label = "Start Game", activate = function() settings.save(); startGame("2p") end },
    { label = "Back", activate = back },
  }, 150, 112, 660, 46, 56)
  lists.setup2.back = back

  lists.puzzles = ui.makeList({
    { label = "Start Puzzles", activate = function() settings.save(); startPuzzle() end },
    { label = "Difficulty", value = function()
        local b = Puzzles.BANDS[opt.pband]
        return b.min and string.format("%s  %d-%d", b.name, b.min, math.min(b.max, 2900)) or b.name
      end,
      change = function(d) opt.pband = ui.wrap(opt.pband + d, #Puzzles.BANDS) end },
    { label = "Back", activate = back },
  }, 150, 112, 660, 46, 56)
  lists.puzzles.back = back

  local trophyRows = {}
  local icons = {}
  local function icon(name)
    if icons[name] == nil then icons[name] = P.loadImage(config.ASSET_DIR .. "art/" .. name .. ".png") or false end
    return icons[name]
  end
  for _, t in ipairs(Trophies.LIST) do
    trophyRows[#trophyRows + 1] = { label = t.name, desc = t.desc,
      icon = function() return icon(stats.unlocked[t.id] and "trophy" or "trophy-locked") end,
      color = function() return stats.unlocked[t.id] and C.accent or C.dim end }
  end
  lists.trophies = ui.makeList(trophyRows, 460, 100, 450, 54, 58, 7)
  lists.trophies.back = back

  local rows = {}
  for ci, course in ipairs(Learn.COURSES) do
    rows[#rows + 1] = { left = true, label = course.title, activate = function() openCourse(ci) end,
      right = function() return Learn.count(course) .. " / " .. #course.lessons end }
  end
  rows[#rows + 1] = { label = "Back", activate = back }
  lists.learn = ui.makeList(rows, 60, 112, 470, 46, 54)
  lists.learn.back = back

  local function leaveSettings()
    settings.save()
    G.pause = nil
    screen = settingsReturn
  end
  lists.settings = ui.makeList({
    { label = "Board theme", value = function() return ui.theme().name end,
      change = function(d)
        opt.theme = ui.wrap(opt.theme + d, #config.THEMES)
        if stats.data.styleTheme == 0 then stats.bump("styleTheme"); awardTrophies() end
      end },
    { label = "Piece set", value = function() return config.PIECE_SETS[opt.pieces].name end,
      change = function(d)
        opt.pieces = ui.wrap(opt.pieces + d, #config.PIECE_SETS)
        if stats.data.stylePieces == 0 then stats.bump("stylePieces"); awardTrophies() end
      end },
    { label = "Menu background", value = function() return ui.MENU_BACKGROUNDS[opt.menubg] end,
      change = function(d) opt.menubg = ui.wrap(opt.menubg + d, #ui.MENU_BACKGROUNDS) end },
    toggleRow("Show legal moves", "legal"),
    toggleRow("Highlight last move", "last"),
    toggleRow("Board coordinates", "coords"),
    toggleRow("Piece animation", "anim"),
    toggleRow("Auto-flip (2 players)", "autoflip", function() if G.game then autoFlip() end end),
    { label = "Sound volume", value = function() return settings.VOLUME_NAMES[opt.sfxvol] end,
      change = function(d) opt.sfxvol = ui.wrap(opt.sfxvol + d, 5); playSound("move") end },
    { label = "Back", activate = leaveSettings },
  }, 32, 84, 580, 36, 42, 10)
  lists.settings.back = leaveSettings

  lists.pause = ui.centerList({
    { label = "Resume", activate = function() G.pause = nil end },
    { label = "Offer Draw", activate = offerDraw },
    { label = "Resign", activate = resign },
    { label = "Restart", activate = function() startGame(G.mode) end },
    { label = "Settings", activate = function() openSettings("game") end },
    { label = "Main Menu", activate = function() goTitle() end },
  }, 340, 42, 52)
  lists.pause.back = function() G.pause = nil end

  lists.ppause = ui.centerList({
    { label = "Resume", activate = function() G.pause = nil end },
    { label = "Try Again", activate = function()
        G.pause = nil; abandonPuzzle(); startPuzzle(G.puzzle.p, true) end },
    { label = "Next Puzzle", activate = nextPuzzle },
    { label = "Settings", activate = function() openSettings("game") end },
    { label = "Main Menu", activate = function() goTitle() end },
  }, 340, 44, 54)
  lists.ppause.back = function() G.pause = nil end

  lists.lpause = ui.centerList({
    { label = "Resume", activate = function() G.pause = nil end },
    { label = "Restart Step", activate = function()
        local L = G.lesson; startStep(L.ci, L.li, L.si) end },
    { label = "Lesson List", activate = function() openCourse(G.lesson.ci) end },
    { label = "Settings", activate = function() openSettings("game") end },
    { label = "Main Menu", activate = function() goTitle() end },
  }, 340, 44, 54)
  lists.lpause.back = function() G.pause = nil end

  lists.over = ui.centerList({
    { label = "Rematch", activate = function() startGame(G.mode) end },
    { label = "Main Menu", activate = function() goTitle() end },
    { label = "View Board", activate = function() G.over = nil end },
  }, 340, 46, 56)
  lists.over.back = function() G.over = nil end
end

---------------------------------------------------------------------------
-- Every frame: clock, computer player, hints. Thinking runs in small slices
-- so the screen stays responsive, and always on a copy of the game.
---------------------------------------------------------------------------
local lastTick
local function tickClock()
  local t = P.now()
  local dt = t - (lastTick or t)
  lastTick = t
  local g, ck = G.game, G.clock
  if screen ~= "game" or not ck or not g or g.result or #g.played == 0 then return end
  if G.pause or G.over or G.confirm then return end     -- menus pause the clock
  local side = g.side
  ck.time[side] = ck.time[side] - dt
  if ck.time[side] <= 0 then
    ck.time[side] = 0
    if Chess.hasMatingMaterial(g, -side) then finishGame("timeout", -side)
    else finishGame("timeout_draw", nil) end
  end
end

local function thinkSettings()
  local level = AI.LEVELS[G.level]
  if not G.clock then return level end
  -- with a clock, don't spend more than a fair share of the remaining time
  local p = {}
  for k, v in pairs(level) do p[k] = v end
  local left = G.clock.time[G.aiSide]
  p.time = math.min(level.time, math.max(150, left / 25 + G.clock.inc * 0.75))
  return p
end

local function updateThinking()
  local g = G.game
  if not g then return end
  if G.mode == "ai" and not g.result and g.side == G.aiSide and not G.confirm then
    if not G.aiCo and G.aiMove == nil then
      G.aiStart = P.now()
      local useBook = G.level >= 4 or (G.level >= 2 and math.random() < 0.5)
      local bm = useBook and #g.played < 16 and Book.pick(g) or nil
      if bm then
        G.aiMove = bm
      else
        local snap, p = Chess.clone(g), thinkSettings()
        G.aiCo = coroutine.create(function() return AI.think(snap, p, true) end)
      end
    end
    if G.aiCo then
      local ok, res = coroutine.resume(G.aiCo)
      if not ok then error(res) end
      if coroutine.status(G.aiCo) == "dead" then G.aiCo, G.aiMove = nil, res or false end
    end
    if G.aiMove ~= nil and P.now() - G.aiStart >= config.MIN_THINK then
      local am = G.aiMove
      G.aiMove = nil
      local m = am and Chess.findMove(g, am.from, am.to, am.promo)
      if m then commitMove(m) end
    end
  end
  if G.hintCo then
    local ok, res = coroutine.resume(G.hintCo)
    if not ok then error(res) end
    if coroutine.status(G.hintCo) == "dead" then
      G.hintCo = nil
      local m = res and Chess.findMove(g, res.from, res.to, res.promo)
      if m then G.hintMove, G.hintSan = m, Chess.san(g, m, g.legal) end
    end
  end
  -- show the game-over menu shortly after the game ends
  if g.result and not G.overShown and G.overAt and P.now() >= G.overAt then
    G.overShown = true
    lists.over.index = 1
    G.over = true
  end
end

---------------------------------------------------------------------------
-- Game screen input
---------------------------------------------------------------------------
local function promoRect(i)
  local w, gap = 88, 12
  local total = 4 * w + 3 * gap
  return BX + (BOARD_PX - total) / 2 + (i - 1) * (w + gap), BY + (BOARD_PX - w) / 2, w, w
end

function lists.pauseFor(mode)
  if mode == "puzzle" then return lists.ppause elseif mode == "lesson" then return lists.lpause end
  return lists.pause
end
local function openPause() lists.pauseFor(G.mode).index = 1; G.pause = true end

local buttons = {
  { label = "Undo", action = doUndo },
  { label = "Hint", action = requestHint },
  { label = "Flip", action = function() G.flipped = not G.flipped; G.anims = nil end },
  { label = "Menu", action = openPause },
}
local puzzleButtons = {
  { label = "Hint", action = function() puzzleHint() end },
  { label = "Solution", action = function() puzzleSolution() end },
  { label = "Next", action = function() nextPuzzle() end },
  { label = "Menu", action = openPause },
}
local lessonButtons = {
  { label = "Back", action = function() lessonBack() end },
  { label = "Hint", action = function() lessonHint() end },
  { label = "Next", action = function() lessonNext() end },
  { label = "Menu", action = openPause },
}
for _, set in ipairs({ buttons, puzzleButtons, lessonButtons }) do
  for i, b in ipairs(set) do b.x, b.y, b.w, b.h = PX + (i - 1) * 96, 476, 88, 48 end
end
local function currentButtons()
  if G.mode == "puzzle" then return puzzleButtons elseif G.mode == "lesson" then return lessonButtons end
  return buttons
end

-- The top-most open pop-up, if any: { list = ..., close = function }
local function activePopup()
  if G.confirm then return { list = G.confirm.list, close = function() G.confirm = nil end } end
  if G.over then return { list = lists.over, close = function() G.over = nil end } end
  if G.pause then return { list = lists.pauseFor(G.mode), close = function() G.pause = nil end } end
  return nil
end

local LIST_X, LIST_Y, LIST_ROWS, LIST_H = PX, 216, 8, 22
local function inMoveList(x, y)
  return G.mode ~= "puzzle" and G.mode ~= "lesson" and ui.inside(x, y, LIST_X, LIST_Y, 368, LIST_ROWS * LIST_H)
end

local function gameTouchDown(x, y)
  cursor.visible = false
  local pop = activePopup()
  if pop then
    if not ui.listTouch(pop.list, x, y) and not ui.inside(x, y, ui.listBox(pop.list)) then pop.close() end
    return
  end
  if G.promo then
    for i = 1, 4 do
      if ui.inside(x, y, promoRect(i)) then commitMove(G.promo.moves[i]); return end
    end
    G.promo = nil
    return
  end
  for _, b in ipairs(currentButtons()) do
    if ui.inside(x, y, b.x, b.y, b.w, b.h) then b.action(); return end
  end
  if inMoveList(x, y) then
    listDrag = { y = y, top = G.listTop, moved = false }
    return
  end
  if G.view then return end                 -- the board is read-only while looking back
  local s = screenToSquare(x, y)
  if not s then return end
  if G.selected and G.targets[s] then tryMoveTo(s); return end
  if selectSquare(s) then
    drag.on, drag.moved, drag.from, drag.x, drag.y = true, false, s, x, y
  else
    clearSelection()
  end
end

local function gameTouchMove(x, y)
  if listDrag then
    local rows = math.floor((listDrag.y - y) / LIST_H + 0.5)
    if math.abs(listDrag.y - y) > 8 then listDrag.moved = true end
    if listDrag.moved then
      local nPairs = math.ceil(#G.game.played / 2)
      G.listTop = math.max(1, math.min(math.max(1, nPairs - LIST_ROWS + 1), listDrag.top + rows))
      G.follow = false
    end
    return
  end
  if drag.on then
    if abs(x - drag.x) > 6 or abs(y - drag.y) > 6 then drag.moved = true end
    if drag.moved then drag.x, drag.y = x, y end
  end
end

local function gameTouchUp(x, y)
  if listDrag then
    local wasTap = not listDrag.moved
    listDrag = nil
    if wasTap then
      local pair = G.listTop + math.floor((y - LIST_Y) / LIST_H)
      local ply = 2 * pair - ((x < LIST_X + 190) and 1 or 0)
      if ply >= 1 and ply <= #G.game.played then
        ui.sound("tick")
        if ply == #G.game.played then goLive() else setView(ply) end
      end
    end
    return
  end
  if not drag.on then return end
  drag.on = false
  local s = screenToSquare(x, y)
  if drag.moved and s and s ~= drag.from and G.targets[s] then tryMoveTo(s, true) end
  drag.moved = false
end

local function clamp(v) if v < 0 then return 0 elseif v > 7 then return 7 end return v end

local function gameButtons(input)
  local p = input.pressed
  local pop = activePopup()
  if pop then
    ui.listInput(pop.list, input)
    if p.start and G.pause and not G.confirm then G.pause = nil end
    return
  end
  if G.promo then
    if p.left then G.promo.index = ui.wrap(G.promo.index - 1, 4) end
    if p.right then G.promo.index = ui.wrap(G.promo.index + 1, 4) end
    if p.cross then commitMove(G.promo.moves[G.promo.index])
    elseif p.circle then G.promo = nil end
    return
  end
  if G.view and (p.cross or p.triangle or p.select) then return end   -- read-only while looking back
  if G.mode == "lesson" and p.cross and (G.lesson.state == "done" or G.lesson.state == "failed") then
    lessonNext()
    return
  end
  local df, dr = 0, 0
  if p.up then dr = 1 end
  if p.down then dr = -1 end
  if p.left then df = -1 end
  if p.right then df = 1 end
  if G.flipped then df, dr = -df, -dr end
  if df ~= 0 or dr ~= 0 then
    if cursor.visible then cursor.f, cursor.r = clamp(cursor.f + df), clamp(cursor.r + dr) end
    cursor.visible = true
  end
  if p.cross then
    cursor.visible = true
    activateSquare(sq(cursor.f, cursor.r))
  end
  if G.mode == "ai" or G.mode == "2p" then
    local total = #G.game.played
    if p.l and total > 0 then ui.sound("tick"); setView((G.view or total) - 1) end
    if p.r and G.view then ui.sound("tick"); setView(G.view + 1) end
    if p.circle and G.view then goLive(); return end
  end
  if p.circle then clearSelection() end
  if p.square then G.flipped = not G.flipped; G.anims = nil end
  if p.start then openPause() end
  if G.mode == "puzzle" then
    if p.select then puzzleHint() end
    if p.triangle then nextPuzzle() end
  elseif G.mode == "lesson" then
    if p.select then lessonHint() end
    if p.triangle then lessonNext() end
  else
    if p.select then requestHint() end
    if p.triangle then doUndo() end
  end
end

local function handleInput()
  local input = P.readInput()
  local tx, ty = input.touchX, input.touchY
  if tx then
    if not touch.on then
      touch.on = true
      if screen == "game" then gameTouchDown(tx, ty) else ui.listTouch(lists[screen], tx, ty) end
    elseif screen == "game" then
      gameTouchMove(tx, ty)
    end
    touch.x, touch.y = tx, ty
  elseif touch.on then
    touch.on = false
    if screen == "game" then gameTouchUp(touch.x, touch.y) end
  end
  if screen == "game" then gameButtons(input) else ui.listInput(lists[screen], input) end
end

---------------------------------------------------------------------------
-- Drawing: menu screens
---------------------------------------------------------------------------
local titleArt
local function drawTitle()
  ui.menuBackground()
  ui.text(70, 66, "VITA CHESS", C.accent, 3, true)
  ui.text(74, 136, "Chess for " .. P.NAME .. "  " .. config.VERSION, C.dim)
  if titleArt == nil then titleArt = P.loadImage(config.ASSET_DIR .. "art/title.png") or false end
  if titleArt then
    P.drawImage(titleArt, 72, 172)
  else
    ui.drawPiece(-6, 120, 196, 3)
    ui.drawPiece(2, 230, 236, 3)
  end
  ui.drawList(lists.title)
  ui.text(24, 508, "Made by", C.dim, 0.85)
  ui.text(24 + ui.textW("Made by ", 0.85), 508, config.AUTHOR, C.accent, 0.85, true)
end

local function drawSetup()
  ui.menuBackground()
  ui.text(150, 44, "PLAY VS COMPUTER", C.accent, 1.8, true)
  ui.drawList(lists.setup)
  local L = AI.LEVELS[opt.level]
  local rec = stats.get(opt.level)
  ui.rect(150, 400, 660, 96, C.panel)
  ui.text(170, 410, L.name .. "  -  about " .. L.elo .. " Elo", C.text, 1.1, true)
  ui.text(170, 438, L.desc, C.dim)
  ui.text(170, 464, string.format("Your record at this level:  %d won   %d lost   %d drawn",
    rec.w, rec.l, rec.d), C.accent, 0.95)
  ui.footer({ { "leftright", "Change" }, { "cross", "Select" }, { "circle", "Back" }, "Elo ratings are rough guides" })
end

local function drawSetup2()
  ui.menuBackground()
  ui.text(150, 44, "TWO PLAYERS", C.accent, 1.8, true)
  ui.drawList(lists.setup2)
  ui.rect(150, 400, 660, 96, C.panel)
  ui.text(170, 414, "Pass-and-play on one Vita.", C.text, 1.1, true)
  ui.text(170, 448, "Auto-flip turns the board to face whoever's move it is.", C.dim)
  ui.footer({ { "leftright", "Change" }, { "cross", "Select" }, { "circle", "Back" } })
end

local function drawPuzzleMenu()
  ui.menuBackground()
  ui.text(150, 44, "PUZZLES", C.accent, 1.8, true)
  ui.drawList(lists.puzzles)
  local pr = Puzzles.progress
  ui.rect(150, 300, 660, 196, C.panel)
  ui.text(174, 316, "Your puzzle rating", C.dim)
  ui.text(174, 340, tostring(pr.rating), C.accent, 2.6, true)
  ui.text(430, 318, string.format("Solved:  %d of %d tried", pr.solved, pr.attempts), C.text)
  ui.text(430, 348, string.format("Current streak:  %d", pr.streak), C.text)
  ui.text(430, 378, string.format("Best streak:  %d", pr.best), C.text)
  ui.text(174, 430, string.format("%d puzzles, %d seen so far.", Puzzles.count(), Puzzles.seenCount()), C.dim)
  ui.text(174, 456, "Adaptive picks puzzles near your rating. Hints mean no rating change.", C.dim, 0.85)
  ui.footer({ { "cross", "Select" }, { "leftright", "Change" }, { "circle", "Back" }, "Puzzles from the Lichess database (CC0)" })
end

local function drawLearnMenu()
  ui.menuBackground()
  ui.text(60, 44, "LEARN", C.accent, 1.8, true)
  ui.drawList(lists.learn)
  -- details of the highlighted course, on the right
  local course = Learn.COURSES[lists.learn.index]
  ui.rect(560, 112, 340, 370, C.panel)
  if course then
    ui.text(584, 132, course.title, C.text, 1.2, true)
    local y = 176
    for _, line in ipairs(ui.wrapText(course.desc, 292, 0.95)) do
      ui.text(584, y, line, C.dim, 0.95); y = y + 24
    end
    local done = Learn.count(course)
    ui.text(584, 400, string.format("%d of %d lessons complete", done, #course.lessons), C.accent, 0.95)
    ui.rect(584, 432, 292, 8, C.box)
    ui.rect(584, 432, math.floor(292 * done / #course.lessons), 8, C.accent)
  else
    ui.text(584, 132, "51 lessons in 6 courses,", C.dim, 0.95)
    ui.text(584, 156, "from the rules to endgames.", C.dim, 0.95)
  end
  ui.footer({ { "cross", "Select" }, { "circle", "Back" } })
end

local function drawCourseMenu()
  ui.menuBackground()
  local course = lists.course.course
  ui.text(150, 36, course.title, C.accent, 1.8, true)
  ui.text(150, 74, string.format("%d of %d lessons complete", Learn.count(course), #course.lessons), C.dim, 0.9)
  ui.drawList(lists.course)
  ui.footer({ { "cross", "Start lesson" }, { "circle", "Back" } })
end

local LEVEL_NAMES = {}
for i, L in ipairs(AI.LEVELS) do LEVEL_NAMES[i] = "Lv" .. i .. " " .. L.name end

local function drawTrophies()
  ui.menuBackground()
  ui.text(40, 36, "STATS & TROPHIES", C.accent, 1.8, true)
  -- your record, on the left
  local d = stats.data
  local w, l, dr = stats.totals()
  local pr = Puzzles.progress
  local lessons, total = 0, 0
  for _, c in ipairs(Learn.COURSES) do lessons, total = lessons + Learn.count(c), total + #c.lessons end
  local favW, nW = stats.favourite(stats.openingsWhite)
  local favB, nB = stats.favourite(stats.openingsBlack)
  local lines = {
    { "Games finished", tostring(d.games) },
    { "vs Computer", string.format("%d won  %d lost  %d drawn", w, l, dr) },
    { "Two-player games", tostring(d.twoPlayer) },
    { "Best win streak", tostring(d.bestStreak) },
    { "Highest level beaten", d.bestLevelBeaten > 0 and LEVEL_NAMES[d.bestLevelBeaten] or "-" },
    { "Fastest win", d.fastestWin > 0 and (d.fastestWin .. " moves") or "-" },
    { "Longest game", d.longest > 0 and (d.longest .. " moves") or "-" },
    { "Favourite first move", favW and ("1. " .. favW .. "  (" .. nW .. "x)") or "-" },
    { "Favourite reply as Black", favB and (favB .. "  (" .. nB .. "x)") or "-" },
    { "Puzzle rating", tostring(pr.rating) },
    { "Puzzles solved", pr.solved .. "  (best streak " .. pr.best .. ")" },
    { "Lessons complete", lessons .. " / " .. total },
  }
  ui.rect(40, 100, 400, 398, C.row)
  for i, ln in ipairs(lines) do
    local y = 112 + (i - 1) * 32
    ui.text(56, y, ln[1], C.dim, 0.85)
    ui.textR(426, y, ln[2], C.text, 0.85, true)
  end
  ui.text(460, 72, "Trophies  " .. Trophies.count() .. " / " .. #Trophies.LIST, C.text, 1, true)
  ui.drawList(lists.trophies)
  ui.footer({ { "updown", "Scroll" }, { "circle", "Back" } })
end

-- Banner sliding down from the top when a trophy unlocks (shown on any screen)
local function drawTrophyToast()
  local toast = trophyToasts[1]
  if not toast then return end
  if not toast.start then toast.start = P.now(); playSound("trophy") end
  local t = (P.now() - toast.start) / 1000
  if t > 3.2 then table.remove(trophyToasts, 1); return end
  local slide = math.min(1, t / 0.25, (3.2 - t) / 0.25)        -- in, hold, out
  local y = math.floor(-70 + 82 * slide)
  ui.rect(250, y, 460, 60, C.panel)
  ui.frame(250, y, 460, 60, 2, C.accent)
  local img = (function()
    for _, r in ipairs(lists.trophies.rows) do if r.label == toast.trophy.name then return r.icon() end end
  end)()
  if img then P.drawImage(img, 264, y + 14) end
  ui.text(308, y + 8, "Trophy unlocked!", C.accent, 0.85, true)
  ui.text(308, y + 30, toast.trophy.name .. "  -  " .. toast.trophy.desc, C.text, 0.85)
end

local previewGame
local function drawSettings()
  ui.menuBackground()
  ui.text(32, 24, "SETTINGS", C.accent, 1.8, true)
  ui.drawList(lists.settings)
  if not previewGame then  -- a short opening to show off the theme
    previewGame = Chess.newGame()
    for _, mv in ipairs({ { 85, 65 }, { 35, 55 }, { 97, 76 }, { 22, 43 }, { 96, 52 } }) do
      Chess.play(previewGame, Chess.findMove(previewGame, mv[1], mv[2], 0))
    end
  end
  ui.text(640, 84, "Preview", C.dim)
  ui.drawBoard(previewGame, 640, 110, 36, {
    coords = opt.coords, last = opt.last,
    selected = opt.legal and 27 or nil,
    targets = opt.legal and { [46] = true, [48] = true, [35] = true } or nil })
  ui.footer({ { "updown", "Choose" }, { "leftright", "Change" }, { "circle", "Back" } })
end

---------------------------------------------------------------------------
-- Drawing: game screen
---------------------------------------------------------------------------
-- Opponent's pieces captured by `side`, as counts per piece type
local function capturedBy(side)
  local counts = { 0, 0, 0, 0, 0, 0 }
  local flying = G.capFly and G.capFly.ply       -- not shown until it lands
  for i, rec in ipairs(G.game.played) do
    local mover = (i % 2 == 1) and 1 or -1
    if rec.cap ~= 0 and mover == side and i ~= flying then
      local t = abs(rec.cap)
      counts[t] = counts[t] + 1
    end
  end
  return counts
end

local function drawPlayerCard(side, y)
  local g = G.game
  local active = not g.result and g.side == side
  ui.rect(PX, y, 368, 64, active and C.boxActive or C.box)
  if active then ui.rect(PX, y, 4, 64, C.accent) end
  ui.rect(PX + 12, y + 10, 20, 20, C.dim)
  ui.rect(PX + 14, y + 12, 16, 16, (side == 1) and C.white or C.black)
  local name
  if G.mode == "ai" then name = (side == G.aiSide) and ("Computer  Lv" .. G.level) or "You"
  else name = sideName(side) end
  ui.text(PX + 42, y + 9, name, C.text, 1, true)
  -- captured pieces, cheapest first, plus the material lead
  local counts, x = capturedBy(side), PX + 10
  for t = 1, 5 do
    for _ = 1, counts[t] do ui.drawPiece(-side * t, x, y + 37, 0.36); x = x + 11 end
    if counts[t] > 0 then x = x + 10 end
  end
  if G.capFly and G.capFly.side == side then G.capFly.tx, G.capFly.ty = x, y + 37 end   -- landing spot
  local w, b = Chess.material(g)
  local lead = (side == 1) and (w - b) or (b - w)
  if lead > 0 then ui.text(x + 14, y + 41, "+" .. lead, C.dim, 0.85) end
  if G.clock then
    local ms = G.clock.time[side]
    local col = (ms < 20000) and C.red or (active and C.accent or C.text)
    ui.textR(PX + 356, y + 12, fmtClock(ms), col, 1.7, true)
  end
end

local function drawPanel()
  local g = G.game
  ui.rect(PX - 10, 8, P.SCREEN_W - PX + 2, 528, C.panel)
  local tcName = G.clock and ("   " .. config.TIME_CONTROLS[G.tc].name) or ""
  if G.mode == "ai" then
    local L = AI.LEVELS[G.level]
    ui.text(PX + 4, 14, "vs Computer", C.accent, 1.3, true)
    ui.text(PX + 4, 44, "Lv" .. G.level .. " " .. L.name .. " (~" .. L.elo .. ")" .. tcName, C.dim, 0.85)
  else
    ui.text(PX + 4, 14, "Two Players", C.accent, 1.3, true)
    ui.text(PX + 4, 44, "Pass-and-play" .. tcName, C.dim, 0.85)
  end

  local topSide = G.flipped and 1 or -1
  drawPlayerCard(topSide, 68)
  drawPlayerCard(-topSide, 400)

  -- status
  if g.result then
    ui.text(PX + 4, 142, resultText(g), C.accent, 1, true)
  else
    local status
    if G.mode == "ai" then status = (g.side == G.aiSide) and "Computer to Move" or "Your Move"
    else status = sideName(g.side) .. " to Move" end
    if g.check then status = status .. "  - CHECK!" end
    ui.text(PX + 4, 142, status, g.check and C.red or C.text)
  end
  local dots = string.rep(".", floor(P.now() / 350) % 4)
  if G.view then
    local x = ui.hints(PX + 4, 166, { { "l", "" }, { "r", "Step" }, { "circle", "Live" } }, 0.8)
    ui.text(x, 166, "Move " .. G.view .. " of " .. #g.played, C.accent, 0.8, true)
  elseif G.toast and P.now() < G.toast.untilT then
    ui.text(PX + 4, 166, G.toast.text, C.accent, 0.9)
  elseif G.aiCo or G.aiMove ~= nil then
    ui.text(PX + 4, 166, "Thinking" .. dots, C.good, 0.9)
  elseif G.hintCo then
    ui.text(PX + 4, 166, "Finding a hint" .. dots, C.good, 0.9)
  elseif G.hintSan then
    ui.text(PX + 4, 166, "Hint: " .. G.hintSan, C.good, 0.9)
  elseif g.result and G.pgnName then
    ui.text(PX + 4, 166, "Saved games/" .. G.pgnName, C.dim, 0.75)
  end

  -- move list: drag to scroll, tap a move to look at that position
  local nPairs = math.ceil(#g.played / 2)
  if G.follow then G.listTop = math.max(1, nPairs - LIST_ROWS + 1) end
  ui.text(PX + 4, 190, "Moves", C.dim, 0.9)
  if G.listTop > 1 then ui.textR(PX + 364, 190, "^ earlier", C.dim, 0.8) end
  ui.rect(PX + 4, 211, 364, 2, C.box)
  local shownPly = G.view or #g.played
  for i = G.listTop, math.min(nPairs, G.listTop + LIST_ROWS - 1) do
    local y = LIST_Y + (i - G.listTop) * LIST_H
    ui.text(PX + 4, y + 2, i .. ".", C.dim)
    for k = 0, 1 do
      local ply = 2 * i - 1 + k
      local rec = g.played[ply]
      if rec then
        local x = PX + (k == 0 and 64 or 200)
        if ply == shownPly and G.view then ui.rect(x - 6, y, 120, LIST_H, C.boxHi) end
        ui.text(x, y + 2, rec.san, C.text)
      end
    end
  end

  for _, b in ipairs(buttons) do
    local label = (b.label == "Undo" and G.view) and "Live" or b.label
    ui.rect(b.x, b.y, b.w, b.h, (label == "Live") and C.boxHi or C.box)
    ui.textC(b.x + b.w / 2, b.y + 13, label, C.text)
  end
end

local function drawPuzzlePanel()
  local g, Z = G.game, G.puzzle
  local pr = Puzzles.progress
  ui.rect(PX - 10, 8, P.SCREEN_W - PX + 2, 528, C.panel)
  ui.text(PX + 4, 14, "Puzzle", C.accent, 1.3, true)
  ui.text(PX + 4, 44, "Your rating " .. pr.rating .. "   Streak " .. pr.streak, C.dim, 0.85)

  -- what to do now
  local finished = Z.state == "solved" or Z.state == "done"
  local title, sub, col
  local who = sideName(Z.solver)
  if Z.state == "intro" then
    title, sub, col = "Watch the opponent's move", "", C.text
  elseif Z.state == "play" then
    title, col = who .. " to Move", C.text
    sub = Z.failed and "Keep trying, or show the solution." or "Find the best move."
  elseif Z.state == "wrong" then
    title, sub, col = "Not the move", "Try again.", C.red
  elseif Z.state == "reply" then
    title, sub, col = "Good move!", "Keep going...", C.good
  elseif Z.state == "showing" then
    title, sub, col = "Showing the solution", "", C.accent
  elseif Z.state == "solved" then
    title = Z.failed and "Solved, after a mistake" or (Z.assisted and "Solved with a hint" or "Solved!")
    sub, col = "", C.good
  else
    title, sub, col = "Solution shown", "", C.accent
  end
  ui.rect(PX, 68, 368, 92, C.box)
  ui.rect(PX + 12, 80, 20, 20, C.dim)
  ui.rect(PX + 14, 82, 16, 16, (Z.solver == 1) and C.white or C.black)
  ui.text(PX + 42, 78, title, col, 1.2, true)
  ui.text(PX + 42, 110, sub, C.dim, 0.9)
  if Z.delta and Z.delta ~= 0 and finished or (Z.delta and Z.delta < 0) then
    local txt = (Z.delta > 0 and "+" or "") .. Z.delta
    ui.textR(PX + 356, 112, txt, (Z.delta > 0) and C.good or C.red, 1.2, true)
  end

  -- puzzle details (the puzzle's rating is revealed once it's over)
  local solverMoves = floor(#Z.p.moves / 2)
  ui.text(PX + 4, 180, "Moves to find: " .. solverMoves, C.text, 0.95)
  if finished then
    ui.text(PX + 4, 206, "Puzzle rating: " .. Z.p.rating, C.text, 0.95)
  else
    ui.text(PX + 4, 206, "Puzzle rating: hidden until solved", C.dim, 0.95)
  end
  ui.text(PX + 4, 232, "Puzzle " .. Z.p.id, C.dim, 0.8)

  ui.rect(PX + 4, 262, 364, 2, C.box)
  ui.text(PX + 4, 274, string.format("Solved %d of %d", pr.solved, pr.attempts), C.dim, 0.9)
  ui.text(PX + 4, 298, string.format("Best streak %d", pr.best), C.dim, 0.9)
  if finished then ui.text(PX + 4, 340, "Press Next (or Triangle) for another.", C.accent, 0.9) end

  ui.hints(PX + 4, 444, { { "select", "Hint" }, { "triangle", "Next" }, { "square", "Flip" } }, 0.8)
  for _, b in ipairs(puzzleButtons) do
    local off = (b.label == "Hint" or b.label == "Solution") and Z.state ~= "play"
    ui.rect(b.x, b.y, b.w, b.h, C.box)
    ui.textC(b.x + b.w / 2, b.y + 13, b.label, off and C.dim or C.text)
  end
end

local function drawLessonPanel()
  local L = G.lesson
  ui.rect(PX - 10, 8, P.SCREEN_W - PX + 2, 528, C.panel)
  ui.text(PX + 4, 12, L.course.title, C.dim, 0.85)
  ui.text(PX + 4, 32, L.lesson.title, C.accent, 1.15, true)
  local n = #L.lesson.steps
  ui.text(PX + 4, 62, "Step " .. L.si .. " of " .. n, C.dim, 0.85)
  ui.rect(PX + 112, 69, 256, 6, C.box)
  ui.rect(PX + 112, 69, floor(256 * L.si / n), 6, C.accent)

  local y = 94
  for _, line in ipairs(ui.wrapText(L.step.text, 360, 0.95)) do
    if y > 372 then break end
    ui.text(PX + 4, y, line, C.text, 0.95)
    y = y + 23
  end
  if L.step.kind == "targets" and L.state ~= "done" then
    local left = 0
    for _ in pairs(L.stars) do left = left + 1 end
    ui.text(PX + 4, y + 8, "Stars left: " .. left, C.star, 0.95, true)
  elseif L.step.kind == "play" then
    local left = L.step.limit - L.k
    ui.text(PX + 4, y + 8, "Moves left: " .. left, (left <= 3) and C.red or C.star, 0.95, true)
    if L.state == "think" then ui.text(PX + 200, y + 8, "Thinking...", C.good, 0.95) end
  elseif L.step.kind == "guide" then
    y = y + 8
    if L.oppSan then
      ui.text(PX + 4, y, ((L.solver == 1) and "Black" or "White") .. " played " .. L.oppSan, C.dim, 0.9, true)
      y = y + 21
      for _, line in ipairs(ui.wrapText(L.oppText or "", 360, 0.85)) do
        ui.text(PX + 4, y, line, C.dim, 0.85); y = y + 19
      end
      y = y + 8
    end
    if L.mySan and L.state ~= "done" then
      ui.text(PX + 4, y, "Your Move: " .. L.mySan, C.accent, 1, true)
      y = y + 23
      for _, line in ipairs(ui.wrapText(L.myText or "", 360, 0.9)) do
        if y < 392 then ui.text(PX + 4, y, line, C.text, 0.9); y = y + 21 end
      end
    end
  end

  -- feedback
  if L.msg then
    local yy = 396
    for i, line in ipairs(ui.wrapText(L.msg, 360, 0.85)) do
      if i <= 4 then ui.text(PX + 4, yy, line, L.msgColor or C.text, 0.85); yy = yy + 19 end
    end
  elseif L.step.kind == "explain" then
    ui.hints(PX + 4, 444, { { "cross", "Continue" } })
  end

  for _, b in ipairs(lessonButtons) do
    local nextOn = L.state == "done" or L.state == "failed"
    local off = (b.label == "Back" and L.si == 1) or (b.label == "Hint" and L.state ~= "play")
             or (b.label == "Next" and not nextOn)
    local label = (b.label == "Next" and L.state == "failed") and "Retry" or b.label
    ui.rect(b.x, b.y, b.w, b.h, (b.label == "Next" and not off) and C.boxHi or C.box)
    ui.textC(b.x + b.w / 2, b.y + 13, label, off and C.dim or C.text)
  end
end

local function drawGame()
  local g = G.game
  ui.rect(0, 0, P.SCREEN_W, P.SCREEN_H, C.bg)

  -- pieces in motion are drawn separately, on top of the board
  local hide, moving = {}, {}
  if G.anims then
    local t = P.now()
    for _, a in ipairs(G.anims) do
      local k = (t - a.start) / config.ANIM_MS
      if k < 1 then
        local e = 1 - (1 - k) * (1 - k)            -- ease out
        hide[a.sq] = true
        moving[#moving + 1] = { a.piece, a.fx + (a.tx - a.fx) * e, a.fy + (a.ty - a.fy) * e }
      end
    end
    if #moving == 0 then G.anims = nil end
  end
  if drag.on and drag.moved then hide[drag.from] = true end

  -- the king shakes for a moment when it's put in check
  local shake
  if G.shake then
    local t = (P.now() - G.shake.start) / 1000
    if t < 0.4 then shake = { sq = G.shake.sq, dx = math.floor(math.sin(t * 60) * 5 * (1 - t / 0.4) + 0.5) }
    else G.shake = nil end
  end
  local L = (G.mode == "lesson") and G.lesson or nil
  local viewing = G.viewGame
  local xy = ui.drawBoard(viewing or g, BX, BY, SQ, {
    flipped = G.flipped, coords = opt.coords, last = opt.last,
    hint = not viewing and G.hintMove or nil, selected = not viewing and G.selected or nil,
    arrow = not viewing and G.hintMove or nil, shake = not viewing and shake or nil,
    targets = (opt.legal and not viewing) and G.targets or nil, hide = not viewing and hide or nil,
    marks = L and L.marks, stars = L and L.step.kind == "targets" and L.stars or nil })
  if viewing then ui.frame(BX, BY, BOARD_PX, BOARD_PX, 3, C.accent) end
  if not viewing then
    for _, mv in ipairs(moving) do ui.drawPiece(mv[1], mv[2], mv[3]) end
  end
  if cursor.visible and not activePopup() and not G.promo then
    local x, y = xy(sq(cursor.f, cursor.r))
    ui.frame(x, y, SQ, SQ, 4, C.cursor)
  end
  if drag.on and drag.moved then ui.drawPiece(g.board[drag.from], drag.x - 32, drag.y - 40) end
  if G.mode == "puzzle" then drawPuzzlePanel()
  elseif G.mode == "lesson" then drawLessonPanel()
  else drawPanel() end

  -- a captured piece flies from the board to its captor's card
  local f = G.capFly
  if f and f.tx then
    local k = (P.now() - f.start) / 450
    if k >= 1 then
      G.capFly = nil
    else
      local e = k * k * (3 - 2 * k)                       -- smooth start and stop
      local scale = 1 - 0.64 * e
      ui.drawPiece(f.piece, f.x + (f.tx - f.x) * e, f.y + (f.ty - f.y) * e, scale)
    end
  end

  if G.promo then
    ui.rect(BX, BY, BOARD_PX, BOARD_PX, C.shade)
    local x0, y0 = promoRect(1)
    ui.text(x0, y0 - 34, "Promote to:", C.text, 1.2, true)
    for i = 1, 4 do
      local x, y, w, h = promoRect(i)
      ui.rect(x, y, w, h, ui.theme().L)
      if i == G.promo.index then ui.frame(x, y, w, h, 4, C.cursor) end
      ui.drawPiece(G.promo.moves[i].promo * g.side, x + (w - SQ) / 2, y + (h - SQ) / 2)
    end
  end
  if G.pause then ui.drawOverlayList(lists.pauseFor(G.mode), "PAUSED") end
  if G.over then ui.drawOverlayList(lists.over, resultText(g), C.accent) end
  if G.confirm then ui.drawOverlayList(G.confirm.list, G.confirm.title, C.text) end
end

local DRAW = { title = drawTitle, setup = drawSetup, setup2 = drawSetup2, puzzles = drawPuzzleMenu,
               learn = drawLearnMenu, course = drawCourseMenu, trophies = drawTrophies,
               settings = drawSettings, game = drawGame }

---------------------------------------------------------------------------
-- Main loop
---------------------------------------------------------------------------
function app.run()
  P.init()
  AI.now = P.now
  ui.init()
  P.loadFonts({ dir = config.FONT_DIR, sizes = config.FONT_SIZES, px = config.fontPx,
                regular = config.FONT, bold = config.FONT_BOLD })
  settings.load()
  stats.load()
  Puzzles.load()
  Learn.load()
  for _, n in ipairs({ "move", "capture", "check", "end", "tick", "select", "back", "trophy" }) do
    sounds[n] = P.loadSound(config.ASSET_DIR .. "sounds/" .. n .. ".wav")
  end
  ui.sound = function(name) playSound(name) end
  buildMenus()
  buildTitle()
  awardTrophies()          -- anything already earned (e.g. from before trophies existed)
  local shown, fadeStart = screen, -1000
  local FADE_MS = 220
  local fades = {}
  for i = 0, 10 do fades[i] = P.color(0, 0, 0, math.floor(255 * i / 10)) end
  while true do
    handleInput()
    tickClock()
    if screen == "game" then updateThinking(); updatePuzzle(); updateLesson() end
    if screen ~= shown then shown, fadeStart = screen, P.now() end   -- fade in each new screen
    P.beginFrame()
    DRAW[screen]()
    local k = (P.now() - fadeStart) / FADE_MS
    if k < 1 then ui.rect(0, 0, P.SCREEN_W, P.SCREEN_H, fades[math.floor((1 - k) * 10 + 0.5)]) end
    drawTrophyToast()
    P.endFrame()
  end
end

return app
