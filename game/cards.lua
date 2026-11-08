-- Upgrade cards. Each card has a rarity and either modifies a player's stats
-- table in apply(), or is a "special" card resolved instantly when picked.
-- Every card stacks: abilities are counted (one per copy), and `stack` describes
-- what extra copies do when that isn't obvious from the stat lines.
local Cards = {}

Cards.RARITIES = {
  { id = "common",    name = "Common",    color = { 0.75, 0.75, 0.8 }, weight = 46 },
  { id = "uncommon",  name = "Uncommon",  color = { 0.35, 0.9, 0.45 }, weight = 30 },
  { id = "rare",      name = "Rare",      color = { 0.3, 0.6, 1 },     weight = 15 },
  { id = "epic",      name = "Epic",      color = { 0.75, 0.35, 1 },   weight = 6 },
  { id = "legendary", name = "Legendary", color = { 1, 0.78, 0.2 },    weight = 3 },
}
Cards.rarity = {}
for _, r in ipairs(Cards.RARITIES) do Cards.rarity[r.id] = r end

local CardData = require "game.carddata"

---------------------------------------------------------------- card files
-- Built-in cards live in data/cards/ (order in data/cards/order.txt) in the card editor's format.
-- Editing one in-game saves an override (user/cards/<id>.txt); custom cards go to user/custom_cards/.
Cards.BUILTIN_DIR = "data/cards/"
Cards.OVERRIDE_DIR = "user/cards/"
Cards.CUSTOM_DIR = "user/custom_cards/"

local function readFile(path)
  if not love.filesystem.getInfo(path) then return nil end
  return love.filesystem.read(path)
end

-- Stable index per card (sent over the network) and an id (settings file).
local function indexList()
  Cards.byId = {}
  for i, c in ipairs(Cards.list) do
    c.index = i
    Cards.byId[c.id] = c
  end
end

local function make(def, id, flags)
  local c = CardData.build(def)
  c.id = id
  for k, v in pairs(flags or {}) do c[k] = v end
  return c
end

function Cards.loadAll()
  local list = {}
  local order = readFile(Cards.BUILTIN_DIR .. "order.txt") or ""
  for id in order:gmatch("[%w_]+") do
    local text = readFile(Cards.BUILTIN_DIR .. id .. ".txt")
    local def = text and CardData.parse(text)
    if def then
      local edited = readFile(Cards.OVERRIDE_DIR .. id .. ".txt")
      local edef = edited and CardData.parse(edited)
      if edef then
        list[#list + 1] = make(edef, id, { builtin = true, edited = true, defaultText = text })
      else
        list[#list + 1] = make(def, id, { builtin = true, defaultText = text })
      end
    end
  end
  local customs = {}
  for _, file in ipairs(love.filesystem.getDirectoryItems(Cards.CUSTOM_DIR)) do
    if file:match("%.txt$") then
      local def = CardData.parse(readFile(Cards.CUSTOM_DIR .. file))
      if def then customs[#customs + 1] = make(def, "c_" .. file:gsub("%.txt$", ""), { custom = true, file = file }) end
    end
  end
  table.sort(customs, function(a, b) return a.name:lower() < b.name:lower() end)
  for _, c in ipairs(customs) do list[#list + 1] = c end
  Cards.list = list
  Cards.session = nil
  indexList()
  if Cards.rules then Cards.applyRules(Cards.rules) end
end

function Cards.saveCustom(card)
  love.filesystem.createDirectory(Cards.CUSTOM_DIR)
  local file = card.file
  if not file then
    local base = CardData.idOf(card.def.name)
    file = base .. ".txt"
    local n = 2
    while love.filesystem.getInfo(Cards.CUSTOM_DIR .. file) do
      file = base .. "_" .. n .. ".txt"
      n = n + 1
    end
  end
  love.filesystem.write(Cards.CUSTOM_DIR .. file, CardData.serialize(card.def))
  return file
end

function Cards.deleteCustom(card)
  if card.file then love.filesystem.remove(Cards.CUSTOM_DIR .. card.file) end
end

function Cards.saveOverride(id, def)
  love.filesystem.createDirectory(Cards.OVERRIDE_DIR)
  love.filesystem.write(Cards.OVERRIDE_DIR .. id .. ".txt", CardData.serialize(def))
end

function Cards.resetOverride(id)
  love.filesystem.remove(Cards.OVERRIDE_DIR .. id .. ".txt")
end

-- Online: the host's card list; text is sent for custom and edited cards.
function Cards.sessionEntries()
  local out = {}
  for _, c in ipairs(Cards.list) do
    out[#out + 1] = { id = c.id, text = (c.custom or c.edited) and CardData.serialize(c.def) or nil }
  end
  return out
end

function Cards.setSession(entries)
  Cards.loadAll()
  local builtins = Cards.byId
  local list = {}
  for _, e in ipairs(entries) do
    local c
    if e.text then
      local def = CardData.parse(e.text)
      if def then c = make(def, e.id, { custom = true, edited = builtins[e.id] ~= nil, fromHost = true }) end
    else
      c = builtins[e.id]
    end
    c = c or make({ name = "Unknown card", rarity = "common", rows = {}, triggers = {}, notes = {} }, e.id)
    list[#list + 1] = c
  end
  Cards.list = list
  Cards.session = true
  indexList()
end

Cards.list = {}
Cards.loadAll()

Cards.DEFAULT_RULES = { pickFrom = 3, picksPerRound = 1, weights = {}, rarity = {}, disabled = {} }
for i, r in ipairs(Cards.RARITIES) do Cards.DEFAULT_RULES.weights[i] = r.weight end
Cards.rules = Cards.DEFAULT_RULES

-- Gameplay rules: { pickFrom, picksPerRound, weights = { per RARITIES index },
-- rarity = { [card index] = rarity id }, disabled = { [card index] = true } }.
-- Sets each card's current rarity / disabled flag (also used when drawing cards).
function Cards.applyRules(rules)
  Cards.rules = rules
  if not Cards.list then return end
  for _, c in ipairs(Cards.list) do
    local r = rules.rarity[c.index]
    c.rarity = (r and Cards.rarity[r]) and r or c.baseRarity
    c.disabled = rules.disabled[c.index] and true or nil
  end
end

-- Can this card be offered to the player right now?
-- Table Flip / Shrine are only offered to a player who already owns cards.
local function offerable(c, player, used)
  if c.disabled or used[c] then return false end
  if c.special and c.special ~= "reroll" and #player.cards == 0 then return false end
  return true
end

-- Deal up to n distinct cards, rolling a rarity for each slot. Only rarities that
-- still have cards to offer take part in the roll; rarities with zero chance are
-- skipped unless nothing else is left. May return fewer than n cards (even none).
function Cards.deal(n, player)
  local weights = Cards.rules.weights
  local hand, used = {}, {}
  while #hand < n do
    local pools, total, any = {}, 0, false
    for i, r in ipairs(Cards.RARITIES) do
      local pool = {}
      for _, c in ipairs(Cards.list) do
        if c.rarity == r.id and offerable(c, player, used) then pool[#pool + 1] = c end
      end
      if #pool > 0 then
        pools[i] = pool
        any = true
        total = total + math.max(0, weights[i] or 0)
      end
    end
    if not any then break end

    local pick
    if total > 0 then
      local x = love.math.random() * total
      for i in ipairs(Cards.RARITIES) do
        local w = pools[i] and math.max(0, weights[i] or 0) or 0
        if w > 0 then
          pick = i
          x = x - w
          if x <= 0 then break end
        end
      end
    else
      local options = {}
      for i in ipairs(Cards.RARITIES) do
        if pools[i] then options[#options + 1] = i end
      end
      pick = options[love.math.random(#options)]
    end

    local pool = pools[pick]
    local c = pool[love.math.random(#pool)]
    used[c] = true
    hand[#hand + 1] = c
  end
  return hand
end

-- A random keepable (non-special, enabled) card of the given rarity, preferring one other than `exclude`.
function Cards.randomOfRarity(rarity, exclude)
  local pool = {}
  for _, c in ipairs(Cards.list) do
    if c.rarity == rarity and not c.special and not c.disabled and c ~= exclude then pool[#pool + 1] = c end
  end
  if #pool == 0 then return exclude end
  return pool[love.math.random(#pool)]
end

function Cards.tableFlip(player)
  for i, c in ipairs(player.cards) do
    player.cards[i] = Cards.randomOfRarity(c.rarity, c)
  end
  player:recompute()
  return string.format("PLAYER %d FLIPPED THE TABLE! %d cards rerolled", player.id, #player.cards)
end

-- Shrine of Order (as in Risk of Rain 2): for each rarity, every card you own of that
-- rarity becomes a copy of one card type you already own of that rarity. Uses each
-- card's current rarity, so cards moved to another rarity in the settings are grouped
-- with the rarity they're in now.
function Cards.shrine(player)
  local types, owned = {}, {} -- rarity id -> distinct card types / count owned
  for _, c in ipairs(player.cards) do
    local r = c.rarity
    types[r] = types[r] or {}
    owned[r] = (owned[r] or 0) + 1
    local seen = false
    for _, t in ipairs(types[r]) do
      if t == c then seen = true end
    end
    if not seen then table.insert(types[r], c) end
  end

  local changes = {}
  for _, r in ipairs(Cards.RARITIES) do
    local list = types[r.id]
    if list then
      local chosen = list[love.math.random(#list)]
      for i, c in ipairs(player.cards) do
        if c.rarity == r.id then player.cards[i] = chosen end
      end
      changes[#changes + 1] = string.format("%d %s became %s", owned[r.id], r.name, chosen.name)
    end
  end
  if #changes == 0 then return "The Shrine of Order found nothing to order" end
  player:recompute()
  return "SHRINE OF ORDER: " .. table.concat(changes, ", ")
end

return Cards
