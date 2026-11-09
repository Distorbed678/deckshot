-- The Community browser: maps and custom cards other players have added on GitHub, plus sending
-- in your own.
local app = require "core.app"
local ui = require "core.ui"
local Map = require "game.map"
local Cards = require "game.cards"
local CardData = require "game.carddata"
local hud = require "gfx.hud"
local Community = require "core.community"

local Screen = {}
Screen.__index = Screen
Screen.noPadHints = true

local COLS, ROWS = 4, 2
local TW, TH = 260, 146

function Screen.new(tab)
  local s = setmetatable({ tab = tab or "maps", page = 1, msg = nil, msgT = 0, parsed = {} }, Screen)
  Community.refresh()
  return s
end

function Screen:say(text, bad) self.msg, self.msgT, self.msgBad = text, 5, bad end

function Screen:back() app.switch(require("screens.editor_hub").new(self.tab == "cards" and "cards" or "maps")) end

function Screen:keypressed(key) if key == "escape" then self:back() end end

function Screen:update(dt)
  self.msgT = math.max(0, self.msgT - dt)
  Community.update()
end

-- The parsed map or card for a community file, once it has downloaded.
function Screen:item(kind, file)
  local key = kind .. "/" .. file
  local got = self.parsed[key]
  if got ~= nil then return got end
  local text = Community.text(kind, file)
  if text == nil then Community.fetch(kind, file) return nil end
  if text == false then return nil end
  local value
  if text ~= "failed" then
    if kind == "maps" then
      local m = Map.parse(text)
      if m then m.custom = true end
      value = m
    else
      local ok, def = pcall(CardData.parse, text)
      if ok and def then
        local built, card = pcall(CardData.build, def)
        value = built and { def = def, card = card } or nil
      end
    end
  end
  self.parsed[key] = value or false
  return self.parsed[key]
end

local function installed(kind, item)
  if kind == "maps" then
    for _, m in ipairs(Map.list) do
      if m.name == item.name then return true end
    end
    return false
  end
  for _, c in ipairs(Cards.list or {}) do
    if c.name == item.def.name then return true end
  end
  return false
end

function Screen:install(kind, item)
  if kind == "maps" then
    Map.saveCustom(item)
    Map.loadAll()
    self:say("Added " .. item.name .. " to your maps")
  else
    Cards.saveCustom({ def = item.def })
    Cards.loadAll()
    self:say("Added " .. item.def.name .. " to your cards")
  end
end

function Screen:drawBrowse(kind)
  local files = Community.entries[kind]
  local first = (self.page - 1) * COLS * ROWS
  local x0 = (app.W - (COLS * TW + (COLS - 1) * 20)) / 2
  if Community.state == "loading" then app.centered("Loading from GitHub...", app.fonts.med, 320, { 1, 1, 1, 0.7 }) end
  if Community.state == "failed" then app.centered(Community.error, app.fonts.med, 320, { 1, 0.55, 0.45 }) end
  if Community.state == "ready" and #files == 0 then
    app.centered("Nothing here yet. Be the first: use Submit Yours.", app.fonts.med, 320, { 1, 1, 1, 0.7 })
  end
  for k = 1, COLS * ROWS do
    local file = files[first + k]
    if not file then break end
    local col, row = (k - 1) % COLS, math.floor((k - 1) / COLS)
    local x, y = x0 + col * (TW + 20), 140 + row * (TH + 96)
    local item = self:item(kind, file)
    ui.panel(x - 6, y - 6, TW + 12, TH + 84, 0.5)
    if item == nil then
      app.centered("", app.fonts.small, y)
      love.graphics.setFont(app.fonts.small)
      love.graphics.setColor(1, 1, 1, 0.5)
      love.graphics.printf("Loading...", x, y + TH / 2 - 10, TW, "center")
    elseif item == false then
      love.graphics.setFont(app.fonts.small)
      love.graphics.setColor(1, 0.55, 0.45)
      love.graphics.printf("Couldn't load " .. file, x, y + TH / 2 - 10, TW, "center")
    else
      if kind == "maps" then
        require("screens.editor_hub").drawThumb(item, x, y, TW, TH)
        love.graphics.setFont(app.fonts.small)
        love.graphics.setColor(1, 1, 1, 0.9)
        ui.printFit(item.name, app.fonts.small, x, y + TH + 6, TW, "center")
      else
        hud.drawCard(item.card, x + TW / 2 - 50, y, 100, 150, false, { 1, 1, 1 })
        ui.printFit(item.def.name, app.fonts.small, x, y + TH + 6, TW, "center")
      end
      local have = installed(kind, item)
      if ui.button(have and "Added" or "Add", x + 40, y + TH + 34, TW - 80, 36, { font = app.fonts.med, disabled = have, color = (not have) and ui.GOOD or nil }) then
        self:install(kind, item)
      end
    end
  end
  local pages = math.max(1, math.ceil(#files / (COLS * ROWS)))
  self.page = math.max(1, math.min(pages, self.page))
  love.graphics.setFont(app.fonts.med)
  love.graphics.setColor(1, 1, 1, 0.6)
  love.graphics.printf("Page " .. self.page .. " / " .. pages, 0, 632, app.W, "center")
  if ui.button("<", app.W / 2 - 200, 626, 50, 32, { disabled = self.page <= 1 }) then self.page = self.page - 1 end
  if ui.button(">", app.W / 2 + 150, 626, 50, 32, { disabled = self.page >= pages }) then self.page = self.page + 1 end
end

function Screen:submit(kind, name, text, id)
  local how = Community.submit(kind, id .. ".txt", text)
  if how == "link" then
    self:say("GitHub opened with your file filled in. Choose Propose new file to send the pull request.")
  else
    self:say("It's too long for a link, so it's on your clipboard. Paste it into the page GitHub opened.")
  end
end

function Screen:drawSubmit()
  love.graphics.setFont(app.fonts.med)
  love.graphics.setColor(1, 1, 1, 0.7)
  love.graphics.printf("Pick something you made. GitHub opens with it filled in, and you send it as a pull request (a free GitHub account is needed).", 160, 124, app.W - 320, "center")
  local mine = {}
  for _, m in ipairs(Map.list) do
    if m.custom then mine[#mine + 1] = { label = "Map: " .. m.name, kind = "maps", id = Map.idOf(m.name), text = function() return Map.serialize(m) end } end
  end
  for _, c in ipairs(Cards.list or {}) do
    if c.custom then mine[#mine + 1] = { label = "Card: " .. c.name, kind = "cards", id = CardData.idOf(c.def.name), text = function() return CardData.serialize(c.def) end } end
  end
  if #mine == 0 then app.centered("You haven't made any custom maps or cards yet.", app.fonts.med, 320, { 1, 1, 1, 0.6 }) end
  local y = 190
  for i = 1, math.min(#mine, 8) do
    local e = mine[i]
    if ui.button(e.label, app.W / 2 - 280, y, 560, 44, { font = app.fonts.med }) then self:submit(e.kind, e.label, e.text(), e.id) end
    y = y + 52
  end
end

function Screen:draw()
  love.graphics.setColor(0.09, 0.09, 0.12)
  love.graphics.rectangle("fill", 0, 0, app.W, app.H)
  app.centered("COMMUNITY", app.fonts.title, 30)
  local tabs = { { "maps", "Maps" }, { "cards", "Custom Cards" }, { "submit", "Submit Yours" } }
  for i, t in ipairs(tabs) do
    if ui.button(t[2], app.W / 2 - 300 + (i - 1) * 205, 84, 190, 34, { font = app.fonts.med, color = self.tab == t[1] and ui.ACCENT or nil }) then
      self.tab, self.page = t[1], 1
    end
  end
  if self.tab == "submit" then self:drawSubmit() else self:drawBrowse(self.tab) end
  if self.msg and self.msgT > 0 then
    app.centered(self.msg, app.fonts.small, 668, self.msgBad and { 1, 0.55, 0.45 } or { 0.5, 1, 0.6 })
  end
  if ui.button("Back", 16, 676, 140, 36, { back = true, font = app.fonts.med }) then self:back() end
  if ui.button("Refresh", app.W - 156, 676, 140, 36, { font = app.fonts.med }) then
    self.parsed = {}
    Community.contents = {}
    Community.refresh()
  end
end

return Screen
