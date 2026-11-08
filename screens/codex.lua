-- Card codex (Main menu > Codex): every card and synergy, with your own pick statistics.
local app = require "core.app"
local ui = require "core.ui"
local Cards = require "game.cards"
local Synergies = require "game.synergies"
local Profile = require "core.profile"
local hud = require "gfx.hud"

local Codex = {}
Codex.__index = Codex

local PER_PAGE = 36
local FILTERS = { "all", "common", "uncommon", "rare", "epic", "legendary" }

function Codex.new()
  return setmetatable({ tab = "cards", page = 1, filter = 1, search = "", sel = nil, typing = false }, Codex)
end

function Codex:enter()
  love.mouse.setVisible(true)
end

function Codex:keypressed(key)
  if self.typing then
    if key == "escape" or key == "return" then self.typing = false end
    return
  end
  if key == "escape" then app.switch(require("screens.menu").new()) end
end

function Codex:wheelmoved(_, dy)
  self.page = self.page - (dy > 0 and 1 or -1)
end

function Codex:items()
  local out = {}
  local q = self.search:lower()
  local list = self.tab == "cards" and Cards.list or Synergies.list
  for _, c in ipairs(list) do
    local okRarity = self.tab ~= "cards" or self.filter == 1 or c.rarity == FILTERS[self.filter]
    if okRarity and (q == "" or c.name:lower():find(q, 1, true)) then out[#out + 1] = c end
  end
  return out
end

function Codex:draw()
  love.graphics.setColor(0.09, 0.09, 0.12)
  love.graphics.rectangle("fill", 0, 0, app.W, app.H)
  love.graphics.setFont(app.fonts.big)
  love.graphics.setColor(1, 1, 1)
  love.graphics.print("CODEX", 40, 22)
  for i, tb in ipairs({ { "cards", "Cards (" .. #Cards.list .. ")" }, { "synergies", "Synergies (" .. #Synergies.list .. ")" } }) do
    if ui.button(tb[2], 200 + (i - 1) * 210, 24, 200, 40, { color = self.tab == tb[1] and ui.ACCENT or nil }) and self.tab ~= tb[1] then
      self.tab, self.page, self.sel = tb[1], 1, nil
    end
  end
  if ui.button("Back", app.W - 180, 24, 140, 40, { back = true }) then app.switch(require("screens.menu").new()) end

  -- Search and filter
  if self.typing then
    ui.focus = ui.count + 1
    local text, done = ui.textField(self.search, 40, 78, 300, 34, { font = app.fonts.med, placeholder = "Search", maxLength = 24 })
    if text ~= self.search then self.search, self.page = text, 1 end
    if done then self.typing = false end
  elseif ui.button(self.search ~= "" and ("Search: " .. self.search) or "Search...", 40, 78, 300, 34, { font = app.fonts.med }) then
    self.typing = true
  end
  if self.tab == "cards" then
    local d = ui.cycler("Rarity", FILTERS[self.filter]:gsub("^%l", string.upper), 350, 78, 260, 34)
    if d ~= 0 then self.filter, self.page = (self.filter - 1 + d) % #FILTERS + 1, 1 end
  end

  local items = self:items()
  local pages = math.max(1, math.ceil(#items / PER_PAGE))
  self.page = math.max(1, math.min(pages, self.page))
  local cols, bw, bh = 3, 228, 30
  for k = 1, PER_PAGE do
    local c = items[(self.page - 1) * PER_PAGE + k]
    if not c then break end
    local col, row = (k - 1) % cols, math.floor((k - 1) / cols)
    local x, y = 40 + col * (bw + 8), 124 + row * (bh + 6)
    local color = self.tab == "cards" and (Cards.rarity[c.rarity] and Cards.rarity[c.rarity].color) or { 1, 0.82, 0.35 }
    if ui.button(c.name, x, y, bw, bh, { font = app.fonts.small, color = self.sel == c and ui.ACCENT or color }) then
      self.sel = c
    end
  end
  love.graphics.setFont(app.fonts.med)
  love.graphics.setColor(1, 1, 1, 0.6)
  love.graphics.printf("Page " .. self.page .. " / " .. pages, 40, 570, 3 * (bw + 8), "center")
  if ui.button("<", 40 + 3 * (bw + 8) / 2 - 140, 562, 50, 36, { disabled = self.page <= 1 }) then self.page = self.page - 1 end
  if ui.button(">", 40 + 3 * (bw + 8) / 2 + 90, 562, 50, 36, { disabled = self.page >= pages }) then self.page = self.page + 1 end

  -- Selected entry
  local s = self.sel or items[1]
  if not s then return end
  ui.panel(760, 80, 480, 620)
  hud.drawCard(s, 800, 100, 260, 390, false, { 1, 1, 1 }, self.tab == "synergies" and "legendary" or nil)
  love.graphics.setFont(app.fonts.med)
  love.graphics.setColor(1, 1, 1, 0.85)
  local y = 506
  if self.tab == "cards" then
    local st = Profile.cards[s.id] or { offered = 0, picked = 0, wins = 0 }
    local rate = st.offered > 0 and math.floor(st.picked / st.offered * 100 + 0.5) or 0
    love.graphics.printf("Offered to you: " .. st.offered .. "\nPicked: " .. st.picked .. "  (" .. rate .. "% of the time)" ..
      "\nRounds won holding it: " .. st.wins, 780, y, 440, "left")
    local syns = Synergies.forCard(s, {})
    if #syns > 0 then
      local names = {}
      for _, syn in ipairs(syns) do names[#names + 1] = syn.name .. " (with " .. Synergies.partners(syn, s) .. ")" end
      love.graphics.setFont(app.fonts.small)
      love.graphics.setColor(1, 0.82, 0.35)
      love.graphics.printf("Synergies: " .. table.concat(names, "; "), 780, y + 84, 440, "left")
    end
  else
    local names = {}
    for _, id in ipairs(s.needs) do names[#names + 1] = Cards.byId[id] and Cards.byId[id].name or id end
    love.graphics.printf("Needs: " .. table.concat(names, " + ") .. "\n\nThe bonus applies once for every full set of these cards you own.",
      780, y, 440, "left")
  end
end

return Codex
