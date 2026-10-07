-- platform_psp.lua - the PSP version of platform.lua, for LuaDEV R0
--
-- Same functions as platform.lua. The game is still laid out for the Vita's
-- 960x544 screen; this file draws everything at half size to fit the PSP's
-- 480x272 screen. Pieces use pre-shrunk 32x32 sprites.
-- tools/build.py --psp bundles this file as the "platform" module.

local P = {}

P.NAME = "PSP"
P.HAS_TOUCH = false
P.SCREEN_W, P.SCREEN_H = 960, 544     -- layout size; drawn at half scale
P.CHAR_W = 10
P.DATA_DIR = "data"                   -- next to EBOOT.PBP (LuaDEV's workspace)
P.ASSET_DIR = ""

local floor = math.floor
local S = 0.5                         -- layout -> PSP screen scale
local TEXT_SIZE = 0.55                -- LuaDEV font size for layout scale 1 (raise if text is too small)
local SPRITE_PX = 32                  -- size of the PSP piece sprites
local NO_SHADOW

local BUTTONS = { "up", "down", "left", "right", "cross", "circle", "triangle", "square", "start", "select" }

---------------------------------------------------------------------------
-- Startup and time
---------------------------------------------------------------------------
function P.init()
  pcall(os.cpu, 333)                  -- full CPU speed helps the computer think
  pcall(function() math.randomseed(os.time()) end)
  math.random(); math.random()
  NO_SHADOW = color.new(0, 0, 0, 0)
end

function P.now() return floor(os.clock() * 1000) end
function P.exit() os.exit() end

function P.date()
  local ok, d = pcall(os.date, "*t")
  if ok and type(d) == "table" then return d end
  return nil
end

---------------------------------------------------------------------------
-- Drawing (coordinates arrive in layout units and are halved here)
---------------------------------------------------------------------------
function P.color(r, g, b, a) return color.new(r, g, b, a or 255) end

function P.beginFrame() end          -- screen.flip() leaves a clean buffer

function P.endFrame()
  screen.flip()
  screen.waitvblankstart()
end

function P.rect(x, y, w, h, c)
  local x1, y1 = floor(x * S + 0.5), floor(y * S + 0.5)
  local x2, y2 = floor((x + w) * S + 0.5), floor((y + h) * S + 0.5)
  if x2 > x1 and y2 > y1 then draw.fillrect(x1, y1, x2 - x1, y2 - y1, c) end
end

-- LuaDEV has no circle function, so fill one row at a time
function P.circle(cx, cy, radius, c)
  cx, cy, radius = cx * S, cy * S, radius * S
  local r = floor(radius + 0.5)
  for dy = -r, r - 1 do
    local yy = dy + 0.5
    local half = math.sqrt(math.max(0, radius * radius - yy * yy))
    local x1, x2 = floor(cx - half + 0.5), floor(cx + half + 0.5)
    if x2 > x1 then draw.fillrect(x1, floor(cy) + dy, x2 - x1, 1, c) end
  end
end

---------------------------------------------------------------------------
-- Text: the PSP's built-in font (no TrueType fonts needed)
---------------------------------------------------------------------------
function P.loadFonts() end   -- the PSP uses its built-in font

function P.text(x, y, s, c, scale)
  screen.print(floor(x * S), floor(y * S), s, (scale or 1) * TEXT_SIZE, c, NO_SHADOW)
end

-- width in layout units
function P.textWidth(s, scale)
  local ok, w = pcall(screen.textwidth, s, (scale or 1) * TEXT_SIZE)
  if ok and w then return w / S end
  return #s * P.CHAR_W * (scale or 1)
end

---------------------------------------------------------------------------
-- Images. Each size an image is drawn at gets its own resized copy.
---------------------------------------------------------------------------
local copies = {}    -- copies[path][pixels] = image

function P.loadImage(path)
  if not files.exists(path) then return nil end
  local img = image.load(path)
  if not img then return nil end
  copies[path] = { [SPRITE_PX] = img }
  return path        -- our handle is the file path
end

function P.drawImage(handle, x, y, scale)
  local px = floor(64 * (scale or 1) * S + 0.5)    -- layout sprites are 64 wide
  local byPx = copies[handle]
  local img = byPx[px]
  if not img then
    img = image.load(handle)
    if img and px ~= SPRITE_PX then image.resize(img, px, px) end
    byPx[px] = img
  end
  if img then image.blit(img, floor(x * S), floor(y * S)) end
end

---------------------------------------------------------------------------
-- Sound
---------------------------------------------------------------------------
function P.loadSound(path)
  if not files.exists(path) then return nil end
  local ok, snd = pcall(sound.load, path)
  return ok and snd or nil
end

function P.playSound(snd)
  if snd then pcall(sound.play, snd) end
end

---------------------------------------------------------------------------
-- Input (no touchscreen on the PSP)
---------------------------------------------------------------------------
function P.readInput()
  controls.read()
  local input = { pressed = {} }
  for _, name in ipairs(BUTTONS) do
    if controls.press(name) then input.pressed[name] = true end
  end
  return input
end

---------------------------------------------------------------------------
-- Files (paths are relative to the EBOOT.PBP folder)
---------------------------------------------------------------------------
function P.readFile(path)
  local ok, data = pcall(function()
    if not files.exists(path) then return nil end
    local f = io.open(path, "r")
    if not f then return nil end
    local d = f:read("*a")
    f:close()
    return d
  end)
  if ok then return data end
  return nil
end

function P.writeFile(path, data)
  pcall(function()
    local dir = ""
    for part in path:gmatch("([^/]+)/") do
      dir = dir .. part
      if not files.exists(dir) then files.mkdir(dir) end
      dir = dir .. "/"
    end
    if #data == 0 then
      if files.exists(path) then files.remove(path) end
      return
    end
    local f = io.open(path, "w")
    f:write(data)
    f:close()
  end)
end

return P
