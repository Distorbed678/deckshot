-- Editor hub (Main menu > Editor): browse maps and cards to edit, create new ones, import codes.
local app = require "core.app"
local ui = require "core.ui"
local Map = require "game.map"

local Hub = {}
Hub.__index = Hub

local COLS, ROWS = 5, 3
local TW, TH = 216, 122
local GAP_X, GAP_Y = 18, 46
local GRID_X, GRID_Y = 40, 112

-- tab: "maps" or "cards"
function Hub.new(tab)
  return setmetatable({ tab = tab or "maps", page = 1, sel = nil, msg = nil, msgT = 0 }, Hub)
end

function Hub:enter()
  love.mouse.setVisible(true)
  Map.loadAll()
end

function Hub:say(text, bad)
  self.msg, self.msgT, self.msgBad = text, 4, bad
end

function Hub:update(dt)
  self.msgT = math.max(0, self.msgT - dt)
end

function Hub:keypressed(key)
  if key == "escape" then require("screens.settings").reopen() end
end

function Hub:wheelmoved(_, dy)
  self.page = self.page - (dy > 0 and 1 or -1)
end

local function pages(n)
  return math.max(1, math.ceil(n / (COLS * ROWS)))
end

-- A small picture of a map (blocks and objects).
function Hub.drawThumb(map, x, y, w, h)
  love.graphics.setColor(0.07, 0.07, 0.1)
  love.graphics.rectangle("fill", x, y, w, h, 6, 6)
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.scale(w / Map.W, h / Map.H)
  Map.draw(map, true)
  local ok, list = pcall(require("game.objects").build, map)
  if ok then pcall(require("game.objects").draw, list, {}) end
  love.graphics.pop()
end

function Hub:drawMaps()
  local list = Map.list
  local n = #list
  self.page = math.max(1, math.min(pages(n), self.page))
  local first = (self.page - 1) * COLS * ROWS + 1
  for k = 0, COLS * ROWS - 1 do
    local i = first + k
    local m = list[i]
    if not m then break end
    local col, row = k % COLS, math.floor(k / COLS)
    local x = GRID_X + col * (TW + GAP_X)
    local y = GRID_Y + row * (TH + GAP_Y)
    local selected = self.sel == m
    if ui.button("", x - 4, y - 4, TW + 8, TH + 34, { color = selected and ui.ACCENT or nil }) then
      if selected then
        app.switch(require("screens.editor_map").new({ map = m }))
        return
      end
      self.sel = m
    end
    Hub.drawThumb(m, x, y, TW, TH)
    love.graphics.setFont(app.fonts.small)
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.printf(m.name, x, y + TH + 6, TW - 50, "left")
    local tag, tc = "BUILT-IN", { 1, 1, 1, 0.35 }
    if m.custom then tag, tc = "CUSTOM", { 0.5, 0.85, 1 } elseif m.edited then tag, tc = "EDITED", { 1, 0.75, 0.3 } end
    love.graphics.setFont(app.fonts.tiny)
    love.graphics.setColor(tc)
    love.graphics.printf(tag, x, y + TH + 8, TW, "right")
  end

  -- Paging
  local np = pages(n)
  love.graphics.setFont(app.fonts.med)
  love.graphics.setColor(1, 1, 1, 0.6)
  love.graphics.printf("Page " .. self.page .. " / " .. np .. "   (" .. n .. " maps)", 0, 616, app.W, "center")
  if ui.button("<", app.W / 2 - 200, 610, 50, 32, { disabled = self.page <= 1 }) then self.page = self.page - 1 end
  if ui.button(">", app.W / 2 + 150, 610, 50, 32, { disabled = self.page >= np }) then self.page = self.page + 1 end

  -- Actions
  local s = self.sel
  local acts = {
    { "New Map", true, function() app.switch(require("screens.editor_map").new()) end },
    { "Edit", s ~= nil, function() app.switch(require("screens.editor_map").new({ map = s })) end },
    { "Duplicate", s ~= nil, function()
      local copy = Map.parse(Map.serialize(s))
      copy.name = (s.name .. " Copy"):sub(1, 30)
      copy.custom = true
      Map.saveCustom(copy)
      Map.loadAll()
      self:say("Made a copy of " .. s.name)
      self.sel = nil
    end },
    { "Share Code", s ~= nil, function()
      local ok = pcall(love.system.setClipboardText, Map.encodeShare(s))
      self:say(ok and "Map code copied" or "Couldn't use the clipboard", not ok)
    end },
    { "Import Code", true, function()
      local ok, text = pcall(love.system.getClipboardText)
      local m, err = Map.decodeShare(ok and text or "")
      if not m then return self:say((err or "No map code") .. " - copy a map code first", true) end
      m.custom = true
      Map.saveCustom(m)
      Map.loadAll()
      self:say("Imported " .. m.name)
    end },
    { s and s.edited and "Reset to Default" or "Delete", s ~= nil and (s.custom or s.edited), function()
      if s.custom then
        Map.deleteCustom(s)
        self:say("Deleted " .. s.name)
      else
        Map.resetOverride(s.id)
        self:say(s.name .. " is back to the original")
      end
      Map.loadAll()
      self.sel = nil
    end },
  }
  local bw = (app.W - 80 - (#acts - 1) * 10) / #acts
  for i, a in ipairs(acts) do
    if ui.button(a[1], 40 + (i - 1) * (bw + 10), 656, bw, 44, { font = app.fonts.med, disabled = not a[2] }) then a[3]() end
  end
end

function Hub:draw()
  local t = love.timer.getTime()
  love.graphics.setColor(0.09, 0.09, 0.12)
  love.graphics.rectangle("fill", 0, 0, app.W, app.H)
  love.graphics.setFont(app.fonts.big)
  love.graphics.setColor(1, 1, 1)
  love.graphics.print("EDITOR", 40, 22)

  local tabs = { { "maps", "Maps" }, { "cards", "Cards" } }
  for i, tb in ipairs(tabs) do
    local on = self.tab == tb[1]
    if ui.button(tb[2], 220 + (i - 1) * 170, 24, 160, 40, { color = on and ui.ACCENT or nil }) and not on then
      self.tab = tb[1]
      self.sel = nil
      ui.reset()
    end
  end
  if ui.button("Back", app.W - 180, 24, 140, 40, { back = true }) then require("screens.settings").reopen() end

  love.graphics.setFont(app.fonts.small)
  love.graphics.setColor(1, 1, 1, 0.45)
  if self.tab == "maps" then
    love.graphics.print("Click a map to select it, click again to edit. Built-in maps you edit keep the original "
      .. "so you can reset them.", 40, 80)
    self:drawMaps()
  else
    require("screens.editor_cards").drawHub(self)
  end

  if self.msg and self.msgT > 0 then
    app.centered(self.msg, app.fonts.med, 576, self.msgBad and { 1, 0.55, 0.45, math.min(1, self.msgT) }
      or { 0.6, 1, 0.6, math.min(1, self.msgT) })
  end
end

return Hub
