-- Rules engine + computer player tests. Run from the repo root:
--   luajit tests/test_rules.lua
package.path = "src/?.lua;" .. package.path
local Chess = require("chess")
local AI = require("ai")

local failures = 0
local function check(cond, msg)
  if cond then print("  ok   " .. msg) else print("  FAIL " .. msg); failures = failures + 1 end
end

local function playSan(g, san)
  for _, m in ipairs(g.legal) do
    if Chess.san(g, m, g.legal) == san then Chess.play(g, m); return end
  end
  error("no legal move " .. san)
end

local function sanList(g)
  local t = {}
  for _, m in ipairs(g.legal) do t[#t + 1] = Chess.san(g, m, g.legal) end
  table.sort(t)
  return table.concat(t, " ")
end

print("Perft (move generation counts vs published values)")
local PERFT = {
  { "start position", Chess.START_FEN, { 20, 400, 8902, 197281 } },
  { "kiwipete", "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", { 48, 2039, 97862 } },
  { "position 3", "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", { 14, 191, 2812, 43238 } },
  { "position 4", "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1", { 6, 264, 9467 } },
  { "position 5", "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8", { 44, 1486, 62379 } },
  { "position 6", "r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10", { 46, 2079, 89890 } },
}
for _, t in ipairs(PERFT) do
  local g, ok = Chess.fromFEN(t[2]), true
  for d, expected in ipairs(t[3]) do
    if Chess.perft(g, d) ~= expected then ok = false end
  end
  check(ok, t[1])
end

print("Game rules")
local g = Chess.newGame()
for _, s in ipairs({ "e4", "e5", "Bc4", "Nc6", "Qh5", "Nf6", "Qxf7#" }) do playSan(g, s) end
check(g.result == "checkmate" and g.winner == 1, "scholar's mate is checkmate")
Chess.undo(g)
check(g.result == nil and #g.played == 6, "undo reverses checkmate")

g = Chess.newGame()
for _, s in ipairs({ "Nf3", "Nf6", "Ng1", "Ng8", "Nf3", "Nf6", "Ng1" }) do playSan(g, s) end
check(g.result == nil, "no draw before third repetition")
playSan(g, "Ng8")
check(g.result == "repetition", "threefold repetition")

check(Chess.fromFEN("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1").result == "stalemate", "stalemate")
check(Chess.fromFEN("8/8/8/4k3/8/8/8/4KB2 w - - 0 1").result == "material", "K+B vs K is a draw")
check(Chess.fromFEN("4k3/8/8/8/8/8/8/4K2R w K - 99 80").result == nil, "49.5 moves is not yet a draw")
check(sanList(Chess.fromFEN("4k3/8/8/8/8/8/8/R3K2R w KQ - 0 1")):find("O-O O-O-O", 1, true) ~= nil, "castling both sides")
check(sanList(Chess.fromFEN("4k3/8/8/8/8/2N3N1/8/4K3 w - - 0 1")):find("Nce2", 1, true) ~= nil, "SAN disambiguation")
local promoSans = sanList(Chess.fromFEN("4k3/1P6/8/3pP3/8/8/8/4K3 w - d6 0 1"))
check(promoSans:find("b8=Q+", 1, true) and promoSans:find("exd6", 1, true), "promotion and en passant")

print("Incremental evaluation matches a full recount")
math.randomseed(3)
local mismatches = 0
for _ = 1, 60 do
  g = Chess.newGame()
  for _ = 1, 150 do
    if g.result then break end
    Chess.play(g, g.legal[math.random(#g.legal)])
    local s, n = Chess.computeScore(g)
    if s ~= g.score or n ~= g.npm then mismatches = mismatches + 1 end
  end
  while Chess.undo(g) do
    local s, n = Chess.computeScore(g)
    if s ~= g.score or n ~= g.npm then mismatches = mismatches + 1 end
  end
end
check(mismatches == 0, "random games and undos")

print("Computer player")
local function aiMove(fen, level)
  local pos = Chess.fromFEN(fen)
  local m = AI.think(pos, AI.LEVELS[level], false)
  return Chess.san(pos, m, pos.legal)
end
check(aiMove("6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1", 5) == "Rd8#", "finds back-rank mate in one")
check(aiMove("r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4", 4) == "Qxf7#", "finds scholar's mate")
check(aiMove("4k3/8/8/3q4/8/8/3R4/4K3 w - - 0 1", 3) == "Rxd5", "takes a hanging queen")

local legalOk = true
for level = 1, 5 do
  local p = {}
  for k, v in pairs(AI.LEVELS[level]) do p[k] = v end
  p.time = 100
  g = Chess.newGame()
  for _ = 1, 40 do
    if g.result then break end
    local m = AI.think(Chess.clone(g), p, false)
    m = m and Chess.findMove(g, m.from, m.to, m.promo)
    if not m then legalOk = false; break end
    Chess.play(g, m)
  end
end
check(legalOk, "levels 1-5 always play legal moves")

print("Opening book, PGN, material")
local Book = require("book")
local PGN = require("pgn")
local bookOk = true
for _, line in ipairs(Book.LINES) do
  local bg = Chess.newGame()
  for san in line:gmatch("%S+") do
    local found
    for _, m in ipairs(bg.legal) do
      if (Chess.san(bg, m, bg.legal):gsub("[+#]", "")) == san then found = m; break end
    end
    if not found then print("       illegal book move " .. san .. " in: " .. line); bookOk = false; break end
    Chess.play(bg, found)
  end
end
check(bookOk, "every book line is legal (" .. #Book.LINES .. " lines)")
local bg = Chess.newGame()
local inBook = true
for _ = 1, 6 do
  local m = Book.pick(bg)
  if not m then inBook = false; break end
  Chess.play(bg, m)
end
check(inBook, "book supplies the first 6 moves")
g = Chess.newGame()
for _, s in ipairs({ "e4", "e5", "Bc4", "Nc6", "Qh5", "Nf6", "Qxf7#" }) do playSan(g, s) end
local text = PGN.build(g, { white = "Player", black = "Computer", date = "2026.10.07", result = "1-0" })
check(text:find('[Result "1-0"]', 1, true) and text:find("1. e4 e5 2. Bc4 Nc6 3. Qh5 Nf6 4. Qxf7# 1-0", 1, true),
  "PGN export")
check(g.played[7].cap == -1, "capture is recorded on the move")
local w, b = Chess.material(g)
check(w == 39 and b == 38, "material count")
check(Chess.hasMatingMaterial(Chess.fromFEN("4k3/8/8/8/8/8/8/R3K3 w - - 0 1"), 1), "rook can mate")
check(not Chess.hasMatingMaterial(Chess.fromFEN("4k3/8/8/8/8/8/8/2B1K3 w - - 0 1"), 1), "lone bishop can't mate")

print("Puzzle collection")
local PROMO = { n = 2, b = 3, r = 4, q = 5 }
local function uciSq(u) return Chess.sq(u:byte(1) - 97, u:byte(2) - 49) end
local count, broken = 0, 0
for line in io.lines("assets/puzzles/puzzles.txt") do
  local id, fen, moves = line:match("^([^#,][^,]*),([^,]+),([^,]+),(%d+)$")
  if id then
    count = count + 1
    local ok = pcall(function()
      local pg = Chess.fromFEN(fen)
      for u in moves:gmatch("%S+") do
        local m = Chess.findMove(pg, uciSq(u:sub(1, 2)), uciSq(u:sub(3, 4)), PROMO[u:sub(5, 5)] or 0)
        assert(m)
        Chess.play(pg, m)
      end
    end)
    if not ok then broken = broken + 1; print("       broken puzzle " .. id) end
  end
end
check(count > 0 and broken == 0, "every puzzle's solution is legal (" .. count .. " puzzles)")

print("Learn lessons")
local Learn = require("learn")
do
local problems = 0
local function bad(where, msg) problems = problems + 1; print("       " .. where .. ": " .. msg) end

local DIRS = { [4] = { -10, -1, 1, 10 }, [3] = { -11, -9, 9, 11 }, [5] = { -11, -10, -9, -1, 1, 9, 10, 11 } }
local KN = { -21, -19, -12, -8, 8, 12, 19, 21 }
local KG = { -11, -10, -9, -1, 1, 9, 10, 11 }

for _, course in ipairs(Learn.COURSES) do
  for _, lesson in ipairs(course.lessons) do
    for si, step in ipairs(lesson.steps) do
      local where = course.id .. "/" .. lesson.id .. "#" .. si
      local ok, g = pcall(Chess.fromFEN, step.fen)
      if not ok then bad(where, "bad FEN " .. tostring(g)) goto next end
      if step.kind == "targets" then
        -- find the single non-king white piece and check every star is reachable
        local from, piece
        for s = 21, 98 do local p = g.board[s]; if p ~= 99 and p > 0 and p ~= 6 then from, piece = s, p end end
        if not from then
          for s = 21, 98 do if g.board[s] == 6 then from, piece = s, 6 end end
        end
        local seen, queue = { [from] = true }, { from }
        local i = 1
        while queue[i] do
          local s = queue[i]; i = i + 1
          local function add(t)
            if g.board[t] == 0 and not seen[t] then seen[t] = true; queue[#queue + 1] = t end
          end
          if piece == 2 then for _, d in ipairs(KN) do add(s + d) end
          elseif piece == 6 then
            for _, d in ipairs(KG) do
              local t = s + d
              local nearBK = false
              for _, e in ipairs(KG) do if g.board[t + e] == -6 then nearBK = true end end
              if not nearBK then add(t) end
            end
          else
            for _, d in ipairs(DIRS[piece]) do
              local t = s + d
              while g.board[t] == 0 do add(t); t = t + d end
            end
          end
        end
        for star in pairs(Learn.parseSquares(step.stars)) do
          if g.board[star] ~= 0 then bad(where, "star on occupied square " .. Chess.sqName(star)) end
          if not seen[star] then bad(where, "star unreachable " .. Chess.sqName(star)) end
        end
      elseif step.kind == "guide" then
        local side = (step.side == "b") and -1 or 1
        if g.side ~= side and step.moves[1] and #step.moves > 0 then
          -- the opponent moves first: fine, as long as every move is legal
        end
        for _, mv in ipairs(step.moves) do
          local m = Learn.toMove(g, mv[1])
          if not m then bad(where, "illegal guide move " .. mv[1]) break end
          if not mv[2] or #mv[2] == 0 then bad(where, "guide move without text " .. mv[1]) end
          Chess.play(g, m)
        end
      elseif step.kind == "play" then
        if g.result then bad(where, "drill starts already finished") end
        if step.goal ~= "mate" and step.goal ~= "promote" then bad(where, "unknown goal") end
        if not step.limit then bad(where, "drill without a move limit") end
      elseif step.kind == "find" then
        for _, u in ipairs(Learn.words(step.intro)) do
          local m = Learn.toMove(g, u)
          if not m then bad(where, "illegal intro " .. u) goto next end
          Chess.play(g, m)
        end
        local line = Learn.words(step.line)
        if step.verify == "best" then
          local m = AI.think(Chess.clone(g), { depth = 4, q = true, noise = 0, random = 0, time = 60000 }, false)
          if Learn.uci(m) ~= line[1] then bad(where, "engine prefers " .. Learn.uci(m) .. " over " .. line[1]) end
        end
        if #line > 0 then
          for i, u in ipairs(line) do
            local m = Learn.toMove(g, u)
            if not m then bad(where, "illegal line move " .. u) goto next end
            Chess.play(g, m)
            if i % 2 == 1 and not Learn.isCorrect(step, (i + 1) / 2, g) then bad(where, "line move judged wrong " .. u) end
          end
          if step.expect and g.result ~= step.expect then bad(where, "expected " .. step.expect .. ", got " .. tostring(g.result)) end
          if step.rule == nil and not step.expect and i == nil then end
        else
          local good, wrong = 0, 0
          for _, m in ipairs(g.legal) do
            local c = Chess.clone(g)
            Chess.play(c, Chess.findMove(c, m.from, m.to, m.promo))
            if Learn.isCorrect(step, 1, c) then good = good + 1 else wrong = wrong + 1 end
          end
          if good == 0 then bad(where, "no correct move exists") end
        end
      end
      ::next::
    end
  end
end
  local steps = 0
  for _, c in ipairs(Learn.COURSES) do for _, l in ipairs(c.lessons) do steps = steps + #l.steps end end
  check(problems == 0, "every lesson step checks out (" .. steps .. " steps)")
end

if failures > 0 then
  print(failures .. " test(s) failed")
  os.exit(1)
end
print("All rules tests passed")
