-- Card editor: build a card from stat rows, trigger rules and notes, with a live preview.
-- Also draws the Cards tab of the editor hub (CardEditor.drawHub).
local app = require "core.app"
local ui = require "core.ui"
local Cards = require "game.cards"
local CardData = require "game.carddata"
local Stats = require "game.stats"
local Triggers = require "game.triggers"
local hud = require "gfx.hud"
local sfx = require "gfx.sfx"
local CardArt = require "gfx.cardart"

local CardEditor = {}
CardEditor.__index = CardEditor
CardEditor.noPadHints = true

local BADGES, TINTS = { false }, { false }
for _, n in ipairs(CardArt.NAMES) do BADGES[#BADGES + 1] = n end
for _, n in ipairs(CardArt.TINT_NAMES) do TINTS[#TINTS + 1] = n end

local RARITY_IDS = {}
for i, r in ipairs(Cards.RARITIES) do RARITY_IDS[i] = r.id end
local OPS = { "add", "mul", "set" }
local OP_NAMES = { add = "Add", mul = "Multiply", set = "Set to" }
local COPIES = { false, "first", "extra" }
local COPY_NAMES = { [false] = "Every copy", first = "First copy", extra = "Extra copies" }
local SPECIALS = { false, "reroll", "tableflip", "shrine" }
local SPECIAL_NAMES = { [false] = "None", reroll = "Reroll hand", tableflip = "Table Flip", shrine = "Shrine of Order" }

local function cycle(list, value, d)
  local idx = 1
  for i, v in ipairs(list) do if v == value then idx = i end end
  return list[(idx - 1 + d) % #list + 1]
end

local function copyDef(def)
  return CardData.parse(CardData.serialize(def))
end

-- How much one click changes a row's value.
local function stepFor(stat, op)
  if op == "mul" then return 0.05 end
  local info = Stats.INFO[stat]
  if not info then return 1 end
  if info.fmt == "count" then return 1 end
  if info.fmt == "secs" or info.fmt == "rate" then return 0.1 end
  if info.fmt == "pct" and math.abs(info.base) <= 5 then return 0.05 end
  if math.abs(info.base) >= 100 then return 10 end
  if math.abs(info.base) >= 10 then return 1 end
  return 1
end

-- opts: { card = existing card (edited as a copy) }
function CardEditor.new(opts)
  opts = opts or {}
  local src = opts.card
  local def = src and copyDef(src.def) or { name = "New Card", rarity = "common", rows = {
    { op = "mul", stat = "gunDamage", value = 1.2 } }, triggers = {}, notes = {} }
  return setmetatable({
    def = def, src = src, scroll = 0, msg = nil, msgT = 0, picker = nil, typing = nil,
    testCopies = 1,
  }, CardEditor)
end

function CardEditor:hubTab()
  return "cards"
end

function CardEditor:say(text, bad)
  self.msg, self.msgT, self.msgBad = text, 4, bad
end

function CardEditor:update(dt)
  self.msgT = math.max(0, self.msgT - dt)
end

function CardEditor:wheelmoved(_, dy)
  self.scroll = math.max(0, self.scroll - dy * 40)
end

function CardEditor:problems()
  local def = self.def
  local p = {}
  if def.name:match("^%s*$") then p[#p + 1] = "The card needs a name" end
  if #def.rows == 0 and #def.triggers == 0 and #def.notes == 0 and not def.special then
    p[#p + 1] = "Add at least one stat, trigger or note"
  end
  for _, c in ipairs(Cards.list) do
    if c ~= self.src and c.name:lower() == def.name:lower() then
      p[#p + 1] = "Another card is already called \"" .. c.name .. "\""
      break
    end
  end
  return p
end

function CardEditor:save()
  local problems = self:problems()
  if #problems > 0 then return self:say(problems[1], true) end
  local src = self.src
  if src and src.builtin then
    Cards.saveOverride(src.id, self.def)
    self:say("Saved your version of " .. self.def.name .. " (reset it from the card list)")
  else
    local card = src or { def = self.def }
    card.def = self.def
    card.file = Cards.saveCustom(card)
    self:say("Saved " .. self.def.name)
  end
  Cards.loadAll()
  for _, c in ipairs(Cards.list) do
    if (src and c.id == src.id) or (not src and c.name == self.def.name) then self.src = c end
  end
  sfx.ui("cardPick")
end

function CardEditor:test()
  local Match = require "screens.match"
  local cards = {}
  local card = CardData.build(copyDef(self.def))
  card.id, card.index = "test", 0
  for _ = 1, self.testCopies do cards[#cards + 1] = card end
  app.switch(Match.newLocal(99, { test = true, returnTo = self, giveCards = cards }))
end

function CardEditor:keypressed(key)
  if self.typing then
    if key == "escape" or key == "return" or key == "kpenter" then self.typing = nil end
    return
  end
  if key == "escape" then
    if self.picker or self.cardPicker then
      self.picker, self.cardPicker = nil, nil
    else
      app.switch(require("screens.editor_hub").new(self:hubTab()))
    end
  elseif key == "s" and love.keyboard.isDown("lctrl", "rctrl") then
    self:save()
  end
end

---------------------------------------------------------------- drawing
local function label(text, x, y, alpha)
  love.graphics.setFont(app.fonts.small)
  love.graphics.setColor(1, 1, 1, alpha or 0.5)
  love.graphics.print(text, x, y)
end

-- A text line being edited: field = { tbl, key }.
function CardEditor:textRow(tbl, key, x, y, w, h, placeholder)
  local editing = self.typing and self.typing[1] == tbl and self.typing[2] == key
  if editing then
    ui.focus = ui.count + 1
    local text, done = ui.textField(tbl[key] or "", x, y, w, h, { font = app.fonts.small, maxLength = 60,
      placeholder = placeholder })
    tbl[key] = text
    if done then self.typing = nil end
  else
    local shown = (tbl[key] and tbl[key] ~= "") and tbl[key] or placeholder
    if ui.button(shown, x, y, w, h, { font = app.fonts.small }) then self.typing = { tbl, key } end
  end
end

function CardEditor:drawStatPicker()
  local pk = self.picker
  love.graphics.setColor(0, 0, 0, 0.75)
  love.graphics.rectangle("fill", 0, 0, app.W, app.H)
  ui.panel(30, 30, app.W - 60, app.H - 60)
  love.graphics.setFont(app.fonts.title)
  love.graphics.setColor(1, 1, 1)
  love.graphics.print("Choose a stat", 54, 44)
  local cols = { Gun = 1, Bullets = 2, Melee = 3, Movement = 3, Defense = 4, Block = 5, Abilities = 6 }
  local colY = {}
  local cw = (app.W - 120) / 6
  for _, group in ipairs(Stats.GROUPS) do
    local c = cols[group]
    local x = 50 + (c - 1) * (cw + 4)
    colY[c] = (colY[c] or 82) + 8
    label(group:upper(), x + 2, colY[c], 0.45)
    colY[c] = colY[c] + 18
    for _, row in ipairs(Stats.LIST) do
      local inf = Stats.INFO[row[1]]
      if inf.group == group then
        if ui.button(inf.label, x, colY[c], cw, 21, { font = app.fonts.tiny, color = pk.row.stat == inf.key and ui.ACCENT or nil }) then
          pk.row.stat = inf.key
          pk.row.value = pk.row.op == "mul" and 1.2 or stepFor(inf.key, pk.row.op)
          self.picker = nil
          return
        end
        colY[c] = colY[c] + 23
      end
    end
  end
  if ui.button("Cancel", app.W / 2 - 80, app.H - 80, 160, 36, { back = true }) then self.picker = nil end
end

function CardEditor:drawRows(x, y, w)
  local def = self.def
  label("STAT ROWS  (applied for each copy, top to bottom)", x, y)
  y = y + 20
  for i, r in ipairs(def.rows) do
    local bw = { 112, 92, 190, 150, 30 }
    local bx = x
    if ui.button(COPY_NAMES[r.copy or false], bx, y, bw[1], 28, { font = app.fonts.tiny }) then
      r.copy = cycle(COPIES, r.copy or false, 1) or nil
    end
    bx = bx + bw[1] + 4
    if ui.button(OP_NAMES[r.op], bx, y, bw[2], 28, { font = app.fonts.small }) then
      r.op = cycle(OPS, r.op, 1)
      if r.op == "mul" and (r.value <= 0 or r.value > 20) then r.value = 1.2 end
    end
    bx = bx + bw[2] + 4
    local info = Stats.INFO[r.stat]
    if ui.button(info and info.label or r.stat, bx, y, bw[3], 28, { font = app.fonts.small }) then
      self.picker = { row = r }
    end
    bx = bx + bw[3] + 4
    local d = ui.cycler("", Stats.num(r.value), bx, y, bw[4], 28)
    if d ~= 0 then
      local step = stepFor(r.stat, r.op)
      r.value = math.floor((r.value + d * step) / step + 0.5) * step
      r.value = math.floor(r.value * 10000 + 0.5) / 10000
    end
    bx = bx + bw[4] + 4
    if ui.button("x", bx, y, bw[5], 28, { font = app.fonts.small, back = true }) then
      table.remove(def.rows, i)
      return y
    end
    local text = CardData.lines({ rows = { r }, triggers = {}, notes = {} })[1]
    love.graphics.setFont(app.fonts.tiny)
    love.graphics.setColor(1, 1, 1, 0.45)
    love.graphics.print(text or "(not shown on the card)", bx + 40, y + 7)
    y = y + 32
  end
  if ui.button("+ Add stat row", x, y, 200, 28, { font = app.fonts.small }) then
    def.rows[#def.rows + 1] = { op = "mul", stat = "gunDamage", value = 1.2 }
  end
  return y + 40
end

function CardEditor:drawTriggers(x, y, w)
  local def = self.def
  label("TRIGGERS  (when something happens, do something)", x, y)
  y = y + 20
  local whens = {}
  for _, wv in ipairs(Triggers.WHEN) do whens[#whens + 1] = wv[1] end
  local effects = {}
  for _, e in ipairs(Triggers.EFFECTS) do effects[#effects + 1] = e.id end
  for i, t in ipairs(def.triggers) do
    if ui.button(Triggers.WHEN_LABEL[t.when] or t.when, x, y, 230, 28, { font = app.fonts.small }) then
      t.when = cycle(whens, t.when, 1)
    end
    local e = Triggers.EFFECT[t.effect]
    if ui.button(e and e.name or t.effect, x + 234, y, 150, 28, { font = app.fonts.small }) then
      t.effect = cycle(effects, t.effect, 1)
      t.params = {}
    end
    if ui.button("x", x + 388, y, 30, 28, { font = app.fonts.small, back = true }) then
      table.remove(def.triggers, i)
      return y
    end
    y = y + 32
    -- Parameters: the effect's, then interval / chance / cooldown.
    local params = {}
    for _, pdef in ipairs(e and e.params or {}) do params[#params + 1] = pdef end
    if t.when == "interval" then params[#params + 1] = { "every", 5, 0.5, 0.5, 60, "Every (s)" } end
    local px = x + 20
    local q = Triggers.params(t)
    for _, pdef in ipairs(params) do
      local key = pdef[1]
      local d = ui.cycler(pdef[6], Stats.num(q[key] or pdef[2]), px, y, 175, 26)
      if d ~= 0 then
        t.params = t.params or {}
        local v = (q[key] or pdef[2]) + d * pdef[3]
        t.params[key] = math.max(pdef[4], math.min(pdef[5], math.floor(v / pdef[3] + 0.5) * pdef[3]))
      end
      px = px + 180
    end
    local d = ui.cycler("Chance", math.floor((t.chance or 1) * 100 + 0.5) .. "%", px, y, 175, 26)
    if d ~= 0 then t.chance = math.max(0.05, math.min(1, (t.chance or 1) + d * 0.05)) end
    px = px + 180
    d = ui.cycler("Cooldown", Stats.num(t.cd or 0) .. "s", px, y, 175, 26)
    if d ~= 0 then t.cd = math.max(0, math.min(30, (t.cd or 0) + d * 0.5)) end
    y = y + 32
  end
  if ui.button("+ Add trigger", x, y, 200, 28, { font = app.fonts.small }) then
    def.triggers[#def.triggers + 1] = { when = "block", effect = "heal", params = {} }
  end
  return y + 40
end

function CardEditor:drawNotes(x, y, w)
  local def = self.def
  label("NOTES  (extra text on the card; start with + or - to colour it)", x, y)
  y = y + 20
  for i = 1, #def.notes do
    self:textRow(def.notes, i, x, y, w - 40, 26, "(empty note)")
    if ui.button("x", x + w - 34, y, 30, 26, { font = app.fonts.small, back = true }) then
      table.remove(def.notes, i)
      return y
    end
    y = y + 30
  end
  if ui.button("+ Add note", x, y, 200, 28, { font = app.fonts.small }) then
    def.notes[#def.notes + 1] = "+"
    self.typing = { def.notes, #def.notes }
  end
  y = y + 40
  label("STACKING TEXT  (what extra copies do; leave empty to generate it)", x, y)
  y = y + 20
  self:textRow(def, "stack", x, y, w - 40, 26, "(generated)")
  if def.stack == "" then def.stack = nil end
  return y + 40
end

function CardEditor:draw()
  love.graphics.setColor(0.09, 0.09, 0.12)
  love.graphics.rectangle("fill", 0, 0, app.W, app.H)
  local def = self.def

  -- Top bar
  love.graphics.setFont(app.fonts.small)
  love.graphics.setColor(1, 1, 1, 0.5)
  local kind = self.src and (self.src.builtin and (self.src.edited and "BUILT-IN CARD (EDITED)" or "BUILT-IN CARD")
    or "CUSTOM CARD") or "NEW CARD"
  love.graphics.print(kind, 20, 8)
  self:textRow(def, "name", 20, 26, 260, 32, "Card name")
  local buttons = {
    { "Test (" .. self.testCopies .. "x)", function() self:test() end },
    { "Copies -", function() self.testCopies = math.max(1, self.testCopies - 1) end },
    { "Copies +", function() self.testCopies = math.min(10, self.testCopies + 1) end },
    { "Save", function() self:save() end },
    { "Share", function()
      local ok = pcall(love.system.setClipboardText, CardData.encodeShare(def))
      self:say(ok and "Card code copied" or "Couldn't use the clipboard", not ok)
    end },
    { "Import", function()
      local ok, text = pcall(love.system.getClipboardText)
      local d, err = CardData.decodeShare(ok and text or "")
      if not d then return self:say((err or "No code") .. " - copy a code first", true) end
      self.def, self.src = d, nil
      self:say("Imported " .. d.name .. " as a new card")
    end },
    { "Exit", function() app.switch(require("screens.editor_hub").new(self:hubTab())) end },
  }
  local bx = 300
  local bw = (app.W - bx - 20 - (#buttons - 1) * 6) / #buttons
  for _, b in ipairs(buttons) do
    if ui.button(b[1], bx, 20, bw, 38, { font = app.fonts.med }) then b[2]() end
    bx = bx + bw + 6
  end

  -- Card settings
  local y = 70
  local d = ui.cycler("Rarity", Cards.rarity[def.rarity] and Cards.rarity[def.rarity].name or def.rarity, 20, y, 260, 30)
  if d ~= 0 then def.rarity = cycle(RARITY_IDS, def.rarity, d) end
  d = ui.cycler("Block card", def.block and "Yes" or "No", 300, y, 220, 30)
  if d ~= 0 then def.block = not def.block or nil end
  d = ui.cycler("Special", SPECIAL_NAMES[def.special or false], 540, y, 300, 30)
  if d ~= 0 then def.special = cycle(SPECIALS, def.special or false, d) or nil end

  -- Scrolling content
  love.graphics.setScissor() -- (canvas)
  local x0, top, w = 20, 114, 860
  love.graphics.push()
  local yy = top - self.scroll
  yy = self:drawRows(x0, yy, w)
  yy = self:drawTriggers(x0, yy, w)
  yy = self:drawNotes(x0, yy, w)
  love.graphics.pop()
  self.contentH = yy + self.scroll - top
  self.scroll = math.min(self.scroll, math.max(0, self.contentH - (app.H - top - 40)))
  love.graphics.setColor(0.09, 0.09, 0.12)
  love.graphics.rectangle("fill", 0, 104, 900, 8)

  -- Preview
  local card = CardData.build(copyDef(def))
  card.id = self.src and self.src.id
  card.custom = not (self.src and self.src.builtin)
  card.edited = self.src and self.src.builtin and CardData.serialize(def) ~= self.src.defaultText or nil
  ui.panel(900, 104, 360, 600)
  label("PREVIEW", 916, 112)
  hud.drawCard(card, 940, 140, 280, 420, false, { 1, 1, 1 })
  do
    local spec = CardArt.specOf(card)
    local main, badge, tint = spec.main, spec.badge or false, spec.tint or false
    local d1 = ui.cycler("Art", main, 912, 640, 336, 26)
    local d2 = ui.cycler("Badge", badge or "None", 912, 672, 166, 26)
    local d3 = ui.cycler("Tint", tint or "Rarity", 1084, 672, 164, 26)
    if d1 ~= 0 then main = cycle(CardArt.NAMES, main, d1) end
    if d2 ~= 0 then badge = cycle(BADGES, badge, d2) end
    if d3 ~= 0 then tint = cycle(TINTS, tint, d3) end
    if d1 ~= 0 or d2 ~= 0 or d3 ~= 0 then
      def.art = main .. (badge and (" " .. badge) or "") .. (tint and (" " .. tint) or "")
    end
  end
  local problems = self:problems()
  love.graphics.setFont(app.fonts.small)
  love.graphics.setColor(#problems == 0 and { 0.5, 1, 0.6 } or { 1, 0.55, 0.45 })
  love.graphics.printf(#problems == 0 and "Ready to save" or problems[1], 916, 580, 330, "center")
  if self.msg and self.msgT > 0 then
    love.graphics.setColor(self.msgBad and { 1, 0.55, 0.45, math.min(1, self.msgT) } or { 1, 1, 1, math.min(1, self.msgT) })
    love.graphics.printf(self.msg, 916, 620, 330, "center")
  end

  if self.picker then self:drawStatPicker() end
end

---------------------------------------------------------------- hub tab
local PER_PAGE = 40
-- Every card, common to legendary, in list order within each rarity.
local function byRarity()
  local rank, list = {}, {}
  for i, r in ipairs(Cards.RARITIES) do rank[r.id] = i end
  for i, c in ipairs(Cards.list) do list[i] = c end
  table.sort(list, function(a, b)
    local ra, rb = rank[a.rarity] or #Cards.RARITIES + 1, rank[b.rarity] or #Cards.RARITIES + 1
    if ra ~= rb then return ra < rb end
    if (a.index or 0) ~= (b.index or 0) then return (a.index or 0) < (b.index or 0) end
    return a.name < b.name
  end)
  return list
end

function CardEditor.drawHub(hub)
  local list = byRarity()
  hub.page = math.max(1, math.min(math.max(1, math.ceil(#list / PER_PAGE)), hub.page))
  local first = (hub.page - 1) * PER_PAGE + 1
  local cols, bw, bh = 4, 290, 30
  for k = 0, PER_PAGE - 1 do
    local c = list[first + k]
    if not c then break end
    local col, row = k % cols, math.floor(k / cols)
    local x, y = 40 + col * (bw + 10), 110 + row * (bh + 6)
    local rc = Cards.rarity[c.rarity] and Cards.rarity[c.rarity].color or { 1, 1, 1 }
    local tag = c.custom and "  (custom)" or c.edited and "  (edited)" or ""
    if ui.button(c.name .. tag, x, y, bw, bh, { font = app.fonts.small, color = hub.sel == c and ui.ACCENT or rc }) then
      if hub.sel == c then
        app.switch(CardEditor.new({ card = c }))
        return
      end
      hub.sel = c
    end
  end
  local pages = math.max(1, math.ceil(#list / PER_PAGE))
  love.graphics.setFont(app.fonts.med)
  love.graphics.setColor(1, 1, 1, 0.6)
  love.graphics.printf("Page " .. hub.page .. " / " .. pages .. "   (" .. #list .. " cards)", 0, 480, app.W, "center")
  if ui.button("<", app.W / 2 - 200, 472, 50, 36, { disabled = hub.page <= 1 }) then hub.page = hub.page - 1 end
  if ui.button(">", app.W / 2 + 150, 472, 50, 36, { disabled = hub.page >= pages }) then hub.page = hub.page + 1 end

  local s = hub.sel
  local acts = {
    { "New Card", true, function() app.switch(CardEditor.new()) end },
    { "Community", not require("core.platform").web, function() app.switch(require("screens.community").new("cards")) end },
    { "Edit", s ~= nil, function() app.switch(CardEditor.new({ card = s })) end },
    { "Duplicate", s ~= nil, function()
      local def = copyDef(s.def)
      def.name = (s.name .. " Copy"):sub(1, 32)
      Cards.saveCustom({ def = def })
      Cards.loadAll()
      hub:say("Made a copy of " .. s.name)
    end },
    { "Share Code", s ~= nil, function()
      local ok = pcall(love.system.setClipboardText, CardData.encodeShare(s.def))
      hub:say(ok and "Card code copied" or "Couldn't use the clipboard", not ok)
    end },
    { "Import Code", true, function()
      local ok, text = pcall(love.system.getClipboardText)
      local d, err = CardData.decodeShare(ok and text or "")
      if not d then return hub:say((err or "No card code") .. " - copy a card code first", true) end
      Cards.saveCustom({ def = d })
      Cards.loadAll()
      hub:say("Imported " .. d.name)
    end },
    { s and s.edited and "Reset to Default" or "Delete", s ~= nil and (s.custom or s.edited), function()
      if s.custom then Cards.deleteCustom(s) else Cards.resetOverride(s.id) end
      hub:say(s.custom and ("Deleted " .. s.name) or (s.name .. " is back to the original"))
      Cards.loadAll()
      hub.sel = nil
    end },
  }
  local w = (app.W - 80 - (#acts - 1) * 10) / #acts
  for i, a in ipairs(acts) do
    if ui.button(a[1], 40 + (i - 1) * (w + 10), 652, w, 44, { font = app.fonts.med, disabled = not a[2] }) then a[3]() end
  end
  love.graphics.setFont(app.fonts.small)
  love.graphics.setColor(1, 1, 1, 0.45)
  love.graphics.printf("Click a card to select it, click again to edit. Edited built-in cards can be reset. " ..
    "Online, the host's cards are used.", 40, 530, app.W - 80, "left")
end

return CardEditor
