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
local Music = require "gfx.music"
local Atmosphere = require "gfx.atmosphere"
local Chat = require "online.chat"
local Cosmetics = require "core.cosmetics"
local Glyphs = require "core.glyphs"
local Recap = require "gfx.recap"
local Voice = require "online.voice"

local Match = {}
Match.__index = Match
Match.noPadHints = true

local SNAPSHOT_INTERVAL = 1 / 30
local INTERP_DELAY = 0.07   -- other players are drawn this far in the past, between real snapshots
local PING_EVERY = 1
local RECONNECT_TIME = 60     -- seconds a dropped player's slot is kept for them
local PICK_DELAY = 0.7 -- ignore "take" presses right after a hand appears
local LOAD_TIME = 1.3  -- the loading screen before a match

local function newMatch(role)
  return setmetatable({
    role = role,
    paused = false,
    toasts = {},
    pickUI = nil,   -- { slot, serial, index, delay, waiting } while this machine controls the pick
  }, Match)
end

local function ease(t)
  t = math.max(0, math.min(1, t))
  return 1 - (1 - t) ^ 3
end

function Match:enter()
  Music.play("match")
  -- In-match chat also pops up above the sender.
  self.bubbles = {}
  Chat.onLine = function(name, text) self.bubbles[name] = { text = text, t = 4 } end
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
  if kind == "mouse" then return Input.mouse(binds.online) end
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
  if opts.tutorial then m.tutorial = { step = 1, returnTo = opts.tutorialReturn } end
  local rules = settingsRules(false)
  rules.teams = opts.teams and true or false
  if opts.practice then
    rules.practice, rules.startCards, rules.suddenDeath = true, 0, 0
    rules.friendlyFire = false
    rules.mapVote, rules.cardBans, rules.mode, rules.subRounds = false, false, "elim", 1
    m.practice = { total = 0, hits = {}, last = 0, quiet = 0, prevHp = nil }
  end
  if opts.map then rules.forceMap = opts.map end
  if opts.test then
    rules.startCards, rules.suddenDeath, rules.mapVote, rules.cardBans, rules.mode, rules.subRounds = 0, 0, false, false, "elim", 1
  end
  if opts.map then rules.mapVote = false end
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
    if i == 1 and not bot then defs[i].hat, defs[i].eyes, defs[i].mouth, defs[i].detail = Cosmetics.mine() end
  end
  World.setSlotColors(colors)
  m.world = World.new(defs, winScore, rules)
  m:hookWorld()
  fx.recorder = nil
  m.loading = opts.loading and { t = 0 } or nil
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
    defs[i] = { name = s.name, input = input, peer = s.peer, team = s.team, bot = s.bot, hat = s.hat, eyes = s.eyes, mouth = s.mouth, detail = s.detail }
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
  m:broadcastRules()
  m.snapTimer = 0
  fx.recorder = {}
  m.loading = { t = 0 }
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
  for i, s in ipairs(slots) do
    m.proxies[i] = m:newProxy(i, s.name)
    m.proxies[i].team = s.team
    m.proxies[i].hat, m.proxies[i].eyes, m.proxies[i].mouth, m.proxies[i].detail = s.hat, s.eyes, s.mouth, s.detail
  end
  m.bulletViews, m.bulletList, m.wellList = {}, {}, {}
  m.snapTime = love.timer.getTime()
  m.loading = { t = 0 }
  fx.recorder = nil
  fx.clear()
  return m
end

function Match:leave()
  self.closed = true
  Profile.save()
  Music.setMuffle(0)
  Music.setIntensity(0)
  require("gfx.sfx").muffle = nil
  fx.solids = nil
  Chat.onLine = nil
  require("game.body").showNames = false
  if self.role == "client" then -- drop the host's session map and card lists
    Map.loadAll()
    Cards.loadAll()
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
  w.on.kill = function(victim, killer, kind)
    self:addKill(victim.slot, killer and killer.slot, kind)
    if self.role == "host" then self:broadcast(net.encodeKill(victim.slot, killer and killer.slot, kind), true) end
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
      suddenLeft = v.suddenLeft, mapVote = v.mapVote, cardBan = v.cardBan, hill = v.hill,
    }
  end
  local w = self.world
  return { state = w.state, timer = w.timer, winScore = w.winScore, winner = w.roundWinner, pick = self:currentPick(),
    suddenLeft = w.suddenLeft, mapVote = w.mapVote, cardBan = w.cardBan, hill = w.hill }
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
  if not self.loading then pu.delay = math.max(0, pu.delay - dt) end
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
    x = -1000, y = -1000, r = 20, leg = 14, subWins = 0, aimX = 1, aimY = 0, facing = 1,
    hp = 100, ammo = 3, reloadTimer = 0, blockTimer = 0, blockCd = 0,
    cloakTimer = 0, invuln = 0, poisonTimer = 0, slowTimer = 0,
    empowered = false, hitFlash = 0, livesLeft = 0, orbAngle = 0, dead = true,
  }, Player)
end

function Match:applySnapshot(v)
  self.snapped = true
  local now = love.timer.getTime()
  local view = self.view
  view.state, view.timer, view.winScore = v.state, v.timer, v.winScore
  view.mapIndex, view.winner, view.pick = v.mapIndex, v.winner, v.pick
  view.suddenLeft, view.mapVote, view.cardBan, view.hill = v.suddenLeft, v.mapVote, v.cardBan, v.hill
  view.banned = v.banned

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
    p.st = pv.st
    p.aimX, p.aimY = math.cos(pv.aim), math.sin(pv.aim)
    p.facing = pv.facing
    if pv.ammo < (p.ammo or 0) then p.shotT = 0.12 end
    p.hp = pv.hp
    p.r = pv.r
    p.leg = pv.r * 0.7
    p.subWins = v.subWins[i] or 0
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
    s.blockCooldown = 1 -- blockCd arrives as a fraction of the cooldown
    p.vote = pv.vote
    p.shield = pv.shield
    s.sentry = pv.sentry
    p.stunTimer = pv.stunned and 1 or 0
    p.charging, p.meleeCharge = pv.charging, pv.meleeCharge
    p.swingTimer, p.swingHeavy, p.swingPower = pv.swingTimer, pv.swingHeavy, pv.swingPower
    p.dashTimer = pv.dashing and 1 or 0
    if (p.vy or 0) > 300 and math.abs(pv.vy) < 60 then p.landSquash = math.min(0.35, p.vy / 3000) end
    p.vy = pv.vy
    p.vx, p.onGround = pv.vx, pv.onGround
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
  view.history = v.history
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
    elseif e[1] == 10 then
      fx.number(e[2], e[3], e[4], e[5], e[6])
    elseif e[1] == 11 then
      fx.gibs(e[2], e[3], e[4], e[5], e[6])
    elseif e[1] == 12 then
      fx.muzzle(e[2], e[3], e[4], e[5])
    elseif e[1] == 13 then
      fx.explosion(e[2], e[3], e[4], e[5])
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
  w.bodies = self.proxies -- other players are solid on your screen too
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
    pr.slot = self.mySlot -- so your own copy isn't an obstacle to yourself
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
  pr.blockTimer = pv.blocking and math.max(pr.blockTimer or 0, 0.05) or 0 -- blocking changes edge bounces
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
    p.shotT = math.max(0, (p.shotT or 0) - dt)
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
      if kind == net.MSG.CARDS then
        local ok, entries = pcall(net.decodeCards, msg.data)
        if ok then Cards.setSession(entries) end
      elseif kind == net.MSG.MAPS then
        local ok, entries = pcall(net.decodeMaps, msg.data)
        if ok then
          Map.setSession(entries)
          self.objMap = nil
        end
        self.mapsReady = true
      elseif kind == net.MSG.KILL then
        local ok, victim, killer, why = pcall(net.decodeKill, msg.data)
        if ok then self:addKill(victim, killer, why) end
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
            -- The gun's look comes from stats, which clients work out from the cards.
            local probe = Player.new(i, p.color, Input.remote())
            for k, c in ipairs(p.cards) do probe.cards[k] = c end
            probe:recompute()
            p.weaponStats = probe.stats
          end
        end
      elseif kind == net.MSG.RULES then
        local rules = net.decodeRules(msg.data, Cards.RARITIES)
        Cards.applyRules(rules)
        active.get().hostRules = rules
      elseif kind == net.MSG.CHAT then
        Chat.handle(active.get(), msg)
      elseif kind == net.MSG.VOICE then
        Voice.receive(active.get(), msg)
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
      elseif kind == net.MSG.CHAT then
        Chat.handle(active.get(), msg)
      elseif kind == net.MSG.VOICE then
        Voice.receive(active.get(), msg)
      elseif kind == net.MSG.MAPVOTE then
        local b = net.decodeByte(msg.data)
        self.world:castMapVote(info.slot, b % 128, b >= 128)
      elseif kind == net.MSG.CARDBAN then
        self.world:castBan(info.slot, Cards.list[net.decodeByte(msg.data)])
      end
    end
  end

  for _, ev in ipairs(self.popEvents()) do
    if ev.type == "left" and self.peers[ev.id] and not self.peers[ev.id].gone then
      local info = self.peers[ev.id]
      info.gone = true
      local who = self.world.players[info.slot]
      Chat.system(active.get(), ((who and who.name) or "Someone") .. " left")
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
      local session = active.get()
      Chat.system(session, (session.memberName and session.memberName(ev.id) or "Someone") .. " joined")
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

-- Everything a newcomer needs to follow the match: the slots, maps, cards, rules, roster.
function Match:sendSetup(peer)
  local t = self.transport
  t:send(peer, net.encodeStart(self.world.winScore, self.slots), true)
  t:send(peer, net.encodeMaps(Map.sessionEntries()), true)
  t:send(peer, net.encodeCards(Cards.sessionEntries()), true)
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
function Match:usesMouseAim()
  for _, inp in ipairs(self.inputs or {}) do if inp.kind == "mouse" then return true end end
  return false
end

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

-- Practice range: the dummy never dies (it heals after a moment), you respawn, and we keep a damage meter.
function Match:updatePractice(dt)
  local pr, w = self.practice, self.world
  if not pr or not w or w.state ~= "playing" then return end
  local me, dummy = w.players[1], w.players[2]
  local now = love.timer.getTime()
  if pr.prevHp and dummy.hp < pr.prevHp then
    local dmg = pr.prevHp - dummy.hp
    pr.total, pr.last, pr.quiet = pr.total + dmg, dmg, 0
    pr.hits[#pr.hits + 1] = { t = now, d = dmg }
  end
  pr.quiet = pr.quiet + dt
  while pr.hits[1] and now - pr.hits[1].t > 3 do table.remove(pr.hits, 1) end
  for _, p in ipairs({ me, dummy }) do
    if p.dead then
      p:spawn(p.spawnX, p.spawnY, p.facing, w)
    end
  end
  if dummy.hp < dummy.stats.maxHp and pr.quiet > 1.5 then dummy.hp = dummy.stats.maxHp end
  dummy.hp = math.max(1, dummy.hp)
  pr.prevHp = dummy.hp
end

function Match:drawPractice()
  local pr = self.practice
  if not pr then return end
  local dps = 0
  for _, h in ipairs(pr.hits) do dps = dps + h.d end
  dps = dps / 3
  love.graphics.setFont(app.fonts.med)
  love.graphics.setColor(1, 1, 1, 0.85)
  love.graphics.printf(string.format("Last hit %d   DPS %d   Total %d", pr.last, dps, pr.total), 0, 92, app.W, "center")
  if ui.button("Cards", app.W / 2 - 230, 130, 150, 34, { font = app.fonts.small }) then self.cardChooser = not self.cardChooser end
  if ui.button("Reset damage", app.W / 2 - 70, 130, 150, 34, { font = app.fonts.small }) then
    pr.total, pr.last, pr.hits = 0, 0, {}
  end
  local dummy = self.world.players[2]
  local isBot = dummy.isBot
  if ui.button(isBot and "Dummy: Bot" or "Dummy: Still", app.W / 2 + 90, 130, 150, 34, { font = app.fonts.small }) then
    if isBot then
      dummy.isBot = nil
      dummy.input = Input.remote()
      dummy.input.aim = nil
    else
      dummy.isBot = 2
      dummy.input = Input.bot(2)
    end
    dummy.seenJump, dummy.seenBlock, dummy.seenDash, dummy.seenMelee = 0, 0, 0, 0
  end
  if self.cardChooser then self:drawCardChooser() end
end

-- Every card (skipping `skip(card)`), grouped under rarity headings; hovering shows the full card.
-- onClick(card), onRight(card); label(card) and highlight(card) are optional.
function Match:drawCardGrid(top, skip, onClick, onRight, label, highlight)
  local cols, bw, bh, gapX, gapY = 7, 172, 18, 4, 3
  local x0 = (app.W - (cols * (bw + gapX) - gapX)) / 2
  local mx, my = app.mouse()
  local y = top
  local hovered
  for _, r in ipairs(Cards.RARITIES) do
    local list = {}
    for _, c in ipairs(Cards.list) do
      if c.rarity == r.id and not skip(c) then list[#list + 1] = c end
    end
    if #list > 0 then
      love.graphics.setFont(app.fonts.tiny)
      love.graphics.setColor(r.color)
      love.graphics.print(r.name:upper(), x0, y)
      y = y + 16
      for i, c in ipairs(list) do
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        local x, cy = x0 + col * (bw + gapX), y + row * (bh + gapY)
        local hi = highlight and highlight(c)
        if ui.button(label and label(c) or c.name, x, cy, bw, bh, { font = app.fonts.tiny, color = hi and ui.ACCENT or r.color }) then
          onClick(c)
        end
        if mx >= x and mx <= x + bw and my >= cy and my <= cy + bh then
          hovered = c
          if self.rightClick and onRight then onRight(c) end
        end
      end
      y = y + math.ceil(#list / cols) * (bh + gapY) + 5
    end
  end
  self.rightClick = nil
  if hovered then
    local w, h = 230, 320
    local px = mx < app.W / 2 and mx + 24 or mx - w - 24
    local py = math.max(10, math.min(app.H - h - 10, my - h / 2))
    hud.drawCard(hovered, px, py, w, h, false, { 1, 1, 1 })
  end
end

-- Click a card to add a copy, right click to remove one. Sorted by rarity.
function Match:drawCardChooser()
  local me = self.world.players[1]
  love.graphics.setColor(0, 0, 0, 0.85)
  love.graphics.rectangle("fill", 0, 0, app.W, app.H)
  local counts = {}
  for _, c in ipairs(me.cards) do counts[c] = (counts[c] or 0) + 1 end
  self:drawCardGrid(14, function(c) return c.special end, function(c)
    table.insert(me.cards, c)
    me:recompute()
  end, function(c)
    for k = #me.cards, 1, -1 do
      if me.cards[k] == c then
        table.remove(me.cards, k)
        break
      end
    end
    me:recompute()
  end, function(c) return c.name .. (counts[c] and ("  x" .. counts[c]) or "") end, function(c) return counts[c] end)
  if ui.button("Clear cards", app.W / 2 - 230, app.H - 44, 220, 34, { font = app.fonts.small }) then
    me.cards = {}
    me:recompute()
  end
  if ui.button("Close", app.W / 2 + 10, app.H - 44, 220, 34, { font = app.fonts.small, back = true }) then
    self.cardChooser = false
  end
end

function Match:update(dt, isTop)
  if self.recapOpen then
    Recap.update(self)
    if self:status().state ~= "matchOver" then self.recapOpen, self.recapShot = false, nil end
  end
  self:updatePresence()
  self:updatePractice(dt)
  if self.cardChooser then isTop = false end -- the practice card chooser is open: hold everyone still
  if self.loading then
    -- Host and clients both hold for the same time; a client also waits for the first snapshot.
    self.loading.t = self.loading.t + dt
    if self.loading.t >= LOAD_TIME and (self.role ~= "client" or self.snapped) then
      self.loading = nil
      app.fadeFrom(0.5)
    end
  end
  self:updateMapSlide(dt)
  if self:usesTouch() and require("core.touch").takePause() and isTop then
    self.paused = not self.paused
    ui.reset()
  end
  local suppressed = self.paused or not isTop or self.chatOpen or self.loading ~= nil
  fx.update(dt)
  self:updateAudio()
  for i = #self.toasts, 1, -1 do
    local t = self.toasts[i]
    t.t = t.t - dt
    if t.t <= 0 then table.remove(self.toasts, i) end
  end

  self:updatePickAnim(dt)
  self:recordRound(self:status())
  self:updateTutorial()
  -- Mouse aim is in world coordinates (the game view is zoomed to fit the screen).
  local mx, my = app.mouse()
  mx, my = mx / Map.VIEW, my / Map.VIEW
  if self.role == "local" then
    for i, inp in ipairs(self.inputs) do
      local p = inp.kind == "mouse" and self.world.players[i] or nil
      if inp.kind ~= "bot" then Input.poll(inp, suppressed, p and p.x, p and p.y, mx, my) end
    end
    if not self.paused and not self.loading then self.world:update(dt) end
    self:syncPick(dt)
  elseif self.role == "host" then
    local me = self.world.players[1]
    Input.poll(self.myInput, suppressed, me.x, me.y, mx, my)
    if not self.loading then self.world:update(dt) end
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

  if self.role ~= "local" or self:usesMouseAim() then
    local st = self:status().state
    if st ~= "matchOver" then self.pendingVote = nil end
    local playing = isTop and not self.paused and (st == "countdown" or st == "playing" or st == "roundOver")
    love.mouse.setVisible(not playing)
  end
end

---------------------------------------------------------------- votes and bans
-- Which player on this machine votes now: online you; on one screen, each player in turn.
function Match:voterSlot(chosen)
  if self.role ~= "local" then return (self.mySlot and self.mySlot > 0) and self.mySlot or nil end
  for i, p in ipairs(self.world.players) do
    if not p.isBot and not chosen[i] then return i end
  end
  return nil
end

function Match:castMapVote(slot, option, confirm)
  if self.role == "client" then
    self.transport:send(self.hostPeer, net.encodeByte(net.MSG.MAPVOTE, option + (confirm and 128 or 0)), true)
  else
    self.world:castMapVote(slot, option, confirm)
  end
end

-- Left / right (d = -1 / 1) and confirm on the map vote.
function Match:moveVote(d)
  local mv = self:status().mapVote
  local slot = self.voteSlot
  if not mv or not slot or mv.winner > 0 or self.voteLocked then return end
  self.voteCursor = ((self.voteCursor or 1) - 1 + d) % #mv.options + 1
  sfx.ui("uiHover")
  self:castMapVote(slot, self.voteCursor, false)
end

function Match:confirmVote()
  local mv = self:status().mapVote
  local slot = self.voteSlot
  if not mv or not slot or mv.winner > 0 or self.voteLocked then return end
  sfx.ui("uiClick")
  self:castMapVote(slot, self.voteCursor or 1, true)
  if self.role ~= "local" then self.voteLocked = true end
end

function Match:drawMapVote(st)
  local mv = st.mapVote
  if not mv then return end
  -- Comes in gently: the backdrop and title fade up, then the maps rise in one after another.
  local voteT = self.voteT or 0
  local fadeK = math.min(1, voteT / 0.4)
  love.graphics.setColor(0, 0, 0, 0.82 * fadeK)
  love.graphics.rectangle("fill", 0, 0, app.W, app.H)
  local players = self:players()
  local slot = mv.winner == 0 and self:voterSlot(mv.confirmed or {}) or nil
  if slot ~= self.voteSlot then
    self.voteSlot = slot
    if slot then
      self.voteCursor = 1
      self:castMapVote(slot, 1, false) -- the highlighted map counts if time runs out
    end
  end
  local title = "VOTE FOR THE NEXT MAP"
  if mv.winner > 0 then title = "NEXT MAP"
  elseif self.role == "local" and slot then title = (players[slot].name or "Player"):upper() .. ": VOTE FOR THE NEXT MAP" end
  app.centered(title, app.fonts.big, 34, { 1, 1, 1, fadeK })
  if mv.winner == 0 and mv.timeLeft then
    app.centered(tostring(math.max(0, math.ceil(mv.timeLeft))), app.fonts.title, 84, { 1, 1, 1, 0.7 * fadeK })
  end
  local n = #mv.options
  local perRow = n <= 3 and n or 3
  local rows = math.ceil(n / perRow)
  local w, h = n <= 3 and 370 or 330, rows == 1 and 300 or 240
  local gap = 22
  local top = rows == 1 and 170 or 130
  for i, idx in ipairs(mv.options) do
    local col, row = (i - 1) % perRow, math.floor((i - 1) / perRow)
    local inRow = row == rows - 1 and (n - (rows - 1) * perRow) or perRow
    local rowW = inRow * w + (inRow - 1) * gap
    local x, y = (app.W - rowW) / 2 + col * (w + gap), top + row * (h + gap)
    local rise = ease((voteT - 0.18 - (i - 1) * 0.1) / 0.42)
    y = y + (1 - rise) * (app.H - y + 20)
    local map = Map.list[idx]
    local mine = slot and (self.voteCursor or 1) == i
    local won = mv.winner == i
    local color = won and ui.GOOD or (mine and (self.voteLocked and ui.GOOD or ui.ACCENT) or nil)
    self.voteRects = self.voteRects or {}
    self.voteRects[i] = { x, y, w, h }
    love.graphics.setColor(ui.WIDGET)
    love.graphics.rectangle("fill", x, y, w, h, 10, 10)
    love.graphics.setColor(color or { 1, 1, 1, 0.12 })
    love.graphics.setLineWidth(color and 3 or 2)
    love.graphics.rectangle("line", x, y, w, h, 10, 10)
    if map then
      local thumbH = h - 62
      require("screens.editor_hub").drawThumb(map, x + 10, y + 10, w - 20, thumbH)
      love.graphics.setColor(1, 1, 1)
      ui.printFit(map.name, app.fonts.med, x + 14, y + h - 46, w - 28, "center")
    end
    local dotX = x + w / 2 - (#players - 1) * 11
    for k, p in ipairs(players) do
      if mv.votes[k] == i then
        love.graphics.setColor(p.color)
        love.graphics.circle("fill", dotX + (k - 1) * 22, y + h - 14, 7)
      end
    end
  end
end

function Match:drawCardBan(st)
  local cb = st.cardBan
  if not cb then return end
  love.graphics.setColor(0, 0, 0, 0.88)
  love.graphics.rectangle("fill", 0, 0, app.W, app.H)
  local players = self:players()
  local slot = self:voterSlot(cb.picks)
  local title = "BAN A CARD"
  if self.role == "local" and slot then title = (players[slot].name or "Player"):upper() .. ": BAN A CARD"
  elseif not slot then title = "WAITING FOR THE OTHERS" end
  app.centered(title .. "   " .. math.max(0, math.ceil(cb.timeLeft)), app.fonts.title, 12)
  local function pickedCard(c)
    for _, v in pairs(cb.picks) do
      if v == c or v == c.index then return true end
    end
    return false
  end
  self:drawCardGrid(50, function(c) return c.disabled end, function(c)
    if not slot then return end
    if self.role == "client" then
      self.transport:send(self.hostPeer, net.encodeByte(net.MSG.CARDBAN, c.index), true)
    else
      self.world:castBan(slot, c)
    end
  end, nil, nil, pickedCard)
end

---------------------------------------------------------------- chat
-- Speech bubbles above whoever just said something.
function Match:drawBubbles(players)
  local dt = love.timer.getDelta()
  local font = app.fonts.small
  for name, b in pairs(self.bubbles or {}) do
    b.t = b.t - dt
    if b.t <= 0 then
      self.bubbles[name] = nil
    else
      for _, p in ipairs(players) do
        if p.name == name and not p.dead then
          local maxW = 220
          local w, lines = font:getWrap(b.text, maxW)
          local h = #lines * font:getHeight() + 12
          local bw = w + 20
          local cx, top = p.x * Map.VIEW, (p.y - p.r - 62) * Map.VIEW - h
          local bx = math.max(6, math.min(app.W - bw - 6, cx - bw / 2))
          local by = math.max(4, top)
          local a = math.min(1, b.t * 2)
          love.graphics.setColor(0.96, 0.96, 0.98, 0.95 * a)
          love.graphics.rectangle("fill", bx, by, bw, h, 8, 8)
          love.graphics.polygon("fill", cx - 6, by + h - 1, cx + 6, by + h - 1, cx, by + h + 8)
          love.graphics.setColor(0.1, 0.1, 0.13, a)
          love.graphics.setFont(font)
          love.graphics.printf(b.text, bx + 10, by + 6, w, "center")
          break
        end
      end
    end
  end
end

function Match:drawChat(st)
  if self.role == "local" then return end
  local session = active.get()
  local x, y, w = 16, app.H - 62, 430
  if self.chatOpen then
    love.graphics.setColor(0, 0, 0, 0.55)
    love.graphics.rectangle("fill", x - 8, y - 190, w + 16, 234, 8, 8)
    Chat.draw(x, y - 4, w, 11)
    if self.chatFresh then
      ui.text = ""
      self.chatFresh = false
    end
    local text, submitted = ui.textField(self.chatText or "", x, y, w, 36, { font = app.fonts.small, maxLength = 240,
      forceFocus = true, align = "left", placeholder = "Say something" })
    self.chatText = text
    if submitted then
      Chat.send(session, text)
      self.chatOpen = false
    end
  else
    Chat.draw(x, y + 28, w, 6, 8)
    if self:usesTouch() and ui.button("Chat", app.W - 110, 62, 90, 34, { font = app.fonts.small }) then self:openChat() end
  end
end

---------------------------------------------------------------- first-run tutorial
local TUTORIAL = {
  { id = "move", text = "Move left and right", key = function(n, b) return n(b.left) .. " / " .. n(b.right) end, pad = "{ls} Left stick", touch = "Drag on the left side" },
  { id = "aim", text = "Aim all around you", only = { mouse = true, pad = true }, key = function() return "Move the mouse" end, pad = "{rs} Right stick", touch = "" },
  { id = "jump", text = "Jump", key = function(n, b) return n(b.up) end, pad = "{a}", touch = "Jump button" },
  { id = "double", text = "Jump again in the air", key = function(n, b) return n(b.up) .. " twice" end, pad = "{a} twice", touch = "Jump button twice" },
  { id = "fire", text = "Shoot", key = function(n, b) return n(b.fire) end, pad = "{rt}", touch = "Drag on the right side" },
  { id = "block", text = "Block: it reflects bullets", key = function(n, b) return n(b.block) end, pad = "{lt}", touch = "Block button" },
  { id = "dash", text = "Dash", key = function(n, b) return n(b.dash) end, pad = "{b}", touch = "Dash button" },
  { id = "melee", text = "Melee: tap, or hold for a heavy hit", key = function(n, b) return n(b.melee) end, pad = "{x}", touch = "Melee button" },
  { id = "hit", text = "Land a shot on the dummy", key = function() return "" end, pad = "", touch = "" },
}

-- The mouse scheme names jump and movement a little differently from the keyboard ones.
local function tutorialBinds(inp)
  local b = inp.controls or Settings.values.binds.p1
  if inp.kind ~= "mouse" then return b end
  return setmetatable({ up = b.jump }, { __index = b })
end

function Match:updateTutorial()
  local tu = self.tutorial
  if not tu or tu.done then return end
  local w = self.world
  local me = w and w.players[1]
  if not me or w.state ~= "playing" then return end
  local inp = me.input
  if not tu.steps then
    tu.steps = {}
    for _, s in ipairs(TUTORIAL) do
      if not s.only or s.only[inp.kind] then tu.steps[#tu.steps + 1] = s end
    end
  end
  local step = tu.steps[tu.step]
  if not step then
    tu.done = true
    return
  end
  tu.base = tu.base or { aim = inp.aim or 0, x = me.x, jump = inp.jumpCount or 0, shots = me.st.shots or 0, block = inp.blockCount or 0,
    dash = inp.dashCount or 0, melee = inp.meleeCount or 0, dmg = me.st.dmg or 0 }
  local b, ok = tu.base, false
  if me.onGround then tu.airJumps = 0 end
  if (inp.jumpCount or 0) ~= (tu.lastJump or 0) then
    if not me.onGround then tu.airJumps = (tu.airJumps or 0) + 1 end
    tu.lastJump = inp.jumpCount or 0
  end
  if step.id == "aim" then
    tu.aimTravel = (tu.aimTravel or 0) + math.abs(math.atan2(math.sin((inp.aim or 0) - b.aim), math.cos((inp.aim or 0) - b.aim)))
    b.aim = inp.aim or 0
    ok = tu.aimTravel > 3
  elseif step.id == "move" then ok = math.abs(me.x - b.x) > 120
  elseif step.id == "jump" then ok = (inp.jumpCount or 0) > b.jump
  elseif step.id == "double" then ok = (tu.airJumps or 0) >= 1
  elseif step.id == "fire" then ok = (me.st.shots or 0) > b.shots
  elseif step.id == "block" then ok = (inp.blockCount or 0) > b.block
  elseif step.id == "dash" then ok = (inp.dashCount or 0) > b.dash
  elseif step.id == "melee" then ok = (inp.meleeCount or 0) > b.melee
  elseif step.id == "hit" then ok = (me.st.dmg or 0) > b.dmg end
  if ok then
    tu.step, tu.base = tu.step + 1, nil
    sfx.ui("uiClick")
    if not tu.steps[tu.step] then tu.done = true end
  end
end

function Match:drawTutorial()
  local tu = self.tutorial
  if not tu or self.paused or self.cardChooser then return end
  if not tu.done and not (tu.steps and tu.steps[tu.step]) then return end -- still counting down
  local x, y, w, h = app.W / 2 - 300, 170, 600, 104
  ui.panel(x, y, w, h, 0.92)
  if tu.done then
    love.graphics.setFont(app.fonts.title)
    love.graphics.setColor(ui.GOOD)
    love.graphics.printf("You're ready!", x, y + 14, w, "center")
    if ui.button("Finish", x + 180, y + 54, 240, 40, { color = ui.GOOD }) then
      app.switch(tu.returnTo and tu.returnTo() or require("screens.menu").new())
    end
    return
  end
  local step = tu.steps and tu.steps[tu.step]
  if not step then return end
  local me = self.world.players[1]
  local kind = me.input.kind
  local hint
  if kind == "pad" then hint = step.pad
  elseif kind == "touch" then hint = step.touch
  else hint = step.key(Input.keyName, tutorialBinds(me.input)) end
  love.graphics.setFont(app.fonts.tiny)
  love.graphics.setColor(1, 1, 1, 0.5)
  love.graphics.print("Step " .. tu.step .. " of " .. #tu.steps, x + 18, y + 12)
  love.graphics.setColor(1, 1, 1)
  ui.printFit(step.text, app.fonts.title, x + 20, y + 28, w - 160, "left")
  love.graphics.setColor(ui.GOLD)
  if kind == "pad" then
    Glyphs.print(hint, app.fonts.med, x + 20, y + 68, w - 160, "left", ui.GOLD)
  else
    ui.printFit(hint, app.fonts.med, x + 20, y + 68, w - 160, "left")
  end
  if ui.button("Skip", x + w - 120, y + 32, 100, 40, { font = app.fonts.small, back = true }) then
    app.switch(tu.returnTo and tu.returnTo() or require("screens.menu").new())
  end
end

---------------------------------------------------------------- input
function Match:scoreboardVisible()
  if self.showScores then return true end
  if not Settings.values.scoreboardHold then return false end
  if Input.isDown(Settings.values.binds.online.scoreboard) then return true end
  for _, j in ipairs(Input.pads()) do
    if j:isGamepadDown("back") then return true end
  end
  return false
end

-- The arena slides out to the left when a round gives way to card picks or the map vote, stays
-- away while they're on screen, and the next map slides in from the right. The HUD stays put.
local MAP_SLIDE_TIME = 0.7
local NO_MAP_STATES = { cardPick = true, mapVote = true, cardBan = true }

function Match:updateMapSlide(dt)
  if self.loading then return end
  if self.role == "client" and not self.snapped then return end -- nothing from the host yet
  local state = self:status().state
  if state == "mapVote" then self.voteT = (self.voteT or 0) + dt else self.voteT = 0 end
  local prev = self.slideState
  if state ~= prev then
    self.slideState = state
    if state == "mapVote" then self.voteSlot, self.voteCursor, self.voteLocked = nil, 1, false end
    if NO_MAP_STATES[state] then
      if prev and not NO_MAP_STATES[prev] then
        self.mapSlide = { kind = "out", t = 0 }
      elseif not prev then
        self.mapHidden = true
      end
    elseif state == "countdown" and prev and prev ~= "countdown" and prev ~= "subRound" then
      self.mapHidden, self.mapSlide = false, { kind = "in", t = 0 }
    end
  end
  local s = self.mapSlide
  if s then
    s.t = s.t + dt
    if s.t >= MAP_SLIDE_TIME then
      if s.kind == "out" then self.mapHidden = true end
      self.mapSlide = nil
    end
  end
end

-- How far the arena is drawn from its place (screen units), and how far a slide has got (0-1).
function Match:mapOffset()
  local s = self.mapSlide
  if not s then return 0, 1 end
  local k = math.min(1, s.t / MAP_SLIDE_TIME)
  local e = 1 - (1 - k) ^ 3
  if s.kind == "out" then return -app.W * e, k end
  return app.W * (1 - e), k
end

-- Music follows sudden death; sound muffles when you're nearly or just dead; the background shifts.
function Match:updateAudio()
  local st = self:status()
  Music.setIntensity((st.suddenLeft and st.suddenLeft <= 0) and 1 or 0)
  local _, _, _, map = self:scene()
  fx.solids = map and map.rects or nil
  local players = self:players()
  local cx, cy, n = 0, 0, 0
  for _, p in ipairs(players) do
    if not p.dead and p.x > -500 then cx, cy, n = cx + p.x, cy + p.y, n + 1 end
  end
  if n > 0 then
    local tx, ty = (cx / n) / (Map.W / 2) - 1, (cy / n) / (Map.H / 2) - 1
    Atmosphere.camX = Atmosphere.camX + (tx - Atmosphere.camX) * 0.06
    Atmosphere.camY = Atmosphere.camY + (ty - Atmosphere.camY) * 0.06
  end
  local mine = self:myPlayers()
  local level = 0
  if #mine == 1 and (st.state == "playing" or st.state == "roundOver") then
    local p = mine[1]
    if p.dead then level = 0.75
    elseif p.hp < p.stats.maxHp * 0.25 then level = 0.5 end
  end
  if st.state == "roundOver" then level = math.max(level, 0.35) end
  self.muffle = (self.muffle or 0) + (level - (self.muffle or 0)) * 0.12
  Music.setMuffle(self.muffle)
  sfx.muffle = self.muffle > 0.03 and { type = "lowpass", volume = 1, highgain = 1 - self.muffle * 0.85 } or nil
end

function Match:openChat()
  if self.role == "local" or self.chatOpen then return end
  self.chatOpen, self.chatText, self.chatFresh = true, "", true
  ui.key = nil
end

function Match:keypressed(key)
  if self.chatOpen then
    if key == "escape" then self.chatOpen = false end
    return
  end
  if self.role ~= "local" and key == Settings.values.binds.online.chat and not self.paused then
    self:openChat()
    return
  end
  local stateNow = self:status().state
  if stateNow == "mapVote" and key ~= "escape" then
    if self.paused or not self.voteSlot then return end
    local left, right, take = self:pickKeys(self.voteSlot)
    if left[key] then self:moveVote(-1) elseif right[key] then self:moveVote(1) elseif take[key] then self:confirmVote() end
    return
  end
  if stateNow == "cardBan" and key ~= "escape" then return end
  if self.practice and key == "c" then
    self.cardChooser = not self.cardChooser
    return
  end
  if self.practice and self.cardChooser and key == "escape" then
    self.cardChooser = false
    return
  end
  if key == Settings.values.binds.online.scoreboard and not Settings.values.scoreboardHold then
    self.showScores = not self.showScores
    return
  end
  if key == "escape" and self.recapOpen then
    self.recapOpen = false
    return
  end
  if key == "escape" and self.showScores then
    self.showScores = false
    return
  end
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
    local left, right, take, discard = self:pickKeys(pu.slot)
    if self.discardMode then
      local owned = self:ownedCards(pu.slot)
      local m = #owned
      self.discardIndex = math.max(1, math.min(m, self.discardIndex or 1))
      if m == 0 or discard[key] then
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
    elseif discard[key] and self:canDiscard(pu.slot) then
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
  if self.recapOpen then return false end -- the recap is a menu: B and Start close it
  if button == "back" then
    if not Settings.values.scoreboardHold then self.showScores = not self.showScores end
    return true
  end
  if button == "start" then
    self.paused = not self.paused
    ui.reset()
    return true
  end
  if self.paused then return false end
  local st = self:status().state
  if st == "mapVote" then
    local slot = self.voteSlot
    local inp = slot and (self.role == "local" and self.world.players[slot].input or self.myInput)
    if inp and (self.role ~= "local" or (inp.kind == "pad" and inp.joystick == j)) then
      if button == "dpleft" then self:moveVote(-1)
      elseif button == "dpright" then self:moveVote(1)
      elseif button == "a" then self:confirmVote() end
    end
    return true
  end
  if st == "matchOver" or st == "cardBan" then return false end
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
      elseif button == "b" or button == "y" then self.discardMode = false end
    elseif n > 0 then
      if button == "dpleft" then pu.index = (pu.index - 2) % n + 1
      elseif button == "dpright" then pu.index = pu.index % n + 1
      elseif button == "a" then self:choosePick(pu.index)
      elseif button == "y" and self:canDiscard(pu.slot) then self.discardMode, self.discardIndex = true, 1 end
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
    return set(b.left), set(b.right), set(b.fire, b.up), set(b.discard)
  end
  local b = Settings.values.binds.online
  return set(b.left, "left"), set(b.right, "right"), set(b.jump), set(b.discard)
end

function Match:mousepressed(x, y, button)
  if self.paused or self.chatOpen then return end
  local stateNow = self:status().state
  if stateNow == "mapVote" and self:usesTouch() and button == 1 then
    -- Phones have no keys: a tap selects, a second tap confirms.
    for i, r in ipairs(self.voteRects or {}) do
      if x >= r[1] and x <= r[1] + r[3] and y >= r[2] and y <= r[2] + r[4] then
        if i == self.voteCursor then self:confirmVote() else self:moveVote(i - (self.voteCursor or 1)) end
        return
      end
    end
  end
  if stateNow == "mapVote" or stateNow == "cardBan" then return end
  if self.cardChooser and button == 2 then self.rightClick = true end
  if self.cardChooser then return end
  local pu = self.pickUI
  if pu then
    local cp = self:currentPick()
    if self.discardMode then return end -- the discard panel's buttons handle clicks
    -- Cards are chosen with the keys; phones have none, so a tap selects and a second tap takes.
    if self:usesTouch() and button == 1 and cp then
      for i, r in ipairs(hud.cardRects(#cp.options, 0)) do
        if x >= r[1] and x <= r[1] + r[3] and y >= r[2] and y <= r[2] + r[4] then
          if pu.index == i then self:choosePick(i) else pu.index = i end
          return
        end
      end
    end
    return
  end
  if self.role ~= "local" then
    Input.mousepressed(self.myInput, button)
  else
    for _, inp in ipairs(self.inputs) do Input.mousepressed(inp, button) end
  end
end

---------------------------------------------------------------- drawing
---------------------------------------------------------------- card pick animation
local DEAL_STAGGER, DEAL_TIME, FLIP_TIME = 0.1, 0.41, 0.37
local DEAL_WAIT = 0.25 -- after a round, the arena is on its way out before the cards come in
local LIFT_SPEED = 14 -- how fast the hovered card slides up
local REVEAL_SOUND = { rare = "revealRare", epic = "revealEpic", legendary = "revealLegendary" }

-- Dealing, flipping and reveal sparkles; also cards flying to a player's panel after a pick.
-- Sounds here are local (every machine animates the same pick), so they aren't recorded.
function Match:updatePickAnim(dt)
  if self.loading then return end
  local cp = self:currentPick()
  local a = self.pickAnim
  if cp then
    if not a or a.serial ~= cp.serial or a.slot ~= cp.slot then
      a = { serial = cp.serial, slot = cp.slot, t = self.mapSlide and -DEAL_WAIT or 0, flip = {}, sparkles = {}, lift = {} }
      self.pickAnim = a
      sfx.play("cardDeal", nil, 1, 1, true)
      if self:isMine(cp.slot) then
        for _, c in ipairs(cp.options) do Profile.add(c.id, "offered") end
      end
    end
    a.t = a.t + dt
    -- The hovered card slides up; a change of hover ticks like hovering a menu button.
    local pu = self.pickUI
    local hovered = pu and pu.index or cp.hover
    for i = 1, #cp.options do
      local target = i == hovered and 1 or 0
      a.lift[i] = (a.lift[i] or 0) + (target - (a.lift[i] or 0)) * math.min(1, dt * LIFT_SPEED)
    end
    if a.lastHover and a.lastHover ~= hovered and pu then sfx.ui("uiHover") end
    a.lastHover = hovered
    for i, card in ipairs(cp.options) do
      local arrived = a.t > (i - 1) * DEAL_STAGGER + DEAL_TIME
      if cp.flipped[i] and arrived then
        local before = a.flip[i] or 0
        a.flip[i] = math.min(1, before + dt / FLIP_TIME)
        if before < 0.5 and a.flip[i] >= 0.5 then
          sfx.play("cardFlip", nil, 0.8, 1, true)
          if REVEAL_SOUND[card.rarity] then sfx.play(REVEAL_SOUND[card.rarity], nil, 1, 1, true) end
          local n = ({ rare = 14, epic = 28, legendary = 56 })[card.rarity]
          if n then
            a.flare = a.flare or {}
            a.flare[i] = 1
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
    for k, v in pairs(a.flare or {}) do a.flare[k] = math.max(0, v - dt * 2.2) end
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
      if self:isMine(i) then
        Profile.add(p.cards[n].id, "picked")
        Profile.bump("picks")
      end
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
  local Ach = require "core.achievements"
  local prev = self.prevState
  self.prevState = st.state
  if st.state == prev then return end
  local players = self:players()
  if st.state == "countdown" then
    local _, _, _, map = self:scene()
    if map and map.id and not self.practice then Profile.visitMap(map.id) end
  elseif st.state == "roundOver" and st.winner then
    for i, p in ipairs(players) do
      local won = p == st.winner or (st.winner.team and p.team == st.winner.team)
      if won and self:isMine(i) then
        if p == st.winner then
          for _, c in ipairs(p.cards) do Profile.add(c.id, "wins") end
        end
        Profile.bump("rounds")
        if st.hill then Profile.bump("hillWins") end
        if p.stats and p.hp and p.hp >= p.stats.maxHp and not p.dead then Profile.bump("flawless") end
        if st.suddenLeft and st.suddenLeft <= 0 then Profile.bump("sudden") end
      end
    end
    Ach.check()
    Profile.save()
  elseif st.state == "matchOver" then
    for i, p in ipairs(players) do
      if self:isMine(i) then
        Profile.bump("matches")
        if st.winner and (p == st.winner or (st.winner.team and p.team == st.winner.team)) then Profile.bump("wins") end
        Profile.record("peakCards", #p.cards)
        local different, seenCards = 0, {}
        for _, c in ipairs(p.cards) do
          if not seenCards[c] then seenCards[c], different = true, different + 1 end
        end
        if different >= 5 then Profile.bump("decks") end
        local blocks = p.st and p.st.blocks or 0
        self.countedBlocks = self.countedBlocks or {}
        if blocks > (self.countedBlocks[i] or 0) then
          Profile.bump("blocks", blocks - (self.countedBlocks[i] or 0))
          self.countedBlocks[i] = blocks
        end
      end
    end
    Ach.check()
    Profile.save()
  end
end

-- Where a player's score panel is (for flying cards).
function Match:panelPos(slot)
  return app.W - 40, 26 + (slot - 1) * 38
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
  -- The arena is leaving; the backdrop darkens behind the cards as it goes.
  local _, slideK = self:mapOffset()
  love.graphics.setColor(0.06, 0.06, 0.09, self.mapSlide and (0.35 + 0.6 * slideK) or 0.97)
  love.graphics.rectangle("fill", 0, 0, app.W, app.H)

  local cp = st.pick
  if not cp or #cp.options == 0 then return end
  local players = self:players()
  local p = players[cp.slot]
  local color = p and p.color or { 1, 1, 1 }
  local name = (p and p.name or ("Player " .. cp.slot)):upper()
  local pu = self.pickUI
  local count = cp.total > 1 and ("  (" .. cp.num .. "/" .. cp.total .. ")") or ""
  local a = self.pickAnim
  local inK = a and math.max(0, math.min(1, a.t / 0.4)) or 1

  local title
  if pu and self.role ~= "local" then title = "PICK A CARD" .. count
  elseif pu then title = name .. " - PICK A CARD" .. count
  else title = name .. " IS PICKING" .. count end
  app.centered(title, app.fonts.big, 18, { color[1], color[2], color[3], inK })
  local hint
  if pu then
    if self.discardMode then hint = "Choose a card to throw away" end
    if pu.waiting then hint = "Waiting for the host..." end
  else
    hint = "Watching " .. (p and p.name or "them") .. " choose"
  end
  if hint then app.centered(hint, app.fonts.med, 64, { 1, 1, 1, 0.7 * inK }) end

  if cp.timeLeft then
    local total = math.max(1, Cards.rules.pickTimer or cp.timeLeft)
    local frac = math.max(0, math.min(1, cp.timeLeft / total))
    local bw = 420
    love.graphics.setColor(1, 1, 1, 0.12)
    love.graphics.rectangle("fill", (app.W - bw) / 2, 94, bw, 6, 3, 3)
    love.graphics.setColor(frac < 0.25 and { 1, 0.35, 0.3 } or color)
    love.graphics.rectangle("fill", (app.W - bw) / 2, 94, bw * frac, 6, 3, 3)
    love.graphics.setFont(app.fonts.small)
    love.graphics.setColor(1, 1, 1, 0.6)
    love.graphics.printf(math.ceil(cp.timeLeft) .. "s", (app.W + bw) / 2 + 10, 88, 60, "left")
  end

  if #cp.queued > 0 then
    local names = {}
    for _, slot in ipairs(cp.queued) do
      names[#names + 1] = players[slot] and players[slot].name or ("Player " .. slot)
    end
    love.graphics.setColor(1, 1, 1, 0.55)
    ui.printFit("Up next: " .. table.concat(names, ", "), app.fonts.med, 24, 680, 340, "left")
  end

  if pu and self.discardMode then return self:drawDiscard(cp, color) end

  local index = pu and pu.index or cp.hover
  local rects = hud.cardRects(#cp.options, index, a and a.lift)
  local handX, handY = app.W / 2, 560
  local function drawOne(i)
    local card, r = cp.options[i], rects[i]
    local appear = a and (a.t - (i - 1) * DEAL_STAGGER) / DEAL_TIME or 1
    if appear <= 0 then return end
    local e = ease(appear)
    local lift = a and (a.lift[i] or 0) or (i == index and 1 or 0)
    local cx = handX + (r.cx - handX) * e
    local cy = handY + (r.cy - handY) * e
    local flip = a and a.flip[i] or (cp.flipped[i] and 1 or 0)
    local sx = (flip < 0.5 and (1 - 2 * flip) or (2 * flip - 1))
    local w, h = r[3], r[4]
    love.graphics.push()
    love.graphics.translate(cx, cy)
    love.graphics.rotate(r.a * e)
    local s = (0.35 + 0.65 * e) * (1 + 0.08 * lift)
    love.graphics.scale(math.max(0.02, sx) * s, s)
    -- A rare card flashes as it turns over.
    local flare = a and a.flare and a.flare[i]
    if flare and flare > 0 then
      local fc = Cards.rarity[card.rarity].color
      local grow = (1 - flare) * 54
      love.graphics.setBlendMode("add")
      love.graphics.setColor(fc[1], fc[2], fc[3], 0.6 * flare)
      love.graphics.rectangle("fill", -w / 2 - grow, -h / 2 - grow, w + grow * 2, h + grow * 2, 14 + grow, 14 + grow)
      love.graphics.setBlendMode("alpha")
    end
    if flip < 0.5 then
      hud.drawCardBack(-w / 2, -h / 2, w, h, i == index, color)
    else
      hud.drawCard(card, -w / 2, -h / 2, w, h, i == index, color)
    end
    if i ~= index then
      love.graphics.setColor(0.04, 0.04, 0.07, 0.42 * (1 - lift))
      love.graphics.rectangle("fill", -w / 2, -h / 2, w, h, 14, 14)
    end
    love.graphics.pop()
  end
  for i = 1, #cp.options do
    if i ~= index then drawOne(i) end
  end
  drawOne(index)

  if a then
    for _, sp in ipairs(a.sparkles) do
      local c = sp.color
      love.graphics.setColor(c[1], c[2], c[3], math.min(1, sp.life * 2))
      love.graphics.circle("fill", sp.x, sp.y, sp.size)
      love.graphics.setColor(1, 1, 1, math.min(1, sp.life * 2) * 0.8)
      love.graphics.circle("fill", sp.x, sp.y, sp.size * 0.4)
    end
  end

  -- The picker's character, aiming at the selected card.
  local fig = self.pickFig
  if not fig or fig.owner ~= cp.slot then
    fig = { owner = cp.slot, x = app.W / 2, y = 556, r = 86, slot = cp.slot, facing = 1, aimX = 0, aimY = -1, armReach = 360, noGun = true }
    self.pickFig = fig
  end
  if p then fig.color, fig.hat, fig.eyes, fig.mouth, fig.detail = p.color, p.hat, p.eyes, p.mouth, p.detail end
  local sel = rects[index]
  local tx, ty = sel.cx, sel.cy + sel[4] * 0.56
  local dx, dy = tx - fig.x, ty - fig.y
  local d = math.max(1, math.sqrt(dx * dx + dy * dy))
  fig.aimX, fig.aimY, fig.gunTarget = dx / d, dy / d, { tx, ty }
  require("game.body").drawFigure(fig, love.timer.getDelta())

  if pu and not pu.waiting and self:isPadPicker(pu.slot) then
    Glyphs.print("{dlr} Choose     {a} Take", app.fonts.med, app.W - 300, 646, 280, "right", { 1, 1, 1, 0.65 })
  end
  if pu and not pu.waiting and self:canDiscard(pu.slot) then
    if self:usesTouch() then
      if ui.button("Discard instead", app.W - 256, 664, 236, 40, { font = app.fonts.med }) then
        self.discardMode, self.discardIndex = true, 1
      end
    else
      self:drawDiscardHint(pu.slot, "discard instead")
    end
  end
end

function Match:isPadPicker(slot)
  local inp = self.role == "local" and self.world.players[slot].input or self.myInput
  return inp and inp.kind == "pad"
end

-- "<discard control>: <what it does>", as an icon for a controller.
function Match:drawDiscardHint(slot, what)
  if self:isPadPicker(slot) then
    Glyphs.print("{y} " .. what, app.fonts.med, app.W - 300, 676, 280, "right", { 1, 1, 1, 0.65 })
  else
    love.graphics.setColor(1, 1, 1, 0.65)
    ui.printFit(self:discardKeyName(slot) .. ": " .. what, app.fonts.med, app.W - 300, 676, 280, "right")
  end
end

-- Discard mode: the picker's owned cards as buttons.
function Match:drawDiscard(cp, color)
  local pu = self.pickUI
  local owned = self:ownedCards(pu.slot)
  self.discardIndex = math.max(1, math.min(#owned, self.discardIndex or 1))
  local touch = self:usesTouch()
  local cols = 4
  local bw, bh, gap = 270, 46, 12
  local rows = math.ceil(#owned / cols)
  local x0 = (app.W - (math.min(cols, #owned) * (bw + gap) - gap)) / 2
  local y0 = 120
  for i, o in ipairs(owned) do
    local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
    local x, y = x0 + col * (bw + gap), y0 + row * (bh + gap)
    local label = o.card.name .. (o.count > 1 and ("  x" .. o.count) or "")
    local rc = Cards.rarity[o.card.rarity].color
    local sel = i == self.discardIndex
    if touch then
      if ui.button(label, x, y, bw, bh, { font = app.fonts.med, color = sel and color or rc }) then
        if sel then
          self:discardCard(o.pos)
          return
        end
        self.discardIndex = i
      end
    else
      love.graphics.setColor(sel and ui.WIDGET_ON or ui.WIDGET)
      love.graphics.rectangle("fill", x, y, bw, bh, 10, 10)
      love.graphics.setColor(sel and color or rc)
      love.graphics.setLineWidth(sel and 3 or 2)
      love.graphics.rectangle("line", x, y, bw, bh, 10, 10)
      love.graphics.setColor(1, 1, 1)
      ui.printFit(label, app.fonts.med, x + 10, y + (bh - app.fonts.med:getHeight()) / 2, bw - 20, "center")
    end
  end
  local show = owned[self.discardIndex]
  if show then
    local y = y0 + rows * (bh + gap) + 10
    hud.drawCard(show.card, app.W / 2 - 110, math.min(y, 390), 220, 300, false, color)
  end
  if touch then
    if ui.button("Back to the cards", app.W / 2 - 150, 690, 300, 26, { font = app.fonts.small, back = true }) then
      self.discardMode = false
    end
  else
    self:drawDiscardHint(pu.slot, "back to the cards")
  end
end

-- The discard control's name for whoever is choosing.
function Match:discardKeyName(slot)
  local inp = self.role == "local" and self.world.players[slot].input or self.myInput
  if inp.kind == "pad" then return "Y" end
  local b = (inp.kind == "keys" and inp.controls) or Settings.values.binds.online
  return Input.keyName(b.discard)
end

---------------------------------------------------------------- HUD
-- Big text that pops in (k: 0 -> 1 over its life).
function Match:drawPop(text, k, color)
  local scale = 1 + 0.6 * math.max(0, 1 - k * 4)
  local a = k < 0.75 and 1 or math.max(0, 1 - (k - 0.75) * 4)
  love.graphics.push()
  love.graphics.translate(app.W / 2, 300)
  love.graphics.scale(scale, scale)
  love.graphics.setFont(app.fonts.huge)
  love.graphics.setColor(0, 0, 0, 0.4 * a)
  love.graphics.printf(text, -app.W / 2 + 4, -app.fonts.huge:getHeight() / 2 + 4, app.W, "center")
  love.graphics.setColor(color[1], color[2], color[3], a)
  love.graphics.printf(text, -app.W / 2, -app.fonts.huge:getHeight() / 2, app.W, "center")
  love.graphics.pop()
end

local KILL_WORDS = {
  melee = "punched out", edge = "hit the edge", explosion = "blown up", saw = "sawed", spikes = "spiked",
  laser = "lasered", crusher = "crushed", fire = "burned", acid = "dissolved", falling = "flattened",
  gas = "gassed", lightning = "struck by lightning",
}

function Match:addKill(victimSlot, killerSlot, kind)
  if killerSlot and self:isMine(killerSlot) then
    Profile.bump("kills")
    if kind == "melee" then Profile.bump("meleeKills") end
  end
  self.killFeed = self.killFeed or {}
  table.insert(self.killFeed, 1, { victim = victimSlot, killer = killerSlot, kind = kind, t = 5 })
  if #self.killFeed > 5 then table.remove(self.killFeed) end
end

-- Top right, under the score panels: "Alice > Bob (melee)", "Carol was sawed".
function Match:drawKillFeed()
  local feed = self.killFeed
  if not feed then return end
  local players = self:players()
  local dt = love.timer.getDelta()
  local y = math.max(120, (hud.cardsBottom or 0) + 8)
  love.graphics.setFont(app.fonts.small)
  for i = #feed, 1, -1 do
    feed[i].t = feed[i].t - dt
    if feed[i].t <= 0 then table.remove(feed, i) end
  end
  for _, k in ipairs(feed) do
    local a = math.min(1, k.t)
    local v, kp = players[k.victim], k.killer and players[k.killer]
    local vName = v and v.name or "?"
    local text = {}
    if kp and kp ~= v then
      local c = kp.color
      text = { { c[1], c[2], c[3], a }, kp.name or "?", { 1, 1, 1, 0.7 * a }, "  >  ", { v.color[1], v.color[2], v.color[3], a }, vName }
      if k.kind and KILL_WORDS[k.kind] then
        text[#text + 1] = { 1, 1, 1, 0.5 * a }
        text[#text + 1] = "  (" .. (k.kind == "melee" and "melee" or KILL_WORDS[k.kind]) .. ")"
      end
    else
      local c = v and v.color or { 1, 1, 1 }
      text = { { c[1], c[2], c[3], a }, vName, { 1, 1, 1, 0.7 * a }, " " .. (KILL_WORDS[k.kind or ""] or "died") }
    end
    local w = 0
    for j = 2, #text, 2 do w = w + app.fonts.small:getWidth(text[j]) end
    love.graphics.setColor(0, 0, 0, 0.45 * a)
    love.graphics.rectangle("fill", app.W - w - 36, y - 2, w + 16, 22, 4, 4)
    love.graphics.setColor(1, 1, 1, a)
    love.graphics.print(text, app.W - w - 28, y)
    y = y + 26
  end
end

-- Players above the open ceiling: an arrow at the top edge with their height.
function Match:drawOffscreen(players)
  for _, p in ipairs(players) do
    if not p.dead and p.y < -p.r then
      local x = math.max(20, math.min(Map.W - 20, p.x))
      local c = p.color
      love.graphics.setColor(c[1], c[2], c[3], 0.9)
      love.graphics.polygon("fill", x, 4, x - 12, 22, x + 12, 22)
      love.graphics.setFont(app.fonts.tiny)
      love.graphics.printf(math.floor(-p.y) .. "", x - 30, 24, 60, "center")
    end
  end
end

-- The human player(s) on this machine.
function Match:myPlayers()
  local out = {}
  local players = self:players()
  if self.role == "local" then
    for _, p in ipairs(players) do
      if not p.isBot and p.input and p.input.kind ~= "remote" then out[#out + 1] = p end
    end
  elseif players[self.mySlot or 0] then
    out[1] = players[self.mySlot]
  end
  return out
end

-- Low HP (one person on this machine): red edges and a heartbeat.
function Match:drawVignette(players)
  local mine = self:myPlayers()
  if #mine ~= 1 then return end
  local p = mine[1]
  local maxHp = p.stats and p.stats.maxHp or 100
  if p.dead or p.hp >= maxHp * 0.3 then
    self.heartT = 0
    return
  end
  local k = 1 - p.hp / (maxHp * 0.3)
  local pulse = 0.6 + 0.4 * math.sin(love.timer.getTime() * 7)
  for i = 1, 6 do
    local w = i * 14
    love.graphics.setColor(0.8, 0, 0, (0.07 + 0.06 * k) * pulse)
    love.graphics.rectangle("fill", 0, 0, w, app.H)
    love.graphics.rectangle("fill", app.W - w, 0, w, app.H)
    love.graphics.rectangle("fill", 0, 0, app.W, w * 0.7)
    love.graphics.rectangle("fill", 0, app.H - w * 0.7, app.W, w * 0.7)
  end
  self.heartT = (self.heartT or 0) - love.timer.getDelta()
  if self.heartT <= 0 then
    self.heartT = 0.95 - 0.35 * k
    sfx.play("heartbeat", nil, 0.5 + 0.5 * k, 1, true)
  end
end

-- Scoreboard (held or toggled with the scoreboard key): stats per player and the round history.
function Match:drawScoreboard()
  local players = self:players()
  local pw, rowH = 1000, 52
  local ph = 150 + #players * rowH + 70
  local px, py = (app.W - pw) / 2, (app.H - ph) / 2
  love.graphics.setColor(0, 0, 0, 0.5)
  love.graphics.rectangle("fill", 0, 0, app.W, app.H)
  ui.panel(px, py, pw, ph)
  love.graphics.setFont(app.fonts.big)
  love.graphics.setColor(1, 1, 1)
  love.graphics.printf("SCOREBOARD", px, py + 16, pw, "center")
  local cols = { { "Player", 0, "left", 240 }, { "Score", 250 }, { "Kills", 340 }, { "Deaths", 430 }, { "Damage", 530 },
    { "Accuracy", 640 }, { "Blocks", 750 }, { "Melee", 840 }, { "Ping", 920 } }
  love.graphics.setFont(app.fonts.small)
  love.graphics.setColor(1, 1, 1, 0.5)
  for _, c in ipairs(cols) do love.graphics.printf(c[1], px + 30 + c[2], py + 74, c[4] or 80, c[3] or "center") end
  local streaks = self.role ~= "local" and active.get().peerStreaks or {}
  for i, p in ipairs(players) do
    local y = py + 100 + (i - 1) * rowH
    local st = p.st or {}
    local acc = (st.shots or 0) > 0 and (math.floor((st.hits or 0) / st.shots * 100 + 0.5) .. "%") or "-"
    local streak = streaks[p.peer or ""] or streaks[p.name or ""]
    local vals = { tostring(p.score), tostring(st.kills or 0), tostring(st.deaths or 0), tostring(math.floor(st.dmg or 0)),
      acc, tostring(st.blocks or 0), tostring(st.melee or 0),
      self.role == "local" and "-" or (p.isBot and "bot" or (i == 1 and "host" or (p.ping and (p.ping .. "") or "-"))) }
    love.graphics.setColor(1, 1, 1, 0.05)
    love.graphics.rectangle("fill", px + 20, y - 6, pw - 40, rowH - 6, 6, 6)
    love.graphics.setFont(app.fonts.med)
    love.graphics.setColor(p.color)
    local name = (p.name or ("Player " .. i)) .. (p.disconnected and "  (left)" or "")
    love.graphics.printf(name, px + 30, y + 6, 240, "left")
    if streak and streak.streak > 1 then
      love.graphics.setFont(app.fonts.tiny)
      love.graphics.setColor(1, 0.8, 0.35)
      love.graphics.print(streak.streak .. " in a row", px + 30, y + 28)
      love.graphics.setFont(app.fonts.med)
    end
    love.graphics.setColor(1, 1, 1, 0.9)
    for k, v in ipairs(vals) do love.graphics.printf(v, px + 30 + cols[k + 1][2], y + 6, 80, "center") end
  end
  -- Round by round: a dot per round in the winner's colour.
  local hist = self.role == "client" and self.view.history or (self.world and self.world.history) or {}
  local y = py + 100 + #players * rowH + 14
  love.graphics.setFont(app.fonts.small)
  love.graphics.setColor(1, 1, 1, 0.5)
  love.graphics.print("Rounds", px + 30, y)
  for k, slot in ipairs(hist) do
    local c = players[slot] and players[slot].color or { 0.5, 0.5, 0.5 }
    love.graphics.setColor(c)
    love.graphics.circle("fill", px + 110 + (k - 1) * 22, y + 9, 8)
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

-- Everyone's names sliding in before the first round.
function Match:drawVersus(players, k)
  local e = ease(k * 2.5)
  local out = math.max(0, math.min(1, (1 - k) * 6))
  local h = 210 * out
  love.graphics.setColor(0, 0, 0, 0.75)
  love.graphics.rectangle("fill", 0, 360 - h / 2, app.W, h)
  if out < 1 then return end
  local n = #players
  local slide = (1 - e) * 500
  local font = app.fonts.big
  if n == 2 then
    local a, b = players[1], players[2]
    love.graphics.setColor(a.color)
    ui.printFit((a.name or "Player"):upper(), font, 80 - slide, 340, 460, "right")
    love.graphics.setColor(b.color)
    ui.printFit((b.name or "Player"):upper(), font, 740 + slide, 340, 460, "left")
    love.graphics.setColor(1, 1, 1)
    ui.printFit("VS", app.fonts.big, app.W / 2 - 60, 340, 120, "center")
    return
  end
  local cellW = 1120 / n
  for i, p in ipairs(players) do
    local x = 80 + (i - 1) * cellW + (i % 2 == 0 and slide or -slide)
    love.graphics.setColor(p.color)
    ui.printFit((p.name or "Player"):upper(), app.fonts.title, x + 10, 345, cellW - 20, "center")
  end
end

-- Between sub-rounds: each side's progress toward the next point.
function Match:drawSubRound(st)
  local players = self:players()
  local need = math.max(1, Cards.rules.subRounds or 1)
  local sides, seen = {}, {}
  for i, p in ipairs(players) do
    local key = p.team or -i
    if not seen[key] then
      seen[key] = true
      sides[#sides + 1] = p
    end
  end
  local t = math.max(0, World.SUB_ROUND_TIME - (st.timer or 0))
  local k = ease(t / 0.3)
  love.graphics.setColor(0, 0, 0, 0.55 * k)
  love.graphics.rectangle("fill", 0, 0, app.W, app.H)
  local r, gap = 74, 40
  local total = #sides * r * 2 + (#sides - 1) * gap
  local x = (app.W - total) / 2 + r
  local line, point
  for _, p in ipairs(sides) do
    local fresh = st.winner and (p == st.winner or (st.winner.team and p.team == st.winner.team))
    hud.drawPie(x, 300, r * k, need, p.subWins or 0, p.color, k, fresh and ease((t - 0.2) / 0.45) or nil)
    local who = (p.team and World.teamName(p.team)) or p.name or "Player"
    if (p.subWins or 0) >= need then
      point = who .. " takes the point!"
    elseif (p.subWins or 0) == need - 1 and need > 1 then
      line = line and "Everyone is one win away" or (who .. " is one win away")
    end
    x = x + r * 2 + gap
  end
  if point then
    app.centered(point, app.fonts.title, 400, { 1, 1, 1, k })
  elseif line then
    app.centered(line, app.fonts.title, 400, { 1, 1, 1, k })
  elseif st.winner == nil then
    app.centered("Draw", app.fonts.title, 400, { 1, 1, 1, k })
  end
end

function Match:drawRoundBanner(st)
  local t = self.roundT or 0
  local k = ease(t / 0.42)
  local c = st.winner and st.winner.color or { 1, 1, 1 }
  local text = st.winner and ((st.winner.name or "Player"):upper() .. " WINS THE ROUND") or "DRAW"
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.rectangle("fill", app.W / 2 - app.W / 2 * k, 262, app.W * k, 92)
  love.graphics.setColor(c)
  love.graphics.rectangle("fill", app.W / 2 - app.W / 2 * k, 262, app.W * k, 4)
  love.graphics.rectangle("fill", app.W / 2 - app.W / 2 * k, 350, app.W * k, 4)
  if k > 0.6 then
    love.graphics.setColor(c)
    ui.printFit(text, app.fonts.big, 100, 287, app.W - 200, "center")
  end
end

-- The winner's podium and final build.
function Match:drawPodium(st)
  local ranked = {}
  for i, p in ipairs(self:players()) do ranked[i] = p end
  table.sort(ranked, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    return (a.slot or a.id or 0) < (b.slot or b.id or 0)
  end)
  local heights = { 130, 104, 84, 68 }
  local order = { { 3, 1, 2, 4 }, { 2, 1, 3 }, { 1, 2 } }
  local slots = #ranked == 4 and order[1] or #ranked == 3 and order[2] or order[3]
  local colW = 180
  local x0 = (app.W - #slots * colW) / 2
  local baseY = 312
  for i, rank in ipairs(slots) do
    local p = ranked[rank]
    if p then
      local x = x0 + (i - 1) * colW
      local h = heights[rank]
      love.graphics.setColor(0.2, 0.2, 0.26, 0.95)
      love.graphics.rectangle("fill", x + 8, baseY - h, colW - 16, h, 8, 8)
      love.graphics.setColor(p.color)
      love.graphics.rectangle("fill", x + 8, baseY - h, colW - 16, 4)
      self.podium = self.podium or {}
      local f = self.podium[rank]
      if not f then
        f = { r = 30, slot = rank, facing = 1, aimX = 1, aimY = 0, x = x + colW / 2, y = baseY - h - 44 }
        self.podium[rank] = f
      end
      f.x, f.y = x + colW / 2, baseY - h - 44
      f.color, f.hat, f.eyes, f.mouth, f.detail = p.color, p.hat, p.eyes, p.mouth, p.detail
      f.aimX = math.sin(love.timer.getTime() * 0.9 + i) * 0.8
      f.aimY = -0.5
      require("game.body").drawFigure(f, love.timer.getDelta())
      love.graphics.setColor(1, 1, 1, 0.9)
      ui.printFit(tostring(p.score), app.fonts.title, x + 8, baseY - h + 8, colW - 16, "center")
      love.graphics.setColor(1, 1, 1, 0.75)
      ui.printFit(p.name or "Player", app.fonts.small, x + 14, baseY - 22, colW - 28, "center")
    end
  end
  local winner = st.winner
  if winner and #winner.cards > 0 then
    local names, seen = {}, {}
    for _, c in ipairs(winner.cards) do
      if not seen[c] then
        seen[c] = 0
        names[#names + 1] = c
      end
      seen[c] = seen[c] + 1
    end
    local parts = {}
    for i, c in ipairs(names) do
      if i > 14 then
        parts[#parts + 1] = "+" .. (#names - 14) .. " more"
        break
      end
      parts[#parts + 1] = c.name .. (seen[c] > 1 and (" x" .. seen[c]) or "")
    end
    love.graphics.setFont(app.fonts.small)
    love.graphics.setColor(1, 1, 1, 0.65)
    love.graphics.printf("Final build: " .. table.concat(parts, ", "), 100, 322, app.W - 200, "center")
  end
end

function Match:drawMatchOver(st)
  love.graphics.setColor(0, 0, 0, 0.72)
  love.graphics.rectangle("fill", 0, 0, app.W, app.H)
  local winner = st.winner
  if winner then
    love.graphics.setColor(winner.color)
    ui.printFit((winner.name or "Player"):upper() .. " WINS!", app.fonts.huge, 80, 8, app.W - 160, "center")
  end
  self:drawPodium(st)
  require("core.achievements").draw(500)

  local x, w, h = app.W / 2 - 280, 560, 52
  local nextScore = st.winScore + World.CONTINUE_ROUNDS
  local continueText = "Continue  (+" .. World.CONTINUE_ROUNDS .. " rounds, first to " .. nextScore .. ")"

  if self.role == "client" and self.mySlot == 0 then
    app.centered("You're watching - you'll play in the next match", app.fonts.med, 370, { 1, 1, 1, 0.7 })
    if ui.button("Match Recap", x, 410, w, h) then self:openRecap() end
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
    self:drawVotes(498)
    if ui.button("Match Recap", x, 540, w, h) then self:openRecap() end
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
  local third = (w - 20) / 3
  if self.role == "host" then
    if ui.button("Back to Lobby", x, 494, third, h) then self:backToLobby() end
  else
    if ui.button("Main Menu", x, 494, third, h) then app.switch(require("screens.menu").new()) end
  end
  if ui.button("Scoreboard", x + third + 10, 494, third, h) then self.showScores = not self.showScores end
  if ui.button("Match Recap", x + (third + 10) * 2, 494, third, h, { color = ui.ACCENT }) then self:openRecap() end
  if self.role == "host" then self:drawVotes(568) end
end

function Match:openRecap()
  self.recapOpen, self.recapShot, self.recapMessage, self.recapSaved = true, nil, nil, nil
  self.showScores = false
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
    if ui.button("Main Menu", bx, y, bw, bh) then
      require("screens.confirm").ask("Leave this match?", "The match in progress will end.", function()
        app.switch(require("screens.menu").new())
      end, { yes = "Leave", danger = true })
    end
  elseif self.role == "host" then
    if ui.button("Back to Lobby (everyone)", bx, y, bw, bh) then
      require("screens.confirm").ask("Back to the lobby?", "This ends the match for everyone.", function()
        self:backToLobby()
      end, { yes = "Back to Lobby", danger = true })
    end
    y = y + 62
    if ui.button("Leave Lobby", bx, y, bw, bh) then
      require("screens.confirm").ask("Close this lobby?", "You're the host, so everyone will be disconnected.", function()
        active.get().leave()
        app.switch(require("screens.menu").new())
      end, { yes = "Close Lobby", danger = true })
    end
  else
    if ui.button("Leave Lobby", bx, y, bw, bh) then
      require("screens.confirm").ask("Leave this match?", "You'll leave the match and the lobby.", function()
        active.get().leave()
        app.switch(require("screens.menu").new())
      end, { yes = "Leave", danger = true })
    end
  end
end

function Match:draw()
  if self.loading then
    love.graphics.setColor(0.09, 0.09, 0.12)
    love.graphics.rectangle("fill", 0, 0, app.W, app.H)
    local k = math.min(1, self.loading.t / LOAD_TIME)
    require("gfx.logo").drawLoading("Loading match...", k, math.min(1, self.loading.t / 0.3))
    return
  end
  local players, bullets, wells, map = self:scene()
  if not map then return end
  local st = self:status()

  local sx, sy = fx.offset()

  local objs, effects, barrier = self:sceneObjects()
  local slideX = self:mapOffset()
  -- Teammates share a colour, so team matches name everyone.
  require("game.body").showNames = self.role ~= "local" or (self.world and self.world.rules.teams) or false
  require("game.body").speakingSlot = self.role ~= "local" and function(p)
    local sl = self.slots and self.slots[p.slot or 0]
    return sl and Voice.isSpeaking(sl.peer)
  end or nil
  if not self.mapHidden then
  love.graphics.push()
  love.graphics.translate(sx + slideX, sy)
  love.graphics.scale(Map.VIEW)
  Map.draw(map)
  if st.hill then hud.drawHill(st.hill, players, World.HILL) end
  Objects.draw(objs, effects)
  hud.drawWells(wells)
  for _, b in ipairs(bullets) do b:draw() end
  for _, p in ipairs(players) do p:draw() end
  fx.draw()
  self:drawOffscreen(players)
  fx.drawNumbers()
  if barrier then hud.drawBarrier(barrier) end
  love.graphics.pop()

  Bloom.draw(function()
    love.graphics.translate(sx + slideX, sy)
    love.graphics.scale(Map.VIEW)
    Objects.drawGlow(objs, effects)
    if barrier then hud.drawBarrier(barrier, true) end
    for _, b in ipairs(bullets) do b:draw() end
    for _, p in ipairs(players) do p:drawGlow() end
    fx.glowPass = true
    fx.draw()
    fx.glowPass = false
  end, app.canvas)
  end

  if not self.mapHidden then self:drawBubbles(players) end
  local cardItems = hud.drawScores(players, st.winScore, self:usesTouch() and 62 or 0)
  if st.state == "playing" or st.state == "countdown" or st.state == "roundOver" then hud.drawTimer(st.suddenLeft) end
  if st.hill then
    local function scoreOf(i)
      if self.role == "client" then return st.hill.scores[i] or 0 end
      return players[i].hillScore or 0
    end
    hud.drawHillScores(players, World.HILL.target, scoreOf)
  end
  love.graphics.setFont(app.fonts.small)
  love.graphics.setColor(1, 1, 1, 0.3)
  love.graphics.printf(map.name .. "   -   First to " .. st.winScore, 0, app.H - 24, app.W, "center")

  for i, t in ipairs(self.toasts) do
    local c = t.color
    app.centered(t.text, app.fonts.med, 92 + i * 26, { c[1], c[2], c[3], math.min(1, t.t) })
  end

  self:drawVignette(players)
  self:drawKillFeed()
  -- While paused only the pause menu's buttons can be used.
  local widgetsLive = ui.active
  if self.paused then ui.active = false end
  if st.state == "countdown" then
    if st.timer > World.COUNTDOWN then
      self:drawVersus(players, 1 - (st.timer - World.COUNTDOWN) / World.INTRO_TIME)
    else
      -- 3, 2, 1: each number pops in big and settles.
      local n = math.max(1, math.ceil(st.timer / 0.8))
      local k = 1 - ((st.timer / 0.8) % 1)
      self:drawPop(tostring(n), k, { 1, 1, 1 })
    end
    self.fightT = 0
    self.roundT = 0
  elseif st.state == "playing" and (self.fightT or 1) < 0.7 then
    self.fightT = (self.fightT or 0) + love.timer.getDelta()
    self:drawPop("FIGHT!", self.fightT / 0.7, { 1, 0.85, 0.3 })
  elseif st.state == "roundOver" then
    self.roundT = (self.roundT or 0) + love.timer.getDelta()
    self:drawRoundBanner(st)
  elseif st.state == "subRound" then
    self:drawSubRound(st)
  elseif st.state == "cardPick" then
    self:drawCardPick(st)
  elseif st.state == "mapVote" then
    self:drawMapVote(st)
  elseif st.state == "cardBan" then
    self:drawCardBan(st)
  end
  if st.state ~= "mapVote" then self:drawFlyers() end
  if st.state == "matchOver" and self.recapOpen then
    Recap.draw(self, st) -- covers the whole screen
    ui.active = widgetsLive
    return
  end
  if st.state == "matchOver" then self:drawMatchOver(st) end
  ui.active = widgetsLive

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

  if self.practice and not self.paused then self:drawPractice() end
  self:drawTutorial()
  self:drawChat(st)
  if self:scoreboardVisible() then self:drawScoreboard() end

  if self.paused then
    self:drawPause()
  elseif (self.role ~= "local" or self:usesMouseAim()) and (st.state == "countdown" or st.state == "playing" or st.state == "roundOver") then
    local mx, my = app.mouse()
    local me = players[self.mySlot or 1]
    hud.drawCrosshair(mx, my, me and me.color or { 1, 1, 1 })
  end
end

return Match
