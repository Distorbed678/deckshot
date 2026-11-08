-- Touch layout editor (Settings > Controls): drag the touch buttons, change their size and opacity.
local app = require "core.app"
local ui = require "core.ui"
local Settings = require "core.settings"
local Touch = require "core.touch"

local Screen = {}
Screen.__index = Screen

function Screen.new()
  return setmetatable({ sel = "jump", drag = nil }, Screen)
end

function Screen:save()
  local v = Settings.values
  v.touchLayout = Touch.layoutString()
  v.touchOpacity = Touch.opacity
  Settings.save()
end

function Screen:keypressed(key)
  if key == "escape" then
    self:save()
    app.pop()
  end
end

function Screen:mousepressed(x, y, button)
  for _, name in ipairs(Touch.BUTTONS) do
    local b = Touch.layout[name]
    if (x - b[1]) ^ 2 + (y - b[2]) ^ 2 < (b[3] + 6) ^ 2 then
      self.sel = name
      self.drag = { name = name, dx = x - b[1], dy = y - b[2] }
      return
    end
  end
end

function Screen:mousereleased()
  self.drag = nil
end

function Screen:update()
  local d = self.drag
  if not d then return end
  local x, y = app.mouse()
  local b = Touch.layout[d.name]
  b[1] = math.max(b[3], math.min(app.W - b[3], math.floor(x - d.dx)))
  b[2] = math.max(b[3], math.min(app.H - b[3], math.floor(y - d.dy)))
end

function Screen:draw()
  love.graphics.setColor(0.07, 0.07, 0.1, 0.96)
  love.graphics.rectangle("fill", 0, 0, app.W, app.H)
  love.graphics.setColor(1, 1, 1, 0.06)
  love.graphics.rectangle("fill", 0, 0, app.W / 2, app.H)
  app.centered("TOUCH LAYOUT", app.fonts.big, 60)
  app.centered("Drag the buttons. Left half: move stick. Right half: aim stick (fires while held).", app.fonts.small, 110,
    { 1, 1, 1, 0.55 })
  Touch.draw()
  local b = Touch.layout[self.sel]
  love.graphics.setColor(1, 0.8, 0.2)
  love.graphics.setLineWidth(3)
  love.graphics.circle("line", b[1], b[2], b[3] + 6)

  local x, y = 340, 200
  local d = ui.cycler("Size (" .. Touch.LABELS[self.sel] .. ")", tostring(b[3]), x, y, 600, 44)
  if d ~= 0 then b[3] = math.max(20, math.min(110, b[3] + d * 4)) end
  d = ui.cycler("Opacity", math.floor(Touch.opacity * 100 + 0.5) .. "%", x, y + 54, 600, 44)
  if d ~= 0 then Touch.opacity = math.max(0.1, math.min(1, Touch.opacity + d * 0.1)) end
  if ui.button("Reset", x, y + 108, 290, 44) then Touch.setLayout("", 0.5) end
  if ui.button("Done", x + 310, y + 108, 290, 44, { back = true }) then
    self:save()
    app.pop()
  end
end

return Screen
