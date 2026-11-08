-- The match screen. Three roles:
--   "local"  : 2 players on one keyboard, simulated here.
--   "host"   : online host; simulates the World, applies remote inputs, broadcasts snapshots.
--   "client" : online client; sends input, renders snapshots from the host.
local app = require "core.app"
local ui = require "core.ui"
local World = require "game.world"
local Player = require "game.player"
local Bullet = require "game.bullet"
local Map = require "game.map"
local Cards = require "game.cards"
local Input = require "core.input"
local Bloom = require "gfx.bloom"
local fx = require "gfx.fx"
local sfx = require "gfx.sfx"
local net = require "online.net"
local Snap = require "online.snapshot"
local hud = require "gfx.hud"
local active = require "online.active"
local Settings = require "core.settings"

local Match = {}
Match.__index = Match

local SNAPSHOT_INTERVAL = 1 / 30
local PICK_DELAY = 0.4 -- ignore "take" presses right after a hand appears

local function newMatch(role)
  return setmetatable({
    role = role,
    paused = false,
    toasts = {},
    pickUI = nil,   -- { slot, serial, index, delay, waiting } while this machine controls the pick
  }, Match)
end

-- Gameplay rules from this machine's settings (local play and the online host).
local function settingsRules(online)
  local rules = Settings.cardRules(online)
  Cards.applyRules(rules)
  return rules
end

---------------------------------------------------------------- construction
function Match.newLocal(winScore)
  local m = newMatch("local")
  local binds = Settings.values.binds
  m.inputs = { Input.keys(binds.p1), Input.keys(binds.p2) }
  m.world = World.new({
    { name = "Player 1", input = m.inputs[1] },
    { name = "Player 2", input = m.inputs[2] },
  }, winScore, settingsRules(false))
  m:hookWorld()
  fx.recorder = nil
  m.world:beginMatch()
  return m
end

-- slots[1] is the host. opts.popEvents overrides the session event source (tests).
function Match.newHost(slots, winScore, transport, opts)
  opts = opts or {}
  local m = newMatch("host")
  m.transport = transport
  m.popEvents = opts.popEvents or active.get().popEvents
  m.myInput = Input.mouse(Settings.values.binds.online)
  m.mySlot = 1
  m.peers = {}
  local defs = {}
  for i, s in ipairs(slots) do
    local input = (i == 1) and m.myInput or Input.remote()
    defs[i] = { name = s.name, input = input, peer = s.peer }
    if i > 1 then m.peers[s.peer] = { slot = i, seq = -1 } end
  end
  m.world = World.new(defs, winScore, settingsRules(true))
  m:hookWorld()
  m:broadcastRules()
  m.snapTimer = 0
  fx.recorder = {}
  m.world:beginMatch()
  return m
end

function Match.newClient(slots, mySlot, winScore, transport, hostPeer, pending, opts)
  opts = opts or {}
  local m = newMatch("client")
  m.transport = transport
  m.popEvents = opts.popEvents or active.get().popEvents
  m.hostPeer = hostPeer
  m.mySlot = mySlot
  m.myInput = Input.mouse(Settings.values.binds.online)
  m.inputSeq = 0
  m.pending = pending
  m.view = { state = "countdown", timer = 0, winScore = winScore, mapIndex = 1, winner = 0,
    pick = { slot = 0, queued = {}, options = {}, flipped = {} } }
  m.proxies = {}
  for i, s in ipairs(slots) do m.proxies[i] = m:newProxy(i, s.name) end
  m.bulletViews, m.bulletList, m.wellList = {}, {}, {}
  m.snapTime = love.timer.getTime()
  fx.recorder = nil
  fx.clear()
  return m
end

function Match:leave()
  self.closed = true
  fx.recorder = nil
  fx.clear()
  love.mouse.setVisible(true)
end

---------------------------------------------------------------- helpers
function Match:showToast(text, code)
  table.insert(self.toasts, { text = text, color = World.toastColor(code), t = 3.5 })
  if #self.toasts > 3 then table.remove(self.toasts, 1) end
end

function Match:broadcast(data, reliable)
  for peer, info in pairs(self.peers) do
    if not info.gone then self.transport:send(peer, data, reliable) end
  end
end

function Match:hookWorld()
  local w = self.world
  w.on.toast = function(text, code)
    self:showToast(text, code)
    if self.role == "host" then self:broadcast(net.encodeToast(text, code), true) end
  end
  w.on.roster = function()
    if self.role == "host" then self:broadcast(net.encodeRoster(w.players), true) end
  end
  w.on.matchOver = function() ui.reset() end
end

-- What to draw and the round status, for any role.
function Match:scene()
  if self.role == "client" then
    return self.proxies, self.bulletList, self.wellList, Map.list[self.view.mapIndex] or Map.list[1]
  end
  local w = self.world
  return w.players, w.bullets, w.wells, w.map
end

function Match:status()
  if self.role == "client" then
    local v = self.view
    return {
      state = v.state, timer = v.timer, winScore = v.winScore,
      winner = v.winner > 0 and self.proxies[v.winner] or nil, pick = self:currentPick(),
    }
  end
  local w = self.world
  return { state = w.state, timer = w.timer, winScore = w.winScore, winner = w.roundWinner, pick = self:currentPick() }
end

function Match:players()
  return self.role == "client" and self.proxies or self.world.players
end

---------------------------------------------------------------- card picks
-- The pick in progress, for any role:
-- { slot, serial, hover, num, total, queued = { slot... }, options = { card... } } or nil.
function Match:currentPick()
  if self.role == "client" then
    local pk = self.view.pick
    if self.view.state ~= "cardPick" or pk.slot == 0 then return nil end
    local options = {}
    for i, idx in ipairs(pk.options) do options[i] = Cards.list[idx] end
    return {
      slot = pk.slot, serial = pk.serial, hover = pk.hover, num = pk.num, total = pk.total,
      queued = pk.queued, options = options, flipped = pk.flipped, timeLeft = pk.timeLeft,
    }
  end
  local w = self.world
  local pk = w.pick
  if w.state ~= "cardPick" or not pk then return nil end
  return {
    slot = pk.slot, serial = pk.serial, hover = pk.hover, num = pk.num, total = pk.total,
    queued = w:queuedPickers(), options = pk.options, flipped = pk.flipped, timeLeft = pk.timeLeft,
  }
end

-- Does this machine make the choice for that slot?
function Match:controlsPick(slot)
  if self.role == "local" then return true end
  return slot == self.mySlot
end

-- Keep pickUI in step with the current pick and share our hover with everyone.
function Match:syncPick(dt)
  local cp = self:currentPick()
  if not cp or not self:controlsPick(cp.slot) then
    self.pickUI = nil
    self.discardMode = false
    if self.myInput then self.myInput.pickHover = 0 end
    return
  end
  local pu = self.pickUI
  if not pu or pu.serial ~= cp.serial or pu.slot ~= cp.slot then
    pu = { slot = cp.slot, serial = cp.serial, index = math.max(1, math.min(#cp.options, cp.hover)),
      delay = PICK_DELAY, waiting = false }
    self.pickUI = pu
    self.discardMode = false
  end
  pu.delay = math.max(0, pu.delay - dt)
  pu.index = math.max(1, math.min(#cp.options, pu.index))
  if self.role == "client" then
    self.myInput.pickHover = pu.index
  else
    self.world:hover(pu.slot, pu.index)
  end
end

function Match:choosePick(index)
  local pu = self.pickUI
  if not pu or pu.delay > 0 or pu.waiting then return end
  pu.index = index
  if self.role == "client" then
    pu.waiting = true
    self.transport:send(self.hostPeer, net.encodeChoose(index, pu.serial), true)
  else
    self.world:choose(pu.slot, index, pu.serial) -- the next hand (if any) is picked up by syncPick
    self.pickUI = nil
  end
end

-- Discard an owned card (cardPos in the picker's card list) instead of taking one.
function Match:discardCard(cardPos)
  local pu = self.pickUI
  if not pu or pu.delay > 0 or pu.waiting then return end
  self.discardMode = false
  if self.role == "client" then
    pu.waiting = true
    self.transport:send(self.hostPeer, net.encodeDiscard(cardPos, pu.serial), true)
  else
    self.world:discard(pu.slot, cardPos, pu.serial)
    self.pickUI = nil
  end
end

-- Can the current picker discard instead? (host rule, and they own a card)
function Match:canDiscard(slot)
  local p = self:players()[slot]
  return Cards.rules.allowDiscard and p and #p.cards > 0
end

-- The picker's distinct owned cards: { { card, pos (first index), count } }.
function Match:ownedCards(slot)
  local p = self:players()[slot]
  local list, seen = {}, {}
  for i, c in ipairs(p and p.cards or {}) do
    if seen[c] then
      seen[c].count = seen[c].count + 1
    else
      seen[c] = { card = c, pos = i, count = 1 }
      list[#list + 1] = seen[c]
    end
  end
  return list
end

-- Host / local: re-read the gameplay rules from the settings (used for New Match).
function Match:newMatch()
  self.world:setRules(settingsRules(self.role == "host"))
  self:broadcastRules()
  self.world:newMatch()
end

function Match:broadcastRules()
  if self.role == "host" then
    self:broadcast(net.encodeRules(self.world.rules, Cards.list, Cards.RARITIES), true)
  end
end

---------------------------------------------------------------- client side
function Match:newProxy(slot, name)
  return setmetatable({
    id = slot, slot = slot, name = name, color = World.COLORS[slot],
    cards = {}, score = 0,
    stats = { maxHp = 100, ammo = 3, reloadTime = 1, blockCooldown = 1, orbs = 0, stasis = 0, sentry = 0,
      meleeRange = 55, heavyCharge = 0.6 },
    stunTimer = 0, charging = false, meleeCharge = 0, swingTimer = 0, swingHeavy = false, swingPower = 0,
    dashTimer = 0, vx = 0, vy = 0,
    vote = 0, shield = 0,
    decay = { { remaining = 0 } },
    x = -1000, y = -1000, r = 20, aimX = 1, aimY = 0, facing = 1,
    hp = 100, ammo = 3, reloadTimer = 0, blockTimer = 0, blockCd = 0,
    cloakTimer = 0, invuln = 0, poisonTimer = 0, slowTimer = 0,
    empowered = false, hitFlash = 0, livesLeft = 0, orbAngle = 0, dead = true,
  }, Player)
end

function Match:applySnapshot(v)
  local now = love.timer.getTime()
  local view = self.view
  view.state, view.timer, view.winScore = v.state, v.timer, v.winScore
  view.mapIndex, view.winner, view.pick = v.mapIndex, v.winner, v.pick

  for i, pv in ipairs(v.players) do
    local p = self.proxies[i]
    if not p then
      p = self:newProxy(i, "Player " .. i)
      self.proxies[i] = p
    end
    local jump = math.abs(pv.x - p.x) + math.abs(pv.y - p.y) > 250
    if p.dead or pv.dead or jump then
      p.fromX, p.fromY = pv.x, pv.y
    else
      p.fromX, p.fromY = p.x, p.y
    end
    p.toX, p.toY = pv.x, pv.y
    p.aimX, p.aimY = math.cos(pv.aim), math.sin(pv.aim)
    p.facing = pv.facing
    p.hp = pv.hp
    p.r = pv.r
    p.dead = pv.dead
    p.blockTimer = pv.blocking and 1 or 0
    p.empowered = pv.empowered
    p.poisonTimer = pv.poisoned and 1 or 0
    p.slowTimer = pv.slowed and 1 or 0
    p.cloakTimer = pv.cloaked and 1 or 0
    p.hitFlash = pv.hitFlash and 0.1 or 0
    p.invuln = pv.invuln
    p.ammo = pv.ammo
    p.reloadTimer = pv.reload / 255
    p.blockCd = pv.blockCd / 255
    p.orbAngle = pv.orbAngle
    p.livesLeft = pv.lives
    p.decay[1].remaining = pv.pending
    p.score = pv.score
    local s = p.stats
    s.maxHp, s.ammo, s.orbs, s.stasis = pv.maxHp, pv.maxAmmo, pv.orbs, pv.stasis
    p.vote = pv.vote
    p.shield = pv.shield
    s.sentry = pv.sentry
    p.stunTimer = pv.stunned and 1 or 0
    p.charging, p.meleeCharge = pv.charging, pv.meleeCharge
    p.swingTimer, p.swingHeavy, p.swingPower = pv.swingTimer, pv.swingHeavy, pv.swingPower
    p.dashTimer = pv.dashing and 1 or 0
    if (p.vy or 0) > 300 and math.abs(pv.vy) < 60 then p.landSquash = math.min(0.35, p.vy / 3000) end
    p.vy = pv.vy
    s.meleeRange, s.heavyCharge = pv.meleeRange, pv.heavyCharge
  end

  local views, list = {}, {}
  for _, bv in ipairs(v.bullets) do
    local b = self.bulletViews[bv.id] or setmetatable({ trail = {}, life = 6 }, Bullet)
    b.id = bv.id
    b.baseX, b.baseY = bv.x, bv.y
    b.x, b.y = bv.x, bv.y
    b.vx, b.vy = bv.vx, bv.vy
    b.r = bv.r
    b.color = bv.colorIdx == 5 and Bullet.CRIT_COLOR or (World.COLORS[bv.colorIdx] or { 1, 1, 1 })
    b.ghost, b.mine, b.laser = bv.ghost, bv.mine, bv.laser
    b.trigger = bv.trigger
    b.armTime = bv.armed and 0 or 1
    if bv.laser then
      b.points = bv.points
      b.beam = bv.beam
    end
    views[bv.id] = b
    list[#list + 1] = b
  end
  self.bulletViews, self.bulletList = views, list

  self.wellList = {}
  for _, w in ipairs(v.wells) do
    self.wellList[#self.wellList + 1] = {
      x = w.x, y = w.y, t = w.t, max = w.max, radius = w.radius,
      owner = { color = World.COLORS[w.slot] or { 1, 1, 1 } },
    }
  end

  for _, e in ipairs(v.fx) do
    if e[1] == 1 then
      fx.burst(e[2], e[3], e[4], e[5], e[6], e[7])
    elseif e[1] == 2 then
      fx.ring(e[2], e[3], e[4], e[5])
    elseif e[1] == 3 then
      fx.addShake(e[2])
    elseif e[1] == 5 then
      sfx.playId(e[2], e[3], e[4], e[5])
    elseif e[1] == 6 then
      fx.spray(e[2], e[3], e[4], e[5], e[6], e[7], e[8], e[9], e[10])
    elseif e[1] == 7 then
      fx.ghost(e[2], e[3], e[4], e[5])
    elseif e[1] == 8 then
      fx.debris(e[2], e[3], e[4], e[5], e[6])
    elseif e[1] == 9 then
      fx.kick(e[2], e[3])
    else
      fx.clear()
    end
  end

  self.snapTime = now
end

function Match:clientInterpolate(dt)
  local t = math.min(1, (love.timer.getTime() - self.snapTime) / SNAPSHOT_INTERVAL)
  for _, p in ipairs(self.proxies) do
    if p.toX then
      p.x = p.fromX + (p.toX - p.fromX) * t
      p.y = p.fromY + (p.toY - p.fromY) * t
    end
    p.hitFlash = math.max(0, p.hitFlash - dt)
    p.swingTimer = math.max(0, (p.swingTimer or 0) - dt)
    p.landSquash = math.max(0, (p.landSquash or 0) - dt * 2.5)
  end
  local age = love.timer.getTime() - self.snapTime
  for _, b in ipairs(self.bulletList) do
    if not b.mine and not b.laser then
      b.x = b.baseX + b.vx * math.min(age, 0.1)
      b.y = b.baseY + b.vy * math.min(age, 0.1)
      table.insert(b.trail, 1, { b.x, b.y })
      if #b.trail > 6 then table.remove(b.trail) end
    end
    b.life = b.life - dt
  end
end

function Match:clientNetwork()
  local msgs = self.transport:receive()
  if self.pending then
    for i = #self.pending, 1, -1 do table.insert(msgs, 1, self.pending[i]) end
    self.pending = nil
  end
  for _, msg in ipairs(msgs) do
    if msg.from == self.hostPeer then
      local kind = net.kind(msg.data)
      if kind == net.MSG.SNAPSHOT then
        local ok, v = pcall(Snap.decode, msg.data)
        if ok then self:applySnapshot(v) end
      elseif kind == net.MSG.ROSTER then
        for i, r in ipairs(net.decodeRoster(msg.data)) do
          local p = self.proxies[i]
          if p then
            p.disconnected = r.disconnected
            p.cards = {}
            for k, idx in ipairs(r.cards) do p.cards[k] = Cards.list[idx] end
          end
        end
      elseif kind == net.MSG.RULES then
        Cards.applyRules(net.decodeRules(msg.data, Cards.RARITIES))
      elseif kind == net.MSG.TOAST then
        self:showToast(net.decodeToast(msg.data))
      elseif kind == net.MSG.TOLOBBY then
        app.switch(require("screens.lobby").new())
        return
      end
    end
  end

  for _, ev in ipairs(self.popEvents()) do
    if ev.type == "hostLeft" then
      active.get().leave()
      app.switch(require("screens.menu").new("The host left the game"))
      return
    end
  end
end

---------------------------------------------------------------- host side
local scratch = Input.remote()

function Match:hostNetwork(dt)
  for _, msg in ipairs(self.transport:receive()) do
    local info = self.peers[msg.from]
    if info and not info.gone then
      local kind = net.kind(msg.data)
      if kind == net.MSG.INPUT then
        local seq = net.decodeInput(msg.data, scratch)
        if seq > info.seq then
          info.seq = seq
          local inp = self.world.players[info.slot].input
          for _, k in ipairs({ "left", "right", "down", "fire", "jumpHeld", "meleeHeld", "aim", "jumpCount", "blockCount",
            "dashCount", "meleeCount" }) do
            inp[k] = scratch[k]
          end
          if scratch.pickHover > 0 then self.world:hover(info.slot, scratch.pickHover) end
        end
      elseif kind == net.MSG.VOTE then
        self.world:vote(info.slot, net.decodeVote(msg.data))
      elseif kind == net.MSG.CHOOSE then
        local index, serial = net.decodeChoose(msg.data)
        self.world:choose(info.slot, index, serial)
      elseif kind == net.MSG.DISCARD then
        local pos, serial = net.decodeDiscard(msg.data)
        self.world:discard(info.slot, pos, serial)
      end
    end
  end

  for _, ev in ipairs(self.popEvents()) do
    if ev.type == "left" and self.peers[ev.id] and not self.peers[ev.id].gone then
      local info = self.peers[ev.id]
      info.gone = true
      local p = self.world.players[info.slot]
      self.world:disconnect(info.slot)
      self.world:toast((p.name or "A player") .. " left the game", info.slot)
      self.world:emit("roster")
      if self.world:connectedCount() < 2 then
        self:backToLobby("Everyone else left the game")
        return
      end
    end
  end

  self.snapTimer = self.snapTimer - dt
  if self.snapTimer <= 0 then
    self.snapTimer = SNAPSHOT_INTERVAL
    local data = Snap.encode(self.world, fx.recorder)
    fx.recorder = {}
    self:broadcast(data, false)
  end
end

function Match:backToLobby(message)
  if self.role == "host" then
    self:broadcast(net.encodeToLobby(), true)
    active.get().setJoinable(true)
  end
  app.switch(require("screens.lobby").new(message))
end

---------------------------------------------------------------- update
function Match:update(dt, isTop)
  local suppressed = self.paused or not isTop
  fx.update(dt)
  for i = #self.toasts, 1, -1 do
    local t = self.toasts[i]
    t.t = t.t - dt
    if t.t <= 0 then table.remove(self.toasts, i) end
  end

  self:updatePickAnim(dt)
  local mx, my = app.mouse()
  if self.role == "local" then
    for _, inp in ipairs(self.inputs) do Input.poll(inp, suppressed) end
    if not self.paused then self.world:update(dt) end
    self:syncPick(dt)
  elseif self.role == "host" then
    local me = self.world.players[1]
    Input.poll(self.myInput, suppressed, me.x, me.y, mx, my)
    self.world:update(dt)
    self:syncPick(dt)
    self:hostNetwork(dt)
  else
    self:clientNetwork()
    if self.closed then return end -- switched to the lobby/menu
    local me = self.proxies[self.mySlot]
    Input.poll(self.myInput, suppressed, me.x, me.y, mx, my)
    self:syncPick(dt)
    self.inputSeq = self.inputSeq + 1
    self.transport:send(self.hostPeer, net.encodeInput(self.myInput, self.inputSeq), false)
    self:clientInterpolate(dt)
  end

  if self.role ~= "local" then
    local st = self:status().state
    if st ~= "matchOver" then self.pendingVote = nil end
    local playing = isTop and not self.paused and (st == "countdown" or st == "playing" or st == "roundOver")
    love.mouse.setVisible(not playing)
  end
end

---------------------------------------------------------------- input
function Match:keypressed(key)
  if key == "escape" then
    self.paused = not self.paused
    ui.reset()
    return
  end
  if self.paused then return end

  local pu = self.pickUI
  if pu then
    local cp = self:currentPick()
    local n = cp and #cp.options or 0
    if n == 0 then return end
    local left, right, take, down = self:pickKeys(pu.slot)
    if self.discardMode then
      local owned = self:ownedCards(pu.slot)
      local m = #owned
      self.discardIndex = math.max(1, math.min(m, self.discardIndex or 1))
      if m == 0 or down[key] then
        self.discardMode = false
      elseif left[key] then
        self.discardIndex = (self.discardIndex - 2) % m + 1
      elseif right[key] then
        self.discardIndex = self.discardIndex % m + 1
      elseif take[key] then
        self:discardCard(owned[self.discardIndex].pos)
      end
      return
    end
    if left[key] then
      pu.index = (pu.index - 2) % n + 1
    elseif right[key] then
      pu.index = pu.index % n + 1
    elseif take[key] then
      self:choosePick(pu.index)
    elseif down[key] and self:canDiscard(pu.slot) then
      self.discardMode, self.discardIndex = true, 1
    end
    return
  end

  if self.role == "local" then
    for _, inp in ipairs(self.inputs) do Input.keypressed(inp, key) end
    if key == "r" and self.world.state == "matchOver" then self:newMatch() end
  else
    Input.keypressed(self.myInput, key)
  end
end

-- Key sets (as lookup tables) for moving the pick selection left / right and taking a card.
function Match:pickKeys(slot)
  local function set(...)
    local t = {}
    for _, k in ipairs({ ... }) do t[k] = true end
    return t
  end
  if self.role == "local" then
    local b = Settings.values.binds["p" .. slot] or Settings.values.binds.p1
    return set(b.left), set(b.right), set(b.fire), set(b.down)
  end
  local b = Settings.values.binds.online
  return set(b.left, "left"), set(b.right, "right"), set(b.fire, b.jump, b.jump2, "return", "kpenter"),
    set(b.down, "down")
end

function Match:mousepressed(x, y, button)
  if self.paused then return end
  local pu = self.pickUI
  if pu then
    local cp = self:currentPick()
    if self.discardMode then return end -- the discard panel's buttons handle clicks
    if button == 1 and cp then
      for i, r in ipairs(hud.cardRects(#cp.options, pu.index)) do
        if x >= r[1] and x <= r[1] + r[3] and y >= r[2] and y <= r[2] + r[4] then
          self:choosePick(i)
          return
        end
      end
    end
    -- Online, a mouse-bound "take" (e.g. fire on a button other than LMB) also works.
    local _, _, take = self:pickKeys(pu.slot)
    if button ~= 1 and take["mouse" .. button] then self:choosePick(pu.index) end
    return
  end
  if self.role ~= "local" then Input.mousepressed(self.myInput, button) end
end

---------------------------------------------------------------- drawing
---------------------------------------------------------------- card pick animation
local DEAL_STAGGER, DEAL_TIME, FLIP_TIME = 0.07, 0.28, 0.2
local REVEAL_SOUND = { rare = "revealRare", epic = "revealEpic", legendary = "revealLegendary" }

local function ease(t)
  t = math.max(0, math.min(1, t))
  return 1 - (1 - t) ^ 3
end

-- Dealing, flipping and reveal sparkles; also cards flying to a player's panel after a pick.
-- Sounds here are local (every machine animates the same pick), so they aren't recorded.
function Match:updatePickAnim(dt)
  local cp = self:currentPick()
  local a = self.pickAnim
  if cp then
    if not a or a.serial ~= cp.serial or a.slot ~= cp.slot then
      a = { serial = cp.serial, slot = cp.slot, t = 0, flip = {}, sparkles = {} }
      self.pickAnim = a
      sfx.play("cardDeal", nil, 1, 1, true)
    end
    a.t = a.t + dt
    for i, card in ipairs(cp.options) do
      local arrived = a.t > (i - 1) * DEAL_STAGGER + DEAL_TIME
      if cp.flipped[i] and arrived then
        local before = a.flip[i] or 0
        a.flip[i] = math.min(1, before + dt / FLIP_TIME)
        if before < 0.5 and a.flip[i] >= 0.5 then
          sfx.play("cardFlip", nil, 0.8, 1, true)
          if REVEAL_SOUND[card.rarity] then sfx.play(REVEAL_SOUND[card.rarity], nil, 1, 1, true) end
          local n = ({ rare = 10, epic = 18, legendary = 32 })[card.rarity]
          if n then
            local r = hud.cardRects(#cp.options, i)[i]
            local col = Cards.rarity[card.rarity].color
            for _ = 1, n do
              local ang = love.math.random() * math.pi * 2
              local sp = 60 + love.math.random() * 220
              a.sparkles[#a.sparkles + 1] = {
                x = r[1] + love.math.random() * r[3], y = r[2] + love.math.random() * r[4],
                vx = math.cos(ang) * sp, vy = math.sin(ang) * sp - 60, life = 0.6 + love.math.random() * 0.6,
                max = 1.2, color = col, size = 2 + love.math.random() * 3,
              }
            end
          end
        end
      end
    end
  elseif a then
    self.pickAnim = nil
  end
  if a then
    for i = #a.sparkles, 1, -1 do
      local sp = a.sparkles[i]
      sp.life = sp.life - dt
      if sp.life <= 0 then
        table.remove(a.sparkles, i)
      else
        sp.x, sp.y = sp.x + sp.vx * dt, sp.y + sp.vy * dt
        sp.vx, sp.vy = sp.vx * (1 - 2 * dt), sp.vy * (1 - 2 * dt)
      end
    end
  end

  -- A player's card count went up: fly the new card to their score panel.
  self.cardCounts = self.cardCounts or {}
  self.flyers = self.flyers or {}
  for i, p in ipairs(self:players()) do
    local n = #p.cards
    local before = self.cardCounts[i]
    if before and n > before and p.cards[n] then
      self.flyers[#self.flyers + 1] = { card = p.cards[n], slot = i, t = 0 }
      sfx.play("cardPick", nil, 1, 1, true)
    end
    self.cardCounts[i] = n
  end
  for i = #self.flyers, 1, -1 do
    local f = self.flyers[i]
    f.t = f.t + dt
    if f.t >= 0.6 then table.remove(self.flyers, i) end
  end
end

-- Where a player's score panel is (for flying cards).
function Match:panelPos(slot)
  local n = #self:players()
  if n <= 2 then return slot == 1 and 140 or app.W - 140, 60 end
  local pw = math.floor((app.W - 48 - (n - 1) * 16) / n)
  return 24 + (slot - 1) * (pw + 16) + pw / 2, 60
end

function Match:drawFlyers()
  for _, f in ipairs(self.flyers or {}) do
    local t = ease(f.t / 0.6)
    local tx, ty = self:panelPos(f.slot)
    local w, h = 230, 340
    local sx = 1 - 0.85 * t
    local cx = app.W / 2 + (tx - app.W / 2) * t
    local cy = 380 + (ty - 380) * t
    local p = self:players()[f.slot]
    love.graphics.push()
    love.graphics.translate(cx, cy)
    love.graphics.scale(sx, sx)
    love.graphics.translate(-w / 2, -h / 2)
    love.graphics.setColor(1, 1, 1)
    hud.drawCard(f.card, 0, 0, w, h, true, p and p.color or { 1, 1, 1 })
    love.graphics.pop()
  end
end

function Match:drawCardPick(st)
  love.graphics.setColor(0, 0, 0, 0.75)
  love.graphics.rectangle("fill", 0, 0, app.W, app.H)

  local cp = st.pick
  if not cp or #cp.options == 0 then return end
  local players = self:players()
  local p = players[cp.slot]
  local color = p and p.color or { 1, 1, 1 }
  local name = (p and p.name or ("Player " .. cp.slot)):upper()
  local pu = self.pickUI
  local count = cp.total > 1 and ("  (" .. cp.num .. "/" .. cp.total .. ")") or ""

  local title
  if pu and self.role ~= "local" then
    title = "PICK A CARD" .. count
  elseif pu then
    title = name .. " - PICK A CARD" .. count
  else
    title = name .. " IS PICKING" .. count
  end
  app.centered(title, app.fonts.big, 80, color)

  local hint
  local b = self.role == "local" and pu and (Settings.values.binds["p" .. pu.slot] or Settings.values.binds.p1)
    or Settings.values.binds.online
  if pu then
    if self.discardMode then
      hint = "Choose a card to throw away  -  " .. Input.keyName(b.down) .. " to go back"
    elseif self.role == "local" then
      hint = Input.keyName(b.left) .. " / " .. Input.keyName(b.right) .. " to turn over and choose, " ..
        Input.keyName(b.fire) .. " to take"
    else
      hint = "Hover to turn a card over, click to take  -  or " .. Input.keyName(b.left) .. " / " ..
        Input.keyName(b.right) .. " and " .. Input.keyName(b.jump)
    end
    if pu.waiting then hint = "Waiting for the host..." end
  else
    hint = "Watching " .. (p and p.name or "them") .. " choose"
  end
  app.centered(hint, app.fonts.med, 128, { 1, 1, 1, 0.7 })

  -- Pick timer
  if cp.timeLeft then
    local total = math.max(1, Cards.rules.pickTimer or cp.timeLeft)
    local frac = math.max(0, math.min(1, cp.timeLeft / total))
    local bw = 420
    love.graphics.setColor(1, 1, 1, 0.12)
    love.graphics.rectangle("fill", (app.W - bw) / 2, 160, bw, 6, 3, 3)
    love.graphics.setColor(frac < 0.25 and { 1, 0.35, 0.3 } or color)
    love.graphics.rectangle("fill", (app.W - bw) / 2, 160, bw * frac, 6, 3, 3)
    love.graphics.setFont(app.fonts.small)
    love.graphics.setColor(1, 1, 1, 0.6)
    love.graphics.printf(math.ceil(cp.timeLeft) .. "s", (app.W + bw) / 2 + 10, 154, 60, "left")
  end

  if #cp.queued > 0 then
    local names = {}
    for _, slot in ipairs(cp.queued) do
      names[#names + 1] = players[slot] and players[slot].name or ("Player " .. slot)
    end
    app.centered("Up next: " .. table.concat(names, ", "), app.fonts.med, 676, { 1, 1, 1, 0.55 })
  end

  if pu and self.discardMode then return self:drawDiscard(cp, color) end

  local index = pu and pu.index or cp.hover
  -- Mouse hover selects for whoever controls the pick (local player 1 can use the mouse too).
  if pu and not pu.waiting and ui.mouseMoved then
    local mx, my = app.mouse()
    for i, r in ipairs(hud.cardRects(#cp.options, index)) do
      if mx >= r[1] and mx <= r[1] + r[3] and my >= r[2] and my <= r[2] + r[4] then pu.index = i end
    end
    index = pu.index
  end
  local a = self.pickAnim
  local rects = hud.cardRects(#cp.options, index)
  for i, card in ipairs(cp.options) do
    local r = rects[i]
    local appear = a and (a.t - (i - 1) * DEAL_STAGGER) / DEAL_TIME or 1
    if appear > 0 then
      local dx = (1 - ease(appear)) * 900
      local flip = a and a.flip[i] or (cp.flipped[i] and 1 or 0)
      local cx = r[1] + dx + r[3] / 2
      local sx = flip < 0.5 and (1 - 2 * flip) or (2 * flip - 1)
      love.graphics.push()
      love.graphics.translate(cx, 0)
      love.graphics.scale(math.max(0.02, sx), 1)
      love.graphics.translate(-cx, 0)
      if flip < 0.5 then
        hud.drawCardBack(r[1] + dx, r[2], r[3], r[4], i == index, color)
      else
        hud.drawCard(card, r[1] + dx, r[2], r[3], r[4], i == index, color)
      end
      love.graphics.pop()
    end
  end
  if a then
    for _, sp in ipairs(a.sparkles) do
      local c = sp.color
      love.graphics.setColor(c[1], c[2], c[3], math.min(1, sp.life * 2))
      love.graphics.circle("fill", sp.x, sp.y, sp.size)
      love.graphics.setColor(1, 1, 1, math.min(1, sp.life * 2) * 0.8)
      love.graphics.circle("fill", sp.x, sp.y, sp.size * 0.4)
    end
  end

  if pu and not pu.waiting and self:canDiscard(pu.slot) then
    local label = "Discard a card instead  (" .. Input.keyName(b.down) .. ")"
    if ui.button(label, app.W / 2 - 180, 612, 360, 44, { font = app.fonts.med }) then
      self.discardMode, self.discardIndex = true, 1
    end
  end
end

-- Discard mode: the picker's owned cards as buttons.
function Match:drawDiscard(cp, color)
  local pu = self.pickUI
  local owned = self:ownedCards(pu.slot)
  self.discardIndex = math.max(1, math.min(#owned, self.discardIndex or 1))
  local cols = 4
  local bw, bh, gap = 270, 46, 12
  local rows = math.ceil(#owned / cols)
  local x0 = (app.W - (math.min(cols, #owned) * (bw + gap) - gap)) / 2
  local y0 = 200
  local hovered
  for i, o in ipairs(owned) do
    local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
    local x, y = x0 + col * (bw + gap), y0 + row * (bh + gap)
    local label = o.card.name .. (o.count > 1 and ("  x" .. o.count) or "")
    local rc = Cards.rarity[o.card.rarity].color
    if ui.button(label, x, y, bw, bh, { font = app.fonts.med, color = i == self.discardIndex and color or rc }) then
      self:discardCard(o.pos)
      return
    end
    local mx, my = app.mouse()
    if mx >= x and mx <= x + bw and my >= y and my <= y + bh then hovered = o end
  end
  local show = hovered or owned[self.discardIndex]
  if show then
    local y = y0 + rows * (bh + gap) + 10
    hud.drawCard(show.card, app.W / 2 - 115, math.min(y, 330), 230, 300, false, color)
  end
  if ui.button("Back to the cards", app.W / 2 - 150, 640, 300, 30, { font = app.fonts.small, back = true }) then
    self.discardMode = false
  end
end

-- slot -> World.VOTE_* (online only; the host's world, or the clients' snapshots).
function Match:votes()
  if self.role == "client" then
    local v = {}
    for i, p in ipairs(self.proxies) do
      if (p.vote or 0) > 0 then v[i] = p.vote end
    end
    return v
  end
  return self.world.votes
end

-- "Alice: Continue   Bob: New Match", each name in its player colour.
function Match:drawVotes(y)
  local players = self:players()
  local text = {}
  for i, p in ipairs(players) do
    local v = self:votes()[i]
    if v then
      if #text > 0 then table.insert(text, { 1, 1, 1, 0.5 }); table.insert(text, "      ") end
      table.insert(text, p.color)
      table.insert(text, (p.name or ("Player " .. i)) .. ": ")
      table.insert(text, { 1, 1, 1, 0.85 })
      table.insert(text, World.VOTE_NAMES[v])
    end
  end
  love.graphics.setFont(app.fonts.med)
  if #text == 0 then
    love.graphics.setColor(1, 1, 1, 0.45)
    love.graphics.printf("No votes yet", 0, y, app.W, "center")
  else
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf(text, 0, y, app.W, "center")
  end
end

function Match:drawMatchOver(st)
  love.graphics.setColor(0, 0, 0, 0.7)
  love.graphics.rectangle("fill", 0, 0, app.W, app.H)
  local winner = st.winner
  if winner then
    app.centered((winner.name or "Player"):upper() .. " WINS!", app.fonts.huge, 150, winner.color)
  end
  local scores = {}
  for _, p in ipairs(self:players()) do scores[#scores + 1] = tostring(p.score) end
  app.centered(table.concat(scores, "  -  "), app.fonts.big, 280)

  local x, w, h = app.W / 2 - 280, 560, 52
  local nextScore = st.winScore + World.CONTINUE_ROUNDS
  local continueText = "Continue  (+" .. World.CONTINUE_ROUNDS .. " rounds, first to " .. nextScore .. ")"

  if self.role == "client" then
    -- Players vote; the host sees the tally and decides.
    local mine = self:votes()[self.mySlot] or self.pendingVote
    local me = self:players()[self.mySlot]
    local function voteButton(label, choice, y)
      local chosen = mine == choice
      if ui.button((chosen and "> " or "") .. label, x, y, w, h, { color = chosen and me and me.color or nil }) then
        self.pendingVote = choice
        self.transport:send(self.hostPeer, net.encodeVote(choice), true)
      end
    end
    app.centered("Vote for what's next - the host decides", app.fonts.med, 335, { 1, 1, 1, 0.7 })
    voteButton(continueText, World.VOTE_CONTINUE, 370)
    voteButton("New Match", World.VOTE_NEW, 432)
    self:drawVotes(510)
    return
  end
  self.pendingVote = nil

  local tally = World.tally(self:votes())
  local function withVotes(label, n)
    if self.role == "local" or n == 0 then return label end
    return label .. "   -   " .. n .. (n == 1 and " vote" or " votes")
  end
  if ui.button(withVotes(continueText, tally[World.VOTE_CONTINUE]), x, 370, w, h) then
    self.world:continueMatch()
  end
  if ui.button(withVotes("New Match", tally[World.VOTE_NEW]), x, 432, w, h) then self:newMatch() end
  if self.role == "host" then
    if ui.button("Back to Lobby", x, 494, w, h) then self:backToLobby() end
    self:drawVotes(568)
  else
    if ui.button("Main Menu", x, 494, w, h) then app.switch(require("screens.menu").new()) end
  end
end

function Match:drawPause()
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.rectangle("fill", 0, 0, app.W, app.H)
  local buttons = self.role == "host" and 4 or 3
  local pw, ph = 420, 120 + buttons * 62
  local px, py = (app.W - pw) / 2, (app.H - ph) / 2
  ui.panel(px, py, pw, ph)
  love.graphics.setFont(app.fonts.big)
  love.graphics.setColor(1, 1, 1)
  love.graphics.printf(self.role == "local" and "PAUSED" or "MENU", px, py + 22, pw, "center")
  if self.role ~= "local" then
    love.graphics.setFont(app.fonts.small)
    love.graphics.setColor(1, 1, 1, 0.5)
    love.graphics.printf("The game keeps running online", px, py + 66, pw, "center")
  end

  local bx, bw, bh = px + 50, pw - 100, 50
  local y = py + 100
  if ui.button("Resume", bx, y, bw, bh) then self.paused = false end
  y = y + 62
  if ui.button("Settings", bx, y, bw, bh) then app.push(require("screens.settings").new()) end
  y = y + 62
  if self.role == "local" then
    if ui.button("Main Menu", bx, y, bw, bh) then app.switch(require("screens.menu").new()) end
  elseif self.role == "host" then
    if ui.button("Back to Lobby (everyone)", bx, y, bw, bh) then self:backToLobby() end
    y = y + 62
    if ui.button("Leave Lobby", bx, y, bw, bh) then
      active.get().leave()
      app.switch(require("screens.menu").new())
    end
  else
    if ui.button("Leave Lobby", bx, y, bw, bh) then
      active.get().leave()
      app.switch(require("screens.menu").new())
    end
  end
end

function Match:draw()
  local players, bullets, wells, map = self:scene()
  if not map then return end
  local st = self:status()

  local sx, sy = fx.offset()

  love.graphics.push()
  love.graphics.translate(sx, sy)
  Map.draw(map)
  hud.drawWells(wells)
  for _, b in ipairs(bullets) do b:draw() end
  for _, p in ipairs(players) do p:draw() end
  fx.draw()
  love.graphics.pop()

  Bloom.draw(function()
    love.graphics.translate(sx, sy)
    for _, b in ipairs(bullets) do b:draw() end
    for _, p in ipairs(players) do p:drawGlow() end
    fx.draw()
  end, app.canvas)

  local cardItems = hud.drawScores(players, st.winScore)
  love.graphics.setFont(app.fonts.small)
  love.graphics.setColor(1, 1, 1, 0.3)
  love.graphics.printf(map.name .. "   -   First to " .. st.winScore, 0, app.H - 24, app.W, "center")

  for i, t in ipairs(self.toasts) do
    local c = t.color
    app.centered(t.text, app.fonts.med, 92 + i * 26, { c[1], c[2], c[3], math.min(1, t.t) })
  end

  if st.state == "countdown" then
    app.centered(tostring(math.max(1, math.ceil(st.timer / 0.8))), app.fonts.huge, 250, { 1, 1, 1, 0.9 })
  elseif st.state == "roundOver" then
    if st.winner then
      app.centered((st.winner.name or "Player"):upper() .. " WINS THE ROUND", app.fonts.big, 280, st.winner.color)
    else
      app.centered("DRAW", app.fonts.big, 280)
    end
  elseif st.state == "cardPick" then
    self:drawCardPick(st)
  end
  self:drawFlyers()
  if st.state == "matchOver" then self:drawMatchOver(st) end

  -- Hovering a card name in someone's score panel shows what it does.
  if not self.paused then
    local mx, my = app.mouse()
    local item = hud.cardAt(cardItems, mx, my)
    if item then hud.drawCardTooltip(item) end
  end

  if self.paused then
    self:drawPause()
  elseif self.role ~= "local" and (st.state == "countdown" or st.state == "playing" or st.state == "roundOver") then
    local mx, my = app.mouse()
    local me = players[self.mySlot]
    hud.drawCrosshair(mx, my, me and me.color or { 1, 1, 1 })
  end
end

return Match
