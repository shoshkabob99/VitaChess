-- LÖVE settings for the Vita Chess desktop preview
function love.conf(t)
  t.identity = "VitaChess"          -- name of the save folder
  t.version = "11.4"
  t.window.title = "Vita Chess (desktop preview)"
  t.window.width = 960
  t.window.height = 544
  t.window.vsync = 1
  t.modules.physics = false
  t.modules.video = false
end
