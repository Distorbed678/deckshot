-- Local Play: versus (the local setup screen) or the practice range.
local app = require "core.app"
local ui = require "core.ui"

local Screen = {}
Screen.__index = Screen

function Screen.new() return setmetatable({}, Screen) end

local function toMenu() app.switch(require("screens.menu").new()) end

function Screen:keypressed(key)
  if key == "escape" then toMenu() end
end

function Screen:draw()
  app.centered("LOCAL PLAY", app.fonts.huge, 60)
  local w, h = 520, 74
  local x = (app.W - w) / 2
  local options = {
    { label = "Versus", text = "2 to 4 players on this computer, with bots if you like",
      go = function() app.switch(require("screens.localsetup").new()) end },
    { label = "Practice", text = "Try any cards against a dummy",
      go = function() app.switch(require("screens.practice").new()) end },
  }
  for i, o in ipairs(options) do
    local y = 220 + (i - 1) * 130
    if ui.button(o.label, x, y, w, h, { font = app.fonts.title }) then o.go() end
    app.centered(o.text, app.fonts.small, y + h + 10, { 1, 1, 1, 0.55 })
  end
  if ui.button("Back", (app.W - 420) / 2, 560, 420, 54, { back = true }) then toMenu() end
end

return Screen
