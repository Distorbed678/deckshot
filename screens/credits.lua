-- Credits.
local app = require "core.app"
local ui = require "core.ui"
local Version = require "core.version"

local Screen = {}
Screen.__index = Screen

function Screen.new() return setmetatable({}, Screen) end

function Screen:keypressed(key)
  if key == "escape" then app.switch(require("screens.menu").new()) end
end

local LINES = {
  { "DECKSHOT", "v" .. Version.VERSION },
  { "Made by", "Distorbed" },
  { "Inspired by", "ROUNDS by Landfall Games. Deckshot is a fan-made game and isn't affiliated with or endorsed by Landfall." },
  { "Built with", "LÖVE 11.5 (love2d.org), LuaJIT, love.js for the browser version" },
  { "Online", "Steamworks via luasteam; LAN play over luasocket and WebSockets" },
  { "Sound", "Every sound is synthesized in code" },
  { "Thanks", "Everyone who played, tested and asked for more cards" },
}

function Screen:draw()
  love.graphics.setColor(0.09, 0.09, 0.12)
  love.graphics.rectangle("fill", 0, 0, app.W, app.H)
  app.centered("CREDITS", app.fonts.big, 40)
  local y = 130
  for _, l in ipairs(LINES) do
    love.graphics.setFont(app.fonts.med)
    love.graphics.setColor(1, 0.8, 0.35)
    love.graphics.printf(l[1], 140, y, 280, "right")
    love.graphics.setColor(1, 1, 1, 0.85)
    love.graphics.printf(l[2], 450, y, 690, "left")
    local _, wr = app.fonts.med:getWrap(l[2], 690)
    y = y + #wr * app.fonts.med:getHeight() + 22
  end
  if ui.button("Back", app.W / 2 - 150, 640, 300, 46, { back = true }) then app.switch(require("screens.menu").new()) end
end

return Screen
