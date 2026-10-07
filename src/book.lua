-- book.lua - a small opening book
--
-- While a game still follows one of these lines, the computer picks a random
-- book move instead of searching. That gives it varied, natural openings
-- (and saves thinking time). Add lines freely: standard notation, one move
-- after another. tests/test_rules.lua checks every line is legal.

local Chess = require("chess")

local LINES = {
  -- 1.e4 e5
  "e4 e5 Nf3 Nc6 Bc4 Bc5 c3 Nf6 d3 d6 O-O O-O",            -- Italian (Giuoco Piano)
  "e4 e5 Nf3 Nc6 Bc4 Nf6 d3 Be7 O-O O-O Re1 d6",           -- Two Knights, quiet
  "e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6 O-O Be7 Re1 b5 Bb3 d6",    -- Ruy Lopez, closed
  "e4 e5 Nf3 Nc6 Bb5 Nf6 O-O Nxe4 d4 Nd6 Bxc6 dxc6",       -- Ruy Lopez, Berlin
  "e4 e5 Nf3 Nc6 d4 exd4 Nxd4 Nf6 Nxc6 bxc6 e5 Qe7",       -- Scotch
  "e4 e5 Nf3 Nf6 Nxe5 d6 Nf3 Nxe4 d4 d5 Bd3 Nc6",          -- Petrov
  "e4 e5 Nc3 Nf6 Nf3 Nc6 Bb5 Bb4 O-O O-O",                 -- Four Knights
  "e4 e5 Nf3 d6 d4 Nf6 Nc3 Nbd7 Bc4 Be7 O-O O-O",          -- Philidor
  -- Sicilian
  "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be2 e5 Nb3 Be7",   -- Najdorf
  "e4 c5 Nf3 Nc6 d4 cxd4 Nxd4 Nf6 Nc3 e5 Ndb5 d6",         -- Sveshnikov
  "e4 c5 Nf3 e6 d4 cxd4 Nxd4 Nc6 Nc3 Qc7 Be2 a6",          -- Taimanov
  "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 g6 Be3 Bg7 f3 O-O",   -- Dragon
  "e4 c5 c3 Nf6 e5 Nd5 d4 cxd4 Nf3 Nc6 cxd4 d6",           -- Alapin
  "e4 c5 Nc3 Nc6 g3 g6 Bg2 Bg7 d3 d6",                     -- Closed Sicilian
  -- other replies to 1.e4
  "e4 e6 d4 d5 Nc3 Nf6 Bg5 Be7 e5 Nfd7 Bxe7 Qxe7",         -- French, classical
  "e4 e6 d4 d5 e5 c5 c3 Nc6 Nf3 Qb6 a3 c4",                -- French, advance
  "e4 e6 d4 d5 Nd2 Nf6 e5 Nfd7 Bd3 c5 c3 Nc6",             -- French, Tarrasch
  "e4 c6 d4 d5 Nc3 dxe4 Nxe4 Bf5 Ng3 Bg6 h4 h6",           -- Caro-Kann, classical
  "e4 c6 d4 d5 e5 Bf5 Nf3 e6 Be2 c5 Be3",                  -- Caro-Kann, advance
  "e4 d5 exd5 Qxd5 Nc3 Qa5 d4 Nf6 Nf3 Bf5 Bc4 e6",         -- Scandinavian
  "e4 d6 d4 Nf6 Nc3 g6 Nf3 Bg7 Be2 O-O O-O c6",            -- Pirc
  "e4 Nf6 e5 Nd5 d4 d6 Nf3 Bg4 Be2 e6 O-O Be7",            -- Alekhine
  -- 1.d4 d5
  "d4 d5 c4 e6 Nc3 Nf6 Bg5 Be7 e3 O-O Nf3 h6",             -- Queen's Gambit Declined
  "d4 d5 c4 dxc4 Nf3 Nf6 e3 e6 Bxc4 c5 O-O a6",            -- Queen's Gambit Accepted
  "d4 d5 c4 c6 Nf3 Nf6 Nc3 dxc4 a4 Bf5 e3 e6",             -- Slav
  "d4 d5 c4 c6 Nc3 Nf6 e3 e6 Nf3 Nbd7 Bd3 dxc4",           -- Semi-Slav
  "d4 d5 Nf3 Nf6 Bf4 e6 e3 c5 c3 Nc6 Nbd2 Bd6",            -- London
  "d4 d5 Bf4 Nf6 e3 c5 c3 Nc6 Nd2 e6 Ngf3 Bd6",            -- London (2.Bf4)
  -- 1.d4 Nf6
  "d4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5",             -- King's Indian
  "d4 Nf6 c4 e6 Nc3 Bb4 e3 O-O Bd3 d5 Nf3 c5",             -- Nimzo-Indian
  "d4 Nf6 c4 e6 Nf3 b6 g3 Ba6 b3 Bb4 Bd2 Be7",             -- Queen's Indian
  "d4 Nf6 c4 g6 Nc3 d5 cxd5 Nxd5 e4 Nxc3 bxc3 Bg7",        -- Grunfeld
  "d4 Nf6 c4 c5 d5 e6 Nc3 exd5 cxd5 d6 e4 g6",             -- Benoni
  "d4 Nf6 Nf3 g6 Bf4 Bg7 e3 O-O Be2 d6 h3",                -- London vs King's Indian
  "d4 f5 g3 Nf6 Bg2 e6 Nf3 Be7 O-O O-O c4 d6",             -- Dutch
  -- flank openings
  "c4 e5 Nc3 Nf6 Nf3 Nc6 g3 d5 cxd5 Nxd5 Bg2 Nb6",         -- English, reversed Sicilian
  "c4 c5 Nc3 Nc6 g3 g6 Bg2 Bg7 Nf3 Nf6 O-O O-O",           -- Symmetrical English
  "c4 Nf6 Nc3 e6 e4 d5 e5 d4 exf6 dxc3",                   -- English, Mikenas
  "Nf3 d5 g3 Nf6 Bg2 c6 O-O Bg4 d3 Nbd7",                  -- Reti / King's Indian Attack
  "Nf3 Nf6 c4 g6 Nc3 Bg7 e4 d6 d4 O-O",                    -- transposes to King's Indian
  "g3 d5 Bg2 Nf6 Nf3 c6 O-O Bg4 d3 Nbd7",                  -- King's Fianchetto
}

local Book = {}
local tree   -- [ "e4 e5 Nf3" ] = { "Nc6", "Nf6", "d6" }

local function build()
  tree = {}
  for _, line in ipairs(LINES) do
    local moves, prefix = {}, ""
    for san in line:gmatch("%S+") do moves[#moves + 1] = san end
    for i = 1, #moves do
      local nexts = tree[prefix] or {}
      tree[prefix] = nexts
      local seen = false
      for _, m in ipairs(nexts) do if m == moves[i] then seen = true end end
      if not seen then nexts[#nexts + 1] = moves[i] end
      prefix = (prefix == "") and moves[i] or (prefix .. " " .. moves[i])
    end
  end
end

-- Returns a legal book move for game g, or nil once the game leaves the book.
-- The game must have started from the normal starting position.
function Book.pick(g)
  if not tree then build() end
  local sans = {}
  for i, rec in ipairs(g.played) do sans[i] = (rec.san:gsub("[+#]", "")) end
  local nexts = tree[table.concat(sans, " ")]
  if not nexts then return nil end
  local want = nexts[math.random(#nexts)]
  for _, m in ipairs(g.legal) do
    if (Chess.san(g, m, g.legal):gsub("[+#]", "")) == want then return m end
  end
  return nil
end

Book.LINES = LINES
return Book
