-- Card Library (Settings > Gameplay): every card and synergy, your statistics for them, and the
-- pool options (rarity, on / off). Opened read-only by a client, it shows the host's content.
local app = require "core.app"
local ui = require "core.ui"
local Settings = require "core.settings"
local Cards = require "game.cards"
local Synergies = require "game.synergies"
local Profile = require "core.profile"
local hud = require "gfx.hud"

local Screen = {}
Screen.__index = Screen

local COLS, ROWS = 5, 11
local PER_PAGE = COLS * ROWS
local GRID_X, GRID_Y = 40, 122
local TILE_W, TILE_H, TILE_GAP = 148, 34, 6
local SYN_PER_PAGE = 21

local FILTERS = { { "All" } }
for _, r in ipairs(Cards.RARITIES) do FILTERS[#FILTERS + 1] = { r.name, rarity = r.id } end
FILTERS[#FILTERS + 1] = { "Disabled", disabled = true }

-- rules: a client's view of the host's rules (read-only); nil = this machine's settings.
function Screen.new(rules)
  return setmetatable({ tab = "cards", selected = Cards.list[1], filter = 1, page = 1, tiles = {}, search = "",
    rules = rules, readOnly = rules ~= nil }, Screen)
end

local function cycle(i, n, d) return (i - 1 + d) % n + 1 end

local function rarityIndex(id)
  for i, r in ipairs(Cards.RARITIES) do
    if r.id == id then return i end
  end
  return 1
end

function Screen:rarityOf(c) return self.readOnly and c.rarity or Settings.cardRarity(c) end
function Screen:enabled(c)
  if self.readOnly then return not c.disabled end
  return Settings.cardEnabled(c)
end

function Screen:visibleCards()
  local f = FILTERS[self.filter]
  local q = self.search:lower()
  local list = {}
  for _, c in ipairs(Cards.list) do
    local ok = q == "" or c.name:lower():find(q, 1, true)
    if f.rarity and self:rarityOf(c) ~= f.rarity then ok = false end
    if f.disabled and self:enabled(c) then ok = false end
    if ok then list[#list + 1] = c end
  end
  table.sort(list, function(a, b)
    local ra, rb = rarityIndex(self:rarityOf(a)), rarityIndex(self:rarityOf(b))
    if ra ~= rb then return ra < rb end
    return a.index < b.index
  end)
  return list
end

function Screen:synOff(s)
  if self.readOnly then return (self.rules.synergyOff and self.rules.synergyOff[s.index]) or self.rules.synergies == false end
  return Settings.values.synergies[s.id] or not Settings.values.synergiesOn
end

local function toggle(c) Settings.setCard(c, Settings.cardRarity(c), not Settings.cardEnabled(c)) end

function Screen:keypressed(key)
  if self.typing then
    if key == "escape" or key == "return" then self.typing = false end
    return
  end
  if key == "escape" then app.pop() end
end

function Screen:mousepressed(x, y, button)
  if button ~= 2 or self.readOnly or self.tab ~= "cards" then return end
  for _, t in ipairs(self.tiles) do
    if x >= t.x and x <= t.x + TILE_W and y >= t.y and y <= t.y + TILE_H then
      self.selected = t.card
      toggle(t.card)
      return
    end
  end
end

function Screen:wheelmoved(_, dy)
  self.page = self.page - (dy > 0 and 1 or -1)
end

local function warning(self)
  local enabled, total = {}, 0
  for _, c in ipairs(Cards.list) do
    if self:enabled(c) then
      local r = self:rarityOf(c)
      enabled[r] = (enabled[r] or 0) + 1
      total = total + 1
    end
  end
  if total == 0 then return "Every card is disabled: card picks will be skipped." end
  if self.readOnly then return nil end
  local empty = {}
  for _, r in ipairs(Cards.RARITIES) do
    if Settings.values["weight_" .. r.id] > 0 and not enabled[r.id] then empty[#empty + 1] = r.name end
  end
  if #empty > 0 then return "No enabled cards for: " .. table.concat(empty, ", ") .. " (those rolls are skipped)." end
end

function Screen:drawHeader()
  love.graphics.setColor(1, 1, 1)
  ui.printFit("CARD LIBRARY", app.fonts.big, GRID_X, 22, 288, "left")
  local tabs = { { "cards", "Cards (" .. #Cards.list .. ")" }, { "synergies", "Synergies (" .. #Synergies.list .. ")" } }
  for i, t in ipairs(tabs) do
    if ui.button(t[2], 340 + (i - 1) * 216, 24, 208, 40, { color = self.tab == t[1] and ui.ACCENT or nil, font = app.fonts.med, viewOnly = true })
      and self.tab ~= t[1] then
      self.tab, self.page = t[1], 1
    end
  end
end

function Screen:drawCards()
  local d
  if self.typing then
    ui.focus = ui.count + 1
    local text, done = ui.textField(self.search, GRID_X, 76, 260, 34, { font = app.fonts.med, placeholder = "Search", maxLength = 24 })
    if text ~= self.search then self.search, self.page = text, 1 end
    if done then self.typing = false end
  elseif ui.button(self.search ~= "" and ("Search: " .. self.search) or "Search...", GRID_X, 76, 260, 34, { font = app.fonts.med, viewOnly = true }) then
    self.typing = true
  end
  local wasRO = ui.readOnly
  ui.readOnly = false
  d = ui.cycler("Show", FILTERS[self.filter][1], 312, 76, 260, 34)
  if d ~= 0 then self.filter, self.page = cycle(self.filter, #FILTERS, d), 1 end
  local cards = self:visibleCards()
  local pages = math.max(1, math.ceil(#cards / PER_PAGE))
  self.page = math.max(1, math.min(pages, self.page))
  if pages > 1 then
    d = ui.cycler("Page", self.page .. " / " .. pages, 582, 76, 208, 34)
    if d ~= 0 then self.page = cycle(self.page, pages, d) end
  end
  ui.readOnly = wasRO

  self.tiles = {}
  local first = (self.page - 1) * PER_PAGE
  for i = 1, math.min(PER_PAGE, #cards - first) do
    local c = cards[first + i]
    local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
    local tx, ty = GRID_X + col * (TILE_W + TILE_GAP), GRID_Y + row * (TILE_H + TILE_GAP)
    self.tiles[#self.tiles + 1] = { x = tx, y = ty, card = c }
    local rc = Cards.rarity[self:rarityOf(c)].color
    local on = self:enabled(c)
    if ui.button("", tx, ty, TILE_W, TILE_H, { viewOnly = true }) then self.selected = c end
    love.graphics.setColor(rc[1], rc[2], rc[3], on and 1 or 0.3)
    love.graphics.rectangle("fill", tx + 5, ty + 6, 5, TILE_H - 12, 2, 2)
    love.graphics.setColor(1, 1, 1, on and 0.9 or 0.3)
    ui.printFit(c.name, app.fonts.small, tx + 16, ty + (TILE_H - app.fonts.small:getHeight()) / 2, TILE_W - (on and 22 or 46), "left")
    if not on then
      love.graphics.setFont(app.fonts.tiny)
      love.graphics.setColor(1, 0.45, 0.45, 0.9)
      love.graphics.printf("OFF", tx, ty + (TILE_H - app.fonts.tiny:getHeight()) / 2, TILE_W - 6, "right")
    end
    if c == self.selected then
      love.graphics.setColor(1, 1, 1)
      love.graphics.setLineWidth(2)
      love.graphics.rectangle("line", tx - 2, ty - 2, TILE_W + 4, TILE_H + 4, 10, 10)
    end
  end
  if #cards == 0 then
    love.graphics.setFont(app.fonts.med)
    love.graphics.setColor(1, 1, 1, 0.4)
    love.graphics.print("No cards match this filter.", GRID_X, GRID_Y + 10)
  end

  local c = self.selected
  if not c then return end
  local px, pw = 830, 410
  local rarity, on = self:rarityOf(c), self:enabled(c)
  local cw, ch = 250, 310
  hud.drawCard(c, px + (pw - cw) / 2, 24, cw, ch, false, { 1, 1, 1 }, rarity)
  if not on then
    love.graphics.setColor(0, 0, 0, 0.55)
    love.graphics.rectangle("fill", px + (pw - cw) / 2, 24, cw, ch, 14, 14)
    love.graphics.setFont(app.fonts.big)
    love.graphics.setColor(1, 0.45, 0.45)
    love.graphics.printf("DISABLED", px, 160, pw, "center")
  end

  local y = 346
  d = ui.cycler("Rarity", Cards.rarity[rarity].name, px, y, pw, 40)
  if d ~= 0 then Settings.setCard(c, Cards.RARITIES[cycle(rarityIndex(rarity), #Cards.RARITIES, d)].id, on) end
  y = y + 46
  d = ui.cycler("Enabled", on and "Yes" or "No", px, y, pw, 40)
  if d ~= 0 then toggle(c) end
  y = y + 46
  local isDefault = c.baseRarity == rarity and on
  if ui.button(isDefault and "Default" or ("Reset (" .. Cards.rarity[c.baseRarity].name .. ")"), px, y, pw, 40,
    { font = app.fonts.med, disabled = isDefault }) then
    Settings.setCard(c, c.baseRarity, true)
  end
  y = y + 46
  local bw = (pw - 12) / 2
  if ui.button("Enable All", px, y, bw, 40, { font = app.fonts.med }) then
    for _, card in ipairs(Cards.list) do Settings.setCard(card, Settings.cardRarity(card), true) end
  end
  if ui.button("Reset All Cards", px + bw + 12, y, bw, 40, { font = app.fonts.med }) then
    require("screens.confirm").ask("Reset every card?", "All rarity changes and disabled cards go back to the defaults.", function()
      Settings.values.cards = {}
    end, { yes = "Reset", danger = true })
  end
  y = y + 46
  local st = Profile.cards[c.id] or { offered = 0, picked = 0, wins = 0 }
  local rate = st.offered > 0 and math.floor(st.picked / st.offered * 100 + 0.5) or 0
  love.graphics.setFont(app.fonts.small)
  love.graphics.setColor(1, 1, 1, 0.7)
  love.graphics.printf("Offered " .. st.offered .. "   Picked " .. st.picked .. " (" .. rate .. "%)   Rounds won " .. st.wins,
    px, y + 2, pw, "center")

  local warn = warning(self)
  local syns = Synergies.forCard(c, {})
  local ty = GRID_Y + ROWS * (TILE_H + TILE_GAP) + 4
  love.graphics.setFont(app.fonts.small)
  if warn then
    love.graphics.setColor(ui.BAD)
    love.graphics.printf(warn, GRID_X, ty, 760, "left")
  elseif #syns > 0 then
    local names = {}
    for _, syn in ipairs(syns) do names[#names + 1] = syn.name .. " (with " .. Synergies.partners(syn, c) .. ")" end
    love.graphics.setColor(ui.GOLD)
    love.graphics.printf("Synergies: " .. table.concat(names, "; "), GRID_X, ty, 760, "left")
  end
end

local function needsText(s)
  local names = {}
  for _, id in ipairs(s.needs) do names[#names + 1] = Cards.byId[id] and Cards.byId[id].name or id end
  return table.concat(names, " + ")
end

function Screen:drawSynergies()
  local v = Settings.values
  local list = Synergies.list
  local pages = math.max(1, math.ceil(#list / SYN_PER_PAGE))
  self.page = math.max(1, math.min(pages, self.page))
  local on = self.readOnly and (self.rules.synergies ~= false) or (not self.readOnly and v.synergiesOn)
  if ui.button(on and "Synergies: ON" or "Synergies: OFF", GRID_X, 76, 220, 34,
    { font = app.fonts.med, color = on and ui.GOOD or ui.BAD }) then
    v.synergiesOn = not v.synergiesOn
  end
  local cols, bw, bh = 3, 384, 66
  for k = 1, SYN_PER_PAGE do
    local s = list[(self.page - 1) * SYN_PER_PAGE + k]
    if not s then break end
    local col, row = (k - 1) % cols, math.floor((k - 1) / cols)
    local x, y = 40 + col * (bw + 10), 122 + row * (bh + 6)
    local off = self:synOff(s)
    if ui.button("", x, y, bw, bh) then v.synergies[s.id] = not v.synergies[s.id] or nil end
    love.graphics.setColor(off and { 1, 1, 1, 0.35 } or { 1, 0.82, 0.35 })
    ui.printFit(s.name, app.fonts.med, x + 12, y + 6, bw - 70, "left")
    love.graphics.setColor(1, 1, 1, off and 0.3 or 0.6)
    ui.printFit(needsText(s), app.fonts.tiny, x + 12, y + 28, bw - 24, "left")
    love.graphics.setColor(0.5, 1, 0.5, off and 0.3 or 0.8)
    ui.printFit(table.concat(s.lines, ", "), app.fonts.tiny, x + 12, y + 46, bw - 24, "left")
    if off then
      love.graphics.setFont(app.fonts.small)
      love.graphics.setColor(1, 0.45, 0.45)
      love.graphics.printf("OFF", x, y + 6, bw - 12, "right")
    end
  end
  local y = 628
  if ui.button("<", app.W / 2 - 130, y, 50, 36, { disabled = self.page <= 1, viewOnly = true }) then self.page = self.page - 1 end
  love.graphics.setFont(app.fonts.med)
  love.graphics.setColor(1, 1, 1, 0.6)
  love.graphics.printf("Page " .. self.page .. " / " .. pages, app.W / 2 - 80, y + 8, 160, "center")
  if ui.button(">", app.W / 2 + 80, y, 50, 36, { disabled = self.page >= pages, viewOnly = true }) then self.page = self.page + 1 end
  if ui.button("All On", 270, 76, 140, 34, { font = app.fonts.med }) then v.synergies = {} end
  if ui.button("All Off", 420, 76, 140, 34, { font = app.fonts.med }) then
    for _, s in ipairs(list) do v.synergies[s.id] = true end
  end
end

function Screen:draw()
  love.graphics.setColor(0, 0, 0, 0.7)
  love.graphics.rectangle("fill", 0, 0, app.W, app.H)
  ui.panel(20, 10, app.W - 40, app.H - 20)
  ui.readOnly = self.readOnly
  self:drawHeader()
  if self.tab == "cards" then self:drawCards() else self:drawSynergies() end
  ui.readOnly = false
  if self.readOnly then
    love.graphics.setFont(app.fonts.small)
    love.graphics.setColor(ui.GOLD)
    love.graphics.print("Host's settings (read-only)", GRID_X, 672)
  end
  if ui.button("Back", app.W - 180, 656, 140, 44, { back = true, font = app.fonts.med }) then app.pop() end
end

return Screen
