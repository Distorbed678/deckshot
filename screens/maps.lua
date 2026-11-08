-- Map pool editor (pushed from Settings > Gameplay): every arena as a thumbnail; click one
-- to turn it on or off. Edits Settings.values.maps; online, the host's pool is used.
local app = require "core.app"
local ui = require "core.ui"
local Settings = require "core.settings"
local Map = require "game.map"

local Screen = {}
Screen.__index = Screen

local COLS, ROWS = 7, 4
local PER_PAGE = COLS * ROWS
local THUMB_W, THUMB_H = 160, 90
local GAP_X, LABEL_H, GAP_Y = 12, 22, 12
local GRID_Y = 106

-- rules: a client's view of the host's rules (read-only); nil = this machine's settings.
function Screen.new(rules)
  return setmetatable({ page = 1, rules = rules, readOnly = rules ~= nil }, Screen)
end

function Screen:isOn(map)
  if self.readOnly then return not (self.rules.maps and self.rules.maps[map.index]) end
  return Settings.mapEnabled(map)
end

function Screen:wheelmoved(_, dy)
  self.page = self.page - (dy > 0 and 1 or -1)
end

function Screen:keypressed(key)
  if key == "escape" then app.pop() end
end

local function drawThumb(map, x, y, on)
  require("screens.editor_hub").drawThumb(map, x, y, THUMB_W, THUMB_H)
  if not on then
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", x, y, THUMB_W, THUMB_H, 6, 6)
    love.graphics.setFont(app.fonts.title)
    love.graphics.setColor(1, 0.45, 0.45)
    love.graphics.printf("OFF", x, y + THUMB_H / 2 - 15, THUMB_W, "center")
  end
end

function Screen:draw()
  love.graphics.setColor(0, 0, 0, 0.7)
  love.graphics.rectangle("fill", 0, 0, app.W, app.H)
  ui.panel(20, 10, app.W - 40, app.H - 20)

  love.graphics.setFont(app.fonts.big)
  love.graphics.setColor(1, 1, 1)
  love.graphics.print("MAP POOL", 44, 26)
  local enabled = 0
  for _, m in ipairs(Map.list) do if self:isOn(m) then enabled = enabled + 1 end end
  love.graphics.setFont(app.fonts.med)
  love.graphics.setColor(1, 1, 1, 0.6)
  love.graphics.printf(enabled .. " / " .. #Map.list .. " maps enabled", 0, 40, app.W - 44, "right")
  love.graphics.setFont(app.fonts.small)
  love.graphics.setColor(1, 1, 1, 0.45)
  love.graphics.print(self.readOnly and "Host's settings (read-only)" or "Click a map to turn it on or off.", 44, 76)

  local gridW = COLS * THUMB_W + (COLS - 1) * GAP_X
  local x0 = (app.W - gridW) / 2
  local pages = math.max(1, math.ceil(#Map.list / PER_PAGE))
  self.page = math.max(1, math.min(pages, self.page))
  for k = 1, PER_PAGE do
    local i = (self.page - 1) * PER_PAGE + k
    local map = Map.list[i]
    if not map then break end
    local col, row = (k - 1) % COLS, math.floor((k - 1) / COLS)
    local x = x0 + col * (THUMB_W + GAP_X)
    local y = GRID_Y + row * (THUMB_H + LABEL_H + GAP_Y)
    local on = self:isOn(map)
    if ui.button("", x - 4, y - 4, THUMB_W + 8, THUMB_H + LABEL_H + 6, { disabled = self.readOnly }) then
      Settings.setMap(map, not on)
    end
    drawThumb(map, x, y, on)
    love.graphics.setFont(app.fonts.small)
    love.graphics.setColor(1, 1, 1, on and 0.9 or 0.35)
    ui.printFit(map.name, app.fonts.small, x, y + THUMB_H + 3, THUMB_W, "center")
  end

  if pages > 1 then
    love.graphics.setFont(app.fonts.med)
    love.graphics.setColor(1, 1, 1, 0.6)
    love.graphics.printf("Page " .. self.page .. " / " .. pages, 0, 614, app.W, "center")
    if ui.button("<", app.W / 2 - 150, 606, 50, 36, { disabled = self.page <= 1, viewOnly = true }) then self.page = self.page - 1 end
    if ui.button(">", app.W / 2 + 100, 606, 50, 36, { disabled = self.page >= pages }) then self.page = self.page + 1 end
  end

  if enabled == 0 then
    love.graphics.setFont(app.fonts.med)
    love.graphics.setColor(1, 0.6, 0.45)
    love.graphics.printf("No maps are enabled, so every map will be used.", 0, 66, app.W, "center")
  end

  local bw, by = 220, 654
  if ui.button("Enable All", app.W / 2 - bw - 10, by, bw, 46, { disabled = self.readOnly }) then Settings.values.maps = {} end
  if ui.button("Back", app.W / 2 + 10, by, bw, 46) then app.pop() end
end

return Screen
