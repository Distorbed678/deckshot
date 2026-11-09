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
  require("gfx.music").play("menu")
  require("online.chat").reset()
  -- Back from an online session: drop the host's map and card lists.
  local Map = require "game.map"
  if Map.session then
    Map.loadAll()
    require("game.cards").loadAll()
    require("game.cards").applyRules(Settings.cardRules())
  end
  require("online.active").get().hostRules = nil
  if Settings.values.checkUpdates then require("core.version").checkForUpdate() end
  require("online.presence").set("In the menus")
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
      rarity = {}, disabled = {}, startCards = 0 })
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

function Menu:update(dt)
  local Version = require "core.version"
  Version.update()
  self:background(dt)
  if app.top() ~= self then return end
  -- First launch: offer the tutorial. Later: offer a new version once per run.
  local v = Settings.values
  if not v.tutorialOffered then
    v.tutorialOffered = true
    Settings.save()
    require("screens.confirm").ask("New to Deckshot?", "A short tutorial covers the basics in about a minute.", function()
      app.switch(require("screens.practice").new({ tutorial = true }))
    end, { yes = "Start Tutorial", no = "Skip" })
  elseif Version.release and not Version.prompted then
    Version.prompted = true
    app.push(require("screens.update").new())
  end
end


function Menu:drawBackground()
  local w = self.bg
  if not w or not w.map then return end
  local Map = require "game.map"
  local Objects = require "game.objects"
  local fx = require "gfx.fx"
  love.graphics.push()
  love.graphics.scale(Map.VIEW)
  Map.draw(w.map)
  Objects.draw(w.objects, w.effects)
  for _, b in ipairs(w.bullets) do b:draw() end
  for _, p in ipairs(w.players) do p:draw() end
  fx.draw()
  love.graphics.pop()
  love.graphics.setColor(0.07, 0.07, 0.1, 0.72)
  love.graphics.rectangle("fill", 0, 0, app.W, app.H)
end

function Menu:draw()
  self:drawBackground()
  local Version = require "core.version"
  require("gfx.logo").draw(app.W / 2, 112, 1)

  local w, h = 360, 54
  local x = (app.W - w) / 2
  local y = 214
  if self.message then app.centered(self.message, app.fonts.med, 182, ui.BAD) end
  if ui.button("Local Play", x, y, w, h) then app.switch(require("screens.localmenu").new()) end
  y = y + 64
  if ui.button("Online Play", x, y, w, h) then app.switch(require("screens.online").new()) end
  y = y + 64
  if ui.button("Customize", x, y, w, h) then app.switch(require("screens.customize").new()) end
  y = y + 64
  if ui.button("How to Play", x, y, w, h) then app.switch(require("screens.howtoplay").new()) end
  y = y + 64
  if ui.button("Settings", x, y, w, h) then app.push(require("screens.settings").new()) end
  y = y + 64
  local half = w / 2 - 5
  if ui.button("Credits", x, y, platform.web and w or half, h) then app.switch(require("screens.credits").new()) end
  if not platform.web and ui.button("Quit", x + half + 10, y, half, h) then
    require("screens.confirm").ask("Quit Deckshot?", "See you next round.", function() love.event.quit() end, { yes = "Quit", danger = true })
  end

  require("core.achievements").draw()

  -- Version, what's new, update notice
  love.graphics.setFont(app.fonts.small)
  love.graphics.setColor(1, 1, 1, 0.4)
  love.graphics.printf("v" .. Version.VERSION, 0, app.H - 30, app.W - 20, "right")
  if ui.button("What's new", app.W - 170, app.H - 70, 150, 32, { font = app.fonts.small }) then
    app.push(require("screens.whatsnew").new())
  end
  if Version.latest then
    love.graphics.setColor(ui.GOOD)
    love.graphics.printf("Version " .. Version.latest .. " is out: github.com/" .. Version.REPO .. "/releases", 20,
      app.H - 30, 800, "left")
  end
end

return Menu
