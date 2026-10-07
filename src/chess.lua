-- chess.lua - the rules of chess
--
-- Board representation, move generation, check/checkmate/draw detection,
-- notation (SAN), and an incremental position score used by the computer.
-- Pure Lua with no Vita code, so it runs (and is tested) on a PC too.

local Chess = {}


local abs, floor = math.abs, math.floor
local OFF = 99                                   -- off-board marker
local PAWN, KNIGHT, BISHOP, ROOK, QUEEN, KING = 1, 2, 3, 4, 5, 6
local FLAG_DOUBLE, FLAG_EP, FLAG_CASTLE = 1, 2, 3
local PROMOS = { QUEEN, ROOK, BISHOP, KNIGHT }

local KNIGHT_D = { -21, -19, -12, -8, 8, 12, 19, 21 }
local KING_D   = { -11, -10, -9, -1, 1, 9, 10, 11 }
local BISHOP_D = { -11, -9, 9, 11 }
local ROOK_D   = { -10, -1, 1, 10 }

local FILES = "abcdefgh"
local PIECE_CHAR = { "P", "N", "B", "R", "Q", "K" }
local CHAR_PIECE = { p = 1, n = 2, b = 3, r = 4, q = 5, k = 6 }
Chess.START_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

-- 10x12 mailbox board. a1 = 91, h1 = 98, a8 = 21, h8 = 28.
local function sq(f, r) return 91 + f - r * 10 end
local function fileOf(s) return s % 10 - 1 end
local function rankOf(s) return 9 - floor(s / 10) end
local function sqName(s)
  local f = fileOf(s)
  return FILES:sub(f + 1, f + 1) .. (rankOf(s) + 1)
end
Chess.sq, Chess.fileOf, Chess.rankOf, Chess.sqName = sq, fileOf, rankOf, sqName

-- Evaluation tables (centipawns). Written from White's view, rank 8 first.
local VAL = { 100, 320, 330, 500, 900, 0 }
local PST = {
  { 0,0,0,0,0,0,0,0, 50,50,50,50,50,50,50,50, 10,10,20,30,30,20,10,10, 5,5,10,25,25,10,5,5,
    0,0,0,20,20,0,0,0, 5,-5,-10,0,0,-10,-5,5, 5,10,10,-20,-20,10,10,5, 0,0,0,0,0,0,0,0 },
  { -50,-40,-30,-30,-30,-30,-40,-50, -40,-20,0,0,0,0,-20,-40, -30,0,10,15,15,10,0,-30,
    -30,5,15,20,20,15,5,-30, -30,0,15,20,20,15,0,-30, -30,5,10,15,15,10,5,-30,
    -40,-20,0,5,5,0,-20,-40, -50,-40,-30,-30,-30,-30,-40,-50 },
  { -20,-10,-10,-10,-10,-10,-10,-20, -10,0,0,0,0,0,0,-10, -10,0,5,10,10,5,0,-10,
    -10,5,5,10,10,5,5,-10, -10,0,10,10,10,10,0,-10, -10,10,10,10,10,10,10,-10,
    -10,5,0,0,0,0,5,-10, -20,-10,-10,-10,-10,-10,-10,-20 },
  { 0,0,0,0,0,0,0,0, 5,10,10,10,10,10,10,5, -5,0,0,0,0,0,0,-5, -5,0,0,0,0,0,0,-5,
    -5,0,0,0,0,0,0,-5, -5,0,0,0,0,0,0,-5, -5,0,0,0,0,0,0,-5, 0,0,0,5,5,0,0,0 },
  { -20,-10,-10,-5,-5,-10,-10,-20, -10,0,0,0,0,0,0,-10, -10,0,5,5,5,5,0,-10,
    -5,0,5,5,5,5,0,-5, 0,0,5,5,5,5,0,-5, -10,5,5,5,5,5,0,-10,
    -10,0,5,0,0,0,0,-10, -20,-10,-10,-5,-5,-10,-10,-20 },
  { -30,-40,-40,-50,-50,-40,-40,-30, -30,-40,-40,-50,-50,-40,-40,-30,
    -30,-40,-40,-50,-50,-40,-40,-30, -30,-40,-40,-50,-50,-40,-40,-30,
    -20,-30,-30,-40,-40,-30,-30,-20, -10,-20,-20,-20,-20,-20,-20,-10,
    20,20,0,0,0,0,20,20, 20,30,10,0,0,10,30,20 },
}
local KING_EG = {
  -50,-40,-30,-20,-20,-30,-40,-50, -30,-20,-10,0,0,-10,-20,-30, -30,-10,20,30,30,20,-10,-30,
  -30,-10,30,40,40,30,-10,-30, -30,-10,30,40,40,30,-10,-30, -30,-10,20,30,30,20,-10,-30,
  -30,-30,0,0,0,0,-30,-30, -50,-30,-30,-30,-30,-30,-30,-50 }

-- PV[piece][square] = signed value (material + position), White positive
local PV, KEGD = {}, {}
for t = 1, 6 do
  for side = -1, 1, 2 do
    local p = t * side
    PV[p] = {}
    if t == KING then KEGD[p] = {} end
    for r = 0, 7 do
      for f = 0, 7 do
        local s = sq(f, r)
        local idx = (side == 1) and ((7 - r) * 8 + f + 1) or (r * 8 + f + 1)
        PV[p][s] = side * (VAL[t] + PST[t][idx])
        if t == KING then KEGD[p][s] = side * (KING_EG[idx] - PST[6][idx]) end
      end
    end
  end
end

-- Is square s attacked by side `by` (1 = white, -1 = black)?
local function attacked(g, s, by)
  local b = g.board
  if by == 1 then
    if b[s + 9] == PAWN or b[s + 11] == PAWN then return true end
  else
    if b[s - 9] == -PAWN or b[s - 11] == -PAWN then return true end
  end
  local kn, kg = KNIGHT * by, KING * by
  for i = 1, 8 do
    if b[s + KNIGHT_D[i]] == kn then return true end
    if b[s + KING_D[i]] == kg then return true end
  end
  local bb, rr, qq = BISHOP * by, ROOK * by, QUEEN * by
  for i = 1, 4 do
    local d = BISHOP_D[i]
    local t = s + d
    while b[t] == 0 do t = t + d end
    local p = b[t]
    if p == bb or p == qq then return true end
    d = ROOK_D[i]
    t = s + d
    while b[t] == 0 do t = t + d end
    p = b[t]
    if p == rr or p == qq then return true end
  end
  return false
end
Chess.attacked = attacked

local function inCheck(g) return attacked(g, g.kingSq[g.side], -g.side) end
Chess.inCheck = inCheck

local function addMove(list, from, to, promo, flag)
  list[#list + 1] = { from = from, to = to, promo = promo or 0, flag = flag or 0 }
end

local function addPawnMove(list, from, to, promoRank, flag)
  if rankOf(to) == promoRank then
    for i = 1, 4 do addMove(list, from, to, PROMOS[i], 0) end
  else
    addMove(list, from, to, 0, flag)
  end
end

-- Pseudo-legal moves (may leave own king in check; filtered later).
-- capsOnly = captures and promotions only (used by the computer's search).
local function genPseudo(g, capsOnly)
  local list = {}
  local b, side = g.board, g.side
  for s = 21, 98 do
    local p = b[s]
    if p ~= OFF and p ~= 0 and (p > 0) == (side > 0) then
      local t = abs(p)
      if t == PAWN then
        local dir = -10 * side
        local promoRank = (side == 1) and 7 or 0
        local startRank = (side == 1) and 1 or 6
        local one = s + dir
        if b[one] == 0 and (not capsOnly or rankOf(one) == promoRank) then
          addPawnMove(list, s, one, promoRank, 0)
          if not capsOnly and rankOf(s) == startRank and b[one + dir] == 0 then
            addMove(list, s, one + dir, 0, FLAG_DOUBLE)
          end
        end
        for k = -1, 1, 2 do
          local to = s + dir + k
          local q = b[to]
          if q ~= OFF and q ~= 0 and (q > 0) ~= (side > 0) then
            addPawnMove(list, s, to, promoRank, 0)
          elseif g.ep ~= 0 and to == g.ep then
            addMove(list, s, to, 0, FLAG_EP)
          end
        end
      elseif t == KNIGHT or t == KING then
        local ds = (t == KNIGHT) and KNIGHT_D or KING_D
        for i = 1, 8 do
          local to = s + ds[i]
          local q = b[to]
          if q == 0 then
            if not capsOnly then addMove(list, s, to) end
          elseif q ~= OFF and (q > 0) ~= (side > 0) then
            addMove(list, s, to)
          end
        end
      else
        local ds = (t == BISHOP) and BISHOP_D or (t == ROOK) and ROOK_D or KING_D
        for i = 1, #ds do
          local d = ds[i]
          local to = s + d
          while true do
            local q = b[to]
            if q == 0 then
              if not capsOnly then addMove(list, s, to) end
            elseif q == OFF then
              break
            else
              if (q > 0) ~= (side > 0) then addMove(list, s, to) end
              break
            end
            to = to + d
          end
        end
      end
    end
  end
  if capsOnly then return list end
  -- Castling (rights + empty squares + king not passing through check)
  if side == 1 then
    if g.cwk and b[95] == KING and b[98] == ROOK and b[96] == 0 and b[97] == 0
       and not attacked(g, 95, -1) and not attacked(g, 96, -1) and not attacked(g, 97, -1) then
      addMove(list, 95, 97, 0, FLAG_CASTLE)
    end
    if g.cwq and b[95] == KING and b[91] == ROOK and b[94] == 0 and b[93] == 0 and b[92] == 0
       and not attacked(g, 95, -1) and not attacked(g, 94, -1) and not attacked(g, 93, -1) then
      addMove(list, 95, 93, 0, FLAG_CASTLE)
    end
  else
    if g.cbk and b[25] == -KING and b[28] == -ROOK and b[26] == 0 and b[27] == 0
       and not attacked(g, 25, 1) and not attacked(g, 26, 1) and not attacked(g, 27, 1) then
      addMove(list, 25, 27, 0, FLAG_CASTLE)
    end
    if g.cbq and b[25] == -KING and b[21] == -ROOK and b[24] == 0 and b[23] == 0 and b[22] == 0
       and not attacked(g, 25, 1) and not attacked(g, 24, 1) and not attacked(g, 23, 1) then
      addMove(list, 25, 23, 0, FLAG_CASTLE)
    end
  end
  return list
end
Chess.genPseudo = genPseudo

local function makeMove(g, m)
  local b, side = g.board, g.side
  local from, to = m.from, m.to
  local piece = b[from]
  local u = { m = m, piece = piece, cap = b[to], capSq = to,
              cwk = g.cwk, cwq = g.cwq, cbk = g.cbk, cbq = g.cbq,
              ep = g.ep, half = g.half, score = g.score, npm = g.npm }
  local score = g.score - PV[piece][from]
  if m.flag == FLAG_EP then
    u.capSq = to + 10 * side
    u.cap = b[u.capSq]
    b[u.capSq] = 0
  end
  local cap = u.cap
  if cap ~= 0 then
    score = score - PV[cap][u.capSq]
    if cap ~= PAWN and cap ~= -PAWN then g.npm = g.npm - VAL[abs(cap)] end
  end
  local newp = piece
  if m.promo ~= 0 then
    newp = m.promo * side
    g.npm = g.npm + VAL[m.promo]
  end
  b[to] = newp
  b[from] = 0
  score = score + PV[newp][to]
  if m.flag == FLAG_CASTLE then
    local rook = ROOK * side
    if to > from then
      b[from + 1] = rook; b[from + 3] = 0
      score = score - PV[rook][from + 3] + PV[rook][from + 1]
    else
      b[from - 1] = rook; b[from - 4] = 0
      score = score - PV[rook][from - 4] + PV[rook][from - 1]
    end
  end
  g.score = score
  if piece == KING or piece == -KING then
    g.kingSq[side] = to
    if side == 1 then g.cwk, g.cwq = false, false else g.cbk, g.cbq = false, false end
  end
  if from == 98 or to == 98 then g.cwk = false end
  if from == 91 or to == 91 then g.cwq = false end
  if from == 28 or to == 28 then g.cbk = false end
  if from == 21 or to == 21 then g.cbq = false end
  g.ep = (m.flag == FLAG_DOUBLE) and floor((from + to) / 2) or 0
  if piece == PAWN or piece == -PAWN or cap ~= 0 then g.half = 0 else g.half = g.half + 1 end
  if side == -1 then g.full = g.full + 1 end
  g.side = -side
  g.hist[#g.hist + 1] = u
end

local function unmakeMove(g)
  local h = g.hist
  local u = h[#h]
  h[#h] = nil
  local m, b = u.m, g.board
  g.side = -g.side
  local side = g.side
  b[m.from] = u.piece
  b[m.to] = 0
  b[u.capSq] = u.cap
  if m.flag == FLAG_CASTLE then
    if m.to > m.from then b[m.from + 3] = b[m.from + 1]; b[m.from + 1] = 0
    else b[m.from - 4] = b[m.from - 1]; b[m.from - 1] = 0 end
  end
  if u.piece == KING or u.piece == -KING then g.kingSq[side] = m.from end
  g.cwk, g.cwq, g.cbk, g.cbq = u.cwk, u.cwq, u.cbk, u.cbq
  g.ep, g.half, g.score, g.npm = u.ep, u.half, u.score, u.npm
  if side == -1 then g.full = g.full - 1 end
end
Chess.makeMove, Chess.unmakeMove = makeMove, unmakeMove

-- Score from the side to move's point of view (centipawns)
function Chess.evaluate(g)
  local s = g.score
  if g.npm <= 1800 then  -- endgame: king should come to the centre
    s = s + KEGD[KING][g.kingSq[1]] + KEGD[-KING][g.kingSq[-1]]
  end
  return s * g.side
end

function Chess.computeScore(g)
  local score, npm = 0, 0
  for s = 21, 98 do
    local p = g.board[s]
    if p ~= OFF and p ~= 0 then
      score = score + PV[p][s]
      local t = abs(p)
      if t ~= PAWN and t ~= KING then npm = npm + VAL[t] end
    end
  end
  return score, npm
end

function Chess.legalMoves(g)
  local out, side = {}, g.side
  local pseudo = genPseudo(g)
  for i = 1, #pseudo do
    local m = pseudo[i]
    makeMove(g, m)
    if not attacked(g, g.kingSq[side], -side) then out[#out + 1] = m end
    unmakeMove(g)
  end
  return out
end

function Chess.perft(g, depth)
  if depth == 0 then return 1 end
  local moves = Chess.legalMoves(g)
  if depth == 1 then return #moves end
  local n = 0
  for i = 1, #moves do
    makeMove(g, moves[i])
    n = n + Chess.perft(g, depth - 1)
    unmakeMove(g)
  end
  return n
end

-- Position key for threefold repetition
function Chess.key(g)
  local t, b = {}, g.board
  for s = 21, 98 do
    local p = b[s]
    if p ~= OFF then t[#t + 1] = string.char(p + 70) end
  end
  t[#t + 1] = (g.side == 1) and "w" or "b"
  t[#t + 1] = (g.cwk and "K" or "") .. (g.cwq and "Q" or "") .. (g.cbk and "k" or "") .. (g.cbq and "q" or "")
  if g.ep ~= 0 then  -- only counts if a pawn could actually take en passant
    local s1, s2 = g.ep + 9 * g.side, g.ep + 11 * g.side
    if b[s1] == PAWN * g.side or b[s2] == PAWN * g.side then t[#t + 1] = tostring(g.ep) end
  end
  return table.concat(t)
end

local function insufficientMaterial(g)
  local knights, light, dark = 0, 0, 0
  for s = 21, 98 do
    local p = g.board[s]
    if p ~= OFF and p ~= 0 then
      local t = abs(p)
      if t == PAWN or t == ROOK or t == QUEEN then return false end
      if t == KNIGHT then knights = knights + 1
      elseif t == BISHOP then
        if (fileOf(s) + rankOf(s)) % 2 == 0 then dark = dark + 1 else light = light + 1 end
      end
    end
  end
  if knights + light + dark <= 1 then return true end
  if knights == 0 and (light == 0 or dark == 0) then return true end
  return false
end

function Chess.updateStatus(g)
  g.legal = Chess.legalMoves(g)
  g.check = inCheck(g)
  g.result, g.winner = nil, nil
  if #g.legal == 0 then
    if g.check then g.result, g.winner = "checkmate", -g.side
    else g.result = "stalemate" end
  elseif g.half >= 100 then
    g.result = "fifty"
  else
    local cur, reps = g.keys[#g.keys], 0
    for i = 1, #g.keys do if g.keys[i] == cur then reps = reps + 1 end end
    if reps >= 3 then g.result = "repetition"
    elseif insufficientMaterial(g) then g.result = "material" end
  end
end

-- Standard algebraic notation for move m (must be legal in position g)
function Chess.san(g, m, legal)
  local b = g.board
  local piece = abs(b[m.from])
  local s
  if m.flag == FLAG_CASTLE then
    s = (m.to > m.from) and "O-O" or "O-O-O"
  else
    local capture = (b[m.to] ~= 0) or (m.flag == FLAG_EP)
    if piece == PAWN then
      s = capture and (FILES:sub(fileOf(m.from) + 1, fileOf(m.from) + 1) .. "x") or ""
      s = s .. sqName(m.to)
      if m.promo ~= 0 then s = s .. "=" .. PIECE_CHAR[m.promo] end
    else
      s = PIECE_CHAR[piece]
      local ambiguous, sameFile, sameRank = false, false, false
      for i = 1, #legal do
        local o = legal[i]
        if o.to == m.to and o.from ~= m.from and abs(b[o.from]) == piece then
          ambiguous = true
          if fileOf(o.from) == fileOf(m.from) then sameFile = true end
          if rankOf(o.from) == rankOf(m.from) then sameRank = true end
        end
      end
      if ambiguous then
        if not sameFile then s = s .. FILES:sub(fileOf(m.from) + 1, fileOf(m.from) + 1)
        elseif not sameRank then s = s .. (rankOf(m.from) + 1)
        else s = s .. sqName(m.from) end
      end
      if capture then s = s .. "x" end
      s = s .. sqName(m.to)
    end
  end
  makeMove(g, m)
  if inCheck(g) then s = s .. ((#Chess.legalMoves(g) == 0) and "#" or "+") end
  unmakeMove(g)
  return s
end

function Chess.fromFEN(fen)
  local g = { board = {}, kingSq = {}, hist = {}, played = {}, keys = {} }
  local b = g.board
  for i = 0, 119 do b[i] = OFF end
  for r = 0, 7 do for f = 0, 7 do b[sq(f, r)] = 0 end end
  local parts = {}
  for w in fen:gmatch("%S+") do parts[#parts + 1] = w end
  local f, r = 0, 7
  for ch in parts[1]:gmatch(".") do
    if ch == "/" then
      r, f = r - 1, 0
    elseif ch:match("%d") then
      f = f + tonumber(ch)
    else
      local t = CHAR_PIECE[ch:lower()]
      local side = ch:match("%u") and 1 or -1
      b[sq(f, r)] = t * side
      if t == KING then g.kingSq[side] = sq(f, r) end
      f = f + 1
    end
  end
  g.side = (parts[2] == "b") and -1 or 1
  local c = parts[3] or "-"
  g.cwk = c:find("K", 1, true) ~= nil
  g.cwq = c:find("Q", 1, true) ~= nil
  g.cbk = c:find("k", 1, true) ~= nil
  g.cbq = c:find("q", 1, true) ~= nil
  g.ep = 0
  local e = parts[4] or "-"
  if e ~= "-" then g.ep = sq(e:byte(1) - 97, tonumber(e:sub(2)) - 1) end
  g.half = tonumber(parts[5] or "0") or 0
  g.full = tonumber(parts[6] or "1") or 1
  g.score, g.npm = Chess.computeScore(g)
  g.keys[1] = Chess.key(g)
  Chess.updateStatus(g)
  return g
end

function Chess.newGame() return Chess.fromFEN(Chess.START_FEN) end

-- The current position as a FEN string (side = override who moves, optional)
function Chess.toFEN(g, side)
  local rows = {}
  for r = 7, 0, -1 do
    local row, empty = "", 0
    for f = 0, 7 do
      local p = g.board[sq(f, r)]
      if p == 0 then
        empty = empty + 1
      else
        if empty > 0 then row = row .. empty; empty = 0 end
        local c = PIECE_CHAR[abs(p)]
        row = row .. ((p > 0) and c or c:lower())
      end
    end
    if empty > 0 then row = row .. empty end
    rows[#rows + 1] = row
  end
  side = side or g.side
  local castle = (g.cwk and "K" or "") .. (g.cwq and "Q" or "") .. (g.cbk and "k" or "") .. (g.cbq and "q" or "")
  return table.concat(rows, "/") .. " " .. ((side == 1) and "w" or "b") .. " " ..
    ((castle == "") and "-" or castle) .. " " .. ((g.ep ~= 0) and sqName(g.ep) or "-") ..
    " " .. g.half .. " " .. g.full
end

-- Independent copy of a position (the computer searches on a copy so the
-- screen never shows its half-finished "what if" moves)
function Chess.clone(g)
  local c = { board = {}, kingSq = { [1] = g.kingSq[1], [-1] = g.kingSq[-1] },
              hist = {}, played = {}, keys = {} }
  for i = 0, 119 do c.board[i] = g.board[i] end
  c.side, c.ep, c.half, c.full = g.side, g.ep, g.half, g.full
  c.cwk, c.cwq, c.cbk, c.cbq = g.cwk, g.cwq, g.cbk, g.cbq
  c.score, c.npm = g.score, g.npm
  for i = 1, #g.keys do c.keys[i] = g.keys[i] end
  c.legal = Chess.legalMoves(c)
  return c
end

-- Play a legal move for real (records notation, updates game status)
function Chess.play(g, m)
  local san = Chess.san(g, m, g.legal)
  local cap = g.board[m.to]
  if m.flag == FLAG_EP then cap = -PAWN * g.side end
  makeMove(g, m)
  g.played[#g.played + 1] = { m = m, san = san, cap = cap }   -- cap = piece taken (0 if none)
  g.keys[#g.keys + 1] = Chess.key(g)
  Chess.updateStatus(g)
end

function Chess.undo(g)
  if #g.played == 0 then return false end
  unmakeMove(g)
  table.remove(g.played)
  table.remove(g.keys)
  Chess.updateStatus(g)
  return true
end

-- Material on the board in pawns (P=1, N=3, B=3, R=5, Q=9): white, black
local POINTS = { 1, 3, 3, 5, 9, 0 }
function Chess.material(g)
  local w, b = 0, 0
  for s = 21, 98 do
    local p = g.board[s]
    if p ~= OFF and p ~= 0 then
      if p > 0 then w = w + POINTS[p] else b = b + POINTS[-p] end
    end
  end
  return w, b
end

-- Could `side` ever deliver checkmate with the pieces it has left?
-- (Used when a clock runs out: no mating material means a draw.)
function Chess.hasMatingMaterial(g, side)
  local minors = 0
  for s = 21, 98 do
    local p = g.board[s]
    if p ~= OFF and p * side > 0 and abs(p) ~= KING then
      p = abs(p)
      if p == KNIGHT or p == BISHOP then minors = minors + 1 else return true end
    end
  end
  return minors >= 2
end

function Chess.findMove(g, from, to, promo)
  for _, m in ipairs(g.legal) do
    if m.from == from and m.to == to and m.promo == (promo or 0) then return m end
  end
  return nil
end

return Chess
