-- Network message codec and transports.
-- A transport has :send(peer, data, reliable) and :receive() -> { {from=, data=}, ... }.
-- The Steam transport lives in session.lua; the loopback one here is for offline testing.
local bit = require "core.bit"

local pack, unpack = love.data.pack, love.data.unpack

local net = {}

net.MSG = {
  INPUT = 1,    -- client -> host, unreliable
  SNAPSHOT = 2, -- host -> clients, unreliable (see snapshot.lua)
  START = 3,    -- host -> clients: player slots, rounds to win
  ROSTER = 4,   -- host -> clients: everyone's cards
  RULES = 5,    -- host -> clients: gameplay rules (cards offered, picks, rarities, disabled cards)
  CHOOSE = 6,   -- client -> host: chosen option (the current pick itself travels in snapshots)
  TOAST = 7,    -- host -> clients: message banner
  TOLOBBY = 8,  -- host -> clients: return to the lobby
  VOTE = 9,     -- client -> host: match-over vote (continue / new match)
  DISCARD = 10, -- client -> host: discard an owned card instead of picking
  MAPS = 11,    -- host -> clients: the map list (full text for custom / edited maps), zlib
  CARDS = 12,   -- host -> clients: the card list (full text for custom / edited cards), zlib
  SYNERGIES = 13, -- host -> clients: the synergy list (full text for custom / edited ones), zlib
  PING = 14,    -- client -> host: a timestamp, echoed back as PONG (round-trip time)
  PONG = 15,
  STREAKS = 16, -- host -> clients: lobby win counts and streaks, by current peer id
  KILL = 17,    -- host -> clients: kill feed entry (victim slot, killer slot or 0, cause)
}
local M = net.MSG

function net.kind(data)
  return data:byte(1)
end

local function truncate(s, n)
  s = tostring(s or "")
  if #s > n then s = s:sub(1, n) end
  return s
end

---------------------------------------------------------------- input
function net.encodeInput(s, seq)
  local flags = bit.bor(
    s.left and 1 or 0, s.right and 2 or 0, s.down and 4 or 0,
    s.fire and 8 or 0, s.jumpHeld and 16 or 0, s.meleeHeld and 32 or 0, s.up and 64 or 0)
  return pack("string", "<BI4BfI4I4I4I4BH", M.INPUT, seq, flags, s.aim or 0, s.jumpCount, s.blockCount,
    s.dashCount or 0, s.meleeCount or 0, math.max(0, math.min(255, s.pickHover or 0)),
    math.max(0, math.min(65535, math.floor(s.ping or 0))))
end

-- Returns the packet's sequence number.
function net.decodeInput(data, s)
  local _, seq, flags, aim, jc, bc, dc, mc, hover, ping = unpack("<BI4BfI4I4I4I4BH", data)
  s.ping = ping
  s.up = bit.band(flags, 64) ~= 0
  s.left = bit.band(flags, 1) ~= 0
  s.right = bit.band(flags, 2) ~= 0
  s.down = bit.band(flags, 4) ~= 0
  s.fire = bit.band(flags, 8) ~= 0
  s.jumpHeld = bit.band(flags, 16) ~= 0
  s.meleeHeld = bit.band(flags, 32) ~= 0
  s.dashCount = dc
  s.meleeCount = mc
  s.aim = aim
  s.jumpCount = jc
  s.blockCount = bc
  s.pickHover = hover
  return seq
end

---------------------------------------------------------------- start
-- slots: list of { peer = id string, name = string, color = palette index (final, after teams),
-- team = 1 / 2 / nil, bot = difficulty or nil }
function net.encodeStart(winScore, slots)
  local parts = { pack("string", "<BHB", M.START, winScore, #slots) }
  for _, s in ipairs(slots) do
    parts[#parts + 1] = pack("string", "<s1s1BBB", truncate(s.peer, 40), truncate(s.name, 64), s.color or 0,
      s.team or 0, s.bot or 0)
  end
  return table.concat(parts)
end

function net.decodeStart(data)
  local _, winScore, n, pos = unpack("<BHB", data)
  local slots = {}
  for i = 1, n do
    local peer, name, color, team, bot
    peer, name, color, team, bot, pos = unpack("<s1s1BBB", data, pos)
    slots[i] = { peer = peer, name = name, color = color > 0 and color or nil, team = team > 0 and team or nil,
      bot = bot > 0 and bot or nil }
  end
  return winScore, slots
end

---------------------------------------------------------------- roster
function net.encodeRoster(players)
  local parts = { pack("string", "<BB", M.ROSTER, #players) }
  for _, p in ipairs(players) do
    local ids = {}
    for i, c in ipairs(p.cards) do ids[i] = string.char(c.index) end
    parts[#parts + 1] = pack("string", "<BH", p.disconnected and 1 or 0, #p.cards)
    parts[#parts + 1] = table.concat(ids)
  end
  return table.concat(parts)
end

-- Returns { { disconnected = bool, cards = { index, ... } }, ... }
function net.decodeRoster(data)
  local _, n, pos = unpack("<BB", data)
  local list = {}
  for i = 1, n do
    local disc, count
    disc, count, pos = unpack("<BH", data, pos)
    local cards = {}
    for k = 1, count do cards[k] = data:byte(pos + k - 1) end
    pos = pos + count
    list[i] = { disconnected = disc == 1, cards = cards }
  end
  return list
end

---------------------------------------------------------------- picks
function net.encodeChoose(optionIndex, serial)
  return pack("string", "<BBB", M.CHOOSE, optionIndex, serial or 0)
end

-- Returns optionIndex, serial.
function net.decodeChoose(data)
  local _, idx, serial = unpack("<BBB", data)
  return idx, serial
end

---------------------------------------------------------------- rules
-- rules: see Cards.applyRules. Card overrides are one byte per card:
-- rarity index (1-5), +128 when the card is disabled.
function net.encodeRules(rules, cards, rarities)
  local rarityIndex = {}
  for i, r in ipairs(rarities) do rarityIndex[r.id] = i end
  local parts = { pack("string", "<BBB", M.RULES, rules.pickFrom, rules.picksPerRound), string.char(#rarities) }
  for i = 1, #rarities do
    parts[#parts + 1] = pack("string", "<H", math.max(0, math.min(65535, rules.weights[i] or 0)))
  end
  parts[#parts + 1] = pack("string", "<H", #cards)
  for _, c in ipairs(cards) do
    local b = rarityIndex[rules.rarity[c.index] or c.baseRarity] or 1
    if rules.disabled[c.index] then b = b + 128 end
    parts[#parts + 1] = string.char(b)
  end
  parts[#parts + 1] = pack("string", "<BBBBB", rules.startCards or 0, math.min(255, rules.pickTimer or 0),
    rules.allowDiscard and 1 or 0, rules.hazards == false and 0 or 1, rules.barrier == false and 0 or 1)
  -- Synergies: on/off, then one byte per synergy (1 = turned off).
  local syn = require "game.synergies"
  parts[#parts + 1] = pack("string", "<BH", rules.synergies == false and 0 or 1, #syn.list)
  for i = 1, #syn.list do parts[#parts + 1] = string.char((rules.synergyOff and rules.synergyOff[i]) and 1 or 0) end
  return table.concat(parts)
end

function net.decodeRules(data, rarities)
  local _, pickFrom, picks, nr, pos = unpack("<BBBB", data)
  local rules = { pickFrom = pickFrom, picksPerRound = picks, weights = {}, rarity = {}, disabled = {} }
  for i = 1, nr do
    rules.weights[i], pos = unpack("<H", data, pos)
  end
  local nc
  nc, pos = unpack("<H", data, pos)
  for i = 1, nc do
    local b = data:byte(pos + i - 1)
    local r = rarities[b % 128]
    rules.rarity[i] = r and r.id
    rules.disabled[i] = b >= 128 or nil
  end
  pos = pos + nc
  local discard, hazards, barrier
  rules.startCards, rules.pickTimer, discard, hazards, barrier = unpack("<BBBBB", data, pos)
  rules.allowDiscard = discard == 1
  rules.hazards = hazards == 1
  rules.barrier = barrier == 1
  local synOn, nsyn
  synOn, nsyn, pos = unpack("<BH", data, pos + 5)
  rules.synergies = synOn == 1
  rules.synergyOff = {}
  for i = 1, nsyn do
    if data:byte(pos + i - 1) == 1 then rules.synergyOff[i] = true end
  end
  return rules
end

function net.encodeDiscard(cardPos, serial)
  return pack("string", "<BBB", M.DISCARD, cardPos, serial)
end

function net.decodeDiscard(data)
  local _, cardPos, serial = unpack("<BBB", data)
  return cardPos, serial
end

-- entries: { { id = string, text = string or nil } } (see Map.sessionEntries / Cards.sessionEntries)
local function encodeEntries(kind, entries)
  local parts = { pack("string", "<H", #entries) }
  for _, e in ipairs(entries) do
    parts[#parts + 1] = pack("string", "<s1", e.id:sub(1, 255))
    parts[#parts + 1] = pack("string", "<s4", e.text or "")
  end
  return string.char(kind) .. love.data.compress("string", "zlib", table.concat(parts), 6)
end

function net.encodeMaps(entries) return encodeEntries(M.MAPS, entries) end
function net.encodeCards(entries) return encodeEntries(M.CARDS, entries) end
function net.encodeSynergies(entries) return encodeEntries(M.SYNERGIES, entries) end

function net.decodeMaps(data)
  local raw = love.data.decompress("string", "zlib", data:sub(2))
  local n, pos = unpack("<H", raw)
  local out = {}
  for i = 1, n do
    local id, text
    id, pos = unpack("<s1", raw, pos)
    text, pos = unpack("<s4", raw, pos)
    out[i] = { id = id, text = text ~= "" and text or nil }
  end
  return out
end

net.decodeCards = function(data) return net.decodeMaps(data) end

-- list: { { id = peer, wins = n, streak = n } }
function net.encodeStreaks(list)
  local parts = { pack("string", "<BB", M.STREAKS, #list) }
  for _, e in ipairs(list) do parts[#parts + 1] = pack("string", "<s1HH", e.id:sub(1, 255), e.wins, e.streak) end
  return table.concat(parts)
end

function net.decodeStreaks(data)
  local _, n, pos = unpack("<BB", data)
  local out = {}
  for i = 1, n do
    local id, wins, streak
    id, wins, streak, pos = unpack("<s1HH", data, pos)
    out[id] = { wins = wins, streak = streak }
  end
  return out
end

function net.encodeKill(victim, killer, kind)
  return pack("string", "<BBBs1", M.KILL, victim, killer or 0, (kind or ""):sub(1, 30))
end

function net.decodeKill(data)
  local _, victim, killer, kind = unpack("<BBBs1", data)
  return victim, killer > 0 and killer or nil, kind ~= "" and kind or nil
end

function net.encodePing(kind, t)
  return pack("string", "<Bd", kind, t)
end

function net.decodePing(data)
  local _, t = unpack("<Bd", data)
  return t
end

function net.encodeVote(choice)
  return pack("string", "<BB", M.VOTE, choice)
end

function net.decodeVote(data)
  local _, choice = unpack("<BB", data)
  return choice
end

---------------------------------------------------------------- misc
function net.encodeToast(text, colorCode)
  return pack("string", "<Bs2B", M.TOAST, truncate(text, 300), colorCode or 0)
end

function net.decodeToast(data)
  local _, text, code = unpack("<Bs2B", data)
  return text, code
end

function net.encodeToLobby()
  return string.char(M.TOLOBBY)
end

---------------------------------------------------------------- loopback transport
-- An in-process "network" for tests: hub:endpoint(id) returns a transport.
-- Unreliable packets are dropped with probability `loss`.
function net.loopback(loss)
  local hub = { queues = {}, loss = loss or 0 }
  function hub:endpoint(id)
    hub.queues[id] = {}
    local ep = { id = id }
    function ep:send(peer, data, reliable)
      local q = hub.queues[peer]
      if not q then return end
      if not reliable and love.math.random() < hub.loss then return end
      q[#q + 1] = { from = id, data = data }
    end
    function ep:receive()
      local q = hub.queues[id]
      hub.queues[id] = {}
      return q
    end
    return ep
  end
  return hub
end

return net
