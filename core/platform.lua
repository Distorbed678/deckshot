-- Where the game is running. love._os is set before conf.lua runs, so this works everywhere.
-- The browser build (love.js) runs plain Lua 5.1: no LuaJIT, no ffi, no `bit` library.
local platform = {}

platform.web = love._os == "Web"

-- The canvas format to draw into. In the browser (WebGL 1) LÖVE's default is only 4 bits per
-- colour, which makes text and gradients muddy, so use full colour where the browser allows it.
local chosen
function platform.canvasFormat()
  if not platform.web then return "normal" end
  if not chosen then
    local formats = love.graphics.getCanvasFormats()
    chosen = formats.rgba16f and "rgba16f" or "normal"
  end
  return chosen
end

return platform
