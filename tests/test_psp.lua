-- Plays the PSP build (build/psp/VitaChess/script.lua) on a fake LuaDEV R0:
-- the LuaDEV functions are stand-ins, input is buttons only (no touch).
-- Run tools/build.py --psp first, then from the repo root: luajit tests/test_psp.lua
-- Set SHOTS=1 to also write the last frame of each scenario to build/psp_<n>.txt
local realOpen, realExit = io.open, os.exit
local ROOT = "build/psp/VitaChess/"

local files, texts, lastTexts, frameLog, lastLog, pressedNow, script, step, idle, waitUntil

local function rec(...) frameLog[#frameLog + 1] = { ... } end

local function fakeFile(path, mode)
  if mode == "w" then
    files[path] = ""
    return { write = function(self, d) files[path] = files[path] .. d end, close = function() end }
  end
  local data = files[path]
  if not data then
    local f = realOpen(ROOT .. path, "rb")
    if not f then return nil end
    data = f:read("*a"); f:close()
  end
  return { read = function() return data end, close = function() end }
end

local function exists(path)
  if files[path] then return true end
  local f = realOpen(ROOT .. path, "rb")
  if f then f:close(); return true end
  return files["dir:" .. path] ~= nil
end

local function installFakes()
  texts, frameLog = {}, {}
  color = { new = function(r, g, b, a) return { r, g, b, a or 255 } end }
  draw = { fillrect = function(x, y, w, h, c)
    assert(x == math.floor(x) and y == math.floor(y), "fractional rect")
    rec("rect", x, y, w, h, c) end }
  screen = {
    print = function(x, y, s, size, c)
      assert(type(s) == "string"); texts[#texts + 1] = s; rec("text", x, y, s, size, c) end,
    textwidth = function(s, size) return #s * size * 9.5 end,
    flip = function() lastTexts, texts = texts, {}; lastLog, frameLog = frameLog, {} end,
    waitvblankstart = function() end,
  }
  image = {
    load = function(p) assert(exists(p), "missing image " .. p); return { path = p, w = 32 } end,
    resize = function(img, w) img.w = w end,
    blit = function(img, x, y) rec("img", x, y, img.path, img.w) end,
  }
  sound = { load = function(p) assert(exists(p), "missing sound " .. p); return p end, play = function() end }
  files = files or {}
  _G.files = {
    exists = exists,
    mkdir = function(p) files["dir:" .. p] = true end,
    remove = function(p) files[p] = nil end,
  }
  io = { open = fakeFile }
  os.cpu = function() end
  os.exit = function() error("EXIT") end
  controls = {
    read = function() pressedNow = nextInput() end,
    press = function(name) return pressedNow.pad == name end,
  }
end

local function hasText(pat)
  for _, s in ipairs(lastTexts or {}) do if s:find(pat, 1, true) then return true end end
  return false
end

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
    if s.waitFor then
      if not hasText(s.waitFor) then
        step = step - 1
        s.started = s.started or os.clock()
        if os.clock() - s.started > 60 then error("timed out waiting for: " .. s.waitFor) end
        return {}
      end
    elseif s.wait then
      waitUntil = os.clock() * 1000 + s.wait
    elseif s.expect then
      if not hasText(s.expect) then error("expected on screen: " .. s.expect) end
    elseif s.expectFile then
      local ok = false
      for path, body in pairs(files) do
        if path:find(s.expectFile) and body:find(s.containing, 1, true) then ok = true end
      end
      if not ok then error("no file " .. s.expectFile .. " containing " .. s.containing) end
    else
      idle = 1
      return s
    end
  end
end

-- Move the board cursor from one square to another (cursor must already be visible)
local function cursorMoves(add, from, to, flipped)
  local df = to:byte(1) - from:byte(1)
  local dr = to:byte(2) - from:byte(2)
  if flipped then df, dr = -df, -dr end
  for _ = 1, math.abs(df) do add({ pad = (df > 0) and "right" or "left" }) end
  for _ = 1, math.abs(dr) do add({ pad = (dr > 0) and "up" or "down" }) end
end

local scenarios = {}

scenarios["computer game with buttons only"] = function()
  local S = {}
  local function add(t) S[#S + 1] = t end
  add({}) add({ expect = "Chess for PSP" }) add({ expect = "X select   O back" })
  add({ pad = "cross" }) add({ expect = "PLAY VS COMPUTER" })
  add({ pad = "down" }) add({ pad = "down" }) add({ pad = "down" }) add({ pad = "cross" })
  add({ expect = "Your move" })
  add({ pad = "up" })                                -- reveals the cursor on e2
  add({ pad = "cross" }) add({ pad = "up" }) add({ pad = "up" }) add({ pad = "cross" })   -- e2-e4
  add({ waitFor = "Thinking" }) add({ waitFor = "Your move" })
  add({ expectFile = "^data/save%.txt$", containing = "85:65:0" })
  add({ pad = "select" }) add({ waitFor = "Hint:" })
  add({ pad = "start" }) add({ expect = "PAUSED" }) add({ pad = "circle" })
  return S
end

scenarios["puzzle solved with the cursor"] = function()
  files["puzzles/puzzles.txt"] =
    "08yJ9,6k1/1N3ppp/p1p2n2/4p3/1r6/4P1P1/5P1P/3R2K1 b - - 0 29,b4b7 d1d8 f6e8 d8e8,400\n"
  local S = {}
  local function add(t) S[#S + 1] = t end
  add({}) add({ pad = "down" }) add({ pad = "down" }) add({ pad = "cross" }) add({ expect = "PUZZLES" })
  add({ pad = "cross" }) add({ waitFor = "White to move" })
  add({ pad = "left" })                              -- reveal cursor on e2
  cursorMoves(add, "e2", "d1") add({ pad = "cross" })
  cursorMoves(add, "d1", "d8") add({ pad = "cross" })
  add({ waitFor = "White to move" })
  add({ pad = "cross" })                             -- select the rook again on d8
  cursorMoves(add, "d8", "e8") add({ pad = "cross" })
  add({}) add({ expect = "Solved!" })
  add({ expectFile = "^data/puzzles%.txt$", containing = "solved=1" })
  return S
end

local failed, n = 0, 0
for name, make in pairs(scenarios) do
  n = n + 1
  files, step, idle, waitUntil, pressedNow, lastTexts = {}, 1, 0, nil, {}, {}
  script = make()
  installFakes()
  local ok, err = pcall(dofile, ROOT .. "script.lua")
  err = tostring(err)
  if os.getenv("SHOTS") and lastLog then
    local f = realOpen("build/psp_" .. n .. ".txt", "w")
    for _, c in ipairs(lastLog) do
      local parts = {}
      for _, v in ipairs(c) do parts[#parts + 1] = type(v) == "table" and table.concat(v, ",") or tostring(v) end
      f:write(table.concat(parts, "|"), "\n")
    end
    f:close()
  end
  if err:find("DONE", 1, true) then print("  ok   " .. name)
  else print("  FAIL " .. name .. "\n       " .. err); failed = failed + 1 end
end
if failed > 0 then realExit(1) end
print("All PSP tests passed")
