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
local Objects = require "game.objects"
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
local Profile = require "core.profile"

local Match = {}
Match.__index = Match

local SNAPSHOT_INTERVAL = 1 / 30
local INTERP_DELAY = 0.07   -- other players are drawn this far in the past, between real snapshots
local PING_EVERY = 1
local RECONNECT_TIME = 60     -- seconds a dropped player's slot is kept for them
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
-- This machine's input online: touch controls on a touch device, else a gamepad if one is in use, else mouse + keys.
function Match.onlineInput()
  if require("core.touch").enabled then return Input.touch() end
  local pads = Input.pads()
  if Settings.values.padOnline and pads[1] then return Input.pad(pads[1]) end
  return Input.mouse(Settings.values.binds.online)
end

-- An input for a local slot kind: "p1" / "p2" (keyboard), "pad1".."pad4", "bot1".."bot3".
function Match.localInput(kind)
  local binds = Settings.values.binds
  if kind == "p1" or kind == "p2" then return Input.keys(binds[kind]) end
  if kind == "touch" then return Input.touch() end
  local pad = kind:match("^pad(%d)$")
  if pad then return Input.pad(Input.pads()[tonumber(pad)]) end
  local bot = kind:match("^bot(%d)$")
  if bot then return Input.bot(tonumber(bot)) end
  return Input.keys(binds.p1)
end

-- opts (optional): setup = { { kind, color, team }, ... } (from the local setup screen),
-- map = play only this map, test = editor test play (player 2 stands still),
-- returnTo = screen to go back to on Esc, teams = 2v2.
function Match.newLocal(winScore, opts)
  opts = opts or {}
  local m = newMatch("local")
  m.returnTo = opts.returnTo
  local rules = settingsRules(false)
  rules.teams = opts.teams and true or false
  if opts.map then rules.forceMap = opts.map end
  if opts.test then rules.startCards = 0 end
  local setup = opts.setup or { { kind = "p1", color = 1, team = 1 }, { kind = opts.test and "dummy" or "p2", color = 2, team = 2 } }
  m.inputs = {}
  local defs, colors, keyCount, padCount = {}, {}, 0, 0
  for i, sl in ipairs(setup) do
    local inp, name, bot
    if sl.kind == "dummy" then
      inp = Input.remote()
      inp.aim = nil
      name = "Dummy"
    else
      inp = Match.localInput(sl.kind)
      bot = sl.kind:match("^bot(%d)$")
      if bot then
        name = "Bot (" .. require("game.bot").NAMES[tonumber(bot)] .. ")"
      else
        name = "Player " .. i
      end
    end
    m.inputs[i] = inp
    colors[i] = sl.color
    defs[i] = { name = name, input = inp, team = sl.team, bot = bot and tonumber(bot) or nil }
  end
  if rules.teams then
    local teams = {}
    for i, sl in ipairs(setup) do teams[i] = sl.team or ((i - 1) % 2 + 1) end
    World.setSlotColors(World.teamColorIndices(teams))
  else
    World.setSlotColors(colors)
  end
  m.world = World.new(defs, winScore, rules)
  m:hookWorld()
  fx.recorder = nil
  m.world:beginMatch()
  if opts.giveCards then -- card editor test: player 1 owns these
    for _, c in ipairs(opts.giveCards) do table.insert(m.world.players[1].cards, c) end
    m.world.players[1]:recompute()
    m.world:startRound()
  end
  return m
end

-- slots[1] is the host. opts.popEvents overrides the session event source (tests).
function Match.newHost(slots, winScore, transport, opts)
  opts = opts or {}
  local m = newMatch("host")
  m.transport = transport
  m.popEvents = opts.popEvents or active.get().popEvents
  m.myInput = Match.onlineInput()
  m.mySlot = 1
  m.peers = {}
  local defs, colors = {}, {}
  for i, s in ipairs(slots) do
    local input
    if i == 1 then input = m.myInput elseif s.bot then input = Input.bot(s.bot) else input = Input.remote() end
    defs[i] = { name = s.name, input = input, peer = s.peer, team = s.team, bot = s.bot }
    colors[i] = s.color
    if i > 1 and not s.bot then m.peers[s.peer] = { slot = i, seq = -1 } end
  end
  World.setSlotColors(colors)
  m.world = World.new(defs, winScore, settingsRules(true))
  m.slots = slots
  local ok, session = pcall(active.get)
  if not ok or not session then session = {} end
  for i, s in ipairs(slots) do
    m.world.players[i].key = session.playerKey and session.playerKey(s.peer) or s.peer
  end
  m:hookWorld()
  m:broadcast(net.encodeMaps(Map.sessionEntries()), true)
  m:broadcast(net.encodeCards(Cards.sessionEntries()), true)
  m:broadcast(net.encodeSynergies(require("game.synergies").sessionEntries()), true)
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
  m.myInput = Match.onlineInput()
  m.inputSeq = 0
  m.pending = pending
  local colors = {}
  for i, s in ipairs(slots) do colors[i] = s.color end
  World.setSlotColors(colors)
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
  Profile.save()
  if self.role == "client" then -- drop the host's session map and card lists
    Map.loadAll()
    Cards.loadAll()
    require("game.synergies").loadAll()
  end
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
  w.on.matchOver = function(winner)
    ui.reset()
    if self.role == "host" then self:recordStreaks(winner) end
  end
end

-- What to draw and the round status, for any role.
function Match:scene()
  if self.role == "client" then
    return self.proxies, self.bulletList, self.wellList, Map.list[self.view.mapIndex] or Map.list[1]
  end
  local w = self.world
  return w.players, w.bullets, w.wells, w.map
end

-- Map objects, spawned effects and the barrier rect, for any role.
function Match:sceneObjects()
  if self.role == "client" then return self.objViews or {}, self.view.effects or {}, self.view.barrier end
  local w = self.world
  return w.objects or {}, w.effects or {}, w.barrier
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

-- Does this machine make the choice for that slot? (Bots pick by themselves.)
function Match:controlsPick(slot)
  if self.role == "local" then
    local p = self.world.players[slot]
    return p and not p.isBot
  end
  if self.role == "host" then
    local p = self.world.players[slot]
    if p and p.isBot then return false end
  end
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
-- Online with people watching, New Match goes through the lobby so they're in it.
function Match:newMatch()
  if self.role == "host" and self:hasSpectators() then
    active.get().autoStart = true
    return self:backToLobby()
  end
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
    -- Position history for interpolation (cleared on teleports, deaths and respawns).
    p.hist = p.hist or {}
    local last = p.hist[#p.hist]
    if p.dead or pv.dead or (last and math.abs(pv.x - last.x) + math.abs(pv.y - last.y) > 250) then p.hist = {} end
    table.insert(p.hist, { t = now, x = pv.x, y = pv.y })
    if #p.hist > 12 then table.remove(p.hist, 1) end
    if #p.hist == 1 then p.x, p.y = pv.x, pv.y end
    p.ping = pv.ping
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

  -- Map objects: rebuilt from the map's list when the map changes, then updated from the snapshot.
  local map = Map.list[v.mapIndex] or Map.list[1]
  if self.objMap ~= map then
    self.objMap = map
    self.objViews = Objects.build(map)
  end
  for i, ov in ipairs(v.objects or {}) do
    local o = self.objViews[i]
    if o then
      o.alive, o.falling, o.x, o.y, o.s = ov.alive, ov.falling, ov.x, ov.y, ov.s
      if o.type == "rope" then o.angle = ov.a else o.a = ov.a end
      if o.maxHp then o.hp = ov.hp * o.maxHp end
    end
  end
  view.effects = v.effects
  view.barrier = v.barrier

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

  self:reconcile(v.players[self.mySlot] or { dead = true })
  self.snapTime = now
end

---------------------------------------------------------------- client prediction
-- Your own player is simulated here as soon as you press something; the host stays authoritative.
-- Each snapshot says which of our inputs the host has applied (ack). We reset to the host's state,
-- replay the inputs it hasn't seen yet, and blend away any small difference.
local PREDICT_FIELDS = { "left", "right", "up", "down", "jumpHeld", "meleeHeld", "aim", "jumpCount", "dashCount",
  "meleeCount" }

function Match:predictionWorld()
  local map = Map.list[self.view.mapIndex] or Map.list[1]
  local solids = {}
  for i, r in ipairs(map.rects) do solids[i] = r end
  for _, o in ipairs(self.objViews or {}) do
    if o.alive and o.solid and not (o.type == "crumble" and o.s == 2) then solids[#solids + 1] = o end
  end
  local w = self.predWorld
  if not w then
    w = { players = {}, bullets = {}, wells = {}, objects = {}, effects = {}, pendingBlasts = {}, time = 0,
      enemiesOf = function() return {} end, nearestEnemy = function() return nil end,
      addBullet = function() end, isEnemy = function() return false end }
    self.predWorld = w
  end
  w.map, w.solids, w.rules = map, solids, Cards.rules
  return w
end

-- Make (or refresh) the predicted player for our slot. Returns nil when we shouldn't predict.
function Match:predicted()
  local st = self.view.state
  local me = self.proxies[self.mySlot]
  if not me or me.dead or (st ~= "playing" and st ~= "countdown" and st ~= "roundOver") then
    self.pred, self.predHistory = nil, {}
    return nil
  end
  local pr = self.pred
  local key = #me.cards .. ":" .. (me.cards[#me.cards] and me.cards[#me.cards].id or "")
  if not pr or pr.cardKey ~= key then
    self.predInput = self.predInput or Input.remote()
    pr = Player.new(self.mySlot, me.color, self.predInput)
    for _, c in ipairs(me.cards) do pr.cards[#pr.cards + 1] = c end
    pr:recompute()
    pr.triggerList = {}
    pr:spawn(me.x, me.y, me.facing or 1, self:predictionWorld())
    pr.cardKey = key
    self.pred = pr
    self.predHistory = {}
    self.predErrX, self.predErrY = 0, 0
  end
  return pr
end

local function copyInput(dst, src)
  for _, k in ipairs(PREDICT_FIELDS) do dst[k] = src[k] end
  dst.fire = false
  dst.blockCount = dst.blockCount or 0
end

function Match:predictStep(dt, frozen)
  local pr = self:predicted()
  if not pr then return end
  pr.game = self:predictionWorld()
  copyInput(self.predInput, self.myInput)
  local sample = {}
  copyInput(sample, self.myInput)
  table.insert(self.predHistory, { seq = self.inputSeq, dt = dt, frozen = frozen, input = sample })
  if #self.predHistory > 240 then table.remove(self.predHistory, 1) end
  fx.mute, sfx.silent = true, true
  pr.invuln = 999
  pr:update(dt, frozen)
  fx.mute, sfx.silent = false, false
end

-- A snapshot arrived: reset the prediction to the host's state and replay newer inputs.
function Match:reconcile(pv)
  local pr = self.pred
  if not pr or pv.dead then return end
  local oldX, oldY = pr.x + (self.predErrX or 0), pr.y + (self.predErrY or 0)
  pr.x, pr.y, pr.vx, pr.vy = pv.x, pv.y, pv.vx, pv.vy
  pr.jumpsLeft, pr.dashesLeft = pv.jumpsLeft, pv.dashesLeft
  pr.onGround, pr.jumping, pr.groundOneway = pv.onGround, pv.jumping, pv.groundOneway
  pr.dashTimer, pr.dashCd = pv.dashT, pv.dashCd2
  if pr.dashTimer > 0 then pr.dashX, pr.dashY = pv.vx, pv.vy end
  pr.facing = pv.facing
  local hist, keep = self.predHistory, {}
  for _, e in ipairs(hist) do
    if e.seq == pv.ack then
      local inp = e.input
      pr.seenJump, pr.seenDash, pr.seenMelee = inp.jumpCount, inp.dashCount, inp.meleeCount
      pr.jumpWasHeld = inp.jumpHeld
    elseif e.seq > pv.ack then
      keep[#keep + 1] = e
    end
  end
  self.predHistory = keep
  pr.game = self:predictionWorld()
  fx.mute, sfx.silent = true, true
  for _, e in ipairs(keep) do
    copyInput(self.predInput, e.input)
    pr:update(e.dt, e.frozen)
  end
  fx.mute, sfx.silent = false, false
  copyInput(self.predInput, self.myInput)
  local ex, ey = oldX - pr.x, oldY - pr.y
  if ex * ex + ey * ey > 140 * 140 then ex, ey = 0, 0 end
  self.predErrX, self.predErrY = ex, ey
end

---------------------------------------------------------------- client interpolation
function Match:clientInterpolate(dt)
  local now = love.timer.getTime()
  local renderT = now - INTERP_DELAY
  for i, p in ipairs(self.proxies) do
    local h = p.hist
    if i == self.mySlot and self.pred then
      -- Our own player: the prediction, with the last correction fading out.
      local k = math.exp(-dt * 12)
      self.predErrX, self.predErrY = (self.predErrX or 0) * k, (self.predErrY or 0) * k
      p.x, p.y = self.pred.x + self.predErrX, self.pred.y + self.predErrY
      p.vy = self.pred.vy
      if self.myInput.aim then p.aimX, p.aimY = math.cos(self.myInput.aim), math.sin(self.myInput.aim) end
    elseif h and #h > 0 then
      local a, b = h[1], nil
      for k = 1, #h do
        if h[k].t <= renderT then a = h[k] else b = h[k] break end
      end
      if b and a.t <= renderT then
        local f = (renderT - a.t) / math.max(0.001, b.t - a.t)
        p.x, p.y = a.x + (b.x - a.x) * f, a.y + (b.y - a.y) * f
      else
        p.x, p.y = (b or a).x, (b or a).y
      end
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
      if kind == net.MSG.SYNERGIES then
        local ok, entries = pcall(net.decodeMaps, msg.data)
        if ok then require("game.synergies").setSession(entries) end
      elseif kind == net.MSG.CARDS then
        local ok, entries = pcall(net.decodeCards, msg.data)
        if ok then Cards.setSession(entries) end
      elseif kind == net.MSG.MAPS then
        local ok, entries = pcall(net.decodeMaps, msg.data)
        if ok then
          Map.setSession(entries)
          self.objMap = nil
        end
        self.mapsReady = true
      elseif kind == net.MSG.STREAKS then
        local ok, st = pcall(net.decodeStreaks, msg.data)
        if ok then active.get().peerStreaks = st end
      elseif kind == net.MSG.PONG then
        local rtt = (love.timer.getTime() - net.decodePing(msg.data)) * 1000
        self.rtt = self.rtt and (self.rtt * 0.7 + rtt * 0.3) or rtt
      elseif kind == net.MSG.SNAPSHOT then
        -- Snapshots refer to the host's map list, so wait for it.
        local ok, v = pcall(Snap.decode, msg.data)
        if ok and self.mapsReady then self:applySnapshot(v) end
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
      local session = active.get()
      if session.kind == "lan" and self.mySlot > 0 then
        -- Lost the connection: keep trying to get back in (the host keeps our slot for a minute).
        app.switch(require("screens.reconnect").new(session.lastAddress))
        return
      end
      session.leave()
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
          for _, k in ipairs({ "left", "right", "up", "down", "fire", "jumpHeld", "meleeHeld", "aim", "jumpCount",
            "blockCount", "dashCount", "meleeCount" }) do
            inp[k] = scratch[k]
          end
          local hp = self.world.players[info.slot]
          hp.ack, hp.ping = seq, scratch.ping
          if scratch.pickHover > 0 then self.world:hover(info.slot, scratch.pickHover) end
        end
      elseif kind == net.MSG.PING then
        self.transport:send(msg.from, net.encodePing(net.MSG.PONG, net.decodePing(msg.data)), false)
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
      if info.spectator then
        self.peers[ev.id] = nil
      else
        local p = self.world.players[info.slot]
        self.world:disconnect(info.slot)
        p.reconnectUntil = love.timer.getTime() + RECONNECT_TIME
        self.world:toast((p.name or "A player") .. " disconnected - " .. RECONNECT_TIME .. "s to reconnect", info.slot)
        self.world:emit("roster")
        if self.world:connectedCount() < 2 then
          self:backToLobby("Everyone else left the game")
          return
        end
      end
    elseif ev.type == "joined" then
      self:peerJoined(ev.id)
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

-- Everything a newcomer needs to follow the match: the slots, maps, cards, synergies, rules, roster.
function Match:sendSetup(peer)
  local t = self.transport
  t:send(peer, net.encodeStart(self.world.winScore, self.slots), true)
  t:send(peer, net.encodeMaps(Map.sessionEntries()), true)
  t:send(peer, net.encodeCards(Cards.sessionEntries()), true)
  t:send(peer, net.encodeSynergies(require("game.synergies").sessionEntries()), true)
  t:send(peer, net.encodeRules(self.world.rules, Cards.list, Cards.RARITIES), true)
  t:send(peer, net.encodeRoster(self.world.players), true)
end

-- Someone joined the lobby mid-match: give a dropped player their slot back, or let them watch.
function Match:peerJoined(peer)
  local session = active.get()
  local key = session.playerKey and session.playerKey(peer) or peer
  for slot, p in ipairs(self.world.players) do
    if p.disconnected and p.key == key and (p.reconnectUntil or 0) > love.timer.getTime() then
      p.disconnected, p.reconnectUntil, p.peer = false, nil, peer
      self.slots[slot].peer = peer
      self.peers[peer] = { slot = slot, seq = -1 }
      self:sendSetup(peer)
      self.world:toast((p.name or "A player") .. " reconnected (back next round)", slot)
      self.world:emit("roster")
      return
    end
  end
  self.peers[peer] = { slot = 0, spectator = true, seq = -1 }
  self:sendSetup(peer)
  local name = session.memberName and session.memberName(peer) or "Someone"
  self.world:toast(name .. " is watching and joins next match")
end

-- Lobby win streaks (host): kept by player key for this lobby, sent to everyone by peer id.
function Match:recordStreaks(winner)
  local session = active.get()
  session.streaks = session.streaks or {}
  local list = {}
  for _, p in ipairs(self.world.players) do
    local key = p.key or p.name
    local st = session.streaks[key] or { wins = 0, streak = 0 }
    local won = p == winner or (self.world.rules.teams and winner and p.team == winner.team)
    if won then
      st.wins, st.streak = st.wins + 1, st.streak + 1
    else
      st.streak = 0
    end
    session.streaks[key] = st
    list[#list + 1] = { id = p.peer or p.name, wins = st.wins, streak = st.streak }
  end
  session.peerStreaks = {}
  for _, e in ipairs(list) do session.peerStreaks[e.id] = e end
  self:broadcast(net.encodeStreaks(list), true)
end

function Match:hasSpectators()
  for _, info in pairs(self.peers or {}) do
    if info.spectator and not info.gone then return true end
  end
  return false
end

function Match:backToLobby(message)
  if self.role == "host" then
    self:broadcast(net.encodeToLobby(), true)
    active.get().setJoinable(true)
  end
  app.switch(require("screens.lobby").new(message))
end

---------------------------------------------------------------- update
-- Does anyone on this machine play with touch controls?
function Match:usesTouch()
  if self.role == "local" then
    for _, inp in ipairs(self.inputs) do if inp.kind == "touch" then return true end end
    return false
  end
  return self.myInput and self.myInput.kind == "touch"
end

-- "Round 3 - 2-1" for the friends list (only changes when the score does).
function Match:updatePresence()
  local players = self:players()
  local scores, total = {}, 0
  for _, p in ipairs(players) do
    scores[#scores + 1] = tostring(p.score)
    total = total + p.score
  end
  local kind = self.role == "local" and "Local match" or "Online match"
  require("online.presence").set(kind .. ": round " .. (total + 1) .. ", " .. table.concat(scores, "-"))
end

function Match:update(dt, isTop)
  self:updatePresence()
  if self:usesTouch() and require("core.touch").takePause() and isTop then
    self.paused = not self.paused
    ui.reset()
  end
  local suppressed = self.paused or not isTop
  fx.update(dt)
  for i = #self.toasts, 1, -1 do
    local t = self.toasts[i]
    t.t = t.t - dt
    if t.t <= 0 then table.remove(self.toasts, i) end
  end

  self:updatePickAnim(dt)
  self:recordRound(self:status())
  local mx, my = app.mouse()
  if self.role == "local" then
    for _, inp in ipairs(self.inputs) do
      if inp.kind ~= "bot" then Input.poll(inp, suppressed) end
    end
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
    if self.mySlot == 0 then -- spectating: no input of our own
      self:clientInterpolate(dt)
      return
    end
    local me = self.proxies[self.mySlot]
    Input.poll(self.myInput, suppressed, me.x, me.y, mx, my)
    self:syncPick(dt)
    self.inputSeq = self.inputSeq + 1
    -- Round-trip time, measured with PING / PONG and reported to the host in INPUT.
    self.pingTimer = (self.pingTimer or 0) - dt
    if self.pingTimer <= 0 then
      self.pingTimer = PING_EVERY
      self.transport:send(self.hostPeer, net.encodePing(net.MSG.PING, love.timer.getTime()), false)
    end
    self.myInput.ping = self.rtt or 0
    self.transport:send(self.hostPeer, net.encodeInput(self.myInput, self.inputSeq), false)
    self:predictStep(dt, self.view.state == "countdown")
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
  if key == "escape" and self.returnTo then
    app.switch(self.returnTo)
    return
  end
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

-- Gamepad buttons in a match. Returns true when used (otherwise they drive the menus).
function Match:gamepadpressed(j, button)
  if button == "start" then
    self.paused = not self.paused
    ui.reset()
    return true
  end
  if self.paused then return false end
  local st = self:status().state
  if st == "matchOver" then return false end
  local pu = self.pickUI
  if pu then
    -- Only the picker's own pad (local) or any pad (online, it's your pick) steers the pick.
    local inp = self.role == "local" and self.world.players[pu.slot].input or self.myInput
    if self.role == "local" and (inp.kind ~= "pad" or inp.joystick ~= j) then return true end
    local cp = self:currentPick()
    local n = cp and #cp.options or 0
    if self.discardMode then
      local owned = self:ownedCards(pu.slot)
      self.discardIndex = math.max(1, math.min(#owned, self.discardIndex or 1))
      if button == "dpleft" then self.discardIndex = (self.discardIndex - 2) % #owned + 1
      elseif button == "dpright" then self.discardIndex = self.discardIndex % #owned + 1
      elseif button == "a" and owned[self.discardIndex] then self:discardCard(owned[self.discardIndex].pos)
      elseif button == "b" or button == "dpdown" then self.discardMode = false end
    elseif n > 0 then
      if button == "dpleft" then pu.index = (pu.index - 2) % n + 1
      elseif button == "dpright" then pu.index = pu.index % n + 1
      elseif button == "a" then self:choosePick(pu.index)
      elseif button == "dpdown" and self:canDiscard(pu.slot) then self.discardMode, self.discardIndex = true, 1 end
    end
    return true
  end
  local inputs = self.role == "local" and self.inputs or { self.myInput }
  for _, inp in ipairs(inputs) do Input.gamepadpressed(inp, j, button) end
  return true
end

-- Key sets (as lookup tables) for moving the pick selection left / right and taking a card.
function Match:pickKeys(slot)
  local function set(...)
    local t = {}
    for _, k in ipairs({ ... }) do t[k] = true end
    return t
  end
  if self.role == "local" then
    local inp = self.world.players[slot] and self.world.players[slot].input
    if not inp or inp.kind ~= "keys" then return {}, {}, {}, {} end -- pads use gamepadpressed
    local b = inp.controls
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
      if self:isMine(cp.slot) then
        for _, c in ipairs(cp.options) do Profile.add(c.id, "offered") end
      end
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
      if self:isMine(i) then Profile.add(p.cards[n].id, "picked") end
    end
    self.cardCounts[i] = n
  end
  for i = #self.flyers, 1, -1 do
    local f = self.flyers[i]
    f.t = f.t + dt
    if f.t >= 0.6 then table.remove(self.flyers, i) end
  end
end

-- Is this slot played on this machine (by a person)? Used for the codex statistics.
function Match:isMine(slot)
  if self.role == "local" then
    local p = self.world.players[slot]
    return p and not p.isBot and not self.returnTo
  end
  return slot == self.mySlot
end

-- A round ended: count a win for every card the winner holds (if the winner is ours).
function Match:recordRound(st)
  local entered = st.state == "roundOver" and self.prevState ~= "roundOver"
  self.prevState = st.state
  if not entered or not st.winner then return end
  for i, p in ipairs(self:players()) do
    if p == st.winner and self:isMine(i) then
      for _, c in ipairs(p.cards) do Profile.add(c.id, "wins") end
      Profile.save()
    end
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
  local pickInput = self.role == "local" and pu and self.world.players[pu.slot].input
  local b = (pickInput and pickInput.kind == "keys" and pickInput.controls) or Settings.values.binds.online
  local padPick = pickInput and pickInput.kind == "pad"
  if pu then
    if self.discardMode then
      hint = "Choose a card to throw away  -  " .. Input.keyName(b.down) .. " to go back"
    elseif padPick then
      hint = "D-pad to turn over and choose, A to take, D-pad down to discard instead"
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

  if self.role == "client" and self.mySlot == 0 then
    app.centered("You're watching - you'll play in the next match", app.fonts.med, 370, { 1, 1, 1, 0.7 })
    return
  end
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

  local objs, effects, barrier = self:sceneObjects()
  love.graphics.push()
  love.graphics.translate(sx, sy)
  Map.draw(map)
  Objects.draw(objs, effects)
  hud.drawWells(wells)
  for _, b in ipairs(bullets) do b:draw() end
  for _, p in ipairs(players) do p:draw() end
  fx.draw()
  love.graphics.pop()

  if barrier then hud.drawBarrier(barrier) end

  Bloom.draw(function()
    love.graphics.translate(sx, sy)
    Objects.drawGlow(objs, effects)
    if barrier then hud.drawBarrier(barrier, true) end
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

  -- Connection trouble (clients): high ping or no snapshots for a while.
  if self.role == "client" then
    local stall = love.timer.getTime() - (self.snapTime or 0)
    if (self.rtt or 0) > 200 or stall > 0.5 then
      local x, y = app.W / 2 + 60, 14
      love.graphics.setColor(1, 0.75, 0.2, 0.9)
      love.graphics.polygon("fill", x, y + 18, x + 10, y, x + 20, y + 18)
      love.graphics.setColor(0.1, 0.1, 0.1)
      love.graphics.rectangle("fill", x + 9, y + 5, 2, 7)
      love.graphics.rectangle("fill", x + 9, y + 14, 2, 2)
      love.graphics.setFont(app.fonts.small)
      love.graphics.setColor(1, 0.75, 0.2, 0.9)
      love.graphics.print(stall > 0.5 and "connection lost?" or (math.floor(self.rtt) .. " ms"), x + 26, y + 1)
    end
  end

  if self:usesTouch() and not self.paused and (st.state == "countdown" or st.state == "playing" or st.state == "roundOver") then
    require("core.touch").draw()
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
