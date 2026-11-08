-- Synergies: owning every card a synergy needs unlocks a bonus (stat rows, trigger rules, notes),
-- written in the card editor's format plus a "needs" line:
--   deckshot-synergy 1
--   name Bouncing Blasts
--   needs explosive bouncy        (card ids)
--   row add bounceExplode 1
-- The bonus applies once per full set: with 2 Explosive and 3 Bouncy it applies twice.
-- Built-ins live in data/synergies/ (order.txt); edits go to user/synergies/, new ones to
-- user/custom_synergies/. Hosts can turn all synergies off or toggle each one (rules).
local CardData = require "game.carddata"

local Synergies = { list = {}, byId = {} }
Synergies.BUILTIN_DIR = "data/synergies/"
Synergies.OVERRIDE_DIR = "user/synergies/"
Synergies.CUSTOM_DIR = "user/custom_synergies/"
Synergies.SHARE_PREFIX = "DSSYN1:"

local function readFile(path)
  if not love.filesystem.getInfo(path) then return nil end
  return love.filesystem.read(path)
end

function Synergies.parse(text)
  if type(text) ~= "string" then return nil, "no synergy data" end
  local body = text:gsub("^%s*deckshot%-synergy 1", "deckshot-card 1", 1)
  if body == text then return nil, "not a Deckshot synergy" end
  local def, err = CardData.parse(body)
  if not def then return nil, err end
  def.needs = {}
  for line in (text .. "\n"):gmatch("([^\r\n]*)\r?\n") do
    local rest = line:match("^%s*needs%s+(.-)%s*$")
    if rest then
      for id in rest:gmatch("[%w_]+") do def.needs[#def.needs + 1] = id end
    end
  end
  return def
end

function Synergies.serialize(def)
  local text = CardData.serialize(def):gsub("^deckshot%-card 1", "deckshot-synergy 1", 1)
  -- "needs" goes right after the name line.
  return (text:gsub("(name [^\n]*\n)", "%1needs " .. table.concat(def.needs or {}, " ") .. "\n", 1))
end

local function make(def, id, flags)
  local s = CardData.build(def)
  s.id, s.needs = id, def.needs or {}
  for k, v in pairs(flags or {}) do s[k] = v end
  return s
end

local function indexList()
  Synergies.byId = {}
  for i, s in ipairs(Synergies.list) do
    s.index = i
    Synergies.byId[s.id] = s
  end
end

function Synergies.loadAll()
  local list = {}
  local order = readFile(Synergies.BUILTIN_DIR .. "order.txt") or ""
  for id in order:gmatch("[%w_]+") do
    local text = readFile(Synergies.BUILTIN_DIR .. id .. ".txt")
    local def = text and Synergies.parse(text)
    if def then
      local edited = readFile(Synergies.OVERRIDE_DIR .. id .. ".txt")
      local edef = edited and Synergies.parse(edited)
      list[#list + 1] = make(edef or def, id, { builtin = true, edited = edef and true or nil, defaultText = text })
    end
  end
  local customs = {}
  for _, file in ipairs(love.filesystem.getDirectoryItems(Synergies.CUSTOM_DIR)) do
    if file:match("%.txt$") then
      local def = Synergies.parse(readFile(Synergies.CUSTOM_DIR .. file))
      if def then customs[#customs + 1] = make(def, "c_" .. file:gsub("%.txt$", ""), { custom = true, file = file }) end
    end
  end
  table.sort(customs, function(a, b) return a.name:lower() < b.name:lower() end)
  for _, s in ipairs(customs) do list[#list + 1] = s end
  Synergies.list = list
  indexList()
end

function Synergies.saveCustom(syn)
  love.filesystem.createDirectory(Synergies.CUSTOM_DIR)
  local file = syn.file
  if not file then
    local base = CardData.idOf(syn.def.name)
    file = base .. ".txt"
    local n = 2
    while love.filesystem.getInfo(Synergies.CUSTOM_DIR .. file) do
      file = base .. "_" .. n .. ".txt"
      n = n + 1
    end
  end
  love.filesystem.write(Synergies.CUSTOM_DIR .. file, Synergies.serialize(syn.def))
  return file
end

function Synergies.deleteCustom(syn)
  if syn.file then love.filesystem.remove(Synergies.CUSTOM_DIR .. syn.file) end
end

function Synergies.saveOverride(id, def)
  love.filesystem.createDirectory(Synergies.OVERRIDE_DIR)
  love.filesystem.write(Synergies.OVERRIDE_DIR .. id .. ".txt", Synergies.serialize(def))
end

function Synergies.resetOverride(id)
  love.filesystem.remove(Synergies.OVERRIDE_DIR .. id .. ".txt")
end

function Synergies.encodeShare(def)
  local packed = love.data.compress("string", "zlib", Synergies.serialize(def), 9)
  return Synergies.SHARE_PREFIX .. love.data.encode("string", "base64", packed)
end

function Synergies.decodeShare(code)
  code = (code or ""):gsub("%s+", "")
  local body = code:match("^DSSYN1:(.+)$")
  if not body then return nil, "That isn't a synergy code" end
  local ok, packed = pcall(love.data.decode, "string", "base64", body)
  local ok2, text = ok and pcall(love.data.decompress, "string", "zlib", packed)
  if not ok2 then return nil, "The synergy code is damaged" end
  return Synergies.parse(text)
end

-- Online: the host's list (text for custom / edited ones).
function Synergies.sessionEntries()
  local out = {}
  for _, s in ipairs(Synergies.list) do
    out[#out + 1] = { id = s.id, text = (s.custom or s.edited) and Synergies.serialize(s.def) or nil }
  end
  return out
end

function Synergies.setSession(entries)
  Synergies.loadAll()
  local builtins = Synergies.byId
  local list = {}
  for _, e in ipairs(entries) do
    local def = e.text and Synergies.parse(e.text)
    list[#list + 1] = def and make(def, e.id, { custom = true }) or builtins[e.id]
      or make({ name = "?", rows = {}, triggers = {}, notes = {}, needs = { "none" } }, e.id)
  end
  Synergies.list = list
  indexList()
end

---------------------------------------------------------------- rules and lookups
-- rules.synergies == false turns them all off; rules.synergyOff = { [index] = true }.
local function enabled(s, rules)
  rules = rules or {}
  if rules.synergies == false then return false end
  return not (rules.synergyOff and rules.synergyOff[s.index])
end
Synergies.enabled = enabled

-- How many full sets of a synergy's cards a player owns. copies: card id -> count.
function Synergies.sets(s, copies)
  if #s.needs == 0 then return 0 end
  local n = math.huge
  for _, id in ipairs(s.needs) do n = math.min(n, copies[id] or 0) end
  return n == math.huge and 0 or n
end

-- Active synergies for a card list: { { syn = s, sets = n } }.
function Synergies.active(cards, rules)
  local copies = {}
  for _, c in ipairs(cards) do copies[c.id] = (copies[c.id] or 0) + 1 end
  local out = {}
  for _, s in ipairs(Synergies.list) do
    if enabled(s, rules) then
      local n = Synergies.sets(s, copies)
      if n > 0 then out[#out + 1] = { syn = s, sets = n } end
    end
  end
  return out
end

-- Synergies a card is part of (enabled ones), for the card face.
function Synergies.forCard(card, rules)
  local out = {}
  for _, s in ipairs(Synergies.list) do
    if enabled(s, rules) then
      for _, id in ipairs(s.needs) do
        if id == card.id then out[#out + 1] = s break end
      end
    end
  end
  return out
end

-- The other cards' names for a synergy, from one card's point of view.
function Synergies.partners(s, card)
  local Cards = require "game.cards"
  local names = {}
  for _, id in ipairs(s.needs) do
    if id ~= card.id then names[#names + 1] = Cards.byId[id] and Cards.byId[id].name or id end
  end
  return table.concat(names, " + ")
end

Synergies.loadAll()

return Synergies
