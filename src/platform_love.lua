-- platform_love.lua - the desktop version of platform.lua, for LÖVE 11 (love2d.org)
--
-- Lets you play and test the Vita version on Windows, Mac or Linux.
-- The window is the Vita's 960x544 screen. The mouse acts as the touchscreen.
--
-- Keyboard:  arrows = D-pad    Enter or Z = Cross    Esc or X = Circle
--            T = Triangle      F = Square            H = Select    Space = Start
-- A gamepad works too (A = Cross, B = Circle, X = Square, Y = Triangle).
-- tools/build.py --desktop bundles this file as the "platform" module.

local P = {}

P.NAME = "PS Vita (desktop preview)"
P.HAS_TOUCH = true
P.SCREEN_W, P.SCREEN_H = 960, 544
P.CHAR_W = 10
P.DATA_DIR = "data"          -- inside LÖVE's save folder
P.ASSET_DIR = ""

local floor = math.floor
local lg = love.graphics

local KEYS = {
  up = { "up" }, down = { "down" }, left = { "left" }, right = { "right" },
  cross = { "return", "kpenter", "z" }, circle = { "escape", "x", "backspace" },
  triangle = { "t" }, square = { "f" }, select = { "h" }, start = { "space" },
  l = { "q", "pageup" }, r = { "e", "pagedown" },
}
local PAD = {
  up = "dpup", down = "dpdown", left = "dpleft", right = "dpright",
  cross = "a", circle = "b", square = "x", triangle = "y", select = "back", start = "start",
  l = "leftshoulder", r = "rightshoulder",
}
local held = {}

function P.init()
  math.randomseed(os.time())
  math.random(); math.random()
  lg.setDefaultFilter("linear", "linear")
end

function P.now() return floor(love.timer.getTime() * 1000) end

function P.exit()
  love.event.quit()
  coroutine.yield("quit")
end

function P.date() return os.date("*t") end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
function P.color(r, g, b, a) return { r / 255, g / 255, b / 255, (a or 255) / 255 } end

function P.beginFrame()
  lg.origin()
  lg.clear(0, 0, 0, 1)
end

function P.endFrame()
  lg.present()
  coroutine.yield()          -- back to main.lua, which handles window events
end

function P.rect(x, y, w, h, c)
  lg.setColor(c)
  lg.rectangle("fill", x, y, w, h)
end

function P.circle(x, y, r, c)
  lg.setColor(c)
  lg.circle("fill", x, y, r)
end

local fonts, fontFiles = {}, {}
local pxFor = function(scale) return floor(17 * (scale or 1) + 0.5) end
function P.loadFonts(opts)
  fontFiles.regular, fontFiles.bold = opts.regular, opts.bold
  pxFor = opts.px or pxFor
end

local function font(scale, bold)
  local px = pxFor(scale)
  local key = (bold and "b" or "r") .. px
  if not fonts[key] then
    local file = bold and fontFiles.bold or fontFiles.regular
    if file and love.filesystem.getInfo(file) then fonts[key] = lg.newFont(file, px, "light")
    else fonts[key] = lg.newFont(px) end
  end
  return fonts[key]
end

function P.text(x, y, s, c, scale, bold)
  lg.setFont(font(scale, bold))
  lg.setColor(c)
  lg.print(s, floor(x), floor(y))
end

function P.textWidth(s, scale, bold) return font(scale, bold):getWidth(s) end

function P.loadImage(path)
  if not love.filesystem.getInfo(path) then return nil end
  return lg.newImage(path)
end

local quads = {}
function P.drawImagePart(img, x, y, sx, sy, w, h, c)
  local key = tostring(img) .. sx .. "," .. sy .. "," .. w .. "," .. h
  local q = quads[key]
  if not q then
    q = lg.newQuad(sx, sy, w, h, img:getDimensions())
    quads[key] = q
  end
  lg.setColor(c)
  lg.draw(img, q, floor(x), floor(y))
end

function P.drawImageRotated(img, cx, cy, sx, sy, w, h, angle, scaleX, scaleY, c)
  local key = tostring(img) .. sx .. "," .. sy .. "," .. w .. "," .. h
  local q = quads[key]
  if not q then
    q = lg.newQuad(sx, sy, w, h, img:getDimensions())
    quads[key] = q
  end
  lg.setColor(c)
  lg.draw(img, q, cx, cy, angle, scaleX, scaleY, w / 2, h / 2)
end

function P.drawImage(img, x, y, scale)
  lg.setColor(1, 1, 1, 1)
  lg.draw(img, x, y, 0, scale or 1, scale or 1)
end

---------------------------------------------------------------------------
-- Sound
---------------------------------------------------------------------------
function P.loadSound(path)
  if not love.filesystem.getInfo(path) then return nil end
  local ok, src = pcall(love.audio.newSource, path, "static")
  return ok and src or nil
end

function P.playSound(src, volume)
  if src and (volume or 1) > 0 then
    local c = src:clone()
    c:setVolume(volume or 1)
    c:play()
  end
end



---------------------------------------------------------------------------
-- Input: keyboard and gamepad as buttons, the mouse as the touchscreen
---------------------------------------------------------------------------
local KEY_TO_BUTTON, PAD_TO_BUTTON = {}, {}
for name, keys in pairs(KEYS) do for _, k in ipairs(keys) do KEY_TO_BUTTON[k] = name end end
for name, b in pairs(PAD) do PAD_TO_BUTTON[b] = name end
local clickRelease = false

function P.readInput()
  local input = { pressed = {} }
  -- presses queued by main.lua since the last frame
  local events = VITACHESS_EVENTS or {}
  VITACHESS_EVENTS = {}
  local click
  for _, e in ipairs(events) do
    if e[1] == "keypressed" and KEY_TO_BUTTON[e[2]] then input.pressed[KEY_TO_BUTTON[e[2]]] = true
    elseif e[1] == "gamepadpressed" and PAD_TO_BUTTON[e[3]] then input.pressed[PAD_TO_BUTTON[e[3]]] = true
    elseif e[1] == "mousepressed" and e[4] == 1 then click = { e[2], e[3] } end
  end
  -- buttons held down still count as held, so a press is only reported once
  local pad = love.joystick.getJoysticks()[1]
  for name, keys in pairs(KEYS) do
    local down = love.keyboard.isDown(unpack(keys))
    if pad and pad:isGamepad() and pad:isGamepadDown(PAD[name]) then down = true end
    held[name] = down
  end
  -- the mouse is the touchscreen (a quick click still counts as a tap)
  if love.mouse.isDown(1) then
    input.touchX, input.touchY = love.mouse.getPosition()
  elseif click and not clickRelease then
    input.touchX, input.touchY = click[1], click[2]
  end
  return input
end

---------------------------------------------------------------------------
-- Files (saved in LÖVE's save folder; see the README for where that is)
---------------------------------------------------------------------------
function P.readFile(path)
  if not love.filesystem.getInfo(path) then return nil end
  return love.filesystem.read(path)
end

function P.writeFile(path, data)
  local dir = path:match("^(.*)/[^/]*$")
  if dir then love.filesystem.createDirectory(dir) end
  if #data == 0 then love.filesystem.remove(path) return end
  love.filesystem.write(path, data)
end

return P
