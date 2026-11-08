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
  require("core.version").checkForUpdate()
  require("online.presence").set("In the menus")
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

-- Bots fighting on a random map behind the menu.
function Menu:background(dt)
  local World = require "game.world"
  local Input = require "core.input"
  local sfx = require "gfx.sfx"
  local fx = require "gfx.fx"
  if not self.bg then
    local defs = {
      { name = "a", input = Input.bot(3), bot = 3 }, { name = "b", input = Input.bot(2), bot = 2 },
    }
    local Cards = require "game.cards"
    World.setSlotColors({ 1, 2, 3, 4 })
    self.bg = World.new(defs, 999, { pickFrom = 3, picksPerRound = 1, weights = Cards.DEFAULT_RULES.weights,
      rarity = {}, disabled = {}, startCards = 0, barrier = false })
    self.bg:startRound()
  end
  local w = self.bg
  local was = sfx.silent
  sfx.silent = true
  w:update(math.min(dt, 1 / 30))
  sfx.silent = was
  if w.state == "matchOver" or (w.state == "cardPick" and not w.pick) then w:startRound() end
  fx.update(dt)
end

function Menu:keypressed(key)
  if key == "escape" and self.notes then self.notes = false end
end

function Menu:update(dt)
  require("core.version").update()
  self:background(dt)
end

function Menu:drawBackground()
  local w = self.bg
  if not w or not w.map then return end
  local Map = require "game.map"
  local Objects = require "game.objects"
  local fx = require "gfx.fx"
  Map.draw(w.map)
  Objects.draw(w.objects, w.effects)
  for _, b in ipairs(w.bullets) do b:draw() end
  for _, p in ipairs(w.players) do p:draw() end
  fx.draw()
  love.graphics.setColor(0.07, 0.07, 0.1, 0.78)
  love.graphics.rectangle("fill", 0, 0, app.W, app.H)
end

function Menu:draw()
  self:drawBackground()
  local Version = require "core.version"
  app.centered("DECKSHOT", app.fonts.huge, 60)
  app.centered("Lose a round, pick a card. Up to 4 players, bots, online and LAN.", app.fonts.med, 172, { 1, 1, 1, 0.55 })

  local w, h = 360, 54
  local x = (app.W - w) / 2
  local y = 230
  if self.message then app.centered(self.message, app.fonts.med, 204, { 1, 0.6, 0.45 }) end
  if ui.button("Local Play", x, y, w, h) then app.switch(require("screens.localsetup").new()) end
  y = y + 64
  if ui.button("Online Play", x, y, w, h) then app.switch(require("screens.online").new()) end
  y = y + 64
  if ui.button("Practice", x, y, w, h) then app.switch(require("screens.practice").new()) end
  y = y + 64
  local half = w / 2 - 5
  if ui.button("Editor", x, y, half, h) then app.switch(require("screens.editor_hub").new()) end
  if ui.button("Codex", x + half + 10, y, half, h) then app.switch(require("screens.codex").new()) end
  y = y + 64
  if ui.button("How to Play", x, y, half, h) then app.switch(require("screens.howtoplay").new()) end
  if ui.button("Settings", x + half + 10, y, half, h) then app.push(require("screens.settings").new()) end
  y = y + 64
  if ui.button("Credits", x, y, platform.web and w or half, h) then app.switch(require("screens.credits").new()) end
  if not platform.web and ui.button("Quit", x + half + 10, y, half, h) then love.event.quit() end

  -- Version, what's new, update notice
  love.graphics.setFont(app.fonts.small)
  love.graphics.setColor(1, 1, 1, 0.4)
  love.graphics.printf("v" .. Version.VERSION, 0, app.H - 30, app.W - 20, "right")
  if ui.button("What's new", app.W - 170, app.H - 66, 150, 30, { font = app.fonts.small }) then self.notes = not self.notes end
  if Version.latest then
    love.graphics.setColor(0.5, 1, 0.6)
    love.graphics.printf("Version " .. Version.latest .. " is out: github.com/" .. Version.REPO .. "/releases", 20,
      app.H - 30, app.W, "left")
  end
  if self.notes then
    ui.panel(160, 120, 960, 480)
    love.graphics.setFont(app.fonts.title)
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf("What's new in v" .. Version.VERSION, 160, 140, 960, "center")
    love.graphics.setFont(app.fonts.med)
    local yy = 196
    for _, line in ipairs(Version.NOTES) do
      love.graphics.setColor(1, 0.8, 0.35)
      love.graphics.print("-", 200, yy)
      love.graphics.setColor(1, 1, 1, 0.85)
      love.graphics.printf(line, 222, yy, 860, "left")
      local _, wr = app.fonts.med:getWrap(line, 860)
      yy = yy + #wr * app.fonts.med:getHeight() + 8
    end
    if ui.button("Close", app.W / 2 - 100, 548, 200, 40, { back = true }) then self.notes = false end
  end
end

return Menu
