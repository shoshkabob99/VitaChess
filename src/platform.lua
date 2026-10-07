-- platform.lua - everything that talks to the Vita (Lua Player Plus Vita)
--
-- The rest of the game only calls the functions in this file. To port the
-- game to another system (e.g. a PSP Lua player), write a new version of
-- this file with the same function names and adjust the screen layout.

local P = {}

P.NAME = "PS Vita"
P.HAS_TOUCH = true
P.SCREEN_W, P.SCREEN_H = 960, 544     -- the game is laid out for this size
P.CHAR_W = 10                        -- approximate width of one character of text

local floor = math.floor
local clock
local oldpad = 0
local BUTTONS                        -- our button names -> Vita button codes

---------------------------------------------------------------------------
-- Startup
---------------------------------------------------------------------------
function P.init()
  pcall(System.setCpuSpeed, 444)     -- full CPU speed helps the computer think
  clock = Timer.new()
  pcall(function() math.randomseed(os.time() + P.now()) end)
  math.random(); math.random()
  pcall(Sound.init)
  BUTTONS = {
    up = SCE_CTRL_UP, down = SCE_CTRL_DOWN, left = SCE_CTRL_LEFT, right = SCE_CTRL_RIGHT,
    cross = SCE_CTRL_CROSS, circle = SCE_CTRL_CIRCLE, triangle = SCE_CTRL_TRIANGLE,
    square = SCE_CTRL_SQUARE, start = SCE_CTRL_START, select = SCE_CTRL_SELECT,
    l = SCE_CTRL_LTRIGGER, r = SCE_CTRL_RTRIGGER,
  }
end

-- Milliseconds since startup
function P.now() return Timer.getTime(clock) end

function P.exit() System.exit() end

-- Today's date and time as a table { year, month, day, hour, min, sec }, or nil
function P.date()
  local ok, d = pcall(os.date, "*t")
  if ok and type(d) == "table" then return d end
  return nil
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
function P.color(r, g, b, a) return Color.new(r, g, b, a or 255) end

function P.beginFrame()
  Graphics.initBlend()
  Screen.clear()
end

function P.endFrame()
  Graphics.termBlend()
  Screen.flip()
  Screen.waitVblankStart()
end

function P.rect(x, y, w, h, c) Graphics.fillRect(x, x + w, y, y + h, c) end

function P.circle(x, y, radius, c) Graphics.fillCircle(x, y, radius, c) end

---------------------------------------------------------------------------
-- Text, drawn from pre-rendered bitmap fonts (see tools/make_fonts.py).
-- Each letter is copied pixel-for-pixel from an atlas image and coloured as
-- it's drawn, so text is crisp at every size. Falls back to the debug font.
---------------------------------------------------------------------------
local fonts = {}       -- fonts["r18"] = { img, glyphs = { [code] = {...} } }
local fontSizes = {}
local pxFor = function(scale) return floor(17 * (scale or 1) + 0.5) end

-- opts = { dir = ".../bitmap/", sizes = { 14, 15, ... }, px = function(scale) }
function P.loadFonts(opts)
  if not opts or not opts.dir then return end
  fontSizes, pxFor = opts.sizes, opts.px
  for _, weight in ipairs({ "r", "b" }) do
    for _, px in ipairs(opts.sizes) do
      local name = weight .. px
      local path = opts.dir .. name
      if System.doesFileExist(path .. ".png") and System.doesFileExist(path .. ".fnt") then
        local h = System.openFile(path .. ".fnt", FREAD)
        local data = System.readFile(h, System.sizeFile(h))
        System.closeFile(h)
        local glyphs = {}
        for code, gx, gy, w, gh, ox, oy, adv in data:gmatch(
            "(%d+) (%d+) (%d+) (%d+) (%d+) (%-?%d+) (%-?%d+) ([%d%.]+)") do
          glyphs[tonumber(code)] = { tonumber(gx), tonumber(gy), tonumber(w), tonumber(gh),
                                     tonumber(ox), tonumber(oy), tonumber(adv) }
        end
        local img = Graphics.loadImage(path .. ".png")
        pcall(Graphics.setImageFilters, img, FILTER_POINT, FILTER_POINT)
        fonts[name] = { img = img, glyphs = glyphs }
      end
    end
  end
end

-- the loaded font closest to the size wanted
local function pickFont(scale, bold)
  local want = pxFor(scale)
  local best, bestDiff
  for _, px in ipairs(fontSizes) do
    local f = fonts[(bold and "b" or "r") .. px]
    if f and (not bestDiff or math.abs(px - want) < bestDiff) then best, bestDiff = f, math.abs(px - want) end
  end
  return best
end

function P.text(x, y, s, c, scale, bold)
  local f = pickFont(scale, bold)
  if not f then Graphics.debugPrint(floor(x), floor(y), s, c, scale or 1); return end
  local pen, img, glyphs = x, f.img, f.glyphs
  y = floor(y + 0.5)
  for i = 1, #s do
    local g = glyphs[s:byte(i)] or glyphs[63]          -- unknown letters become "?"
    if g then
      if g[3] > 0 then
        Graphics.drawPartialImage(floor(pen + g[5] + 0.5), y + g[6], img, g[1], g[2], g[3], g[4], c)
      end
      pen = pen + g[7]
    end
  end
end

function P.textWidth(s, scale, bold)
  local f = pickFont(scale, bold)
  if not f then return #s * P.CHAR_W * (scale or 1) end
  local w, glyphs = 0, f.glyphs
  for i = 1, #s do
    local g = glyphs[s:byte(i)] or glyphs[63]
    if g then w = w + g[7] end
  end
  return w
end

-- Returns an image handle, or nil if the file doesn't exist
function P.loadImage(path)
  if System.doesFileExist(path) then return Graphics.loadImage(path) end
  return nil
end

-- Draw part of an image (sx, sy, w, h), coloured by c
function P.drawImagePart(img, x, y, sx, sy, w, h, c)
  Graphics.drawPartialImage(floor(x), floor(y), img, sx, sy, w, h, c)
end

-- Draw part of an image rotated (radians) and scaled, centred on (cx, cy)
function P.drawImageRotated(img, cx, cy, sx, sy, w, h, angle, scaleX, scaleY, c)
  Graphics.drawImageExtended(cx, cy, img, sx, sy, w, h, angle, scaleX, scaleY, c)
end

function P.drawImage(img, x, y, scale)
  if not scale or scale == 1 then Graphics.drawImage(x, y, img)
  else Graphics.drawScaleImage(x, y, img, scale, scale) end
end

---------------------------------------------------------------------------
-- Sound
---------------------------------------------------------------------------
function P.loadSound(path)
  local ok, snd = pcall(function()
    if System.doesFileExist(path) then return Sound.open(path) end
  end)
  return ok and snd or nil
end

-- volume: 0 to 1
function P.playSound(snd, volume)
  if snd and (volume or 1) > 0 then
    pcall(Sound.setVolume, snd, floor(32767 * (volume or 1)))
    pcall(Sound.play, snd, false)
  end
end

---------------------------------------------------------------------------
-- Input
-- Returns { pressed = { cross = true, ... }, touchX = x, touchY = y }
-- "pressed" only lists buttons that went down this frame (not held ones).
-- touchX/touchY are nil when nothing is touching the front screen.
---------------------------------------------------------------------------
function P.readInput()
  local pad = Controls.read()
  local input = { pressed = {} }
  for name, code in pairs(BUTTONS) do
    if Controls.check(pad, code) and not Controls.check(oldpad, code) then
      input.pressed[name] = true
    end
  end
  oldpad = pad
  input.touchX, input.touchY = Controls.readTouch()
  return input
end

---------------------------------------------------------------------------
-- Files
---------------------------------------------------------------------------
function P.readFile(path)
  local ok, data = pcall(function()
    if not System.doesFileExist(path) then return nil end
    local h = System.openFile(path, FREAD)
    local d = System.readFile(h, System.sizeFile(h))
    System.closeFile(h)
    return d
  end)
  if ok then return data end
  return nil
end

-- Replaces the file's contents (creating its folder if needed).
-- Writing an empty string deletes the file.
function P.writeFile(path, data)
  pcall(function()
    -- create each missing folder along the path, e.g. ux0:data/VitaChess/games
    local dir = ""
    for part in path:gmatch("([^/]+)/") do
      dir = dir .. part
      if not dir:find(":$") and not System.doesDirExist(dir) then System.createDirectory(dir) end
      dir = dir .. "/"
    end
    if System.doesFileExist(path) then System.deleteFile(path) end
    if #data == 0 then return end
    local h = System.openFile(path, FCREATE)
    System.writeFile(h, data, #data)
    System.closeFile(h)
  end)
end

return P
