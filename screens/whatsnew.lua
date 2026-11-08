-- "What's new" notes, as a dialog over the main menu (buttons behind it can't be clicked).
local app = require "core.app"
local ui = require "core.ui"
local Version = require "core.version"

local Screen = {}
Screen.__index = Screen

function Screen.new() return setmetatable({ scroll = { y = 0 } }, Screen) end

function Screen:keypressed(key)
  if key == "escape" then app.pop() end
end

function Screen:wheelmoved(_, dy) ui.wheel(self.scroll, dy) end

function Screen:draw()
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.rectangle("fill", 0, 0, app.W, app.H)
  local px, py, pw, ph = 140, 60, 1000, 600
  ui.panel(px, py, pw, ph, 1)
  love.graphics.setFont(app.fonts.title)
  love.graphics.setColor(1, 1, 1)
  love.graphics.printf("What's new in v" .. Version.VERSION, px, py + 20, pw, "center")
  local font = app.fonts.med
  local tw = pw - 110
  local h = 0
  for _, line in ipairs(Version.NOTES) do
    local _, wr = font:getWrap(line, tw)
    h = h + #wr * font:getHeight() + 8
  end
  local top, viewH = py + 70, ph - 150
  local y = ui.beginScroll(self.scroll, px + 30, top, pw - 60, viewH, h)
  love.graphics.setFont(font)
  for _, line in ipairs(Version.NOTES) do
    love.graphics.setColor(ui.GOLD)
    love.graphics.print("-", px + 40, y)
    love.graphics.setColor(1, 1, 1, 0.85)
    love.graphics.printf(line, px + 62, y, tw, "left")
    local _, wr = font:getWrap(line, tw)
    y = y + #wr * font:getHeight() + 8
  end
  ui.endScroll(self.scroll)
  if ui.button("Close", app.W / 2 - 110, py + ph - 62, 220, 46, { back = true }) then app.pop() end
end

return Screen
