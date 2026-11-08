-- Compact binary snapshots of the world, sent host -> clients ~30 times a second.
local bit = require "core.bit"
local Bullet = require "game.bullet"
local net = require "online.net"

local pack, unpack = love.data.pack, love.data.unpack

local Snap = {}

Snap.STATES = { "countdown", "playing", "roundOver", "cardPick", "matchOver" }
local STATE_CODE = {}
for i, s in ipairs(Snap.STATES) do STATE_CODE[s] = i end

local COMPRESS_OVER = 1100
local MAX_BULLETS = 1500
local MAX_LASER_POINTS = 64

local function i16(v)
  v = math.floor((v or 0) + 0.5)
  if v > 32767 then return 32767 elseif v < -32768 then return -32768 end
  return v
end

local function u8(v)
  v = math.floor((v or 0) + 0.5)
  if v < 0 then return 0 elseif v > 255 then return 255 end
  return v
end

local function u16(v)
  v = math.floor((v or 0) + 0.5)
  if v < 0 then return 0 elseif v > 65535 then return 65535 end
  return v
end

-- ..., score, stasis copies, match-over vote, shield, sentries, melee/dash flags, melee charge,
-- swing timer, swing power, melee range, heavy charge time, vertical speed
-- ..., then for client prediction: last input applied (ack), vx, air jumps left, dashes left,
-- movement flags, dash time left, dash cooldown, and the player's ping in ms.
local PLAYER_FMT = "<fffbffBBfBBBBBfBfHBBBBBBBBBBhI4hBBBBBH"
local BULLET_FMT = "<HhhhhBBB"

function Snap.encode(world, events)
  local P = {}
  local function add(fmt, ...) P[#P + 1] = pack("string", fmt, ...) end

  local winner = world.roundWinner and world.roundWinner.slot or 0
  add("<BfHBBB", STATE_CODE[world.state] or 1, world.timer, u16(world.winScore), world.mapIndex or 1,
    winner, #world.players)

  -- The card pick in progress (slot 0 = none), so everyone can watch it.
  local pk = world.state == "cardPick" and world.pick
  if pk then
    add("<BBBBB", pk.slot, pk.serial, pk.hover, pk.num, pk.total)
    local queued = world:queuedPickers()
    add("<B", #queued)
    for _, slot in ipairs(queued) do add("<B", slot) end
    add("<B", #pk.options)
    for _, c in ipairs(pk.options) do add("<B", c.index) end
    local mask = 0
    for i in pairs(pk.flipped or {}) do mask = mask + 2 ^ (i - 1) end
    add("<BB", mask, pk.timeLeft and u8(math.ceil(pk.timeLeft)) or 255)
  else
    add("<BBBBBBBBB", 0, 0, 0, 0, 0, 0, 0, 0, 255)
  end

  for _, p in ipairs(world.players) do
    local s = p.stats
    local flags = bit.bor(
      p.dead and 1 or 0, p:isBlocking() and 2 or 0, p.empowered and 4 or 0, 0,
      (p.poisonTimer or 0) > 0 and 16 or 0, (p.slowTimer or 0) > 0 and 32 or 0,
      (p.cloakTimer or 0) > 0 and 64 or 0, (p.hitFlash or 0) > 0 and 128 or 0)
    local pending = 0
    for _, d in ipairs(p.decay or {}) do pending = pending + d.remaining end
    local reload = 0
    if p.ammo == 0 and (p.reloadTimer or 0) > 0 then reload = u8(255 * p.reloadTimer / s.reloadTime) end
    add(PLAYER_FMT,
      p.x or 0, p.y or 0, math.atan2(p.aimY or 0, p.aimX or 1), p.facing or 1,
      p.hp or 0, s.maxHp, u8(p.r), flags,
      p.invuln or 0, u8(p.ammo), u8(s.ammo), reload, u8(255 * (p.blockCd or 0) / s.blockCooldown),
      u8(s.orbs), p.orbAngle or 0, u8(p.livesLeft), pending, u16(p.score),
      u8(s.stasis), (world.votes and world.votes[p.slot]) or 0, u8(p.shield), u8(s.sentry),
      bit.bor((p.stunTimer or 0) > 0 and 1 or 0, p.charging and 2 or 0, p.swingHeavy and 4 or 0,
        (p.dashTimer or 0) > 0 and 8 or 0),
      u8((p.meleeCharge or 0) * 100), u8((p.swingTimer or 0) * 800), u8((p.swingPower or 0) * 255),
      u8(s.meleeRange), u8(s.heavyCharge * 100), i16(p.vy),
      p.ack or 0, i16(p.vx), u8(p.jumpsLeft), u8(p.dashesLeft),
      bit.bor(p.onGround and 1 or 0, p.jumping and 2 or 0, p.groundOneway and 4 or 0),
      u8((p.dashTimer or 0) * 1000), u8((p.dashCd or 0) * 100), u16(p.ping))
  end

  local bullets = world.bullets
  local n = math.min(#bullets, MAX_BULLETS)
  add("<H", n)
  for i = 1, n do
    local b = bullets[i]
    local colorIdx = b.crit and 5 or (b.owner.slot or 0)
    local flags = bit.bor(b.ghost and 1 or 0, b.mine and 2 or 0, b.laser and 4 or 0,
      (b.mine and b.armTime <= 0) and 8 or 0)
    add(BULLET_FMT, b.id or 0, i16(b.x), i16(b.y), i16(b.vx), i16(b.vy), u8(b.r * 4), colorIdx, flags)
    if b.mine then add("<B", u8((b.trigger or 85) / 2)) end
    if b.laser then
      local pts = b.points or {}
      local np = math.min(#pts, MAX_LASER_POINTS)
      add("<BB", u8(255 * (b.beam or Bullet.LASER_FADE) / Bullet.LASER_FADE), np)
      for k = 1, np do add("<hh", i16(pts[k][1]), i16(pts[k][2])) end
    end
  end

  local wells = world.wells
  add("<B", math.min(#wells, 255))
  for i = 1, math.min(#wells, 255) do
    local w = wells[i]
    add("<hhffBH", i16(w.x), i16(w.y), w.t, w.max, w.owner.slot or 0, u16(w.radius))
  end

  -- Map objects (same order as the map's list), spawned effects, the barrier.
  local objs = world.objects or {}
  add("<B", math.min(#objs, 255))
  for i = 1, math.min(#objs, 255) do
    local o = objs[i]
    local flags = (o.alive and 1 or 0) + (o.falling and 2 or 0)
    local hpFrac = o.maxHp and o.maxHp > 0 and u8(255 * math.max(0, o.hp or 0) / o.maxHp) or 255
    add("<BhhfBB", flags, i16(o.x), i16(o.y), o.angle or o.a or 0, u8(o.s), hpFrac)
  end
  local effects = world.effects or {}
  add("<B", math.min(#effects, 255))
  for i = 1, math.min(#effects, 255) do
    local e = effects[i]
    local code = e.type == "pickup" and 1 or e.type == "cloud" and 2 or 3
    add("<BhhBBB", code, i16(e.x), i16(e.y), e.kind or 0, u8(math.max(0, e.life) * 20), u8((e.radius or 0) / 2))
  end
  local b = world.barrier
  if b then
    add("<Bhhhh", 1, i16(b[1]), i16(b[2]), i16(b[3]), i16(b[4]))
  else
    add("<B", 0)
  end

  events = events or {}
  add("<H", #events)
  for _, e in ipairs(events) do
    local kind = e[1]
    if kind == 1 then
      local c = e[4]
      add("<BhhBBBBHB", 1, i16(e[2]), i16(e[3]), u8(c[1] * 255), u8(c[2] * 255), u8(c[3] * 255),
        u8(e[5]), u16(e[6]), u8(e[7] * 10))
    elseif kind == 2 then
      local c = e[5]
      add("<BhhHBBB", 2, i16(e[2]), i16(e[3]), u16(e[4]), u8(c[1] * 255), u8(c[2] * 255), u8(c[3] * 255))
    elseif kind == 3 then
      add("<BB", 3, u8(e[2]))
    elseif kind == 5 then
      add("<BBhBB", 5, u8(e[2]), i16(e[3]), u8(e[4] * 100), u8(e[5] * 100))
    elseif kind == 6 then
      local c = e[6]
      add("<BhhhBBBBBHBB", 6, i16(e[2]), i16(e[3]), i16(e[4] * 1000), u8(e[5] * 40),
        u8(c[1] * 255), u8(c[2] * 255), u8(c[3] * 255), u8(e[7]), u16(e[8]), u8(e[9] * 10), u8(e[10] * 50))
    elseif kind == 7 then
      local c = e[5]
      add("<BhhBBBB", 7, i16(e[2]), i16(e[3]), u8(e[4]), u8(c[1] * 255), u8(c[2] * 255), u8(c[3] * 255))
    elseif kind == 8 then
      local c = e[4]
      add("<BhhBBBBB", 8, i16(e[2]), i16(e[3]), u8(c[1] * 255), u8(c[2] * 255), u8(c[3] * 255), u8(e[5]), u8(e[6]))
    elseif kind == 9 then
      add("<Bhh", 9, i16(e[2] * 10), i16(e[3] * 10))
    else
      add("<B", 4)
    end
  end

  local raw = table.concat(P)
  if #raw > COMPRESS_OVER then
    return string.char(net.MSG.SNAPSHOT, 1) .. love.data.compress("string", "lz4", raw)
  end
  return string.char(net.MSG.SNAPSHOT, 0) .. raw
end

function Snap.decode(data)
  local raw = data:sub(3)
  if data:byte(2) == 1 then raw = love.data.decompress("string", "lz4", raw) end

  local v = { players = {}, bullets = {}, wells = {}, fx = {} }
  local st, np, pos
  st, v.timer, v.winScore, v.mapIndex, v.winner, np, pos = unpack("<BfHBBB", raw, 1)
  v.state = Snap.STATES[st] or "countdown"

  -- pick = { slot, serial, hover, num, total, queued = { slot... }, options = { card index... } }
  local pk = { queued = {}, options = {} }
  local nq, no
  pk.slot, pk.serial, pk.hover, pk.num, pk.total, nq, pos = unpack("<BBBBBB", raw, pos)
  for i = 1, nq do pk.queued[i], pos = unpack("<B", raw, pos) end
  no, pos = unpack("<B", raw, pos)
  for i = 1, no do pk.options[i], pos = unpack("<B", raw, pos) end
  local mask, left
  mask, left, pos = unpack("<BB", raw, pos)
  pk.flipped = {}
  for i = 1, 8 do
    if math.floor(mask / 2 ^ (i - 1)) % 2 == 1 then pk.flipped[i] = true end
  end
  pk.timeLeft = left < 255 and left or nil
  v.pick = pk

  for i = 1, np do
    local p = {}
    local flags, flags2, mflags
    p.x, p.y, p.aim, p.facing, p.hp, p.maxHp, p.r, flags,
    p.invuln, p.ammo, p.maxAmmo, p.reload, p.blockCd,
    p.orbs, p.orbAngle, p.lives, p.pending, p.score, p.stasis, p.vote, p.shield, p.sentry,
    flags2, p.meleeCharge, p.swingTimer, p.swingPower, p.meleeRange, p.heavyCharge, p.vy,
    p.ack, p.vx, p.jumpsLeft, p.dashesLeft, mflags, p.dashT, p.dashCd2, p.ping, pos =
      unpack(PLAYER_FMT, raw, pos)
    p.onGround = bit.band(mflags, 1) ~= 0
    p.jumping = bit.band(mflags, 2) ~= 0
    p.groundOneway = bit.band(mflags, 4) ~= 0
    p.dashT = p.dashT / 1000
    p.dashCd2 = p.dashCd2 / 100
    p.stunned = bit.band(flags2, 1) ~= 0
    p.charging = bit.band(flags2, 2) ~= 0
    p.swingHeavy = bit.band(flags2, 4) ~= 0
    p.dashing = bit.band(flags2, 8) ~= 0
    p.meleeCharge = p.meleeCharge / 100
    p.swingTimer = p.swingTimer / 800
    p.swingPower = p.swingPower / 255
    p.heavyCharge = p.heavyCharge / 100
    p.dead = bit.band(flags, 1) ~= 0
    p.blocking = bit.band(flags, 2) ~= 0
    p.empowered = bit.band(flags, 4) ~= 0
    p.poisoned = bit.band(flags, 16) ~= 0
    p.slowed = bit.band(flags, 32) ~= 0
    p.cloaked = bit.band(flags, 64) ~= 0
    p.hitFlash = bit.band(flags, 128) ~= 0
    v.players[i] = p
  end

  local nb
  nb, pos = unpack("<H", raw, pos)
  for i = 1, nb do
    local b = {}
    local flags, r4
    b.id, b.x, b.y, b.vx, b.vy, r4, b.colorIdx, flags, pos = unpack(BULLET_FMT, raw, pos)
    b.r = r4 / 4
    b.ghost = bit.band(flags, 1) ~= 0
    b.mine = bit.band(flags, 2) ~= 0
    b.laser = bit.band(flags, 4) ~= 0
    b.armed = bit.band(flags, 8) ~= 0
    if b.mine then
      local t
      t, pos = unpack("<B", raw, pos)
      b.trigger = t * 2
    end
    if b.laser then
      local beam, npts
      beam, npts, pos = unpack("<BB", raw, pos)
      b.beam = beam / 255 * Bullet.LASER_FADE
      b.points = {}
      for k = 1, npts do
        local x, y
        x, y, pos = unpack("<hh", raw, pos)
        b.points[k] = { x, y }
      end
    end
    v.bullets[i] = b
  end

  local nw
  nw, pos = unpack("<B", raw, pos)
  for i = 1, nw do
    local w = {}
    w.x, w.y, w.t, w.max, w.slot, w.radius, pos = unpack("<hhffBH", raw, pos)
    v.wells[i] = w
  end

  local no2
  no2, pos = unpack("<B", raw, pos)
  v.objects = {}
  for i = 1, no2 do
    local flags, x, y, a, s, hp
    flags, x, y, a, s, hp, pos = unpack("<BhhfBB", raw, pos)
    v.objects[i] = { alive = flags % 2 == 1, falling = flags >= 2, x = x, y = y, a = a, s = s, hp = hp / 255 }
  end
  local nfx
  nfx, pos = unpack("<B", raw, pos)
  v.effects = {}
  for i = 1, nfx do
    local kind, x, y, k, life, rad
    kind, x, y, k, life, rad, pos = unpack("<BhhBBB", raw, pos)
    v.effects[i] = { type = kind == 1 and "pickup" or kind == 2 and "cloud" or "strike", x = x, y = y, kind = k,
      life = life / 20, max = 0.75, radius = rad * 2 }
  end
  local hasBarrier
  hasBarrier, pos = unpack("<B", raw, pos)
  if hasBarrier == 1 then
    local x0, y0, x1, y1
    x0, y0, x1, y1, pos = unpack("<hhhh", raw, pos)
    v.barrier = { x0, y0, x1, y1 }
  end

  local ne
  ne, pos = unpack("<H", raw, pos)
  for i = 1, ne do
    local kind
    kind, pos = unpack("<B", raw, pos)
    if kind == 1 then
      local x, y, r, g, b, count, speed, size
      x, y, r, g, b, count, speed, size, pos = unpack("<hhBBBBHB", raw, pos)
      v.fx[i] = { 1, x, y, { r / 255, g / 255, b / 255 }, count, speed, size / 10 }
    elseif kind == 2 then
      local x, y, radius, r, g, b
      x, y, radius, r, g, b, pos = unpack("<hhHBBB", raw, pos)
      v.fx[i] = { 2, x, y, radius, { r / 255, g / 255, b / 255 } }
    elseif kind == 3 then
      local amount
      amount, pos = unpack("<B", raw, pos)
      v.fx[i] = { 3, amount }
    elseif kind == 5 then
      local id, x, vol, pitch
      id, x, vol, pitch, pos = unpack("<BhBB", raw, pos)
      v.fx[i] = { 5, id, x, vol / 100, pitch / 100 }
    elseif kind == 6 then
      local x, y, ang, spread, r, g, b, count, speed, size, grav
      x, y, ang, spread, r, g, b, count, speed, size, grav, pos = unpack("<hhhBBBBBHBB", raw, pos)
      v.fx[i] = { 6, x, y, ang / 1000, spread / 40, { r / 255, g / 255, b / 255 }, count, speed, size / 10, grav / 50 }
    elseif kind == 7 then
      local x, y, rad, r, g, b
      x, y, rad, r, g, b, pos = unpack("<hhBBBB", raw, pos)
      v.fx[i] = { 7, x, y, rad, { r / 255, g / 255, b / 255 } }
    elseif kind == 8 then
      local x, y, r, g, b, count, size
      x, y, r, g, b, count, size, pos = unpack("<hhBBBBB", raw, pos)
      v.fx[i] = { 8, x, y, { r / 255, g / 255, b / 255 }, count, size }
    elseif kind == 9 then
      local dx, dy
      dx, dy, pos = unpack("<hh", raw, pos)
      v.fx[i] = { 9, dx / 10, dy / 10 }
    else
      v.fx[i] = { 4 }
    end
  end
  return v
end

return Snap
