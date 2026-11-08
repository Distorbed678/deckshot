-- Online menu: choose Steam or LAN, then (Steam) host a lobby or join one with a code.
-- LAN has its own screen (screens/lan.lua).
local app = require "core.app"
local ui = require "core.ui"
local steam = require "online.steam"
local session = require "online.session"
local Settings = require "core.settings"
local platform = require "core.platform"

local Online = {}
Online.__index = Online

-- mode: nil = the Steam / LAN choice, "steam" = the Steam page.
function Online.new(mode)
  return setmetatable({ code = "", mode = mode }, Online)
end

function Online:enter()
  session.error = nil
end

local function toMenu()
  app.switch(require("screens.menu").new())
end

local function toChoice()
  app.switch(Online.new())
end

function Online:keypressed(key)
  if key == "escape" then
    if self.mode then toChoice() else toMenu() end
  end
end

function Online:drawChoice()
  app.centered("ONLINE", app.fonts.huge, 60)
  local w, h = 520, 74
  local x = (app.W - w) / 2
  local options = {
    { label = "Steam", text = "Play over the internet with Steam friends: lobby codes and invites",
      go = function() app.switch(Online.new("steam")) end },
    { label = "LAN", text = platform.web and "Join a game hosted on a computer on this network"
        or "Play with computers on the same network. Browsers on the network can join too",
      go = function() app.switch(require("screens.lan").new()) end },
  }
  for i, o in ipairs(options) do
    local y = 220 + (i - 1) * 130
    if ui.button(o.label, x, y, w, h, { font = app.fonts.title }) then o.go() end
    app.centered(o.text, app.fonts.small, y + h + 10, { 1, 1, 1, 0.55 })
  end
  love.graphics.setFont(app.fonts.small)
  love.graphics.setColor(1, 1, 1, 0.45)
  love.graphics.printf("Online games use the Online controls (mouse aim). Change them in Settings > Controls.",
    0, 500, app.W, "center")
  if ui.button("Back", (app.W - 420) / 2, 560, 420, 54) then toMenu() end
end

local function codeFilter(s)
  return (s:upper():gsub("[^A-Z0-9]", ""))
end

function Online:draw()
  if not self.mode then return self:drawChoice() end
  local back = toChoice
  app.centered("STEAM", app.fonts.huge, 60)

  local w = 420
  local x = (app.W - w) / 2

  if platform.web then
    app.centered("Steam needs the desktop version", app.fonts.title, 230, { 1, 0.6, 0.45 })
    love.graphics.setFont(app.fonts.med)
    love.graphics.setColor(1, 1, 1, 0.75)
    love.graphics.printf("Steam matches need Steam, which a browser can't use. Download the Windows or " ..
      "Linux version from the game's GitHub releases page to play over Steam:", app.W / 2 - 360, 280, 720, "center")
    love.graphics.setColor(1, 0.85, 0.4)
    love.graphics.printf("github.com/Distorbed678/deckshot/releases", app.W / 2 - 360, 360, 720, "center")
    if ui.button("Back", x, 470, w, 54) then back() end
    return
  end

  if not steam.available then
    app.centered("Steam isn't available", app.fonts.title, 230, { 1, 0.6, 0.45 })
    love.graphics.setFont(app.fonts.med)
    love.graphics.setColor(1, 1, 1, 0.75)
    love.graphics.printf(steam.error or "Unknown error", app.W / 2 - 360, 280, 720, "center")
    love.graphics.setColor(1, 1, 1, 0.5)
    love.graphics.printf("Steam play uses Steam (test app Spacewar, 480). Make sure Steam is running " ..
      "and you're logged in, then restart the game. LAN play works without Steam.", app.W / 2 - 360, 350, 720, "center")
    if ui.button("Back", x, 470, w, 54) then back() end
    return
  end

  app.centered("Signed in as " .. steam.myName(), app.fonts.med, 175, { 0.6, 1, 0.6 })

  local busy = session.busy
  if ui.button("Host Lobby", x, 225, w, 58, { disabled = busy }) then
    session.host(Settings.values.roundsToWin, Settings.values)
  end

  app.centered("or join with a lobby code", app.fonts.med, 315, { 1, 1, 1, 0.6 })
  local submitted
  self.code, submitted = ui.textField(self.code, x, 350, w, 60, {
    placeholder = "ENTER CODE", maxLength = 6, filter = codeFilter, font = app.fonts.big,
  })
  if ui.button("Join", x, 424, w, 54, { disabled = busy or #self.code < 6 }) or (submitted and #self.code == 6) then
    session.joinByCode(self.code)
  end

  if session.status then
    app.centered(session.status, app.fonts.med, 500, { 1, 1, 1, 0.8 })
  elseif session.error then
    app.centered(session.error, app.fonts.med, 500, { 1, 0.6, 0.45 })
  end

  love.graphics.setFont(app.fonts.small)
  love.graphics.setColor(1, 1, 1, 0.45)
  love.graphics.printf("Got a Steam invite? Accept it in Steam while the game is open and you'll join automatically.",
    0, 545, app.W, "center")

  if ui.button("Back", x, 590, w, 50) then back() end
end

return Online
