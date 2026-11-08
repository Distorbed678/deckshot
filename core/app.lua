-- Screen stack and the virtual 1280x720 canvas that is letterboxed to the window.
-- Everything is laid out in 1280x720 units but rendered at the window's real resolution:
-- the canvas and fonts use a DPI scale equal to the window / virtual scale, so text and
-- shapes stay sharp at any window size instead of being stretched up from 1280x720.
local ui = require "core.ui"

local app = {
  W = 1280, H = 720,
  stack = {},
  fonts = {},
  scale = 1, ox = 0, oy = 0,
  renderScale = nil, -- DPI scale the canvas and fonts were built for
  textScale = 1,     -- text size option (Settings.TEXT_SIZES)
  showFps = false,
}

local FONT_SIZES = { tiny = 12, small = 14, med = 18, button = 22, title = 26, big = 36, huge = 96 }
-- Headings and buttons use the display face; everything you read in sentences uses the body face.
local BODY_FILE, DISPLAY_FILE = "assets/fonts/Barlow-Medium.ttf", "assets/fonts/RussoOne-Regular.ttf"
local DISPLAY = { button = true, title = true, big = true, huge = true }

local function newFont(name, size, s)
  local file = DISPLAY[name] and DISPLAY_FILE or BODY_FILE
  if love.filesystem.getInfo(file) then
    local ok, font = pcall(love.graphics.newFont, file, size, "normal", s)
    if ok then return font end
  end
  return love.graphics.newFont(size, "normal", s)
end

-- (Re)create the canvas and fonts for a render scale. Must not run while a canvas is active.
local function buildTargets(s)
  app.renderScale = s
  for name, size in pairs(FONT_SIZES) do
    app.fonts[name] = newFont(name, math.floor(size * app.textScale + 0.5), s)
  end
  if app.canvas then app.canvas:release() end
  local ok, canvas = pcall(love.graphics.newCanvas, app.W, app.H, { msaa = 4, dpiscale = s })
  app.canvas = ok and canvas or love.graphics.newCanvas(app.W, app.H, { dpiscale = s })
  if app.transCanvas then app.transCanvas:release() end
  app.transCanvas = love.graphics.newCanvas(app.W, app.H, { dpiscale = s })
  app.trans = nil
end

function app.load()
  app.fonts.overlay = love.graphics.newFont(14) -- drawn straight onto the window (FPS counter)
  app.updateViewport()
end

---------------------------------------------------------------- screens
-- A screen is a table with optional enter, leave, update(dt, isTop), draw,
-- keypressed, keyreleased, mousepressed, mousereleased, textinput.

---------------------------------------------------------------- transitions
-- The next frame slides in from the right while the last one slides out to the left.
local SLIDE_TIME = 0.6
function app.slide()
  if app.skipSlide then
    app.skipSlide = false
    return
  end
  if not app.noSlide then app.transPending = true end
end

-- The next switch happens without sliding.
function app.instant()
  app.skipSlide = true
end

-- The screen fades up from dark over `dur` seconds.
function app.fadeFrom(dur)
  app.fade = { t = 0, dur = dur }
end

function app.switch(screen, ...)
  app.slide()
  for i = #app.stack, 1, -1 do
    local s = app.stack[i]
    if s.leave then s:leave() end
  end
  app.stack = { screen }
  ui.reset()
  if screen.enter then screen:enter(...) end
end

function app.push(screen, ...)
  table.insert(app.stack, screen)
  ui.reset()
  if screen.enter then screen:enter(...) end
end

function app.pop()
  local s = table.remove(app.stack)
  if s and s.leave then s:leave() end
  ui.reset()
end

function app.top()
  return app.stack[#app.stack]
end

function app.base()
  return app.stack[1]
end

---------------------------------------------------------------- coordinates
function app.updateViewport()
  local ww, wh = love.graphics.getDimensions()
  app.scale = math.min(ww / app.W, wh / app.H)
  app.ox = math.floor((ww - app.W * app.scale) / 2)
  app.oy = math.floor((wh - app.H * app.scale) / 2)
  local s = math.max(0.5, app.scale)
  if not app.renderScale or math.abs(s - app.renderScale) > 0.001 then buildTargets(s) end
end

-- Mouse position in game (virtual) coordinates.
function app.mouse()
  local x, y = love.mouse.getPosition()
  return (x - app.ox) / app.scale, (y - app.oy) / app.scale
end

---------------------------------------------------------------- loop
function app.update(dt)
  app.updateViewport()
  local n = #app.stack
  for i = 1, n do
    local s = app.stack[i]
    if s and s.update then s:update(dt, i == #app.stack) end
  end
end

function app.draw()
  app.updateViewport()
  if app.transPending and app.transCanvas then
    -- Keep the last finished frame for the slide.
    app.transPending = false
    love.graphics.setCanvas(app.transCanvas)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setColor(1, 1, 1)
    love.graphics.setBlendMode("alpha", "premultiplied")
    love.graphics.draw(app.canvas, 0, 0)
    love.graphics.setBlendMode("alpha")
    app.trans = { t = 0 }
  end
  love.graphics.setCanvas(app.canvas)
  love.graphics.clear(0.11, 0.11, 0.15)
  love.graphics.origin()
  for i, s in ipairs(app.stack) do
    ui.active = (i == #app.stack)
    if ui.active then ui.beginFrame() end
    if s.draw then s:draw() end
  end
  ui.endFrame()
  love.graphics.setCanvas()

  love.graphics.clear(0, 0, 0)
  love.graphics.setColor(1, 1, 1)
  love.graphics.setBlendMode("alpha", "premultiplied")
  local tr = app.trans
  if tr then
    tr.t = tr.t + math.min(1 / 30, love.timer.getDelta())
    local k = math.min(1, tr.t / SLIDE_TIME)
    local e = 1 - (1 - k) ^ 3
    local w = app.W * app.scale
    love.graphics.setScissor(app.ox, app.oy, w, app.H * app.scale)
    love.graphics.draw(app.transCanvas, app.ox - w * e, app.oy, 0, app.scale, app.scale)
    love.graphics.draw(app.canvas, app.ox + w * (1 - e), app.oy, 0, app.scale, app.scale)
    love.graphics.setScissor()
    if k >= 1 then app.trans = nil end
  else
    love.graphics.draw(app.canvas, app.ox, app.oy, 0, app.scale, app.scale)
  end
  love.graphics.setBlendMode("alpha")

  local fade = app.fade
  if fade then
    fade.t = fade.t + math.min(1 / 30, love.timer.getDelta())
    local k = math.min(1, fade.t / fade.dur)
    love.graphics.setColor(0.09, 0.09, 0.12, 1 - k * k * (3 - 2 * k))
    love.graphics.rectangle("fill", 0, 0, love.graphics.getDimensions())
    if k >= 1 then app.fade = nil end
  end

  if app.showFps then
    love.graphics.setFont(app.fonts.overlay)
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", 4, 4, 70, 20)
    love.graphics.setColor(0.6, 1, 0.6)
    love.graphics.print(love.timer.getFPS() .. " FPS", 10, 7)
  end
end

local function forward(name, ...)
  local s = app.top()
  if s and s[name] then s[name](s, ...) end
end

function app.keypressed(key, scancode, isrepeat)
  ui.keypressed(key)
  forward("keypressed", key, isrepeat)
end

function app.keyreleased(key)
  forward("keyreleased", key)
end

function app.mousepressed(x, y, button)
  local vx, vy = (x - app.ox) / app.scale, (y - app.oy) / app.scale
  ui.mousepressed(vx, vy, button)
  forward("mousepressed", vx, vy, button)
end

function app.mousereleased(x, y, button)
  forward("mousereleased", (x - app.ox) / app.scale, (y - app.oy) / app.scale, button)
end

function app.wheelmoved(x, y)
  forward("wheelmoved", x, y)
end

function app.mousemoved()
  ui.mouseMoved = true
end

-- Gamepad buttons: the top screen may use them (in a match); otherwise they drive menus
-- like the keyboard (d-pad = arrows, A = Enter, B / Start = Escape).
local PAD_KEYS = { dpup = "up", dpdown = "down", dpleft = "left", dpright = "right", a = "return", b = "escape",
  start = "escape" }
function app.gamepadpressed(joystick, button)
  local s = app.top()
  if s and s.gamepadpressed and s:gamepadpressed(joystick, button) then return end
  local key = PAD_KEYS[button]
  if key then app.keypressed(key) end
end

function app.textinput(t)
  ui.textinput(t)
  forward("textinput", t)
end

---------------------------------------------------------------- helpers
function app.centered(text, font, y, color)
  love.graphics.setFont(font)
  love.graphics.setColor(color or { 1, 1, 1 })
  love.graphics.printf(text, 0, y, app.W, "center")
end

return app
