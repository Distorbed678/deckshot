-- Synergy pool (Settings > Gameplay > Synergies): turn synergies on or off. Online, the host's are used.
local app = require "core.app"
local ui = require "core.ui"
local Settings = require "core.settings"
local Synergies = require "game.synergies"
local Cards = require "game.cards"

local Screen = {}
Screen.__index = Screen

local PER_PAGE = 21

function Screen.new()
  return setmetatable({ page = 1 }, Screen)
end

function Screen:keypressed(key)
  if key == "escape" then app.pop() end
end

function Screen:wheelmoved(_, dy)
  self.page = self.page - (dy > 0 and 1 or -1)
end

local function needsText(s)
  local names = {}
  for _, id in ipairs(s.needs) do names[#names + 1] = Cards.byId[id] and Cards.byId[id].name or id end
  return table.concat(names, " + ")
end

function Screen:draw()
  local v = Settings.values
  love.graphics.setColor(0, 0, 0, 0.7)
  love.graphics.rectangle("fill", 0, 0, app.W, app.H)
  ui.panel(20, 10, app.W - 40, app.H - 20)
  love.graphics.setFont(app.fonts.big)
  love.graphics.setColor(1, 1, 1)
  love.graphics.print("SYNERGIES", 44, 26)
  local on = 0
  for _, s in ipairs(Synergies.list) do if not v.synergies[s.id] then on = on + 1 end end
  love.graphics.setFont(app.fonts.med)
  love.graphics.setColor(1, 1, 1, 0.6)
  love.graphics.printf(on .. " / " .. #Synergies.list .. " on", 0, 40, app.W - 44, "right")
  if ui.button(v.synergiesOn and "Synergies: ON" or "Synergies: OFF", 300, 26, 220, 40,
    { color = v.synergiesOn and { 0.5, 1, 0.6 } or { 1, 0.5, 0.45 } }) then
    v.synergiesOn = not v.synergiesOn
  end

  local pages = math.max(1, math.ceil(#Synergies.list / PER_PAGE))
  self.page = math.max(1, math.min(pages, self.page))
  local cols, bw, bh = 3, 384, 66
  for k = 1, PER_PAGE do
    local s = Synergies.list[(self.page - 1) * PER_PAGE + k]
    if not s then break end
    local col, row = (k - 1) % cols, math.floor((k - 1) / cols)
    local x, y = 40 + col * (bw + 10), 84 + row * (bh + 6)
    local off = v.synergies[s.id] or not v.synergiesOn
    if ui.button("", x, y, bw, bh) then v.synergies[s.id] = not v.synergies[s.id] or nil end
    love.graphics.setFont(app.fonts.med)
    love.graphics.setColor(off and { 1, 1, 1, 0.35 } or { 1, 0.82, 0.35 })
    love.graphics.print(s.name, x + 12, y + 6)
    love.graphics.setFont(app.fonts.tiny)
    love.graphics.setColor(1, 1, 1, off and 0.3 or 0.6)
    love.graphics.print(needsText(s), x + 12, y + 28)
    love.graphics.setColor(0.5, 1, 0.5, off and 0.3 or 0.8)
    love.graphics.printf(table.concat(s.lines, ", "), x + 12, y + 44, bw - 24, "left")
    if v.synergies[s.id] then
      love.graphics.setFont(app.fonts.small)
      love.graphics.setColor(1, 0.45, 0.45)
      love.graphics.printf("OFF", x, y + 6, bw - 12, "right")
    end
  end
  love.graphics.setFont(app.fonts.med)
  love.graphics.setColor(1, 1, 1, 0.6)
  love.graphics.printf("Page " .. self.page .. " / " .. pages, 0, 604, app.W, "center")
  if ui.button("<", app.W / 2 - 150, 596, 50, 36, { disabled = self.page <= 1 }) then self.page = self.page - 1 end
  if ui.button(">", app.W / 2 + 100, 596, 50, 36, { disabled = self.page >= pages }) then self.page = self.page + 1 end
  if ui.button("All On", app.W / 2 - 340, 646, 200, 46) then v.synergies = {} end
  if ui.button("All Off", app.W / 2 - 100, 646, 200, 46) then
    for _, s in ipairs(Synergies.list) do v.synergies[s.id] = true end
  end
  if ui.button("Back", app.W / 2 + 140, 646, 200, 46, { back = true }) then app.pop() end
end

return Screen
