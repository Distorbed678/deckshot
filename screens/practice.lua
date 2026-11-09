-- Practice range: you against a dummy that can't die, with any cards you like (C / the Cards button).
-- Practice.new shows the control picker first (also used to start the tutorial); touch devices skip it.
local app = require "core.app"
local ui = require "core.ui"
local Settings = require "core.settings"

local Practice = {}

local function start(kind, opts)
  local Map = require "game.map"
  local map = Map.byId.open_field or Map.list[1]
  return require("screens.match").newLocal(99, {
    setup = { { kind = kind, color = 1, team = 1 }, { kind = "dummy", color = 2, team = 2 } },
    map = map, practice = true, tutorial = opts.tutorial, tutorialReturn = opts.tutorialReturn,
    returnTo = nil,
  })
end

local Picker = {}
Picker.__index = Picker

local function choices()
  local Input = require "core.input"
  local list = {
    { kind = "p1", label = "Keyboard", text = "Your Player 1 keys" },
    { kind = "mouse", label = "Mouse and keyboard", text = "Your online controls: aim with the mouse" },
  }
  if Input.pads()[1] then list[#list + 1] = { kind = "pad1", label = "Gamepad", text = "The first connected gamepad" } end
  return list
end

function Picker:back()
  if self.opts.tutorialReturn then
    app.switch(self.opts.tutorialReturn())
  elseif self.opts.tutorial then
    app.switch(require("screens.menu").new())
  else
    app.switch(require("screens.localmenu").new())
  end
end

function Picker:keypressed(key)
  if key == "escape" then self:back() end
end

function Picker:go(kind)
  Settings.values.practiceControls = kind
  Settings.save()
  app.switch(start(kind, self.opts))
end

function Picker:draw()
  love.graphics.setColor(0.09, 0.09, 0.12)
  love.graphics.rectangle("fill", 0, 0, app.W, app.H)
  app.centered(self.opts.tutorial and "TUTORIAL" or "PRACTICE", app.fonts.huge, 60)
  app.centered("Which controls do you want to use?", app.fonts.title, 160, { 1, 1, 1, 0.8 })
  local list = choices()
  local w, h = 520, 66
  local x = (app.W - w) / 2
  local saved = Settings.values.practiceControls
  for i, c in ipairs(list) do
    local y = 230 + (i - 1) * 112
    local opts = { font = app.fonts.title, color = c.kind == saved and ui.ACCENT or nil }
    if ui.button(c.label, x, y, w, h, opts) then self:go(c.kind) end
    app.centered(c.text, app.fonts.small, y + h + 8, { 1, 1, 1, 0.55 })
  end
  if ui.button("Back", app.W / 2 - 150, 640, 300, 46, { back = true }) then self:back() end
end

-- opts.tutorial: the guided first-run steps on top of the range.
function Practice.new(opts)
  opts = opts or {}
  if require("core.touch").enabled then return start("touch", opts) end
  return setmetatable({ opts = opts }, Picker)
end

return Practice
