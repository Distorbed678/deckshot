function love.conf(t)
  t.identity = "deckshot"
  t.version = "11.4"
  t.window.title = "Deckshot"
  t.window.width = 1280
  t.window.height = 720
  t.window.resizable = true
  t.window.minwidth = 640
  t.window.minheight = 360
  t.window.vsync = 1

  -- Start Steam before the window exists so the Steam overlay (invite dialog) can hook in.
  -- Any failure just leaves online play unavailable.
  pcall(function() require("online.steam").init() end)
end
