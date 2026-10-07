-- Plays the built game (build/VitaChess/index.lua) on a fake Vita: the
-- Lua Player Plus functions are replaced with stand-ins, and each scenario
-- feeds in taps and button presses and checks what appears on screen.
-- Run tools/build.py first, then from the repo root:  luajit tests/test_ui.lua
package.path = "src/?.lua;" .. package.path
local bit = require("bit")
local INDEX = "build/VitaChess/index.lua"

---------------------------------------------------------------------------
-- Fake Vita
---------------------------------------------------------------------------
local files, texts, frameTexts, soundsPlayed, script, step, idle, cur, waitUntil
local useBitmapFonts, glyphDraws = false, 0
local lastTexts = {}

local function installFakes()
  local imgs = {}
  Graphics = {
    loadImage = function(p) imgs[#imgs + 1] = p; return #imgs end,
    fillRect = function() end, fillCircle = function() end,
    drawImage = function() end, drawScaleImage = function() end,
    setImageFilters = function() end,
    drawImageExtended = function(x, y, img, sx, sy, w, h, rad, scx, scy, c)
      assert(type(rad) == "number" and type(scx) == "number" and type(c) == "number", "bad drawImageExtended call")
    end,
    drawPartialImage = function(x, y, img, sx, sy, w, h, c)
      assert(x == math.floor(x) and y == math.floor(y), "glyph drawn at a fractional position")
      assert(type(c) == "number", "glyph drawn without a colour")
      glyphDraws = glyphDraws + 1
    end,
    debugPrint = function(x, y, s) assert(type(s) == "string"); frameTexts[#frameTexts + 1] = s end,
    initBlend = function() frameTexts = {} end,
    termBlend = function() lastTexts = frameTexts end,
  }
  Font = {
    load = function(path) return { path = path } end, setPixelSizes = function() end,
    print = function(f, x, y, s) assert(type(s) == "string"); frameTexts[#frameTexts + 1] = s end,
    getTextWidth = function(f, s) return #s * 9 end,
  }
  Screen = { clear = function() end, flip = function() end, waitVblankStart = function() end }
  Color = { new = function(r, g, b, a) return r + g * 256 + b * 65536 + (a or 255) * 16777216 end }
  Timer = { new = function() return 1 end, getTime = function() return math.floor(os.clock() * 1000) end }
  Sound = { init = function() end, open = function(p) return p end,
            play = function(h, loop) assert(loop == false); soundsPlayed = soundsPlayed + 1 end }
  System = {
    setCpuSpeed = function() end, exit = function() error("EXIT") end,
    doesFileExist = function(p)
      -- most scenarios hide the bitmap fonts so the fake can read text from debugPrint
      if p:find("fonts/bitmap") and not useBitmapFonts then return false end
      if p:find("^app0:") then
        local f = io.open("build/VitaChess/" .. p:sub(7), "rb")
        if f then f:close(); return true end
        return false
      end
      return files[p] ~= nil
    end,
    doesDirExist = function() return true end, createDirectory = function() end,
    deleteFile = function(p) files[p] = nil end,
    openFile = function(p, mode)
      if mode == FCREATE then files[p] = "" end
      if not files[p] and p:find("^app0:/") then  -- app files come from the build folder
        local f = io.open("build/VitaChess/" .. p:sub(7), "rb")
        files[p] = f and f:read("*a") or ""
        if f then f:close() end
      end
      return p
    end,
    writeFile = function(h, s, n) files[h] = files[h] .. s:sub(1, n) end,
    readFile = function(h, n) return files[h]:sub(1, n) end,
    sizeFile = function(h) return #files[h] end, closeFile = function() end,
  }
  FREAD, FCREATE = 1, 2
  FILTER_POINT = 0
  for i, n in ipairs({ "UP", "DOWN", "LEFT", "RIGHT", "CROSS", "CIRCLE", "TRIANGLE", "SQUARE", "START", "SELECT",
                       "LTRIGGER", "RTRIGGER" }) do
    _G["SCE_CTRL_" .. n] = bit.lshift(1, i)
  end
  Controls = {
    read = function()
      cur = nextInput()
      return cur.pad and _G["SCE_CTRL_" .. cur.pad] or 0
    end,
    check = function(pad, b) return bit.band(pad, b) ~= 0 end,
    readTouch = function() if cur.tap then return cur.tap[1], cur.tap[2] end end,
  }
end

local function hasText(pat)
  for _, s in ipairs(lastTexts) do if s:find(pat, 1, true) then return true end end
  return false
end

local SAVE = "ux0:data/VitaChess/save.txt"

-- Each script step: {} idle frame, {pad=...}, {tap={x,y}}, {wait=ms},
-- {waitFor=text}, {expect=text}, {expectNot=text}, {expectSave=pattern}
function nextInput()
  while true do
    if idle > 0 then idle = idle - 1; return {} end
    if waitUntil then
      if os.clock() * 1000 < waitUntil then return {} end
      waitUntil = nil
    end
    local s = script[step]
    if not s then error("DONE") end
    step = step + 1
    if s.wait then
      waitUntil = os.clock() * 1000 + s.wait
    elseif s.waitFor then
      if not hasText(s.waitFor) then
        step = step - 1
        s.started = s.started or os.clock()
        if os.clock() - s.started > 30 then error("timed out waiting for: " .. s.waitFor) end
        return {}
      end
    elseif s.expect then
      if not hasText(s.expect) then error("expected on screen: " .. s.expect .. " | " .. table.concat(lastTexts, " / ")) end
    elseif s.expectNot then
      if hasText(s.expectNot) then error("did not expect on screen: " .. s.expectNot) end
    elseif s.expectFile then
      local found
      for path, body in pairs(files) do
        if path:find(s.expectFile) and (not s.containing or body:find(s.containing, 1, true)) then found = true end
      end
      if not found then error("no file matching " .. s.expectFile .. " containing " .. tostring(s.containing)) end
    elseif s.expectSave then
      if not (files[SAVE] or ""):find(s.expectSave) then
        error("save file " .. tostring(files[SAVE]) .. " doesn't match " .. s.expectSave)
      end
    else
      idle = 1
      return s
    end
  end
end

---------------------------------------------------------------------------
-- Scenario helpers
---------------------------------------------------------------------------
local function sqXY(name, flipped)
  local f, r = name:byte(1) - 97, tonumber(name:sub(2)) - 1
  if flipped then return { 16 + (7 - f) * 64 + 32, 16 + r * 64 + 32 } end
  return { 16 + f * 64 + 32, 16 + (7 - r) * 64 + 32 }
end
local function newScript()
  local S = {}
  local api = {}
  function api.add(t) S[#S + 1] = t end
  function api.tap(x, y) S[#S + 1] = { tap = { x, y } } end
  function api.move(a, b, flipped) S[#S + 1] = { tap = sqXY(a, flipped) }; S[#S + 1] = { tap = sqXY(b, flipped) } end
  function api.press(b) S[#S + 1] = { pad = b } end
  return S, api
end


---------------------------------------------------------------------------
-- Scenarios
---------------------------------------------------------------------------
local scenarios = {}

-- Menu row centres (see the ui.makeList / ui.centerList calls in app.lua)
local function titleRow(i, n)
  n = n or 7
  local step, h = (n > 7) and 45 or 50, (n > 7) and 38 or 42
  return 700, 150 + (i - 1) * step + h / 2
end
local function setupRow(i) return 480, 112 + (i - 1) * 56 + 23 end
local function settingsRowY(i) return 84 + (i - 1) * 42 + 18 end
local function pauseRow(i) return 480, 141 + (i - 1) * 52 + 21 end
function PX_BUTTON(i) return 568 + (i - 1) * 96 + 44, 476 + 24 end

scenarios["menus, computer game, hint, undo, continue, 2P checkmate"] = function()
  local S, a = newScript()
  a.add({}) a.add({ expect = "Play vs Computer" }) a.add({ expectNot = "Continue" })
  a.tap(titleRow(6)) a.add({}) a.add({ expect = "SETTINGS" })
  a.tap(550, settingsRowY(1)) for _ = 1, 3 do a.tap(550, settingsRowY(2)) end a.add({})
  a.tap(550, settingsRowY(3)) a.add({}) a.add({ expect = "Waves" })
  a.add({ expect = "Ice Blue" }) a.add({ expect = "Pixel" })   -- one step on from Tournament, three from Staunton
  a.press("CIRCLE") a.add({}) a.add({ expect = "Play vs Computer" })
  a.tap(titleRow(1)) a.add({}) a.add({ expect = "PLAY VS COMPUTER" })
  a.tap(600, select(2, setupRow(1))) a.tap(760, select(2, setupRow(2))) a.add({})
  a.add({ expect = "Lv3  Casual" }) a.add({ expect = "Black" }) a.add({ expect = "Your record at this level" })
  a.tap(setupRow(4))                                 -- Start Game (computer plays White)
  a.add({ waitFor = "Your Move" }) a.add({ expectSave = "^v3 mode=ai level=3 side=1 tc=1 %d+:%d+:0$" })
  a.move("e7", "e5", true)
  a.add({ wait = 50 }) a.add({ expect = "Thinking" })
  a.add({ waitFor = "Your Move" })
  a.press("SELECT") a.add({ waitFor = "Hint:" })
  a.press("TRIANGLE") a.add({}) a.add({ expect = "Your Move" })
  a.add({ expectSave = "^v3 mode=ai level=3 side=1 tc=1 %d+:%d+:0$" })   -- undo took back both moves
  a.press("START") a.add({}) a.add({ expect = "PAUSED" }) a.add({ expect = "Offer Draw" })
  for _ = 1, 5 do a.press("DOWN") end
  a.press("CROSS") a.add({}) a.add({ expect = "Continue" })
  a.press("CROSS") a.add({}) a.add({ expect = "vs Computer" })
  a.press("START") a.tap(pauseRow(6)) a.add({}) a.add({ expect = "Two Players" })
  a.tap(titleRow(3, 8)) a.add({}) a.add({ expect = "TWO PLAYERS" })
  a.tap(setupRow(3)) a.add({}) a.add({ expect = "White to Move" })
  for _, m in ipairs({ { "e2", "e4" }, { "e7", "e5" }, { "f1", "c4" }, { "b8", "c6" },
                       { "d1", "h5" }, { "g8", "f6" }, { "h5", "f7" } }) do a.move(m[1], m[2]) end
  a.add({}) a.add({ expect = "Checkmate" }) a.add({ wait = 1100 }) a.add({}) a.add({ expect = "Rematch" })
  a.add({ expectFile = "games/game%-.*%.pgn$", containing = "4. Qxf7# 1-0" })
  a.add({ expect = "Trophy unlocked!" })
  a.add({ expectFile = "stats%.txt$", containing = "twoPlayer=1" })
  a.press("CROSS") a.add({}) a.add({ expect = "White to Move" })
  return S
end

scenarios["continue old save, auto-flip, promotion picker"] = function()
  local Chess = require("chess")
  local g, toks = Chess.newGame(), {}
  for _, san in ipairs({ "a4", "b5", "axb5", "a6", "bxa6", "Bb7", "axb7", "Nc6" }) do
    for _, m in ipairs(g.legal) do
      if Chess.san(g, m, g.legal) == san then toks[#toks + 1] = m.from .. ":" .. m.to .. ":0"; Chess.play(g, m); break end
    end
  end
  files[SAVE] = table.concat(toks, " ")             -- a v0.1-style save (moves only)
  local S, a = newScript()
  a.add({}) a.press("CROSS") a.add({}) a.add({ expect = "Two Players" })
  a.press("START") for _ = 1, 4 do a.press("DOWN") end a.press("CROSS") a.add({}) a.add({ expect = "SETTINGS" })
  for _ = 1, 7 do a.press("DOWN") end                 -- down to "Auto-flip"
  a.press("RIGHT") a.press("CIRCLE") a.add({}) a.add({ expect = "White to Move" })
  a.move("b7", "a8") a.add({}) a.add({ expect = "Promote to:" })
  a.press("RIGHT") a.press("RIGHT") a.press("CROSS") a.add({}) a.add({ expect = "bxa8=B" })
  a.move("e7", "e6", true) a.add({}) a.add({ expectSave = "35:45:0$" })   -- board had flipped for Black
  return S
end

scenarios["clock, draw offer, resign, stats, PGN"] = function()
  local S, a = newScript()
  a.add({}) a.tap(titleRow(1)) a.add({})
  a.tap(760, select(2, setupRow(3))) a.add({}) a.add({ expect = "3 min + 2" })
  a.tap(setupRow(4)) a.add({}) a.add({ expect = "3:00" }) a.add({ expect = "You" })
  a.move("e2", "e4") a.add({ waitFor = "Your Move" })
  a.add({ expectSave = "^v3 mode=ai level=4 side=%-1 tc=2 wt=%d+ bt=%d+ 85:65:0 %d+:%d+:0$" })
  a.press("START") a.press("DOWN") a.press("CROSS") a.add({}) a.add({ expect = "declines the draw" })
  a.press("START") a.press("DOWN") a.press("DOWN") a.press("CROSS") a.add({}) a.add({ expect = "Resign this game?" })
  a.press("CROSS") a.add({}) a.add({ expect = "Your Move" })      -- "No" is the default
  a.press("START") a.press("DOWN") a.press("DOWN") a.press("CROSS") a.press("UP") a.press("CROSS") a.add({})
  a.add({ expect = "You resigned" })
  a.add({ expectSave = "end=resign:%-1" })
  a.add({ expectFile = "stats%.txt$", containing = "4=0,1,0" })
  a.add({ expectFile = "games/.*%.pgn$", containing = '[Result "0-1"]' })
  a.add({ wait = 1000 }) a.add({}) a.add({ expect = "Rematch" })
  a.press("DOWN") a.press("CROSS") a.add({}) a.add({ expectNot = "Continue" })   -- finished games can't be continued
  return S
end

local ONE_PUZZLE = "08yJ9,6k1/1N3ppp/p1p2n2/4p3/1r6/4P1P1/5P1P/3R2K1 b - - 0 29,b4b7 d1d8 f6e8 d8e8,400\n"

scenarios["puzzle: mistake, solve, hint, solution, rating"] = function()
  files["app0:/puzzles/puzzles.txt"] = ONE_PUZZLE
  local S, a = newScript()
  a.add({}) a.tap(titleRow(3)) a.add({}) a.add({ expect = "PUZZLES" }) a.add({ expect = "1000" })
  a.tap(setupRow(1))
  a.add({ expect = "Watch the opponent" })
  a.add({ waitFor = "White to Move" }) a.add({ expect = "hidden until solved" })
  a.move("g1", "f1") a.add({}) a.add({ expect = "Not the move" })
  a.add({ expectFile = "data/VitaChess/puzzles%.txt$", containing = "rating=961" })
  a.add({ waitFor = "Keep trying" })
  a.move("d1", "d8") a.add({}) a.add({ expect = "Good move!" })
  a.add({ waitFor = "White to Move" })
  a.move("d8", "e8") a.add({}) a.add({ expect = "Solved, after a mistake" }) a.add({ expect = "Puzzle rating: 400" })
  a.add({ expectFile = "data/VitaChess/puzzles%.txt$", containing = "solved=0" })
  a.press("TRIANGLE") a.add({ waitFor = "Find the best move" })
  a.press("SELECT") a.press("SELECT") a.add({})
  a.tap(PX_BUTTON(2)) a.add({}) a.add({ expect = "Showing the solution" })
  a.add({ waitFor = "Solution shown" })
  a.add({ expectFile = "data/VitaChess/puzzles%.txt$", containing = "attempts=2" })
  a.press("START") a.add({}) a.add({ expect = "Try Again" })
  for _ = 1, 4 do a.press("DOWN") end a.press("CROSS") a.add({}) a.add({ expect = "Puzzles" })
  a.add({ expectNot = "Continue" })          -- puzzles never overwrite your saved game
  return S
end

scenarios["puzzle: clean solve raises rating"] = function()
  files["app0:/puzzles/puzzles.txt"] = ONE_PUZZLE
  local S, a = newScript()
  a.add({}) a.tap(titleRow(3)) a.add({}) a.press("CROSS")
  a.add({ waitFor = "White to Move" })
  a.move("d1", "d8") a.add({ waitFor = "White to Move" })
  a.move("d8", "e8") a.add({}) a.add({ expect = "Solved!" }) a.add({ expect = "+1" })
  a.add({ expectFile = "data/VitaChess/puzzles%.txt$", containing = "rating=1001" })
  a.add({ expectFile = "data/VitaChess/puzzles%.txt$", containing = "streak=1" })
  return S
end

scenarios["learn: rook stars, lesson complete"] = function()
  local S, a = newScript()
  a.add({}) a.tap(titleRow(4)) a.add({}) a.add({ expect = "LEARN" }) a.add({ expect = "0 / 14" })
  a.press("CROSS") a.add({}) a.add({ expect = "The Basics" }) a.add({ expect = "2.  The Rook" })
  a.press("DOWN") a.press("CROSS") a.add({}) a.add({ expect = "Step 1 of 2" })
  a.press("CROSS") a.add({}) a.add({ expect = "Stars left: 4" })
  a.move("d2", "d7") a.move("d7", "a7") a.move("a7", "a2") a.add({}) a.add({ expect = "Stars left: 1" })
  a.move("a2", "g2") a.add({}) a.add({ expect = "Rooks love open lines" })
  a.press("TRIANGLE") a.add({}) a.add({ expect = "Lesson complete! Next up: The Bishop" })
  a.add({ expectFile = "learn%.txt$", containing = "basics/rook" })
  a.press("START") for _ = 1, 2 do a.press("DOWN") end a.press("CROSS") a.add({})
  a.add({ expect = "1 of 14 lessons complete" }) a.add({ expect = "Done" })
  return S
end

scenarios["learn: check lesson with wrong answers"] = function()
  local S, a = newScript()
  a.add({}) a.tap(titleRow(4)) a.add({}) a.press("CROSS") a.add({})
  for _ = 1, 8 do a.press("DOWN") end a.press("CROSS") a.add({}) a.add({ expect = "Check" })
  a.press("CROSS") a.add({})                                  -- past the explanation
  a.move("f2", "f3") a.add({}) a.add({ expectNot = "Not quite" })   -- illegal while in check
  a.move("e1", "d2") a.add({}) a.add({ expect = "out of the rook" })
  a.press("CROSS") a.add({ expect = "Check from the bishop!" })
  a.move("g1", "h1") a.add({}) a.add({ expect = "Not quite" }) a.add({ wait = 1000 })
  a.move("d3", "d4") a.add({}) a.add({ expect = "A blocked check" })
  a.press("CROSS") a.add({}) a.move("c3", "e2") a.add({}) a.add({ expect = "Capturing the" })
  a.press("CROSS") a.add({}) a.add({ expect = "Checkmate and Stalemate" })
  return S
end

scenarios["learn: en passant intro and the rook ladder"] = function()
  local S, a = newScript()
  a.add({}) a.tap(titleRow(4)) a.add({}) a.press("CROSS") a.add({})
  for _ = 1, 11 do a.press("DOWN") end a.press("CROSS") a.add({}) a.add({ expect = "En Passant" })
  a.press("CROSS") a.add({}) a.add({ waitFor = "Capture it en passant" }) a.add({ wait = 900 })
  a.move("e5", "d6") a.add({}) a.add({ expect = "landed on an empty square" })
  a.press("START") for _ = 1, 4 do a.press("DOWN") end a.press("CROSS") a.add({})   -- main menu
  a.tap(titleRow(4)) a.add({}) a.press("DOWN") a.press("CROSS") a.add({})
  for _ = 1, 6 do a.press("DOWN") end a.press("CROSS") a.add({}) a.add({ expect = "The Ladder Mate" })
  a.press("CROSS") a.add({})
  a.move("h3", "h5") a.add({ wait = 800 }) a.move("g4", "g6") a.add({ wait = 800 })
  a.move("h5", "h7") a.add({ wait = 800 }) a.move("g6", "g8") a.add({}) a.add({ expect = "rook ladder" })
  return S
end

scenarios["learn: guided Italian Game and a drill"] = function()
  local S, a = newScript()
  a.add({}) a.tap(titleRow(4)) a.add({}) a.add({ expect = "0 / 9" })
  for _ = 1, 3 do a.press("DOWN") end a.press("CROSS") a.add({}) a.add({ expect = "Openings" })
  a.press("DOWN") a.press("CROSS") a.add({}) a.add({ expect = "Your Move: e4" })
  a.move("d2", "d4") a.add({}) a.add({ expect = "Play the highlighted move" }) a.add({ wait = 1000 })
  for _, m in ipairs({ { "e2", "e4" }, { "g1", "f3" }, { "f1", "c4" }, { "c2", "c3" }, { "d2", "d3" } }) do
    a.move(m[1], m[2]) a.add({ wait = 1100 })
  end
  a.add({ expect = "Black played d6" }) a.add({ expect = "Your Move: O-O" })
  a.move("e1", "g1") a.add({}) a.add({ expect = "That's the Italian Game" })
  a.press("START") a.press("DOWN") a.press("DOWN") a.press("CROSS") a.add({})     -- lesson list
  a.press("CIRCLE") a.add({}) for _ = 1, 2 do a.press("DOWN") end a.press("CROSS") a.add({})
  for _ = 1, 3 do a.press("DOWN") end a.press("CROSS") a.add({}) a.add({ expect = "Drill: Queen Checkmate" })
  a.press("CROSS") a.add({}) a.add({ expect = "Moves left: 25" })
  a.move("h1", "h4") a.add({}) a.add({ expect = "Thinking..." }) a.add({ wait = 2500 })
  a.add({ expectNot = "Thinking..." }) a.add({ expect = "Moves left: 24" })
  return S
end

scenarios["move list: tap a move, L/R, back to live"] = function()
  local S, a = newScript()
  a.add({}) a.tap(titleRow(2)) a.add({}) a.tap(setupRow(3)) a.add({}) a.add({ expect = "White to Move" })
  for _, m in ipairs({ { "e2", "e4" }, { "e7", "e5" }, { "g1", "f3" }, { "b8", "c6" } }) do a.move(m[1], m[2]) end
  a.add({}) a.add({ expect = "Nc6" })
  a.tap(568 + 80, 216 + 11) a.add({}) a.add({ expect = "Move 1 of 4" }) a.add({ expect = "Live" })
  a.press("RTRIGGER") a.add({}) a.add({ expect = "Move 2 of 4" })
  a.move("d2", "d4") a.add({}) a.add({ expect = "Move 2 of 4" })          -- board is read-only while looking back
  a.press("CIRCLE") a.add({}) a.add({ expectNot = "Move 2 of 4" }) a.add({ expect = "White to Move" })
  a.press("LTRIGGER") a.add({}) a.add({ expect = "Move 3 of 4" })
  a.tap(568 + 44, 476 + 24) a.add({}) a.add({ expectNot = "Move 3 of 4" })    -- the Live button
  a.move("d2", "d4") a.add({}) a.add({ expect = "d4" })
  return S
end

scenarios["stats and trophies screen"] = function()
  files["ux0:data/VitaChess/learn.txt"] = "basics/board"
  files["ux0:data/VitaChess/stats.txt"] = "3=0,0,1"          -- a record from before the game counters
  local S, a = newScript()
  a.add({}) a.add({ expect = "Trophy unlocked!" }) a.add({ expect = "First Steps" })   -- the old draw counts now
  a.tap(titleRow(5)) a.add({}) a.add({ expect = "STATS & TROPHIES" })
  a.add({ expect = "Trophies  2 / 25" }) a.add({ expect = "Lessons complete" }) a.add({ expect = "1 / 51" })
  a.add({ expect = "Games finished" }) a.add({ expect = "0 won  0 lost  1 drawn" })
  for _ = 1, 10 do a.press("DOWN") end a.add({}) a.add({ expect = "Hat Trick" })
  a.press("CIRCLE") a.add({}) a.add({ expect = "Play vs Computer" })
  return S
end

scenarios["running out of time"] = function()
  files[SAVE] = "v3 mode=2p level=4 side=-1 tc=2 wt=1200 bt=100000 85:65:0 35:55:0"
  local S, a = newScript()
  a.add({}) a.add({ expect = "Continue" }) a.press("CROSS") a.add({}) a.add({ expect = "White to Move" })
  a.add({ waitFor = "Black wins on time" })
  a.add({ expectSave = "end=timeout:%-1" })
  return S
end

scenarios["computer opens from the book"] = function()
  local S, a = newScript()
  a.add({}) a.tap(titleRow(1)) a.add({})
  a.tap(760, select(2, setupRow(2))) a.tap(setupRow(4))
  a.add({ waitFor = "Your Move" })
  a.add({ expectSave = " (%d+):(%d+):0$" })
  return S
end

---------------------------------------------------------------------------
-- Runner
---------------------------------------------------------------------------
scenarios["bitmap fonts draw every screen"] = function()
  useBitmapFonts = true
  local S, a = newScript()
  for _, pad in ipairs({ "DOWN", "DOWN", "DOWN", "CROSS", "CROSS", "DOWN", "CROSS", "CROSS" }) do
    a.press(pad)
  end
  a.add({}) a.add({})
  return S
end

local failed = 0
for name, make in pairs(scenarios) do
  files, soundsPlayed, step, idle, waitUntil = {}, 0, 1, 0, nil
  useBitmapFonts, glyphDraws = false, 0
  installFakes()
  script = make()
  for _, m in ipairs({ "config", "platform", "chess", "ai", "book", "pgn", "settings", "stats", "puzzles", "lessons", "learn", "trophies", "ui", "app" }) do package.loaded[m] = nil end
  local ok, err = pcall(dofile, INDEX)
  err = tostring(err)
  if useBitmapFonts and glyphDraws < 1000 then err = "only " .. glyphDraws .. " letters drawn from the bitmap fonts" end
  if err:find("DONE", 1, true) then
    print("  ok   " .. name .. "  (" .. soundsPlayed .. " sounds" .. (useBitmapFonts and (", " .. glyphDraws .. " letters") or "") .. ")")
  else
    print("  FAIL " .. name .. "\n       " .. err)
    failed = failed + 1
  end
end
if failed > 0 then os.exit(1) end
print("All UI tests passed")
