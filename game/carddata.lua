-- Card files (the card editor's format) and turning them into playable cards.
--   deckshot-card 1
--   name Heavy Shot
--   rarity common
--   block                          (optional: a block card, shown in the card's footer)
--   special reroll                 (optional: reroll | tableflip | shrine)
--   row mul gunDamage 1.7          (op add | mul | set, stat, value)
--   row first mul gunDamage 0.85   (first copy only)
--   row extra mul gunDamage 1.5    (extra copies only)
--   trigger block explode radius=120 damage=30 chance=1 cd=0
--   note +aim down to fly          (extra text on the card)
--   stack Ramps up faster per copy (what extra copies do; generated when left out)
local Stats = require "game.stats"

local CardData = {}

CardData.HEADER = "deckshot-card 1"
CardData.SHARE_PREFIX = "DSCARD1:"
CardData.SPECIALS = { "reroll", "tableflip", "shrine" }

local function fmt(v)
  if type(v) == "number" then
    if math.abs(v - math.floor(v + 0.5)) < 1e-9 then return tostring(math.floor(v + 0.5)) end
    return (string.format("%.6f", v):gsub("0+$", ""):gsub("%.$", ""))
  end
  return tostring(v)
end

function CardData.idOf(name)
  local id = (name or "card"):lower():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
  return id ~= "" and id or "card"
end

-- Text -> card definition (or nil, error).
function CardData.parse(text)
  if type(text) ~= "string" then return nil, "no card data" end
  local def = { name = "Untitled", rarity = "common", rows = {}, triggers = {}, notes = {} }
  local first = true
  for line in (text .. "\n"):gmatch("([^\r\n]*)\r?\n") do
    local word, rest = line:match("^%s*(%S+)%s*(.-)%s*$")
    if first and word then
      if word ~= "deckshot-card" then return nil, "not a Deckshot card" end
      first = false
    elseif word == "name" then
      def.name = rest:sub(1, 32)
    elseif word == "rarity" then
      def.rarity = rest
    elseif word == "block" then
      def.block = true
    elseif word == "special" then
      def.special = rest
    elseif word == "note" then
      def.notes[#def.notes + 1] = rest
    elseif word == "stack" then
      def.stack = rest
    elseif word == "row" then
      local parts = {}
      for p in rest:gmatch("%S+") do parts[#parts + 1] = p end
      local copy
      if parts[1] == "first" or parts[1] == "extra" then copy = table.remove(parts, 1) end
      local op, stat, value = parts[1], parts[2], tonumber(parts[3])
      stat = Stats.ALIAS[stat] or stat
      if (op == "add" or op == "mul" or op == "set") and Stats.INFO[stat] and value then
        def.rows[#def.rows + 1] = { op = op, stat = stat, value = value, copy = copy }
      end
    elseif word == "trigger" then
      local when, effect, props = rest:match("^(%S+)%s+(%S+)%s*(.*)$")
      if when then
        local t = { when = when, effect = effect, params = {} }
        for k, v in props:gmatch("([%w_]+)=(%S+)") do
          if k == "chance" then t.chance = tonumber(v)
          elseif k == "cd" then t.cd = tonumber(v)
          else t.params[k] = tonumber(v) or v end
        end
        def.triggers[#def.triggers + 1] = t
      end
    end
  end
  if first then return nil, "empty card" end
  return def
end

function CardData.serialize(def)
  local out = { CardData.HEADER, "name " .. def.name, "rarity " .. (def.rarity or "common") }
  if def.block then out[#out + 1] = "block" end
  if def.special then out[#out + 1] = "special " .. def.special end
  for _, r in ipairs(def.rows) do
    out[#out + 1] = "row " .. (r.copy and (r.copy .. " ") or "") .. r.op .. " " .. r.stat .. " " .. fmt(r.value)
  end
  for _, t in ipairs(def.triggers) do
    local keys = {}
    for k in pairs(t.params or {}) do keys[#keys + 1] = k end
    table.sort(keys)
    local parts = { "trigger", t.when, t.effect }
    for _, k in ipairs(keys) do parts[#parts + 1] = k .. "=" .. fmt(t.params[k]) end
    if t.chance and t.chance < 1 then parts[#parts + 1] = "chance=" .. fmt(t.chance) end
    if t.cd and t.cd > 0 then parts[#parts + 1] = "cd=" .. fmt(t.cd) end
    out[#out + 1] = table.concat(parts, " ")
  end
  for _, n in ipairs(def.notes) do out[#out + 1] = "note " .. n end
  if def.stack then out[#out + 1] = "stack " .. def.stack end
  return table.concat(out, "\n") .. "\n"
end

-- Apply one copy of a card's rows to a stats table. copyIndex: 1 for the first copy.
function CardData.applyRows(def, s, copyIndex)
  for _, r in ipairs(def.rows) do
    if not r.copy or (r.copy == "first" and copyIndex == 1) or (r.copy == "extra" and copyIndex > 1) then
      local cur = s[r.stat] or 0
      if r.op == "add" then
        s[r.stat] = cur + r.value
      elseif r.op == "mul" then
        s[r.stat] = cur * r.value
      else
        s[r.stat] = r.value
      end
    end
  end
end

-- The card's text lines: generated stat lines, trigger lines, then notes.
-- Returns lines and a parallel list of colours (true good / false bad / nil neutral).
function CardData.lines(def)
  local Triggers = require "game.triggers"
  local lines, good = {}, {}
  for _, r in ipairs(def.rows) do
    if r.copy ~= "extra" then
      local text, g = Stats.describe(r)
      if text then
        lines[#lines + 1] = text
        good[#lines] = g
      end
    end
  end
  for _, t in ipairs(def.triggers) do
    lines[#lines + 1] = Triggers.describe(t)
    good[#lines] = true
  end
  for _, n in ipairs(def.notes) do
    lines[#lines + 1] = n
    local c = n:sub(1, 1)
    good[#lines] = (c == "+" and true) or (c == "-" and false) or nil
  end
  return lines, good
end

-- What extra copies do (generated from "extra" rows when the card doesn't say).
function CardData.stackText(def)
  if def.stack then return def.stack end
  local parts = {}
  for _, r in ipairs(def.rows) do
    if r.copy == "extra" then
      local text = Stats.describe(r)
      if text then parts[#parts + 1] = text end
    end
  end
  if #parts > 0 then return "extra copies: " .. table.concat(parts, ", ") end
  return nil
end

-- A playable card from a definition.
function CardData.build(def)
  local card = {
    name = def.name, rarity = def.rarity, baseRarity = def.rarity, block = def.block,
    special = def.special, def = def, triggers = def.triggers,
  }
  card.lines, card.lineGood = CardData.lines(def)
  card.stack = CardData.stackText(def)
  card.apply = function(s, copyIndex) CardData.applyRows(def, s, copyIndex or 1) end
  return card
end

function CardData.encodeShare(def)
  local packed = love.data.compress("string", "zlib", CardData.serialize(def), 9)
  return CardData.SHARE_PREFIX .. love.data.encode("string", "base64", packed)
end

function CardData.decodeShare(code)
  code = (code or ""):gsub("%s+", "")
  local body = code:match("^DSCARD1:(.+)$")
  if not body then return nil, "That isn't a card code" end
  local ok, packed = pcall(love.data.decode, "string", "base64", body)
  if not ok then return nil, "The card code is damaged" end
  local ok2, text = pcall(love.data.decompress, "string", "zlib", packed)
  if not ok2 then return nil, "The card code is damaged" end
  return CardData.parse(text)
end

return CardData
