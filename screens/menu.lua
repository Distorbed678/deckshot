local app = require "core.app"
local ui = require "core.ui"
local Settings = require "core.settings"
local platform = require "core.platform"

local Menu = {}
Menu.__index = Menu

-- message: optional notice, e.g. "The host left the game"
function Menu.new(message)
  return setmetatable({ message = message }, Menu)
end

function Menu:enter()
  love.mouse.setVisible(true)
end

-- One line per control scheme, built from the current key bindings.
function Menu.controlsText()
  local name = require("core.input").keyName
  local b = Settings.values.binds
  local function scheme(s)
    return string.format("%s/%s/%s/%s, %s fire, %s block", name(s.left), name(s.up), name(s.down), name(s.right),
      name(s.fire), name(s.block))
  end
  local o = b.online
  return "Local:  P1 " .. scheme(b.p1) .. "   |   P2 " .. scheme(b.p2) .. "\n" ..
    string.format("Online:  %s/%s move, %s or %s jump, %s fast-fall, mouse aim, %s fire, %s block   |   Esc: menu",
      name(o.left), name(o.right), name(o.jump), name(o.jump2), name(o.down), name(o.fire), name(o.block))
end

function Menu:draw()
  local t = love.timer.getTime()
  -- Drifting background dots in the four player colours.
  local colors = require("game.world").COLORS
  for i = 1, 24 do
    local c = colors[(i - 1) % 4 + 1]
    local x = (i * 173 + t * (12 + i % 5 * 6)) % (app.W + 80) - 40
    local y = (i * 97) % app.H
    love.graphics.setColor(c[1], c[2], c[3], 0.07)
    love.graphics.circle("fill", x, y, 18 + (i % 4) * 10)
  end

  app.centered("DECKSHOT", app.fonts.huge, 80)
  app.centered("Lose a round, pick a card. Up to 4 players online.", app.fonts.med, 192, { 1, 1, 1, 0.55 })

  local w, h = 340, 58
  local x = (app.W - w) / 2
  local y = 250
  if ui.button("Local Play", x, y, w, h) then
    app.switch(require("screens.match").newLocal(Settings.values.roundsToWin))
  end
  if ui.button("Online Play", x, y + 72, w, h) then
    app.switch(require("screens.online").new())
  end
  if ui.button("Editor", x, y + 144, w / 2 - 5, h) then
    app.switch(require("screens.editor_hub").new())
  end
  if ui.button("Codex", x + w / 2 + 5, y + 144, w / 2 - 5, h) then
    app.switch(require("screens.codex").new())
  end
  if ui.button("Settings", x, y + 216, w, h) then
    app.push(require("screens.settings").new())
  end
  if not platform.web and ui.button("Quit", x, y + 288, w, h) then
    love.event.quit()
  end

  if self.message then
    app.centered(self.message, app.fonts.med, 230, { 1, 0.6, 0.45 })
  end

  love.graphics.setFont(app.fonts.small)
  love.graphics.setColor(1, 1, 1, 0.4)
  love.graphics.printf(Menu.controlsText(), 0, app.H - 56, app.W, "center")
end

return Menu
