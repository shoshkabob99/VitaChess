-- ui.lua - reusable drawing pieces: colours, text, menus, the chess board

local P = require("platform")
local Chess = require("chess")
local config = require("config")
local settings = require("settings")

local ui = {}
local floor, abs = math.floor, math.abs
local FILES = "abcdefgh"
local NAMES = { "P", "N", "B", "R", "Q", "K" }

---------------------------------------------------------------------------
-- Colours (created in ui.init, after the platform is ready)
---------------------------------------------------------------------------
ui.C = {}
local C = ui.C

function ui.init()
  local c = P.color
  C.bg     = c(28, 30, 36);        C.panel  = c(40, 43, 52)
  C.sel    = c(246, 246, 105, 150); C.last   = c(205, 210, 106, 110)
  C.hint   = c(20, 20, 20, 80);    C.check  = c(230, 50, 50, 170)
  C.hintSq = c(70, 150, 255, 140)
  C.cursor = c(70, 160, 255);      C.text   = c(240, 240, 240)
  C.dim    = c(172, 178, 192);     C.accent = c(255, 200, 90)
  C.shade  = c(0, 0, 0, 170);      C.box    = c(58, 62, 74)
  C.boxHi  = c(80, 125, 200);      C.white  = c(250, 250, 250)
  C.black  = c(25, 25, 25);        C.red    = c(255, 110, 110)
  C.good   = c(120, 220, 140);     C.boxActive = c(70, 76, 94)
  C.star   = c(255, 205, 60);      C.starRing = c(120, 80, 0, 160)
  C.row    = c(16, 20, 44, 185);   C.pulse = {}
  for i = 0, 15 do C.pulse[i] = c(255, 255, 255, i * 2) end    -- for the glowing highlight
  C.markG  = c(80, 200, 110, 120); C.markR = c(235, 70, 70, 120)
  C.markB  = c(70, 150, 255, 120); C.markY = c(250, 220, 70, 130)
  C.arrow  = c(255, 170, 40, 210)
  for _, t in ipairs(config.THEMES) do
    t.L = c(t.light[1], t.light[2], t.light[3])
    t.D = c(t.dark[1], t.dark[2], t.dark[3])
    t.Lf = c(t.light[1], t.light[2], t.light[3], 26)   -- faint, for backgrounds
  end
end

function ui.theme() return config.THEMES[settings.values.theme] end

---------------------------------------------------------------------------
-- Basic shapes and text
---------------------------------------------------------------------------
ui.rect = P.rect
function ui.frame(x, y, w, h, t, c)
  P.rect(x, y, w, t, c); P.rect(x, y + h - t, w, t, c)
  P.rect(x, y, t, h, c); P.rect(x + w - t, y, t, h, c)
end
ui.text = P.text      -- ui.text(x, y, string, colour, scale, bold)
ui.textW = P.textWidth
function ui.textC(cx, y, s, c, scale, bold) P.text(cx - P.textWidth(s, scale, bold) / 2, y, s, c, scale, bold) end
function ui.textR(rx, y, s, c, scale, bold) P.text(rx - P.textWidth(s, scale, bold), y, s, c, scale, bold) end
function ui.inside(x, y, rx, ry, rw, rh) return x >= rx and x < rx + rw and y >= ry and y < ry + rh end
function ui.wrap(v, n) return (v - 1) % n + 1 end

-- The plain checkered background (the "Classic" menu background)
function ui.checkerBackground()
  local t = ui.theme()
  P.rect(0, 0, P.SCREEN_W, P.SCREEN_H, C.bg)
  for r = 0, 7 do
    for f = 0, 14 do
      if (f + r) % 2 == 0 then P.rect(f * 68, r * 68, 68, 68, t.Lf) end
    end
  end
end

---------------------------------------------------------------------------
-- Animated menu backgrounds. Settings: 1 Floating pieces, 2 Waves, 3 Classic.
---------------------------------------------------------------------------
ui.MENU_BACKGROUNDS = { "Floating pieces", "Waves", "Classic" }
local MB = "art/menubg/"
local mb = nil                -- loaded images and moving things, set up on first use

local function loadMenuArt()
  mb = { floating = P.loadImage(config.ASSET_DIR .. MB .. "floating.png"),
         waves = P.loadImage(config.ASSET_DIR .. MB .. "waves.png"),
         ribbon = P.loadImage(config.ASSET_DIR .. MB .. "ribbon.png"),
         speck = P.loadImage(config.ASSET_DIR .. MB .. "speck.png"),
         sprites = {}, pieces = {}, specks = {} }
  local kinds = { "K", "Q", "R", "B", "N", "P" }
  for depth = 0, 2 do
    mb.sprites[depth] = {}
    for _, k in ipairs(kinds) do
      mb.sprites[depth][k] = P.loadImage(config.ASSET_DIR .. MB .. "piece" .. depth .. k .. ".png")
    end
  end
  -- far pieces drift slowly, near ones faster (parallax)
  local SIZE, SPEED, COUNT = { 114, 174, 244 }, { 9, 16, 26 }, { 6, 4, 2 }
  for depth = 0, 2 do
    for _ = 1, COUNT[depth + 1] do
      mb.pieces[#mb.pieces + 1] = { depth = depth, kind = kinds[math.random(6)], size = SIZE[depth + 1],
        x = math.random(-60, P.SCREEN_W - 60), y = math.random(-60, P.SCREEN_H),
        speed = SPEED[depth + 1] * (0.8 + math.random() * 0.4), sway = math.random() * 6.28 }
    end
  end
  for _ = 1, 26 do
    mb.specks[#mb.specks + 1] = { x = math.random(0, P.SCREEN_W), y = math.random(0, P.SCREEN_H),
                                  speed = 6 + math.random() * 14, sway = math.random() * 6.28 }
  end
  mb.last = P.now()
  mb.waveColors = { P.color(90, 160, 255, 255), P.color(150, 110, 255, 255),
                    P.color(80, 220, 255, 255), P.color(255, 150, 220, 255) }
end

local function drawFloating(dt, t)
  P.drawImage(mb.floating, 0, 0)
  for _, sp in ipairs(mb.specks) do
    sp.y = sp.y - sp.speed * dt
    if sp.y < -24 then sp.y, sp.x = P.SCREEN_H + 10, math.random(0, P.SCREEN_W) end
    if mb.speck then P.drawImage(mb.speck, sp.x + math.sin(t * 0.5 + sp.sway) * 10, sp.y) end
  end
  for _, pc in ipairs(mb.pieces) do
    pc.y = pc.y - pc.speed * dt
    if pc.y < -pc.size then
      pc.y, pc.x = P.SCREEN_H + math.random(0, 80), math.random(-60, P.SCREEN_W - 60)
      pc.kind = ({ "K", "Q", "R", "B", "N", "P" })[math.random(6)]
    end
    local img = mb.sprites[pc.depth][pc.kind]
    if img then P.drawImage(img, pc.x + math.sin(t * 0.3 + pc.sway) * 14, pc.y) end
  end
end

-- each wave: height, wavelength, speed, base line, colour
local WAVES = { { 40, 0.008, 0.35, 330 }, { 55, 0.006, -0.25, 362 }, { 30, 0.011, 0.5, 384 }, { 48, 0.005, 0.2, 404 } }
local function drawWaves(t)
  P.drawImage(mb.waves, 0, 0)
  if not (mb.ribbon and P.drawImagePart) then return end
  for i, w in ipairs(WAVES) do
    local amp, freq, speed, base = w[1], w[2], w[3], w[4]
    local c = mb.waveColors[i]
    for x = 0, P.SCREEN_W - 1, 4 do
      local y = base + amp * math.sin(x * freq + t * speed + i * 1.7) + 12 * math.sin(x * freq * 2.3 - t * speed * 1.5)
      P.drawImagePart(mb.ribbon, x, y, 0, 0, 4, 140, c)
    end
  end
end

function ui.menuBackground()
  local which = settings.values.menubg or 1
  if which == 3 or not P.loadImage then ui.checkerBackground(); return end
  if not mb then loadMenuArt() end
  local now = P.now()
  local dt = math.min(0.1, (now - mb.last) / 1000)
  mb.last = now
  local t = now / 1000
  if which == 2 and mb.waves then drawWaves(t)
  elseif mb.floating then drawFloating(dt, t)
  else ui.checkerBackground() end
end



-- Controller hints: a row of button icons, each followed by what it does.
-- items = { { "cross", "Select" }, { "circle", "Back" }, "plain text", ... }
-- Icons: cross circle triangle square dpad updown leftright start select
local icons = {}
local ICON_LABELS = { cross = "X", circle = "O", triangle = "TRI", square = "SQR", dpad = "D-pad",
                      updown = "Up/Down", leftright = "Left/Right", start = "START", select = "SELECT",
                      l = "L", r = "R" }
function ui.hints(x, y, items, scale)
  scale = scale or 0.85
  for _, item in ipairs(items) do
    if type(item) == "string" then
      P.text(x, y, item, C.dim, scale)
      x = x + P.textWidth(item, scale) + 22
    else
      local name, label = item[1], item[2]
      if icons[name] == nil then icons[name] = P.loadImage(config.ASSET_DIR .. "art/buttons/" .. name .. ".png") or false end
      local icon = icons[name]
      if icon then
        P.drawImage(icon, x, y - 4)
        x = x + ((name == "start") and 58 or (name == "select") and 62 or (name == "l" or name == "r") and 36 or 26) + 6
      else
        P.text(x, y, ICON_LABELS[name] or name, C.text, scale, true)
        x = x + P.textWidth(ICON_LABELS[name] or name, scale, true) + 6
      end
      P.text(x, y, label, C.dim, scale)
      x = x + P.textWidth(label, scale) + 18
    end
  end
  return x
end

function ui.footer(items) ui.hints(24, 510, items) end

-- Split text into lines that fit maxW at the given scale. "\n" starts a new paragraph.
function ui.wrapText(s, maxW, scale)
  local lines = {}
  for para in (s .. "\n"):gmatch("(.-)\n") do
    local line = ""
    for word in para:gmatch("%S+") do
      local try = (line == "") and word or (line .. " " .. word)
      if line ~= "" and P.textWidth(try, scale) > maxW then
        lines[#lines + 1] = line
        line = word
      else
        line = try
      end
    end
    lines[#lines + 1] = line
  end
  return lines
end

---------------------------------------------------------------------------
-- Pieces (each set is loaded the first time it's used)
---------------------------------------------------------------------------
local pieceCache = {}
local function pieceImages()
  local i = settings.values.pieces
  if not pieceCache[i] then
    local set = {}
    for t = 1, 6 do
      for _, side in ipairs({ 1, -1 }) do
        set[t * side] = P.loadImage(config.ASSET_DIR .. "pieces/" .. config.PIECE_SETS[i].dir ..
          "/" .. (side == 1 and "w" or "b") .. NAMES[t] .. ".png")
      end
    end
    pieceCache[i] = set
  end
  return pieceCache[i]
end

-- p = piece code (+ White, - Black), x/y = top-left, scale 1 = 64 pixels
function ui.drawPiece(p, x, y, scale)
  scale = scale or 1
  local im = pieceImages()[p]
  if im then
    P.drawImage(im, x, y, scale)
  else  -- missing sprite: draw a disc with a letter
    local w = p > 0
    P.circle(x + 32 * scale, y + 32 * scale, 24 * scale, w and C.white or C.black)
    P.text(x + 24 * scale, y + 16 * scale, NAMES[abs(p)], w and C.black or C.white, 1.3 * scale)
  end
end

---------------------------------------------------------------------------
-- Menu lists (used by every screen)
-- row = { label = "..." or function, value = function() -> string,
--         change = function(dir), activate = function() }
-- Rows with a value show "<  value  >" and change with Left/Right.
---------------------------------------------------------------------------
-- visible (optional) = how many rows fit; longer lists scroll
function ui.makeList(rows, x, y, w, h, step, visible)
  return { rows = rows, index = 1, top = 1, x = x, y = y, w = w, h = h, step = step or h + 10,
           visible = visible }
end
local function keepVisible(L)
  if not L.visible then return end
  if L.index < L.top then L.top = L.index end
  if L.index > L.top + L.visible - 1 then L.top = L.index - L.visible + 1 end
end
local function shown(L, i)
  return not L.visible or (i >= L.top and i < L.top + L.visible)
end
local function listRect(L, i)
  local top = L.visible and L.top or 1
  return L.x, L.y + (i - top) * L.step, L.w, L.h
end

function ui.drawList(L)
  keepVisible(L)
  if L.visible and #L.rows > L.visible then   -- scroll hints
    local x = L.x + L.w + 10
    if L.top > 1 then P.text(x, L.y, "^", C.dim, 1.2) end
    if L.top + L.visible - 1 < #L.rows then
      P.text(x, L.y + (L.visible - 1) * L.step + L.h - 24, "v", C.dim, 1.2)
    end
  end
  for i, row in ipairs(L.rows) do
    if shown(L, i) then ui.drawRow(L, i, row) end
  end
end

-- Called with "tick", "select" or "back" when menus are used (app.lua plays the sound)
ui.sound = function() end

function ui.drawRow(L, i, row)
  do
    local x, y, w, h = listRect(L, i)
    if i == L.index then
      P.rect(x, y, w, h, C.boxHi)
      local glow = math.floor((math.sin(P.now() / 260) + 1) * 7.5)   -- gentle pulse
      P.rect(x, y, w, h, C.pulse[glow])
      P.rect(x, y, 4, h, C.accent)
    else
      P.rect(x, y, w, h, C.row)
    end
    local label = type(row.label) == "function" and row.label() or row.label
    local ty = y + (h - 20) / 2
    if row.icon then                       -- icon + title + description rows (trophies)
      local icon = row.icon()
      if icon then P.drawImage(icon, x + 12, y + (h - 32) / 2) end
      P.text(x + 56, y + 7, label, row.color and row.color() or C.text, 0.95, true)
      if row.desc then P.text(x + 56, y + 31, row.desc, C.dim, 0.8) end
      return
    end
    if row.value then
      P.text(x + 16, ty, label, C.text)
      local vx = x + w - 250
      P.text(vx, ty, "<", C.dim)
      P.text(x + w - 26, ty, ">", C.dim)
      ui.textC(vx + 118, ty, row.value(), C.accent)
    elseif row.left then
      P.text(x + 16, ty, label, row.color or C.text)
      local right = type(row.right) == "function" and row.right() or row.right
      if right then ui.textR(x + w - 16, ty, right, (i == L.index) and C.text or (row.rightColor or C.dim)) end
    else
      ui.textC(x + w / 2, ty, label, C.text)
    end
  end
end

-- Returns true if the touch landed on a row
function ui.listTouch(L, x, y)
  for i, row in ipairs(L.rows) do
    local rx, ry, rw, rh = listRect(L, i)
    if shown(L, i) and ui.inside(x, y, rx, ry, rw, rh) then
      L.index = i
      ui.sound(row.change and "tick" or "select")
      if row.change and x >= rx + rw - 250 then row.change(x < rx + rw - 125 and -1 or 1)
      elseif row.activate then row.activate()
      elseif row.change then row.change(1) end
      return true
    end
  end
  return false
end

function ui.listInput(L, input)
  local p = input.pressed
  if p.up then L.index = ui.wrap(L.index - 1, #L.rows); ui.sound("tick") end
  if p.down then L.index = ui.wrap(L.index + 1, #L.rows); ui.sound("tick") end
  local row = L.rows[L.index]
  if row.change and (p.left or p.right) then
    ui.sound("tick")
    row.change(p.left and -1 or 1)
  end
  if p.cross then
    ui.sound(row.activate and "select" or "tick")
    if row.activate then row.activate() elseif row.change then row.change(1) end
  elseif p.circle and L.back then
    ui.sound("back")
    L.back()
  end
end

-- A list centred on screen, for pop-up menus
function ui.centerList(rows, w, h, step)
  local total = 64 + #rows * step + 14
  return ui.makeList(rows, (P.SCREEN_W - w) / 2, (P.SCREEN_H - total) / 2 + 64, w, h, step)
end

-- Area of the box drawn behind a pop-up list
function ui.listBox(L)
  return L.x - 24, L.y - 64, L.w + 48, 64 + #L.rows * L.step + 14
end

function ui.drawOverlayList(L, title, titleColor)
  P.rect(0, 0, P.SCREEN_W, P.SCREEN_H, C.shade)
  local bx, by, bw, bh = ui.listBox(L)
  P.rect(bx, by, bw, bh, C.panel)
  ui.frame(bx, by, bw, bh, 2, C.box)
  ui.textC(bx + bw / 2, by + 20, title, titleColor or C.accent, 1.3, true)
  ui.drawList(L)
end

---------------------------------------------------------------------------
-- Arrows (for hints): a stretched bar plus a triangle head, rotated to fit
---------------------------------------------------------------------------
local arrowBody, arrowHead
function ui.drawArrow(x1, y1, x2, y2, c, thick)
  if not P.drawImageRotated then return end
  if arrowBody == nil then
    arrowBody = P.loadImage(config.ASSET_DIR .. "art/arrow-body.png") or false
    arrowHead = P.loadImage(config.ASSET_DIR .. "art/arrow-head.png") or false
  end
  if not (arrowBody and arrowHead) then return end
  thick = thick or 12
  local dx, dy = x2 - x1, y2 - y1
  local len = math.sqrt(dx * dx + dy * dy)
  if len < 1 then return end
  local ux, uy, angle = dx / len, dy / len, math.atan2(dy, dx)
  local headLen = thick * 2.4
  local bodyLen = len - headLen
  P.drawImageRotated(arrowBody, x1 + ux * bodyLen / 2, y1 + uy * bodyLen / 2, 0, 0, 16, 16, angle,
    bodyLen / 16, thick / 16, c)
  P.drawImageRotated(arrowHead, x2 - ux * headLen / 2, y2 - uy * headLen / 2, 0, 0, 32, 32, angle,
    headLen / 32, (thick * 2.4) / 32, c)
end

---------------------------------------------------------------------------
-- Chess board
-- opts: flipped, coords, last, hint (move), selected (square),
--       targets ({ [square] = ... }), hide ({ [square] = true } not to draw),
--       marks ({ { sq = square, color = colour }, ... }), stars ({ [square] = true }),
--       arrow ({ from, to }), shake ({ sq = square, dx = pixels })
-- Returns a function mapping a square to its top-left screen position.
---------------------------------------------------------------------------
function ui.drawBoard(g, ox, oy, size, opts)
  local t = ui.theme()
  local sq, fileOf, rankOf = Chess.sq, Chess.fileOf, Chess.rankOf
  local function xy(s)
    local f, r = fileOf(s), rankOf(s)
    if opts.flipped then return ox + (7 - f) * size, oy + r * size end
    return ox + f * size, oy + (7 - r) * size
  end
  -- squares
  for r = 0, 7 do
    for f = 0, 7 do
      local x, y = xy(sq(f, r))
      P.rect(x, y, size, size, ((f + r) % 2 == 0) and t.D or t.L)
    end
  end
  -- coordinates (drawn in the opposite square colour so they're readable)
  if opts.coords then
    for i = 0, 7 do
      local f = opts.flipped and 7 - i or i
      local bottomRank = opts.flipped and 7 or 0
      P.text(ox + i * size + size - 13, oy + 8 * size - 19, FILES:sub(f + 1, f + 1),
        ((f + bottomRank) % 2 == 0) and t.L or t.D, 0.75)
      local r = opts.flipped and i or 7 - i
      local leftFile = opts.flipped and 7 or 0
      P.text(ox + 3, oy + i * size + 1, tostring(r + 1), ((leftFile + r) % 2 == 0) and t.L or t.D, 0.75)
    end
  end
  -- highlights
  local last = g.played[#g.played]
  if opts.last and last then
    local x, y = xy(last.m.from); P.rect(x, y, size, size, C.last)
    x, y = xy(last.m.to); P.rect(x, y, size, size, C.last)
  end
  if opts.hint then
    local x, y = xy(opts.hint.from); P.rect(x, y, size, size, C.hintSq)
    x, y = xy(opts.hint.to); P.rect(x, y, size, size, C.hintSq)
  end
  if opts.marks then
    for _, mk in ipairs(opts.marks) do local x, y = xy(mk.sq); P.rect(x, y, size, size, mk.color) end
  end
  if opts.selected then local x, y = xy(opts.selected); P.rect(x, y, size, size, C.sel) end
  if (g.check and not g.result) or g.result == "checkmate" then
    local x, y = xy(g.kingSq[g.side]); P.rect(x, y, size, size, C.check)
  end
  -- legal move markers: dot on empty squares, ring on captures
  if opts.targets then
    for to in pairs(opts.targets) do
      local x, y = xy(to)
      local c = size / 2
      if g.board[to] ~= 0 then P.circle(x + c, y + c, c - 1, C.hint)
      else P.circle(x + c, y + c, size / 6, C.hint) end
    end
  end
  if opts.stars then
    for s in pairs(opts.stars) do
      local x, y = xy(s)
      P.circle(x + size / 2, y + size / 2, size * 0.22, C.starRing)
      P.circle(x + size / 2, y + size / 2, size * 0.16, C.star)
    end
  end
  -- pieces
  local scale = size / 64
  for s = 21, 98 do
    local p = g.board[s]
    if p ~= 99 and p ~= 0 and not (opts.hide and opts.hide[s]) then
      local x, y = xy(s)
      if opts.shake and opts.shake.sq == s then x = x + opts.shake.dx end
      ui.drawPiece(p, x, y, scale)
    end
  end
  if opts.arrow and opts.arrow.from ~= opts.arrow.to then
    local x1, y1 = xy(opts.arrow.from)
    local x2, y2 = xy(opts.arrow.to)
    local c = size / 2
    ui.drawArrow(x1 + c, y1 + c, x2 + c, y2 + c, C.arrow, size * 0.19)
  end
  return xy
end

return ui
