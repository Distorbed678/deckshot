-- The authoritative match simulation (used for local play and by the online host).
-- Rendering and networking live in screens/match.lua; this file only runs the game.
local Player = require "game.player"
local Map = require "game.map"
local Cards = require "game.cards"
local fx = require "gfx.fx"

local World = {}
World.__index = World

World.COLORS = {
  { 1, 0.55, 0.15 },
  { 0.25, 0.6, 1 },
  { 0.35, 0.9, 0.4 },
  { 1, 0.4, 0.75 },
}
World.CONTINUE_ROUNDS = 3

-- Match-over votes (a suggestion to the host): 0 none, 1 continue, 2 new match.
World.VOTE_CONTINUE, World.VOTE_NEW = 1, 2
World.VOTE_NAMES = { "Continue", "New Match" }

-- Toast colour codes (also sent over the network): 0 white, 1-4 player slot, 5 legendary.
function World.toastColor(code)
  if code and code >= 1 and code <= 4 then return World.COLORS[code] end
  if code == 5 then return Cards.rarity.legendary.color end
  return { 1, 1, 1 }
end

-- defs: list of { name = string, input = input state, peer = optional network id }
-- rules: gameplay rules (see Cards.applyRules); defaults to Cards.rules.
function World.new(defs, winScore, rules)
  local w = setmetatable({
    players = {}, bullets = {}, pending = {}, wells = {},
    state = "countdown", timer = 0,
    winScore = winScore,
    startScore = winScore,
    rules = rules or Cards.rules,
    pick = nil,       -- the card pick in progress: { slot, options, hover, num, total, serial }
    pickQueue = {},   -- upcoming picks: { slot, num, total }
    pickSerial = 0,   -- bumped on every new hand (u8), so stale choices can be ignored
    votes = {},       -- slot -> World.VOTE_* while the match is over
    on = {},
  }, World)
  for i, d in ipairs(defs) do
    local p = Player.new(i, World.COLORS[i], d.input)
    p.slot = i
    p.name = d.name
    p.peer = d.peer
    w.players[i] = p
  end
  return w
end

function World:emit(event, ...)
  local f = self.on[event]
  if f then f(...) end
end

function World:toast(text, colorCode)
  self:emit("toast", text, colorCode or 0)
end

function World:addBullet(b)
  table.insert(self.pending, b)
end

-- Living, connected players other than p.
function World:enemiesOf(p)
  local list = {}
  for _, e in ipairs(self.players) do
    if e ~= p and not e.dead then list[#list + 1] = e end
  end
  return list
end

function World:nearestEnemy(p, x, y, visibleOnly)
  local best, bestD
  for _, e in ipairs(self.players) do
    if e ~= p and not e.dead and not (visibleOnly and e.cloakTimer > 0) then
      local dx, dy = e.x - x, e.y - y
      local d = dx * dx + dy * dy
      if not bestD or d < bestD then best, bestD = e, d end
    end
  end
  return best
end

function World:startRound()
  self.map, self.mapIndex = Map.random(self.mapIndex, self.rules.maps)
  -- Everything players and bullets collide with: the map's rects (objects add to this later).
  self.solids = {}
  for i, r in ipairs(self.map.rects) do self.solids[i] = r end
  self.bullets = {}
  self.pending = {}
  self.wells = {}
  fx.clear()
  for i, p in ipairs(self.players) do
    local s = self.map.spawns[i]
    p:spawn(s[1], s[2], s[1] < 640 and 1 or -1, self)
    if p.disconnected then
      p.dead = true
      p.hp = 0
    end
  end
  self.pick = nil
  self.pickQueue = {}
  self.roundWinner = nil
  self.state = "countdown"
  self.timer = 2.4
  self:emit("roster")
end

function World:update(dt)
  if self.state == "countdown" then
    self.timer = self.timer - dt
    for _, p in ipairs(self.players) do p:update(dt, true) end
    if self.timer <= 0 then self.state = "playing" end
  elseif self.state == "playing" or self.state == "roundOver" then
    local sdt = (self.state == "roundOver") and dt * 0.35 or dt
    for _, p in ipairs(self.players) do p:update(sdt, false) end
    for i = #self.bullets, 1, -1 do
      local b = self.bullets[i]
      if not b.dead then b:update(sdt, self) end
      if b.dead then table.remove(self.bullets, i) end
    end
    for _, b in ipairs(self.pending) do table.insert(self.bullets, b) end
    self.pending = {}
    for i = #self.wells, 1, -1 do
      local w = self.wells[i]
      w.t = w.t - sdt
      if w.t <= 0 then table.remove(self.wells, i) end
    end
    if self.state == "playing" then
      self:checkRoundEnd()
    else
      self.timer = self.timer - dt
      if self.timer <= 0 then self:afterRound() end
    end
  end
end

function World:connectedCount()
  local n = 0
  for _, p in ipairs(self.players) do
    if not p.disconnected then n = n + 1 end
  end
  return n
end

function World:checkRoundEnd()
  local alive, last = 0, nil
  for _, p in ipairs(self.players) do
    if not p.dead and not p.disconnected then
      alive = alive + 1
      last = p
    end
  end
  if alive > 1 then return end
  self.roundWinner = last
  if last then last.score = last.score + 1 end
  self.state = "roundOver"
  self.timer = 1.6
end

function World:afterRound()
  if self.roundWinner and self.roundWinner.score >= self.winScore then
    self.state = "matchOver"
    self.votes = {}
    self:emit("matchOver", self.roundWinner)
  else
    self:openPicks()
  end
end

-- Every connected player except the round winner picks cards, one player at a
-- time: lowest score first (ties by slot), each making all their picks in a row.
-- A draw skips picks.
function World:openPicks()
  if not self.roundWinner then return self:startRound() end
  local pickers = {}
  for _, p in ipairs(self.players) do
    if p ~= self.roundWinner and not p.disconnected then pickers[#pickers + 1] = p end
  end
  table.sort(pickers, function(a, b)
    if a.score ~= b.score then return a.score < b.score end
    return a.slot < b.slot
  end)
  local total = math.max(1, self.rules.picksPerRound or 1)
  self.pickQueue = {}
  for _, p in ipairs(pickers) do
    for num = 1, total do
      self.pickQueue[#self.pickQueue + 1] = { slot = p.slot, num = num, total = total }
    end
  end
  self.state = "cardPick"
  self:nextPick()
end

function World:dealPick(slot, num, total)
  local options = Cards.deal(self.rules.pickFrom or 3, self.players[slot])
  if #options == 0 then return false end
  self.pickSerial = (self.pickSerial + 1) % 256
  self.pick = {
    slot = slot, options = options, hover = math.ceil(#options / 2),
    num = num, total = total, serial = self.pickSerial,
  }
  self:emit("pick", slot, options)
  return true
end

-- Hand the next queued pick out, or start the next round when nobody is left.
function World:nextPick()
  self.pick = nil
  while #self.pickQueue > 0 do
    local q = table.remove(self.pickQueue, 1)
    if not self.players[q.slot].disconnected and self:dealPick(q.slot, q.num, q.total) then return end
  end
  self:startRound()
end

-- Slots still waiting for their turn (not counting the current picker).
function World:queuedPickers()
  local list, seen = {}, {}
  if self.pick then seen[self.pick.slot] = true end
  for _, q in ipairs(self.pickQueue) do
    if not seen[q.slot] then
      seen[q.slot] = true
      list[#list + 1] = q.slot
    end
  end
  return list
end

-- The current picker moved their selection (shown to everyone).
function World:hover(slot, index)
  local pk = self.pick
  if self.state == "cardPick" and pk and pk.slot == slot and pk.options[index] then pk.hover = index end
end

-- serial: optional; a choice made for an older hand is ignored.
function World:choose(slot, optionIndex, serial)
  if self.state ~= "cardPick" then return end
  local pk = self.pick
  if not pk or pk.slot ~= slot then return end
  if serial and serial ~= pk.serial then return end
  local card = pk.options[optionIndex]
  if not card then return end
  local p = self.players[slot]

  if card.special == "reroll" then
    if not self:dealPick(slot, pk.num, pk.total) then self:nextPick() end
    return
  elseif card.special == "tableflip" then
    self:toast(Cards.tableFlip(p), slot)
  elseif card.special == "shrine" then
    self:toast(Cards.shrine(p), 5)
  else
    p:addCard(card)
  end
  self:emit("roster")
  self:nextPick()
end

-- New gameplay rules (from the settings), used from the next deal on.
function World:setRules(rules)
  self.rules = rules
end

-- A player's match-over vote. The host sees the tally but still decides.
function World:vote(slot, choice)
  local p = self.players[slot]
  if self.state ~= "matchOver" or not p or p.disconnected then return end
  if choice == World.VOTE_CONTINUE or choice == World.VOTE_NEW then self.votes[slot] = choice end
end

-- { [World.VOTE_CONTINUE] = n, [World.VOTE_NEW] = n }
function World.tally(votes)
  local t = { 0, 0 }
  for _, v in pairs(votes) do
    if t[v] then t[v] = t[v] + 1 end
  end
  return t
end

function World:continueMatch()
  if self.state ~= "matchOver" then return end
  self.votes = {}
  self.winScore = self.winScore + World.CONTINUE_ROUNDS
  self:toast("CONTINUE! First to " .. self.winScore)
  self:openPicks()
end

function World:newMatch()
  self.votes = {}
  for _, p in ipairs(self.players) do
    p.cards = {}
    p.score = 0
    p:recompute()
  end
  self.winScore = self.startScore
  self.mapIndex = nil
  self:startRound()
end

-- A network player left: they sit out the rest of the match.
function World:disconnect(slot)
  local p = self.players[slot]
  if not p or p.disconnected then return end
  p.disconnected = true
  if not p.dead then
    fx.burst(p.x, p.y, p.color, 30, 300, 5)
    p.dead = true
    p.hp = 0
  end
  for i = #self.pickQueue, 1, -1 do
    if self.pickQueue[i].slot == slot then table.remove(self.pickQueue, i) end
  end
  if self.state == "cardPick" and self.pick and self.pick.slot == slot then self:nextPick() end
end

return World
