-- Which controls the editors' test play uses: Settings.values.testInput, or a quick choice
-- when that is "ask". InputPick.choose(callback) calls callback(kind) with an input kind
-- (screens/match.lua Match.localInput: "p1", "mouse", "pad1").
local app = require "core.app"
local ui = require "core.ui"
local Settings = require "core.settings"

local InputPick = {}
InputPick.__index = InputPick

InputPick.CHOICES = {
  { "ask", "Ask each time" }, { "p1", "Keyboard" }, { "mouse", "Mouse and keyboard" }, { "pad1", "Gamepad" },
}

local function available()
  local Input = require "core.input"
  local list = { { "p1", "Keyboard", "Your Player 1 keys" }, { "mouse", "Mouse and keyboard", "Your online controls: aim with the mouse" } }
  if Input.pads()[1] then list[#list + 1] = { "pad1", "Gamepad", "The first connected gamepad" } end
  return list
end

function InputPick.choose(callback)
  local kind = Settings.values.testInput or "ask"
  if kind == "pad1" and not require("core.input").pads()[1] then kind = "ask" end
  if kind ~= "ask" then return callback(kind) end
  app.push(setmetatable({ callback = callback }, InputPick))
end

function InputPick:keypressed(key)
  if key == "escape" then app.pop() end
end

function InputPick:draw()
  love.graphics.setColor(0, 0, 0, 0.7)
  love.graphics.rectangle("fill", 0, 0, app.W, app.H)
  local list = available()
  local w, h = 560, 120 + #list * 84 + 60
  local x, y = (app.W - w) / 2, (app.H - h) / 2
  ui.panel(x, y, w, h, 1)
  love.graphics.setFont(app.fonts.title)
  love.graphics.setColor(1, 1, 1)
  love.graphics.printf("Test with which controls?", x, y + 22, w, "center")
  for i, c in ipairs(list) do
    local by = y + 80 + (i - 1) * 84
    if ui.button(c[2], x + 40, by, w - 80, 52, { font = app.fonts.med }) then
      app.pop()
      self.callback(c[1])
      return
    end
    love.graphics.setFont(app.fonts.small)
    love.graphics.setColor(1, 1, 1, 0.5)
    love.graphics.printf(c[3], x, by + 56, w, "center")
  end
  love.graphics.setFont(app.fonts.tiny)
  love.graphics.setColor(1, 1, 1, 0.4)
  love.graphics.printf("Settings > Controls > Editor test play with skips this question.", x, y + h - 74, w, "center")
  if ui.button("Cancel", x + w / 2 - 100, y + h - 52, 200, 40, { back = true }) then app.pop() end
end

return InputPick
