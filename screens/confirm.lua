-- A small "are you sure?" dialog, pushed on top of any screen.
local app = require "core.app"
local ui = require "core.ui"

local Confirm = {}
Confirm.__index = Confirm

-- onYes runs after the dialog closes. opts: yes, no (button labels), danger (red confirm button).
function Confirm.ask(title, text, onYes, opts)
  opts = opts or {}
  app.push(setmetatable({ title = title, text = text, onYes = onYes, yes = opts.yes or "Yes", no = opts.no or "Cancel",
    danger = opts.danger }, Confirm))
end

function Confirm:keypressed(key)
  if key == "escape" then app.pop() end
end

function Confirm:draw()
  love.graphics.setColor(0, 0, 0, 0.65)
  love.graphics.rectangle("fill", 0, 0, app.W, app.H)
  local w, h = 620, 260
  local x, y = (app.W - w) / 2, (app.H - h) / 2
  ui.panel(x, y, w, h, 1)
  love.graphics.setFont(app.fonts.title)
  love.graphics.setColor(1, 1, 1)
  love.graphics.printf(self.title, x + 30, y + 26, w - 60, "center")
  love.graphics.setFont(app.fonts.med)
  love.graphics.setColor(1, 1, 1, 0.75)
  love.graphics.printf(self.text, x + 40, y + 78, w - 80, "center")
  local bw = (w - 90) / 2
  if ui.button(self.no, x + 30, y + h - 76, bw, 52, { back = true }) then
    app.pop()
    return
  end
  if ui.button(self.yes, x + 60 + bw, y + h - 76, bw, 52, { color = self.danger and ui.BAD or ui.GOOD }) then
    app.pop()
    if self.onYes then self.onYes() end
  end
end

return Confirm
