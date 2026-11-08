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
    s.fire and 8 or 0, s.jumpHeld and 16 or 0, s.meleeHeld and 32 or 0)
  return pack("string", "<BI4BfI4I4I4I4B", M.INPUT, seq, flags, s.aim or 0, s.jumpCount, s.blockCount,
    s.dashCount or 0, s.meleeCount or 0, math.max(0, math.min(255, s.pickHover or 0)))
end

-- Returns the packet's sequence number.
function net.decodeInput(data, s)
  local _, seq, flags, aim, jc, bc, dc, mc, hover = unpack("<BI4BfI4I4I4I4B", data)
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
-- slots: list of { peer = id string, name = string }
function net.encodeStart(winScore, slots)
  local parts = { pack("string", "<BHB", M.START, winScore, #slots) }
  for _, s in ipairs(slots) do
    parts[#parts + 1] = pack("string", "<s1s1", truncate(s.peer, 40), truncate(s.name, 64))
  end
  return table.concat(parts)
end

function net.decodeStart(data)
  local _, winScore, n, pos = unpack("<BHB", data)
  local slots = {}
  for i = 1, n do
    local peer, name
    peer, name, pos = unpack("<s1s1", data, pos)
    slots[i] = { peer = peer, name = name }
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
  return rules
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
