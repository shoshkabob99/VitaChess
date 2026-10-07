-- ai.lua - the computer player
--
-- Alpha-beta search with iterative deepening, quiescence search, check
-- extensions, MVV-LVA + killer move ordering. Difficulty comes from search
-- depth, thinking time, deliberate "noise" in its judgement, and an
-- occasional random move at the lowest levels.
-- Pure Lua with no Vita code. Platform code sets AI.now to a millisecond clock.
local Chess = require("chess")

local AI = {}
AI.now = function() return os.clock() * 1000 end   -- replaced on the Vita

local MATE, INF = 100000, 1000000
local makeMove, unmakeMove, attacked = Chess.makeMove, Chess.unmakeMove, Chess.attacked
local genPseudo, evaluate = Chess.genPseudo, Chess.evaluate

-- Elo figures are rough guides only, not calibrated ratings.
-- time is in milliseconds.
AI.LEVELS = {
  { name = "Beginner",     elo = 400,  depth = 1, q = false, noise = 260, random = 0.25, time = 1000,
    desc = "Barely looks ahead. Plays lots of random moves." },
  { name = "Novice",       elo = 600,  depth = 1, q = true,  noise = 160, random = 0.10, time = 1000,
    desc = "Grabs free pieces but misses most threats." },
  { name = "Casual",       elo = 800,  depth = 2, q = true,  noise = 100, random = 0.05, time = 1500,
    desc = "Looks one move ahead. Still blunders often." },
  { name = "Intermediate", elo = 1000, depth = 2, q = true,  noise = 55,  random = 0.02, time = 1500,
    desc = "Sees simple tactics. Makes the odd mistake." },
  { name = "Club",         elo = 1200, depth = 3, q = true,  noise = 30,  random = 0,    time = 2500,
    desc = "Solid and careful. Punishes hanging pieces." },
  { name = "Strong Club",  elo = 1400, depth = 4, q = true,  noise = 15,  random = 0,    time = 3500,
    desc = "Calculates 4 moves deep. Few mistakes." },
  { name = "Expert",       elo = 1600, depth = 6, q = true,  noise = 5,   random = 0,    time = 5000,
    desc = "Thinks up to 5 seconds per move." },
  { name = "Master",       elo = 1800, depth = 9, q = true,  noise = 0,   random = 0,    time = 8000,
    desc = "Full strength. Thinks up to 8 seconds." },
}
AI.HINT = { depth = 9, q = true, noise = 0, random = 0, time = 2000 }

local S = {}           -- search state for the current think
local killers = {}
for i = 0, 64 do killers[i] = {} end

local function abs(x) return x < 0 and -x or x end

local function checkTime()
  local t = AI.now()
  if S.canAbort and t >= S.hardStop then S.aborted = true end
  if S.yieldable and t - S.sliceStart >= S.slice then
    coroutine.yield()
    S.sliceStart = AI.now()
  end
end

local function sameMove(a, b)
  return b and a.from == b.from and a.to == b.to and a.promo == b.promo
end

local VALUE = { 100, 320, 330, 500, 900, 2000 }

local function orderMoves(g, moves, ply)
  local b = g.board
  local k1, k2 = killers[ply][1], killers[ply][2]
  for i = 1, #moves do
    local m = moves[i]
    local sc = 0
    local cap = b[m.to]
    if cap ~= 0 then
      sc = 10000 + VALUE[abs(cap)] * 10 - VALUE[abs(b[m.from])] / 10
    elseif m.flag == 2 then
      sc = 11000
    elseif sameMove(m, k1) then
      sc = 8000
    elseif sameMove(m, k2) then
      sc = 7000
    end
    if m.promo ~= 0 then sc = sc + 9000 + VALUE[m.promo] end
    m.order = sc
  end
  table.sort(moves, function(a, c) return a.order > c.order end)
end

local function quiesce(g, alpha, beta, ply)
  S.nodes = S.nodes + 1
  if S.nodes % 256 == 0 then checkTime() end
  if S.aborted then return 0 end
  local stand = evaluate(g)
  if stand >= beta then return beta end
  if stand > alpha then alpha = stand end
  if ply > 40 then return alpha end
  local moves = genPseudo(g, true)
  orderMoves(g, moves, ply < 64 and ply or 64)
  local side, b = g.side, g.board
  for i = 1, #moves do
    local m = moves[i]
    local cap = b[m.to]
    -- delta pruning: even winning this piece can't lift us to alpha
    if m.promo ~= 0 or cap == 0 or stand + VALUE[abs(cap)] + 200 > alpha then
      makeMove(g, m)
      if not attacked(g, g.kingSq[side], -side) then
        local sc = -quiesce(g, -beta, -alpha, ply + 1)
        unmakeMove(g)
        if S.aborted then return 0 end
        if sc >= beta then return beta end
        if sc > alpha then alpha = sc end
      else
        unmakeMove(g)
      end
    end
  end
  return alpha
end

local function search(g, depth, alpha, beta, ply)
  if depth <= 0 then
    if S.useQ then return quiesce(g, alpha, beta, ply) end
    S.nodes = S.nodes + 1
    return evaluate(g)
  end
  S.nodes = S.nodes + 1
  if S.nodes % 256 == 0 then checkTime() end
  if S.aborted then return 0 end
  if g.half >= 100 then return 0 end
  local side = g.side
  local inChk = attacked(g, g.kingSq[side], -side)
  if inChk and ply < 24 then depth = depth + 1 end    -- check extension
  local moves = genPseudo(g)
  local kp = ply < 64 and ply or 64
  orderMoves(g, moves, kp)
  local legal = 0
  for i = 1, #moves do
    local m = moves[i]
    local quiet = g.board[m.to] == 0 and m.promo == 0 and m.flag ~= 2
    makeMove(g, m)
    if not attacked(g, g.kingSq[side], -side) then
      legal = legal + 1
      local sc = -search(g, depth - 1, -beta, -alpha, ply + 1)
      unmakeMove(g)
      if S.aborted then return 0 end
      if sc > alpha then
        alpha = sc
        if alpha >= beta then
          if quiet and not sameMove(m, killers[kp][1]) then
            killers[kp][2] = killers[kp][1]
            killers[kp][1] = m
          end
          return beta
        end
      end
    else
      unmakeMove(g)
    end
  end
  if legal == 0 then return inChk and (-MATE + ply) or 0 end
  return alpha
end

-- Stop a think early (the coroutine unwinds cleanly on its next resume)
function AI.abort() S.aborted = true end

-- Pick a move for position g with settings p (a LEVELS entry or AI.HINT).
-- Call inside a coroutine with yieldable=true to keep the screen responsive.
function AI.think(g, p, yieldable)
  local root = {}
  for i, m in ipairs(g.legal) do root[i] = m end
  if #root == 0 then return nil end
  S = { nodes = 0, aborted = false, canAbort = false, useQ = p.q,
        yieldable = yieldable, slice = 24 }
  for i = 0, 64 do killers[i] = {} end
  local start = AI.now()
  S.sliceStart, S.hardStop = start, start + p.time
  if #root == 1 then return root[1] end
  if p.random > 0 and math.random() < p.random then return root[math.random(#root)] end

  -- Moves that would allow a threefold repetition count as a draw
  local isRep = {}
  for _, m in ipairs(root) do
    makeMove(g, m)
    local k, c = Chess.key(g), 0
    for _, kk in ipairs(g.keys) do if kk == k then c = c + 1 end end
    isRep[m] = c >= 2
    unmakeMove(g)
  end

  orderMoves(g, root, 0)
  local scores, best, bestScore = {}, root[1], -INF
  local fullWindow = p.noise > 0
  for depth = 1, p.depth do
    local alpha, iterBest, iterScore = -INF, nil, -INF
    local iterScores = {}
    for _, m in ipairs(root) do
      makeMove(g, m)
      local sc
      if isRep[m] then
        sc = 0
      else
        sc = -search(g, depth - 1, -INF, fullWindow and INF or -alpha, 1)
      end
      unmakeMove(g)
      if S.aborted then break end
      iterScores[m] = sc
      if sc > iterScore then iterScore, iterBest = sc, m end
      if sc > alpha then alpha = sc end
    end
    if S.aborted then break end
    best, bestScore, scores = iterBest, iterScore, iterScores
    S.depthDone = depth
    S.canAbort = true
    -- best move first next time round
    table.sort(root, function(a, c) return (scores[a] or -INF) > (scores[c] or -INF) end)
    if bestScore >= MATE - 100 then break end
    if AI.now() - start > p.time * 0.45 then break end
  end

  if p.noise > 0 then
    local pick, pickScore = best, -INF
    for _, m in ipairs(root) do
      local sc = scores[m]
      if sc then
        local n = (math.random() * 2 - 1) * p.noise
        if sc >= MATE - 100 and p.noise < 100 then n = 0 end   -- don't miss mate (from Casual up)
        if sc + n > pickScore then pickScore, pick = sc + n, m end
      end
    end
    best = pick
  end
  AI.lastNodes, AI.lastDepth, AI.lastScore = S.nodes, S.depthDone, bestScore
  return best
end

return AI
