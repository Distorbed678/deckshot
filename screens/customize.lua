-- Customize (main menu): hat, eyes, mouth and detail, plus the achievements that unlock them.
-- Others see your look in online and LAN games.
local app = require "core.app"
local ui = require "core.ui"
local Settings = require "core.settings"
local Cosmetics = require "core.cosmetics"
local Achievements = require "core.achievements"
local Body = require "game.body"
local World = require "game.world"

local Screen = {}
Screen.__index = Screen

local TABS = { "Hats", "Eyes", "Mouths", "Details", "Achievements" }

function Screen.new()
  local s = setmetatable({ tab = 1, scroll = { y = 0 } }, Screen)
  s.fig = { x = 240, y = 300, r = 80, slot = 1, facing = 1, aimX = 1, aimY = 0 }
  return s
end

local function toMenu() app.switch(require("screens.menu").new()) end

function Screen:keypressed(key)
  if key == "escape" then toMenu() end
end

function Screen:wheelmoved(_, dy) ui.wheel(self.scroll, dy) end

function Screen:drawSlot(slot, x, y, w, h)
  local cols, bw, bh, gap = 5, 138, 56, 10
  local rows = math.ceil(#slot.list / cols)
  local cy = ui.beginScroll(self.scroll, x, y, w, h, rows * (bh + gap))
  local mx, my = app.mouse()
  local current = slot.index[Settings.values[slot.key]] or 1
  for i, item in ipairs(slot.list) do
    local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
    local bx, by = x + col * (bw + gap), cy + row * (bh + gap)
    local open = Cosmetics.unlocked(item)
    if ui.button(open and item.name or "Locked", bx, by, bw, bh,
      { font = app.fonts.small, color = current == i and ui.ACCENT or nil, disabled = not open }) then
      Settings.values[slot.key] = item.id
      Settings.save()
    end
    if not open and mx >= bx and mx <= bx + bw and my >= math.max(by, y) and my <= by + bh then
      self.tip = Cosmetics.unlockText(item)
    end
  end
  ui.endScroll(self.scroll)
end

function Screen:drawAchievements(x, y, w, h)
  local rowH = 62
  local total = Achievements.count()
  local cy = ui.beginScroll(self.scroll, x, y, w, h, total * rowH)
  for i = 1, total do
    local a = Achievements[i]
    local ry = cy + (i - 1) * rowH
    if ry + rowH > y and ry < y + h then
      local done = Achievements.earned(a.id)
      love.graphics.setColor(ui.WIDGET)
      love.graphics.rectangle("fill", x, ry, w - 8, rowH - 8, 8, 8)
      love.graphics.setColor(done and ui.GOLD or { 1, 1, 1, 0.75 })
      ui.printFit(a.name, app.fonts.med, x + 14, ry + 5, 280, "left")
      love.graphics.setColor(1, 1, 1, 0.6)
      ui.printFit(a.desc, app.fonts.small, x + 14, ry + 30, 330, "left")
      love.graphics.setColor(done and ui.GOOD or { 1, 1, 1, 0.5 })
      ui.printFit(done and "Earned" or (Achievements.progress(a) .. " / " .. a.n), app.fonts.small, x + w - 300, ry + 6, 280, "right")
      if a.reward then
        love.graphics.setColor(1, 1, 1, 0.5)
        ui.printFit("Unlocks " .. a.reward, app.fonts.small, x + w - 300, ry + 30, 280, "right")
      end
    end
  end
  ui.endScroll(self.scroll)
end

function Screen:draw()
  love.graphics.setColor(0.09, 0.09, 0.12)
  love.graphics.rectangle("fill", 0, 0, app.W, app.H)
  app.centered("CUSTOMIZE", app.fonts.big, 18)

  -- Live preview.
  local v = Settings.values
  ui.panel(40, 76, 400, 540)
  local mx, my = app.mouse()
  local f = self.fig
  local dx, dy = mx - f.x, my - f.y
  local d = math.max(1, math.sqrt(dx * dx + dy * dy))
  f.aimX, f.aimY, f.facing = dx / d, dy / d, dx >= 0 and 1 or -1
  f.color = World.PALETTE[v.playerColor or 1] or World.PALETTE[1]
  f.hat, f.eyes, f.mouth, f.detail = Cosmetics.mine()
  Body.drawFigure(f, love.timer.getDelta())
  love.graphics.setColor(1, 1, 1, 0.75)
  local names = {}
  for i, slot in ipairs(Cosmetics.SLOTS) do
    local idx = ({ f.hat, f.eyes, f.mouth, f.detail })[i]
    names[#names + 1] = slot.list[idx].name
  end
  love.graphics.setFont(app.fonts.med)
  love.graphics.printf(table.concat(names, "  -  "), 60, 520, 360, "center")

  self.tip = nil
  local x, w = 470, 760
  local tabW = (w - 4 * 10) / 5
  for i, name in ipairs(TABS) do
    if ui.button(name, x + (i - 1) * (tabW + 10), 76, tabW, 42, { font = app.fonts.med, color = i == self.tab and ui.ACCENT or nil })
      and self.tab ~= i then
      self.tab, self.scroll.y = i, 0
    end
  end
  local top, h = 132, 484
  if self.tab == 5 then
    self:drawAchievements(x, top, w - 14, h)
  else
    self:drawSlot(Cosmetics.SLOTS[self.tab], x, top, w - 14, h)
  end

  if self.tab < 5 then
    love.graphics.setColor(self.tip and ui.GOLD or { 1, 1, 1, 0.5 })
    ui.printFit(self.tip or "Hover over or tap a locked item to see how to earn it", app.fonts.med, x, 626, w, "center")
  end
  if ui.button("Back", app.W / 2 - 150, 660, 300, 46, { back = true }) then toMenu() end
  Achievements.draw()
end

return Screen
