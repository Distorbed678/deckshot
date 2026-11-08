-- The authoritative match simulation (used for local play and by the online host).
-- Rendering and networking live in screens/match.lua; this file only runs the game.
local Player = require "game.player"
local Map = require "game.map"
local Cards = require "game.cards"
local Objects = require "game.objects"
local Bot = require "game.bot"
local fx = require "gfx.fx"
local sfx = require "gfx.sfx"

local World = {}
World.__index = World

-- Player colours players can choose (lobby / local setup). No two players share one.
World.PALETTE = {
  { 1, 0.55, 0.15 },   -- orange
  { 0.25, 0.6, 1 },    -- blue
  { 0.35, 0.9, 0.4 },  -- green
  { 1, 0.4, 0.75 },    -- pink
  { 0.95, 0.25, 0.25 },-- red
  { 0.2, 0.9, 0.9 },   -- cyan
  { 1, 0.9, 0.25 },    -- yellow
  { 0.65, 0.45, 1 },   -- purple
  { 0.95, 0.95, 0.95 },-- white
  { 0.6, 0.85, 0.2 },  -- lime
  { 0.2, 0.45, 0.85 }, -- navy
  { 0.75, 0.5, 0.3 },  -- brown
}
World.PALETTE_NAMES = { "Orange", "Blue", "Green", "Pink", "Red", "Cyan", "Yellow", "Purple", "White", "Lime", "Navy", "Brown" }
-- Teams mode: team 1 gets warm colours, team 2 cool ones.
World.TEAM_COLORS = { { 5, 1, 7, 12 }, { 2, 6, 11, 8 } }
World.TEAM_NAMES = { "Red Team", "Blue Team" }

-- The colour of each slot this match (World.setSlotColors); used everywhere players are drawn.
World.COLORS = { World.PALETTE[1], World.PALETTE[2], World.PALETTE[3], World.PALETTE[4] }

-- colorIndex per slot (palette indices). Duplicates are replaced by the first free colour.
function World.setSlotColors(indices)
  local used = {}
  for i = 1, 4 do
    local idx = indices and indices[i]
    if not idx or not World.PALETTE[idx] or used[idx] then
      idx = nil
      for k = 1, #World.PALETTE do
        if not used[k] then idx = k break end
      end
    end
    used[idx] = true
    World.COLORS[i] = World.PALETTE[idx]
  end
end

-- Palette indices for a teams match: each team's players get that team's colours in order.
function World.teamColorIndices(teams)
  local out, count = {}, { 0, 0 }
  for i, t in ipairs(teams) do
    count[t] = count[t] + 1
    out[i] = World.TEAM_COLORS[t][count[t]]
  end
  return out
end
World.CONTINUE_ROUNDS = 3
World.COUNTDOWN, World.INTRO_TIME = 2.4, 1.4
World.SUB_ROUND_TIME = 1.5

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
    pick = nil,       -- the card pick in progress: { slot, options, hover, num, total, serial, flipped, timeLeft }
    pickQueue = {},   -- upcoming picks: { slot, num, total }
    pickSerial = 0,   -- bumped on every new hand (u8), so stale choices can be ignored
    votes = {},       -- slot -> World.VOTE_* while the match is over
    objects = {}, effects = {}, pendingBlasts = {},
    time = 0,         -- seconds of play (drives hazard cycles)
    suddenLeft = nil, -- seconds until sudden death (nil = no timer this match)
    barrierT = 0,     -- seconds since the barrier started closing
    barrier = nil,    -- { x0, y0, x1, y1 } once the barrier is closing in
    on = {},
  }, World)
  for i, d in ipairs(defs) do
    local p = Player.new(i, World.COLORS[i], d.input)
    p.slot = i
    p.name = d.name
    p.peer = d.peer
    p.team = (w.rules.teams and (d.team or ((i - 1) % 2 + 1))) or nil
    p.isBot = d.bot
    p.hat, p.eyes, p.mouth, p.detail = d.hat, d.eyes, d.mouth, d.detail
    p.subWins = 0
    w.players[i] = p
  end
  w.startPlayers = #defs
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

-- Can a hurt b? (Teammates can't, unless friendly fire is on.)
function World:isEnemy(a, b)
  if a == b then return false end
  if self.rules.teams and a.team and b.team and a.team == b.team then return self.rules.friendlyFire == true end
  return true
end

-- Living, connected players p can hurt.
function World:enemiesOf(p)
  local list = {}
  for _, e in ipairs(self.players) do
    if not e.dead and self:isEnemy(p, e) then list[#list + 1] = e end
  end
  return list
end

-- Opponents for AI and homing: other team's players (teammates never, even with friendly fire).
function World:nearestEnemy(p, x, y, visibleOnly)
  local best, bestD
  for _, e in ipairs(self.players) do
    if e ~= p and not e.dead and not (visibleOnly and e.cloakTimer > 0)
        and not (self.rules.teams and p.team and e.team == p.team) then
      local dx, dy = e.x - x, e.y - y
      local d = dx * dx + dy * dy
      if not bestD or d < bestD then best, bestD = e, d end
    end
  end
  return best
end

-- Pick a map and build the collision list.
function World:loadMap()
  if self.rules.forceMap then
    self.map, self.mapIndex = self.rules.forceMap, self.rules.forceMap.index or 0
  elseif self.keepMap and self.map then
    self.keepMap = nil
  elseif self.nextMap and Map.list[self.nextMap] then
    self.map, self.mapIndex = Map.list[self.nextMap], self.nextMap
    self.nextMap = nil
  else
    self.map, self.mapIndex = Map.random(self.mapIndex, self.rules.maps)
  end
  -- Objects come back fresh every round. With hazards off, hazards (and ropes holding them) sit out.
  self.objects = Objects.build(self.map)
  if self.rules.hazards == false then
    for _, o in ipairs(self.objects) do
      if Objects.HAZARD[o.type] or (o.type == "rope" and o.held and Objects.HAZARD[o.held.type]) then o.alive = false end
    end
  end
  self.effects, self.pendingBlasts = {}, {}
  self.barrier, self.barrierT, self.barrierStart = nil, 0, nil
  local sd = self.rules.suddenDeath
  self.suddenLeft = (sd and sd > 0) and sd or nil
  -- Everything players and bullets collide with: the map's rects plus solid objects.
  Objects.rebuildSolids(self)
end

-- Put everyone on the current map's spawns (for screens that show the arena behind them).
function World:placePlayers()
  self.bullets, self.pending, self.wells = {}, {}, {}
  for i, p in ipairs(self.players) do
    local s = self.map.spawns[i]
    p:spawn(s[1], s[2], s[1] < Map.W / 2 and 1 or -1, self)
    if p.disconnected then p.dead, p.hp = true, 0 end
  end
end

-- Start of a match: card bans (if the host turned them on), starting cards, then round 1.
function World:beginMatch()
  self.roundCount = 0
  self:clearBans()
  if self.rules.cardBans and not self.rules.practice then return self:openCardBan() end
  self:afterBans()
end

-- Everyone picks their starting cards (rules.startCards, slot order), then round 1.
function World:afterBans()
  local n = self.rules.startCards or 0
  if n <= 0 then return self:startRound() end
  self:loadMap()
  self:placePlayers()
  self.roundWinner = nil
  self.pickQueue = {}
  for _, p in ipairs(self.players) do
    if not p.disconnected then
      for num = 1, n do
        self.pickQueue[#self.pickQueue + 1] = { slot = p.slot, num = num, total = n, start = true }
      end
    end
  end
  self.state = "cardPick"
  self:emit("roster")
  self:nextPick()
end

-- The next round: through the map vote when the host has it on.
function World:startRound()
  if self.rules.mapVote and not self.rules.forceMap and #Map.list > 1 then return self:openMapVote() end
  self:beginRound()
end

-- sameMap: the next sub-round on this map (everything on it is rebuilt).
function World:beginRound(sameMap)
  self.mapVote = nil
  self.keepMap = sameMap
  self:loadMap()
  self.bullets = {}
  self.pending = {}
  self.wells = {}
  fx.clear()
  for i, p in ipairs(self.players) do
    local s = self.map.spawns[i]
    p:spawn(s[1], s[2], s[1] < Map.W / 2 and 1 or -1, self)
    if p.disconnected then
      p.dead = true
      p.hp = 0
    end
  end
  self.pick = nil
  self.pickQueue = {}
  self.roundWinner = nil
  self.state = "countdown"
  self.roundCount = (self.roundCount or 0) + 1
  -- The first round opens with the versus intro (World.INTRO_TIME before the 3-2-1).
  self.timer = World.COUNTDOWN + ((self.roundCount == 1 and not self.rules.practice) and World.INTRO_TIME or 0)
  self:setupHill()
  if not sameMap then self:announceMatchPoint() end
  self:emit("roster")
end

function World:announceMatchPoint()
  if self.rules.practice then return end
  local names = {}
  for _, p in ipairs(self.players) do
    if not p.disconnected and p.score == self.winScore - 1 then
      names[#names + 1] = (self.rules.teams and p.team) and World.TEAM_NAMES[p.team] or (p.name or "Player")
    end
  end
  if #names == 0 then return end
  local seen, list = {}, {}
  for _, n in ipairs(names) do
    if not seen[n] then seen[n] = true; list[#list + 1] = n end
  end
  self:toast("MATCH POINT: " .. table.concat(list, ", "), 5)
  sfx.play("stingerMatchPoint")
end

---------------------------------------------------------------- map vote
World.MAP_VOTE_SHOW = 1.4

function World:openMapVote()
  if not self.map then
    self:loadMap()
    self:placePlayers()
  end
  local pool = {}
  for i in ipairs(Map.list) do
    if not (self.rules.maps and self.rules.maps[i]) and i ~= self.mapIndex then pool[#pool + 1] = i end
  end
  if #pool == 0 then return self:beginRound() end
  local options = {}
  for _ = 1, math.min(self.rules.mapVoteCount or 3, #pool) do
    options[#options + 1] = table.remove(pool, love.math.random(#pool))
  end
  -- The vote lasts as long as a card pick; with no pick timer it waits for everyone.
  local limit = self.rules.pickTimer or 0
  self.mapVote = { options = options, votes = {}, confirmed = {}, timeLeft = limit > 0 and limit or nil, t = 0, winner = 0 }
  self.pick = nil
  self.state = "mapVote"
end

-- confirm: locks it in. An unconfirmed selection still counts when time runs out.
function World:castMapVote(slot, option, confirm)
  local mv = self.mapVote
  local p = self.players[slot]
  if self.state ~= "mapVote" or not mv or mv.winner > 0 or not p or p.disconnected or not mv.options[option] then return end
  mv.votes[slot] = option
  if confirm then mv.confirmed[slot] = true end
end

function World:updateMapVote(dt)
  local mv = self.mapVote
  mv.t = mv.t + dt
  if mv.winner > 0 then
    mv.show = mv.show - dt
    if mv.show <= 0 then
      self.nextMap = mv.options[mv.winner]
      self:beginRound()
    end
    return
  end
  if mv.timeLeft then mv.timeLeft = mv.timeLeft - dt end
  local allIn = true
  for _, p in ipairs(self.players) do
    if not p.disconnected and not mv.confirmed[p.slot] then
      if p.isBot and mv.t > 0.5 + p.slot * 0.35 then
        mv.votes[p.slot] = love.math.random(#mv.options)
        mv.confirmed[p.slot] = true
      else
        allIn = false
      end
    end
  end
  if (not mv.timeLeft or mv.timeLeft > 0) and not allIn then return end
  -- Most votes wins; ties (and no votes at all) are random.
  local counts, best = {}, 0
  for _, o in pairs(mv.votes) do
    counts[o] = (counts[o] or 0) + 1
    best = math.max(best, counts[o])
  end
  local top = {}
  for i in ipairs(mv.options) do
    if best == 0 or counts[i] == best then top[#top + 1] = i end
  end
  mv.winner = top[love.math.random(#top)]
  mv.show = World.MAP_VOTE_SHOW
  sfx.play("cardPick")
end

---------------------------------------------------------------- card bans
World.BAN_TIME = 30

function World:clearBans()
  self.banned = {}
  for _, c in ipairs(Cards.list) do c.banned = nil end
end

function World:openCardBan()
  self.cardBan = { picks = {}, timeLeft = World.BAN_TIME, t = 0 }
  if not self.map then
    self:loadMap()
    self:placePlayers()
  end
  self.state = "cardBan"
end

function World:castBan(slot, card)
  local cb = self.cardBan
  local p = self.players[slot]
  if self.state ~= "cardBan" or not cb or not p or p.disconnected or not card or card.disabled then return end
  cb.picks[slot] = card
end

function World:updateCardBan(dt)
  local cb = self.cardBan
  cb.t = cb.t + dt
  cb.timeLeft = cb.timeLeft - dt
  local allIn = true
  for _, p in ipairs(self.players) do
    if not p.disconnected and not cb.picks[p.slot] then
      if p.isBot and cb.t > 0.6 + p.slot * 0.4 then
        cb.picks[p.slot] = Bot.banChoice(self)
      else
        allIn = false
      end
    end
  end
  if cb.timeLeft > 0 and not allIn then return end
  local names, seen = {}, {}
  self.banned = {}
  for _, p in ipairs(self.players) do
    local c = cb.picks[p.slot]
    if c and not seen[c] then
      seen[c] = true
      c.banned = true
      self.banned[#self.banned + 1] = c
      names[#names + 1] = c.name
    end
  end
  self.cardBan = nil
  if #names > 0 then self:toast("Banned: " .. table.concat(names, ", ")) end
  self:afterBans()
end

---------------------------------------------------------------- king of the hill
World.HILL = { w = 280, h = 200, target = 30, move = 20, respawn = 3 }

function World:isKoth()
  return self.rules.mode == "koth" and not self.rules.practice
end

function World:setupHill()
  self.hill = nil
  for _, p in ipairs(self.players) do p.hillScore, p.respawnT = 0, nil end
  if not self:isKoth() then return end
  self.hillPoints = Map.hillPoints(self.map)
  local pt = self.hillPoints[love.math.random(#self.hillPoints)]
  self.hill = { x = pt[1], y = pt[2], t = World.HILL.move, owner = 0 }
end

function World:moveHill()
  local h = self.hill
  local options = {}
  for _, pt in ipairs(self.hillPoints) do
    if pt[1] ~= h.x or pt[2] ~= h.y then options[#options + 1] = pt end
  end
  if #options == 0 then options = self.hillPoints end
  local pt = options[love.math.random(#options)]
  h.x, h.y, h.t = pt[1], pt[2], World.HILL.move
  sfx.play("barrier", h.x, 0.5, 1.4)
end

function World:updateHill(dt)
  local h = self.hill
  if not h or self.state ~= "playing" then return end
  local H = World.HILL
  if self.suddenLeft and self.suddenLeft <= 0 then
    -- Sudden death: the hill goes to the arena centre and stays there.
    h.x, h.y, h.t = Map.W / 2, Map.H / 2, 0
  else
    h.t = h.t - dt
    if h.t <= 0 then self:moveHill() end
  end

  -- Scoring: one side alone on the hill.
  local sides, inside, count = {}, {}, 0
  for _, p in ipairs(self.players) do
    if not p.dead and not p.disconnected and math.abs(p.x - h.x) <= H.w / 2 and math.abs(p.y - h.y) <= H.h / 2 then
      local side = p.team or -p.slot
      if not sides[side] then
        sides[side] = true
        count = count + 1
      end
      inside[#inside + 1] = p
    end
  end
  if count == 0 then
    h.owner = 0
  elseif count > 1 then
    h.owner = 255
  else
    local first = inside[1]
    h.owner = first.slot
    for _, p in ipairs(self.players) do
      if p == first or (first.team and p.team == first.team) then
        p.hillScore = (p.hillScore or 0) + dt
      end
    end
    if first.hillScore >= H.target then return self:endRound(first) end
  end

  -- Respawns (not in sudden death).
  if self.suddenLeft and self.suddenLeft <= 0 then return end
  for _, p in ipairs(self.players) do
    if p.dead and not p.disconnected then
      p.respawnT = (p.respawnT or H.respawn) - dt
      if p.respawnT <= 0 then
        p.respawnT = nil
        local score = p.hillScore
        local best, bestD
        for _, s in ipairs(self.map.spawns) do
          local d = math.huge
          for _, e in ipairs(self:enemiesOf(p)) do d = math.min(d, (e.x - s[1]) ^ 2 + (e.y - s[2]) ^ 2) end
          if not bestD or d > bestD then best, bestD = s, d end
        end
        p:spawn(best[1], best[2], best[1] < Map.W / 2 and 1 or -1, self)
        p.hillScore = score
        p.invuln = math.max(p.invuln or 0, 1)
        if self.barrier then
          local b = self.barrier
          p.x = math.max(b[1] + p.r + 4, math.min(b[3] - p.r - 4, p.x))
          p.y = math.max(b[2] + p.r + 4, math.min(b[4] - p.r - 4, p.y))
        end
      end
    end
  end
end

function World:update(dt)
  if self.state == "subRound" then
    self.timer = self.timer - dt
    if self.timer <= 0 then self:finishSubRound() end
  elseif self.state == "mapVote" then
    self:updateMapVote(dt)
  elseif self.state == "cardBan" then
    self:updateCardBan(dt)
  elseif self.state == "countdown" then
    local before = math.ceil(self.timer / 0.8)
    self.timer = self.timer - dt
    for _, p in ipairs(self.players) do p:update(dt, true) end
    local now = math.ceil(self.timer / 0.8)
    if self.timer <= 0 then
      self.state = "playing"
      sfx.play("fight")
    elseif now ~= before and self.timer <= World.COUNTDOWN then
      sfx.play("beep")
    end
  elseif self.state == "cardPick" then
    local pk = self.pick
    if pk and self.players[pk.slot] and self.players[pk.slot].isBot then Bot.pick(self, pk, dt) end
    pk = self.pick
    if pk and pk.timeLeft then
      pk.timeLeft = pk.timeLeft - dt
      if pk.timeLeft <= 0 then
        -- Out of time: take the hovered card, or a random one if it was never turned over.
        local idx = pk.flipped[pk.hover] and pk.hover or love.math.random(#pk.options)
        self:toast((self.players[pk.slot].name or "Player") .. " ran out of time", pk.slot)
        self:choose(pk.slot, idx, pk.serial)
      end
    end
  elseif self.state == "playing" or self.state == "roundOver" then
    local sdt = (self.state == "roundOver") and dt * 0.35 or dt
    self.time = self.time + sdt
    Objects.update(self, sdt)
    for _, p in ipairs(self.players) do
      if p.isBot then Bot.update(p, self, sdt) end
    end
    for _, p in ipairs(self.players) do p:update(sdt, false) end
    self:updateBarrier(sdt)
    self:updateHill(sdt)
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

-- Melee swings hit map objects too (called from Player:meleeHitCheck).
function World:meleeObjects(p, reach, heavy, power)
  Objects.melee(self, p, reach, heavy, power)
end

-- Sudden death: a countdown runs through every round (host setting rules.suddenDeath, seconds).
-- At zero a red barrier closes in from all four sides toward the arena centre and stops at a
-- small box. The settings pick how fast it closes, the box size and how much it hurts.
World.BARRIER_TIMES = { 40, 20, 10 }                          -- Slow, Normal, Fast
World.BARRIER_BOXES = { { 360, 264 }, { 504, 384 }, { 768, 528 } } -- Small, Medium, Large
World.BARRIER_DAMAGE = { 0.5, 1, 2 }                          -- Low, Normal, High
function World:updateBarrier(dt)
  if self.state ~= "playing" or not self.suddenLeft then return end
  local alive = {}
  for _, p in ipairs(self.players) do
    if not p.dead and not p.disconnected then alive[#alive + 1] = p end
  end
  if self.suddenLeft > 0 then
    local before = math.ceil(self.suddenLeft)
    self.suddenLeft = math.max(0, self.suddenLeft - dt)
    local now = math.ceil(self.suddenLeft)
    if now ~= before and now > 0 and now <= 10 then sfx.play("beep") end
    if self.suddenLeft > 0 then return end
    sfx.play("barrier")
    self:toast("SUDDEN DEATH - the walls are closing in!", 5)
    -- The top edge starts above anyone who is in the air, so nobody is snapped down by it.
    local top = 0
    for _, p in ipairs(alive) do top = math.min(top, p.y - p.r - 30) end
    self.barrierStart = top
  end
  local r = self.rules
  self.barrierT = self.barrierT + dt
  local k = math.min(1, self.barrierT / (World.BARRIER_TIMES[r.barrierClose or 2] or 20))
  local t = k * k * (3 - 2 * k)
  local box = World.BARRIER_BOXES[r.barrierBox or 2] or World.BARRIER_BOXES[2]
  local cx, cy = Map.W / 2, Map.H / 2
  local hw, hh = box[1] / 2, box[2] / 2
  local top = self.barrierStart or 0
  self.barrier = {
    (cx - hw) * t, top + (cy - hh - top) * t,
    Map.W + (cx + hw - Map.W) * t, Map.H + (cy + hh - Map.H) * t,
  }
  local damage = World.BARRIER_DAMAGE[r.barrierDamage or 2] or 1
  for _, p in ipairs(alive) do
    p:checkBounds(self.barrier[1], self.barrier[2], self.barrier[3], self.barrier[4], true, damage)
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
  if self.rules.practice or self.state ~= "playing" then return end -- the practice range never ends a round
  if self:isKoth() then
    -- Decided by holding the hill, unless everyone else has left.
    local connected, last = 0, nil
    for _, p in ipairs(self.players) do
      if not p.disconnected then
        connected = connected + 1
        last = p
      end
    end
    if connected <= 1 then return self:endRound(last) end
    -- Once sudden death starts nobody respawns, so the last side standing wins.
    if not (self.suddenLeft and self.suddenLeft <= 0) then return end
  end
  local alive, last, teams = 0, nil, {}
  for _, p in ipairs(self.players) do
    if not p.dead and not p.disconnected then
      alive = alive + 1
      last = p
      if p.team then teams[p.team] = true end
    end
  end
  if self.rules.teams then
    local n = 0
    for _ in pairs(teams) do n = n + 1 end
    if n > 1 then return end
  elseif alive > 1 then
    return
  end
  self:endRound(last)
end

-- A round is a sub-round: first player or team to rules.subRounds wins takes the point, everyone
-- else then picks a card and all progress resets.
function World:endRound(last)
  self.roundWinner = last
  local need = math.max(1, self.rules.subRounds or 1)
  self.pointWon = false
  if last then
    last.subWins = (last.subWins or 0) + 1
    if self.rules.teams and last.team then
      for _, p in ipairs(self.players) do
        if p ~= last and p.team == last.team then p.subWins = (p.subWins or 0) + 1 end
      end
    end
    self.pointWon = last.subWins >= need
  end
  sfx.play("stingerRound")
  self.state = "roundOver"
  self.timer = 1.85
end

-- The point goes on the board and everyone's sub-round progress starts again.
function World:applyPoint()
  local last = self.roundWinner
  if self.pointWon then
    for _, p in ipairs(self.players) do
      if p == last or (self.rules.teams and last.team and p.team == last.team) then p.score = p.score + 1 end
    end
    for _, p in ipairs(self.players) do p.subWins = 0 end
  end
  if self.pointWon or (self.rules.subRounds or 1) <= 1 then
    self.history = self.history or {}
    self.history[#self.history + 1] = last and last.slot or 0
  end
end

function World:afterPoint()
  if self.pointWon and self.roundWinner.score >= self.winScore then
    self.state = "matchOver"
    self.votes = {}
    sfx.play("matchWin")
    self:emit("matchOver", self.roundWinner)
  else
    self:openPicks()
  end
end

function World:afterRound()
  if (self.rules.subRounds or 1) > 1 then
    -- Always show the progress first, including the win that completes a point.
    self.state = "subRound"
    self.timer = World.SUB_ROUND_TIME
    return
  end
  self:applyPoint()
  self:afterPoint()
end

function World:finishSubRound()
  if self.pointWon then
    self:applyPoint()
    self:afterPoint()
  else
    self:beginRound(true)
  end
end

-- Every connected player except the round winner picks cards, one player at a
-- time: lowest score first (ties by slot), each making all their picks in a row.
-- A draw skips picks.
function World:openPicks()
  if not self.roundWinner then return self:startRound() end
  local pickers = {}
  local winTeam = self.rules.teams and self.roundWinner.team
  for _, p in ipairs(self.players) do
    local won = p == self.roundWinner or (winTeam and p.team == winTeam)
    if not won and not p.disconnected then pickers[#pickers + 1] = p end
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
  local timer = self.rules.pickTimer or 0
  local hover = math.ceil(#options / 2)
  self.pick = {
    slot = slot, options = options, hover = hover,
    num = num, total = total, serial = self.pickSerial,
    flipped = { [hover] = true }, -- cards are dealt face down; hovering one turns it over
    timeLeft = timer > 0 and timer or nil,
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
  if self.state == "cardPick" and pk and pk.slot == slot and pk.options[index] then
    pk.hover = index
    pk.flipped[index] = true
  end
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
    local before = {}
    for _, a in ipairs(p.synergies or {}) do before[a.syn] = a.sets end
    p:addCard(card)
    for _, a in ipairs(p.synergies or {}) do
      if (before[a.syn] or 0) < a.sets then
        self:toast("SYNERGY! " .. (p.name or "Player") .. " unlocked " .. a.syn.name, 5)
        sfx.play("revealLegendary")
      end
    end
  end
  self:emit("roster")
  self:nextPick()
end

-- Instead of taking a card, the picker removes one they own (if the host allows it).
-- cardPos: index into the player's card list.
function World:discard(slot, cardPos, serial)
  if self.state ~= "cardPick" or not self.rules.allowDiscard then return end
  local pk = self.pick
  if not pk or pk.slot ~= slot then return end
  if serial and serial ~= pk.serial then return end
  local p = self.players[slot]
  local card = p.cards[cardPos]
  if not card then return end
  table.remove(p.cards, cardPos)
  p:recompute()
  self:toast((p.name or "Player") .. " discarded " .. card.name, slot)
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
  self.nextMap = nil
  for _, p in ipairs(self.players) do
    p.cards = {}
    p.score = 0
    p.subWins = 0
    p:recompute()
  end
  self.winScore = self.startScore
  self.mapIndex = nil
  for _, p in ipairs(self.players) do p:resetStats() end
  self.history = {}
  self:beginMatch()
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
