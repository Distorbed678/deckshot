-- Customize (main menu): choose a hat and face. Others see them in online and LAN games.
local app = require "core.app"
local ui = require "core.ui"
local Settings = require "core.settings"
local Cosmetics = require "core.cosmetics"
local World = require "game.world"

local Screen = {}
Screen.__index = Screen

function Screen.new()
  return setmetatable({ hat = Cosmetics.HAT_INDEX[Settings.values.hat] or 1, face = Cosmetics.FACE_INDEX[Settings.values.face] or 1 }, Screen)
end

local function toMenu() app.switch(require("screens.menu").new()) end

function Screen:keypressed(key)
  if key == "escape" then toMenu() end
end

local function grid(self, list, field, x, y, cols, settingsKey)
  local bw, bh, gap = 150, 62, 10
  for i, item in ipairs(list) do
    local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
    local bx, by = x + col * (bw + gap), y + row * (bh + gap)
    local open = Cosmetics.unlocked(item)
    if ui.button(open and item.name or "Locked", bx, by, bw, bh,
      { font = app.fonts.small, color = self[field] == i and ui.ACCENT or nil, disabled = not open }) then
      self[field] = i
      Settings.values[settingsKey] = item.id
      Settings.save()
    end
    if not open then
      local mx, my = app.mouse()
      if mx >= bx and mx <= bx + bw and my >= by and my <= by + bh then self.tip = Cosmetics.unlockText(item) end
    end
  end
  return y + math.ceil(#list / cols) * (bh + gap)
end

function Screen:draw()
  love.graphics.setColor(0.09, 0.09, 0.12)
  love.graphics.rectangle("fill", 0, 0, app.W, app.H)
  app.centered("CUSTOMIZE", app.fonts.big, 28)

  ui.panel(50, 90, 400, 520)
  local c = World.PALETTE[Settings.values.playerColor or 1] or World.PALETTE[1]
  local mx, my = app.mouse()
  local dx, dy = mx - 250, my - 300
  local d = math.max(1, math.sqrt(dx * dx + dy * dy))
  Cosmetics.drawPreview(250, 320, 90, c, self.hat, self.face, { dx / d, dy / d })
  love.graphics.setFont(app.fonts.title)
  love.graphics.setColor(1, 1, 1)
  love.graphics.printf(Cosmetics.HATS[self.hat].name, 50, 470, 400, "center")
  love.graphics.setFont(app.fonts.med)
  love.graphics.setColor(1, 1, 1, 0.6)
  love.graphics.printf(Cosmetics.FACES[self.face].name, 50, 510, 400, "center")

  self.tip = nil
  local x, y = 490, 90
  love.graphics.setFont(app.fonts.title)
  love.graphics.setColor(1, 1, 1, 0.9)
  love.graphics.print("Hats", x, y)
  y = grid(self, Cosmetics.HATS, "hat", x, y + 40, 4, "hat") + 8
  love.graphics.setFont(app.fonts.title)
  love.graphics.setColor(1, 1, 1, 0.9)
  love.graphics.print("Faces", x, y)
  y = grid(self, Cosmetics.FACES, "face", x, y + 40, 4, "face")

  love.graphics.setFont(app.fonts.med)
  if self.tip then
    love.graphics.setColor(ui.GOLD)
    love.graphics.printf(self.tip, 490, 628, 700, "center")
  else
    love.graphics.setColor(1, 1, 1, 0.5)
    love.graphics.printf("Hover a locked item to see how to earn it", 490, 628, 700, "center")
  end
  if ui.button("Back", app.W / 2 - 150, 660, 300, 46, { back = true }) then toMenu() end
end

return Screen
