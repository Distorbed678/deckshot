-- LAN menu: host a game on this network, or join one from the list of games found or by address.
-- In the browser you can only join, and only the desktop host that served the page.
local app = require "core.app"
local ui = require "core.ui"
local lan = require "online.lan"
local Settings = require "core.settings"
local platform = require "core.platform"

local Lan = {}
Lan.__index = Lan

function Lan.new()
  return setmetatable({ name = Settings.values.playerName or "", address = Settings.values.lastLanAddress or "",
    games = {} }, Lan)
end

function Lan:enter()
  lan.error = nil
  if platform.web then
    self.webAvailable, self.webHost = require("online.webbridge").info()
  end
end

function Lan:leave()
  lan.stopBrowsing()
end

local function back()
  if lan.busy then lan.leave() end
  app.switch(require("screens.online").new())
end

function Lan:keypressed(key)
  if key == "escape" then back() end
end

function Lan:update()
  if not platform.web then self.games = lan.browse() end
end

function Lan:saveName()
  self.name = lan.cleanName(self.name)
  if Settings.values.playerName ~= self.name then
    Settings.values.playerName = self.name
    Settings.save()
  end
end

function Lan:host()
  self:saveName()
  lan.host(Settings.values.roundsToWin, Settings.values)
end

function Lan:join(address)
  if address and address ~= "" then
    Settings.values.lastLanAddress = address
    Settings.save()
  end
  self:saveName()
  lan.join(address)
end

local function addressFilter(s)
  return (s:gsub("[^%w%.:%-]", ""))
end

local function note(text, y, alpha, x, w)
  love.graphics.setFont(app.fonts.small)
  love.graphics.setColor(1, 1, 1, alpha or 0.5)
  love.graphics.printf(text, x or 0, y, w or app.W, "center")
end

function Lan:drawWeb(busy)
  local x, y, w = 260, 250, 760
  ui.panel(x, y, w, 270)
  if self.webAvailable then
    love.graphics.setFont(app.fonts.med)
    love.graphics.setColor(1, 1, 1, 0.6)
    love.graphics.printf("This page comes from the game hosted at", x, y + 30, w, "center")
    love.graphics.setFont(app.fonts.big)
    love.graphics.setColor(1, 0.85, 0.4)
    love.graphics.printf(self.webHost or "?", x, y + 60, w, "center")
    if ui.button("Join Game", x + 170, y + 130, w - 340, 58, { disabled = busy, color = { 0.4, 1, 0.5 } }) then
      self:join()
    end
    note("The host has to be in its lobby (not in a match) for you to join.", y + 210, 0.45, x, w)
  else
    love.graphics.setFont(app.fonts.title)
    love.graphics.setColor(1, 0.6, 0.45)
    love.graphics.printf("Open the game from the host's address", x, y + 26, w, "center")
    love.graphics.setFont(app.fonts.med)
    love.graphics.setColor(1, 1, 1, 0.75)
    love.graphics.printf("To play LAN in a browser, someone on your network hosts a LAN game in the desktop " ..
      "version. Its lobby shows a browser address like http://192.168.1.20:27960. Open that address in this " ..
      "browser and choose Online Play > LAN > Join Game.", x + 30, y + 76, w - 60, "center")
    note("This page can't connect to computers on your network: browsers block that for pages from the internet.",
      y + 210, 0.45, x, w)
  end
end

function Lan:drawDesktop(busy)
  -- Host
  local lx, ly, lw, lh = 60, 240, 560, 300
  ui.panel(lx, ly, lw, lh)
  love.graphics.setFont(app.fonts.title)
  love.graphics.setColor(1, 1, 1)
  love.graphics.print("Host", lx + 24, ly + 18)
  if ui.button("Host LAN Game", lx + 60, ly + 80, lw - 120, 62, { disabled = busy, color = { 0.4, 1, 0.5 } }) then
    self:host()
  end
  note("Players on this network can then pick your game from their LAN list, or type the address your " ..
    "lobby shows. Browsers on the network can join too, by opening the browser address shown in the lobby.",
    ly + 166, 0.55, lx + 30, lw - 60)
  note("Windows may ask whether to let the game through the firewall: allow it on private networks.",
    ly + 246, 0.4, lx + 30, lw - 60)

  -- Join
  local rx, ry, rw, rh = 660, 240, 560, 300
  ui.panel(rx, ry, rw, rh)
  love.graphics.setFont(app.fonts.title)
  love.graphics.setColor(1, 1, 1)
  love.graphics.print("Games on this network", rx + 24, ry + 18)
  if #self.games == 0 then
    love.graphics.setFont(app.fonts.med)
    love.graphics.setColor(1, 1, 1, 0.35 + 0.15 * math.sin(love.timer.getTime() * 3))
    love.graphics.print("Searching...", rx + 24, ry + 66)
  end
  for i = 1, math.min(#self.games, 3) do
    local g = self.games[i]
    local gy = ry + 60 + (i - 1) * 52
    love.graphics.setColor(0.17, 0.17, 0.22)
    love.graphics.rectangle("fill", rx + 20, gy, rw - 40, 44, 8, 8)
    love.graphics.setFont(app.fonts.med)
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.print(g.name .. "'s game", rx + 34, gy + 4)
    love.graphics.setFont(app.fonts.tiny)
    love.graphics.setColor(1, 1, 1, 0.45)
    local info = g.address .. "   " .. g.players .. "/" .. g.max .. " players"
    if not g.compatible then info = info .. "   different version"
    elseif not g.joinable then info = info .. "   match running" end
    love.graphics.print(info, rx + 34, gy + 26)
    local can = g.compatible and g.joinable and g.players < g.max
    if ui.button("Join", rx + rw - 130, gy + 6, 96, 32, { font = app.fonts.small, disabled = busy or not can }) then
      self:join(g.address)
    end
  end

  love.graphics.setFont(app.fonts.small)
  love.graphics.setColor(1, 1, 1, 0.5)
  love.graphics.print("or enter the host's address", rx + 24, ry + 220)
  local submitted
  self.address, submitted = ui.textField(self.address, rx + 20, ry + 242, rw - 170, 44, {
    placeholder = "192.168.1.20", maxLength = 64, filter = addressFilter, font = app.fonts.med,
  })
  local ok = #self.address > 0 and not busy
  if ui.button("Join", rx + rw - 140, ry + 242, 120, 44, { disabled = not ok }) or (submitted and ok) then
    self:join(self.address)
  end
end

function Lan:draw()
  app.centered("LAN", app.fonts.huge, 30)

  local busy = lan.busy
  love.graphics.setFont(app.fonts.small)
  love.graphics.setColor(1, 1, 1, 0.5)
  love.graphics.printf("Your name", 0, 142, app.W, "center")
  self.name = ui.textField(self.name, (app.W - 360) / 2, 164, 360, 50, { placeholder = "Player", maxLength = 24 })

  if not lan.available then
    app.centered("LAN play isn't available (no network library)", app.fonts.title, 300, { 1, 0.6, 0.45 })
  elseif platform.web then
    self:drawWeb(busy)
  else
    self:drawDesktop(busy)
  end

  if lan.status then
    app.centered(lan.status, app.fonts.med, 556, { 1, 1, 1, 0.8 })
  elseif lan.error then
    app.centered(lan.error, app.fonts.med, 556, { 1, 0.6, 0.45 })
  end

  if ui.button(busy and "Cancel" or "Back", (app.W - 420) / 2, 600, 420, 50) then back() end
  note("LAN games use the Online controls (mouse aim). Change them in Settings > Controls.", 670, 0.4)
end

return Lan
