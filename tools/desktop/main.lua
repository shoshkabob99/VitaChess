-- Vita Chess desktop preview: runs the Vita game (game.lua) inside LÖVE.
-- The game has its own main loop, so it runs as a coroutine that hands
-- control back once per frame (see platform_love.lua).
function love.run()
  local game = love.filesystem.load("game.lua")
  local co = coroutine.create(game)
  local frames = 0
  local shotAt = tonumber(os.getenv("VITACHESS_SHOT_SECONDS") or "")   -- for automated testing
  local start = love.timer.getTime()
  return function()
    love.event.pump()
    for name, a, b, c in love.event.poll() do
      if name == "quit" then return 0 end
      -- quick taps and key presses are queued so none are missed between frames
      if name == "keypressed" or name == "gamepadpressed" or name == "mousepressed" then
        VITACHESS_EVENTS = VITACHESS_EVENTS or {}
        table.insert(VITACHESS_EVENTS, { name, a, b, c })
        if os.getenv("VITACHESS_DEBUG") then print(name, a, b, c) end
      end
    end
    love.timer.step()
    local ok, res = coroutine.resume(co)
    if not ok then error(debug.traceback(co, res), 0) end
    if res == "quit" or coroutine.status(co) == "dead" then return 0 end
    frames = frames + 1
    if shotAt and love.timer.getTime() - start >= shotAt then
      shotAt = nil
      love.graphics.captureScreenshot(function(img)
        img:encode("png", "selftest.png")
        love.event.quit()
      end)
    end
  end
end
