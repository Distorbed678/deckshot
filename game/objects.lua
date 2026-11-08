-- Map objects: hazards (saws, spikes, lasers...), breakables (crates, glass, barrels...),
-- ropes that hold things up, and spawned effects (pickups, gas clouds).
--
-- A map lists objects as { type = "saw", x = .., y = .., ...props }. Every round the world
-- builds fresh instances from that list (Objects.build), so breakables come back.
-- Rect-shaped objects use x, y (top-left), w, h. Round ones (saw, blade arm pivot, rope anchor,
-- laser emitter, turret, weight, pickup) use x, y as their centre.
--
-- Solid objects (crates, platforms, walls...) are added to world.solids, so players and
-- bullets collide with them like map rects. They carry `isObject = true` and their own `type`.
-- On clients, objects are rebuilt from the same map list and updated from snapshots; draw()
-- only reads synced fields (x, y, a, s, alive, flags) plus the map's props.
local Map = require "game.map"
local fx = require "gfx.fx"
local sfx = require "gfx.sfx"

local Objects = {}

local GRAVITY = 1800
local SHOVE = 750        -- speed hazards push you away with
local SHOVE_UP = 380
local BURN = { 0.4, 0.9, 0.2 }

-- Network codes for object types (append only).
Objects.CODES = {
  "saw", "spikes", "laser", "crusher", "flame", "acid", "turret", "conveyor", "pad", "fan",
  "crumble", "arm", "platform", "crate", "glass", "rope", "barrel", "gas", "wall", "plank", "weight",
}
Objects.CODE = {}
for i, n in ipairs(Objects.CODES) do Objects.CODE[n] = i end
Objects.EFFECTS = { "pickup", "cloud" }
-- Types removed by the "Map hazards: off" rule (breakables stay).
Objects.HAZARD = { saw = true, spikes = true, laser = true, crusher = true, flame = true, acid = true,
  turret = true, arm = true }

Objects.T = {}
local T = Objects.T

sfx.define("saw", { { wave = "saw", dur = 0.18, f0 = 900, f1 = 700, vol = 0.12, lp = 0.3 },
  { wave = "noise", dur = 0.15, vol = 0.12, lp = 0.6 } })
sfx.define("spike", { { wave = "noise", dur = 0.08, vol = 0.35, lp = 0.6 },
  { wave = "square", dur = 0.08, f0 = 700, f1 = 300, vol = 0.2, lp = 0.5 } })
sfx.define("crateBreak", { { wave = "noise", dur = 0.22, vol = 0.5, lp = 0.25, decay = 2.5 },
  { wave = "square", dur = 0.12, f0 = 180, f1 = 90, vol = 0.25, lp = 0.3 } })
sfx.define("glassBreak", { { wave = "noise", dur = 0.3, vol = 0.4, lp = 0.9, decay = 3 },
  { wave = "sine", dur = 0.25, f0 = 3200, f1 = 2400, vol = 0.12 }, { wave = "sine", dur = 0.2, f0 = 4100, vol = 0.08, at = 0.04 } })
sfx.define("ropeSnap", { { wave = "noise", dur = 0.06, vol = 0.4, lp = 0.7 },
  { wave = "tri", dur = 0.12, f0 = 600, f1 = 200, vol = 0.25 } })
sfx.define("thud", { { wave = "sine", dur = 0.15, f0 = 110, f1 = 50, vol = 0.5 }, { wave = "noise", dur = 0.08, vol = 0.3, lp = 0.2 } })
sfx.define("crusher", { { wave = "noise", dur = 0.3, vol = 0.6, lp = 0.15 }, { wave = "sine", dur = 0.3, f0 = 70, f1 = 35, vol = 0.6 } })
sfx.define("turretShot", { { wave = "square", dur = 0.08, f0 = 600, f1 = 200, vol = 0.22, lp = 0.4 } })
sfx.define("pad", { { wave = "sine", dur = 0.2, f0 = 200, f1 = 900, vol = 0.35 }, { wave = "tri", dur = 0.15, f0 = 400, f1 = 1200, vol = 0.15 } })
sfx.define("crumble", { { wave = "noise", dur = 0.3, vol = 0.35, lp = 0.2, attack = 0.05 } })
sfx.define("gas", { { wave = "noise", dur = 0.6, vol = 0.35, lp = 0.5, attack = 0.05, decay = 1 } })
sfx.define("pickup", { { wave = "sine", dur = 0.08, f0 = 880, vol = 0.25 }, { wave = "sine", dur = 0.12, f0 = 1320, vol = 0.25, at = 0.07 } })
sfx.define("laserCharge", { { wave = "saw", dur = 0.5, f0 = 200, f1 = 900, vol = 0.12, lp = 0.2, attack = 0.2, decay = 0.5 } })
sfx.define("laserFire", { { wave = "saw", dur = 0.35, f0 = 120, f1 = 110, vol = 0.3, lp = 0.4, vib = 30 } })
sfx.define("flame", { { wave = "noise", dur = 0.5, vol = 0.35, lp = 0.15, attack = 0.05, decay = 1 } })
sfx.define("barrier", { { wave = "square", dur = 0.25, f0 = 440, vol = 0.2, lp = 0.4 },
  { wave = "square", dur = 0.25, f0 = 440, vol = 0.2, lp = 0.4, at = 0.4 }, { wave = "square", dur = 0.4, f0 = 330, vol = 0.25, lp = 0.4, at = 0.8 } })
sfx.define("acid", { { wave = "noise", dur = 0.15, vol = 0.3, lp = 0.3 }, { wave = "sine", dur = 0.1, f0 = 300, f1 = 600, vol = 0.12 } })

---------------------------------------------------------------- helpers
local function clamp(v, a, b) return math.max(a, math.min(b, v)) end

-- Cycle phase helper: returns "off" | "warn" | "on" and the time into the cycle.
-- p: props with off, warn, on durations and an optional phase offset.
local function cyclePhase(time, off, warn, on, offset)
  local total = off + warn + on
  local t = (time + (offset or 0)) % total
  if t < off then return "off", t end
  if t < off + warn then return "warn", t - off end
  return "on", t - off - warn
end

local function rectOf(o)
  return o.x, o.y, o.w, o.h
end

local function playerBox(p)
  return p.x - p.r, p.y - p.r, p.r * 2, p.r * 2
end

local function overlapsPlayer(o, p)
  local x, y, w, h = playerBox(p)
  return Map.overlaps(x, y, w, h, o)
end

local function circleHitsPlayer(cx, cy, r, p)
  local dx, dy = p.x - cx, p.y - cy
  local reach = r + p.r
  return dx * dx + dy * dy < reach * reach
end

-- Distance from point to segment.
local function segDist(px, py, ax, ay, bx, by)
  local vx, vy = bx - ax, by - ay
  local len2 = vx * vx + vy * vy
  local t = len2 > 0 and clamp(((px - ax) * vx + (py - ay) * vy) / len2, 0, 1) or 0
  local qx, qy = ax + vx * t, ay + vy * t
  return math.sqrt((px - qx) ^ 2 + (py - qy) ^ 2)
end
Objects.segDist = segDist

-- A hazard touched a player: blocking bounces them off for free, otherwise damage and a shove.
-- (dx, dy): direction away from the hazard. Per-player cooldown per object.
function Objects.hazardHit(world, o, p, damage, dx, dy, kind, cooldown, source)
  o.cd = o.cd or {}
  local now = world.time
  if (o.cd[p] or -1) > now then return end
  o.cd[p] = now + (cooldown or 0.4)
  local len = math.sqrt(dx * dx + dy * dy)
  if len < 0.01 then dx, dy, len = 0, -1, 1 end
  dx, dy = dx / len, dy / len
  p.vx = dx * SHOVE
  p.vy = math.min(dy * SHOVE, -SHOVE_UP)
  if dy > 0.7 then p.vy = dy * SHOVE end -- pushed down (ceiling spikes)
  p.controlLock = math.max(p.controlLock, 0.15)
  p.dashTimer, p.lungeTimer = 0, 0
  damage = damage * (p.stats.hazardTaken or 1)
  if p:isBlocking() then
    fx.burst(p.x - dx * p.r, p.y - dy * p.r, { 1, 1, 1 }, 10, 260, 3)
    p:emitSound("edgeBlock")
    p:blocked()
    return
  end
  p:hit(damage, 0, 0, 0, source, kind)
end

---------------------------------------------------------------- building
-- Default sizes / props per type (the editor uses these too).
Objects.DEFAULTS = {
  saw = { r = 28, speed = 160, damage = 25 },
  spikes = { w = 80, h = 16, dir = "up", damage = 30 },
  laser = { dir = "down", off = 2.0, warn = 0.8, on = 1.0, damage = 40 },
  crusher = { w = 120, h = 60, travel = 200, wait = 1.8, damage = 60 },
  flame = { length = 150, off = 2.5, warn = 0.5, on = 1.0, damage = 12 },
  acid = { w = 200, h = 40, damage = 20 },
  turret = { hp = 60, rate = 2, damage = 20 },
  conveyor = { w = 200, h = 20, speed = 160 },
  pad = { w = 70, h = 14, power = 1350 },
  fan = { w = 80, h = 260, dir = "up", force = 3000 },
  crumble = { w = 120, h = 18, delay = 0.5, back = 4 },
  arm = { length = 110, count = 2, spin = 1.6, r = 22, damage = 25 },
  platform = { w = 120, h = 18, speed = 120 },
  crate = { w = 50, h = 50, hp = 60, drop = 0.08 },
  glass = { w = 16, h = 120, hp = 1 },
  rope = {},
  barrel = { w = 36, h = 48, hp = 30, radius = 110, damage = 55 },
  gas = { w = 28, h = 42, hp = 20, radius = 110 },
  wall = { w = 40, h = 120, hp = 150 },
  plank = { w = 100, h = 14, hp = 0 },
  weight = { r = 26, damage = 60 },
}

local function copy(t)
  local c = {}
  for k, v in pairs(t) do c[k] = v end
  return c
end

-- Fresh instances for a map. Works without a world (clients draw from the same list).
function Objects.build(map)
  local list = {}
  for i, def in ipairs(map.objects or {}) do
    local o = copy(Objects.DEFAULTS[def.type] or {})
    for k, v in pairs(def) do o[k] = v end
    o.index = i
    o.alive = true
    o.a = 0
    o.s = 0
    o.flags = 0
    if o.path then
      local pts = {}
      for k, pt in ipairs(o.path) do pts[k] = { pt[1], pt[2] } end
      o.path = pts
    end
    local t = T[o.type]
    if t then
      o.solid = t.solid
      o.isObject = t.solid or nil
      if t.init then t.init(o, list) end
    end
    list[i] = o
  end
  -- Ropes find what they hold (by index) and measure their length.
  for _, o in ipairs(list) do
    if o.type == "rope" and o.target and list[o.target] then
      local tgt = list[o.target]
      o.held = tgt
      tgt.rope = o
      local tx, ty = Objects.hangPoint(tgt)
      o.length = math.max(10, math.sqrt((tx - o.x) ^ 2 + (ty - o.y) ^ 2))
      o.angle = math.atan2(tx - o.x, ty - o.y) -- 0 = straight down
      o.omega = 0
    end
  end
  return list
end

-- The point of an object a rope attaches to (top centre for rects, centre for round ones).
function Objects.hangPoint(o)
  if o.w then return o.x + o.w / 2, o.y end
  return o.x, o.y
end

local function setHang(o, x, y)
  if o.w then
    o.x, o.y = x - o.w / 2, y
  else
    o.x, o.y = x, y
  end
end

---------------------------------------------------------------- shared behaviours
-- Solid rects other than `self` (for falling objects).
local function solidsExcept(world, self)
  local out = {}
  for _, r in ipairs(world.solids) do
    if r ~= self then out[#out + 1] = r end
  end
  return out
end

local function hitExcept(rects, self, x, y, w, h)
  for _, b in ipairs(rects) do
    if b ~= self and not b.oneway and Map.overlaps(x, y, w, h, b) then return b end
  end
end

-- Falling objects: gravity, landing, hurting whoever they land on.
local function fall(o, world, dt)
  o.vy = math.min((o.vy or 0) + GRAVITY * dt, 1400)
  o.vx = (o.vx or 0) * (1 - 1.5 * dt)
  local rects = solidsExcept(world, o)
  local w, h = o.w or o.r * 2, o.h or o.r * 2
  local left = o.w and o.x or o.x - o.r
  local top = o.w and o.y or o.y - o.r
  local nx, ny = left + o.vx * dt, top + o.vy * dt
  if Map.hit(rects, nx, top, w, h) then o.vx = 0 nx = left end
  local hitRect = Map.hit(rects, nx, ny, w, h)
  local landed = false
  if hitRect then
    if o.vy > 0 then ny = hitRect.y - h end
    if o.vy > 350 then sfx.play("thud", nx + w / 2, math.min(1, o.vy / 1000)) end
    o.vy = 0
    landed = true
  end
  -- Hurt players it falls on.
  if (o.vy or 0) > 250 or (landed and not o.landedOnce) then
    for _, p in ipairs(world.players) do
      if not p.dead and Map.overlaps(p.x - p.r, p.y - p.r, p.r * 2, p.r * 2, { x = nx, y = ny, w = w, h = h }) then
        local dmg = o.fallDamage or (o.type == "weight" and o.damage) or 30
        Objects.hazardHit(world, o, p, dmg, p.x - (nx + w / 2), 0.3, "falling", 1, o.breaker)
      end
    end
  end
  if o.w then o.x, o.y = nx, ny else o.x, o.y = nx + o.r, ny + o.r end
  if landed then
    o.falling = false
    o.landedOnce = true
  end
  if o.y > 900 then o.alive = false end
end

-- Physics objects (crates, barrels...) fall when nothing holds them up.
local function supported(o, world)
  if o.rope then return true end
  return hitExcept(world.solids, o, o.x + 2, o.y + o.h, o.w - 4, 2) ~= nil
end

-- Move along a path of waypoints (ping-pong or loop). Returns dx, dy moved.
local function followPath(o, dt)
  local pts = o.path
  if not pts or #pts < 2 then return 0, 0 end
  o.seg = o.seg or 1
  o.dirn = o.dirn or 1
  local cx, cy = o.x, o.y
  if o.w then cx, cy = o.x + o.w / 2, o.y + o.h / 2 end
  local remaining = (o.speed or 120) * dt
  local x, y = cx, cy
  for _ = 1, 8 do
    local nextIndex = o.seg + o.dirn
    if nextIndex > #pts or nextIndex < 1 then
      if o.loop then
        nextIndex = nextIndex > #pts and 1 or #pts
      else
        o.dirn = -o.dirn
        nextIndex = o.seg + o.dirn
      end
    end
    local tx, ty = pts[nextIndex][1], pts[nextIndex][2]
    local dx, dy = tx - x, ty - y
    local d = math.sqrt(dx * dx + dy * dy)
    if d <= remaining then
      x, y = tx, ty
      remaining = remaining - d
      o.seg = nextIndex
    else
      x, y = x + dx / d * remaining, y + dy / d * remaining
      break
    end
  end
  local mx, my = x - cx, y - cy
  o.x, o.y = o.x + mx, o.y + my
  return mx, my
end

-- Riders (players standing on top) move with a platform.
local function carryRiders(o, world, dx, dy)
  if dx == 0 and dy == 0 then return end
  for _, p in ipairs(world.players) do
    if not p.dead and p.groundRect == o then
      p.x = p.x + dx
      if dy < 0 or p.onGround then p.y = p.y + dy end
    end
  end
end

-- An object took damage. Returns true if it broke.
function Objects.damage(world, o, amount, source, x, y)
  if not o.alive or not o.hp or o.hp <= 0 then return false end
  if source and source.stats and source.stats.objectDamage then amount = amount * source.stats.objectDamage end
  o.hp = o.hp - amount
  o.hitFlash = 0.1
  o.breaker = source or o.breaker
  if o.hp > 0 then
    if o.type == "wall" then fx.spray(x or o.x + o.w / 2, y or o.y + o.h / 2, -math.pi / 2, 2, { 0.55, 0.55, 0.6 }, 3, 160, 3, 1) end
    return false
  end
  o.alive = false
  local t = T[o.type]
  if t and t.broken then t.broken(o, world, source) end
  return true
end

-- Cut a rope: whatever it held falls (keeping its swing velocity).
function Objects.cut(world, rope, source)
  if not rope.alive then return end
  rope.alive = false
  local h = rope.held
  sfx.play("ropeSnap", rope.x)
  fx.spray(rope.x, rope.y, math.pi / 2, 1, { 0.75, 0.6, 0.4 }, 6, 150, 2, 1)
  if h and h.alive then
    h.rope = nil
    h.falling = true
    h.breaker = source
    local v = (rope.omega or 0) * rope.length
    h.vx = math.cos(rope.angle) * v
    h.vy = -math.sin(rope.angle) * v
  end
end

-- Swing a hanging object (impulse in px/s, horizontal).
function Objects.push(o, impulse)
  local rope = o.rope
  if rope and rope.alive then rope.omega = (rope.omega or 0) + impulse / math.max(20, rope.length) end
end

---------------------------------------------------------------- hazards
T.saw = {
  init = function(o) o.a = 0 end,
  update = function(o, world, dt)
    o.a = (o.a + dt * 12) % (math.pi * 2)
    if o.falling then
      fall(o, world, dt)
    elseif not o.rope then
      followPath(o, dt)
    end
    for _, p in ipairs(world.players) do
      if not p.dead and circleHitsPlayer(o.x, o.y, o.r - 3, p) then
        if not (o.cd and (o.cd[p] or -1) > world.time) then sfx.play("saw", o.x) end
        Objects.hazardHit(world, o, p, o.damage, p.x - o.x, p.y - o.y, "saw", 0.4, o.breaker)
      end
    end
  end,
  draw = function(o)
    local teeth = 12
    local pts = {}
    for i = 0, teeth * 2 - 1 do
      local ang = o.a + i * math.pi / teeth
      local rr = (i % 2 == 0) and o.r or o.r * 0.78
      pts[#pts + 1] = o.x + math.cos(ang) * rr
      pts[#pts + 1] = o.y + math.sin(ang) * rr
    end
    love.graphics.setColor(0.78, 0.8, 0.86)
    love.graphics.polygon("fill", pts)
    love.graphics.setColor(0.45, 0.47, 0.52)
    love.graphics.circle("fill", o.x, o.y, o.r * 0.55)
    love.graphics.setColor(0.25, 0.26, 0.3)
    love.graphics.circle("fill", o.x, o.y, o.r * 0.18)
    if o.path and #o.path > 1 then
      love.graphics.setColor(1, 1, 1, 0.07)
      love.graphics.setLineWidth(3)
      local flat = {}
      for _, pt in ipairs(o.path) do flat[#flat + 1] = pt[1]; flat[#flat + 1] = pt[2] end
      love.graphics.line(flat)
    end
  end,
}

-- Spikes point in `dir`; retracting ones (props off/warn/on) only hurt while out.
T.spikes = {
  update = function(o, world, dt)
    local out = true
    if o.on then
      local ph = cyclePhase(world.time, o.off or 2, o.warn or 0.5, o.on, o.phase)
      out = ph == "on"
      o.s = ph == "on" and 2 or ph == "warn" and 1 or 0
      if ph == "on" and not o.wasOut then sfx.play("spike", o.x + o.w / 2, 0.6) end
      o.wasOut = ph == "on"
    else
      o.s = 2
    end
    if not out then return end
    local nx, ny = 0, -1
    if o.dir == "down" then nx, ny = 0, 1 elseif o.dir == "left" then nx, ny = -1, 0 elseif o.dir == "right" then nx, ny = 1, 0 end
    for _, p in ipairs(world.players) do
      if not p.dead and overlapsPlayer(o, p) then
        if not (o.cd and (o.cd[p] or -1) > world.time) then sfx.play("spike", p.x) end
        Objects.hazardHit(world, o, p, o.damage, nx * 2 + (p.x - (o.x + o.w / 2)) / 200, ny, "spikes", 0.5)
      end
    end
  end,
  draw = function(o)
    local ext = o.s == 2 and 1 or o.s == 1 and 0.25 or (o.on and 0.08 or 1)
    if o.s == 1 then ext = 0.25 + 0.1 * math.sin(love.timer.getTime() * 40) end
    local vertical = o.dir == "up" or o.dir == "down"
    local len = vertical and o.w or o.h
    local depth = vertical and o.h or o.w
    local n = math.max(1, math.floor(len / 16 + 0.5))
    local step = len / n
    love.graphics.setColor(0.3, 0.31, 0.36)
    if o.dir == "up" then love.graphics.rectangle("fill", o.x, o.y + o.h - 4, o.w, 4)
    elseif o.dir == "down" then love.graphics.rectangle("fill", o.x, o.y, o.w, 4)
    elseif o.dir == "left" then love.graphics.rectangle("fill", o.x + o.w - 4, o.y, 4, o.h)
    else love.graphics.rectangle("fill", o.x, o.y, 4, o.h) end
    love.graphics.setColor(0.85, 0.85, 0.9)
    for i = 0, n - 1 do
      local a0, a1 = i * step, (i + 1) * step
      local d = depth * ext
      if o.dir == "up" then
        local base = o.y + o.h
        love.graphics.polygon("fill", o.x + a0, base, o.x + a1, base, o.x + (a0 + a1) / 2, base - d)
      elseif o.dir == "down" then
        love.graphics.polygon("fill", o.x + a0, o.y, o.x + a1, o.y, o.x + (a0 + a1) / 2, o.y + d)
      elseif o.dir == "left" then
        local base = o.x + o.w
        love.graphics.polygon("fill", base, o.y + a0, base, o.y + a1, base - d, o.y + (a0 + a1) / 2)
      else
        love.graphics.polygon("fill", o.x, o.y + a0, o.x, o.y + a1, o.x + d, o.y + (a0 + a1) / 2)
      end
    end
  end,
}

local DIRS = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

-- Laser emitter: charge line, then a beam that stops at the first solid (crates are cover).
T.laser = {
  update = function(o, world, dt)
    local ph = cyclePhase(world.time, o.off, o.warn, o.on, o.phase)
    local prev = o.s
    o.s = ph == "on" and 2 or ph == "warn" and 1 or 0
    if o.s == 1 and prev == 0 then sfx.play("laserCharge", o.x, 0.7) end
    if o.s == 2 and prev ~= 2 then sfx.play("laserFire", o.x) end
    local d = DIRS[o.dir] or DIRS.down
    -- Beam length: march until a solid.
    local len = 0
    local rects = world.solids
    while len < 1500 do
      local px, py = o.x + d[1] * (len + 14), o.y + d[2] * (len + 14)
      if px < -10 or px > 1290 or py < -10 or py > 730 or Map.hit(rects, px - 2, py - 2, 4, 4) then break end
      len = len + 6
    end
    o.a = len
    if o.s ~= 2 then return end
    local ex, ey = o.x + d[1] * (len + 14), o.y + d[2] * (len + 14)
    for _, p in ipairs(world.players) do
      if not p.dead and segDist(p.x, p.y, o.x, o.y, ex, ey) < p.r + 5 then
        -- Pushed sideways off the beam.
        local side = d[1] == 0 and (p.x >= o.x and 1 or -1) or 0
        local sideY = d[2] == 0 and (p.y >= o.y and 1 or -1) or -0.4
        Objects.hazardHit(world, o, p, o.damage, side, sideY, "laser", 0.5)
      end
    end
  end,
  draw = function(o)
    local d = DIRS[o.dir] or DIRS.down
    local len = o.a or 0
    local ex, ey = o.x + d[1] * (len + 14), o.y + d[2] * (len + 14)
    if o.s == 1 then
      love.graphics.setColor(1, 0.25, 0.25, 0.35 + 0.25 * math.sin(love.timer.getTime() * 30))
      love.graphics.setLineWidth(2)
      love.graphics.line(o.x, o.y, ex, ey)
    elseif o.s == 2 then
      love.graphics.setColor(1, 0.2, 0.25, 0.85)
      love.graphics.setLineWidth(10)
      love.graphics.line(o.x, o.y, ex, ey)
      love.graphics.setColor(1, 0.9, 0.9)
      love.graphics.setLineWidth(3)
      love.graphics.line(o.x, o.y, ex, ey)
    end
    love.graphics.setColor(0.35, 0.36, 0.42)
    love.graphics.rectangle("fill", o.x - 14, o.y - 14, 28, 28, 5, 5)
    love.graphics.setColor(o.s == 0 and 0.4 or 1, 0.2, 0.25)
    love.graphics.circle("fill", o.x + d[1] * 8, o.y + d[2] * 8, 6)
  end,
  glow = function(o)
    if o.s ~= 2 then return end
    local d = DIRS[o.dir] or DIRS.down
    local len = o.a or 0
    love.graphics.setColor(1, 0.2, 0.25, 0.9)
    love.graphics.setLineWidth(12)
    love.graphics.line(o.x, o.y, o.x + d[1] * (len + 14), o.y + d[2] * (len + 14))
  end,
}

-- Crusher: waits at the top, slams down `travel` px, waits, rises. Solid.
T.crusher = {
  solid = true,
  init = function(o) o.top = o.y; o.state = "wait"; o.timer = o.phase or 0 end,
  update = function(o, world, dt)
    local before = o.y
    o.timer = o.timer + dt
    if o.state == "wait" and o.timer >= o.wait then
      o.state, o.timer = "down", 0
    elseif o.state == "down" then
      o.y = math.min(o.top + o.travel, o.y + 1300 * dt)
      if o.y >= o.top + o.travel then
        o.state, o.timer = "bottom", 0
        sfx.play("crusher", o.x + o.w / 2)
        fx.addShake(5)
        fx.spray(o.x, o.y + o.h, math.pi, 0.6, { 0.7, 0.7, 0.75 }, 6, 220, 3, 0.3)
        fx.spray(o.x + o.w, o.y + o.h, 0, 0.6, { 0.7, 0.7, 0.75 }, 6, 220, 3, 0.3)
      end
    elseif o.state == "bottom" and o.timer >= 0.5 then
      o.state, o.timer = "up", 0
    elseif o.state == "up" then
      o.y = math.max(o.top, o.y - 220 * dt)
      if o.y <= o.top then o.state, o.timer = "wait", 0 end
    end
    o.s = o.state == "down" and 1 or 0
    local dy = o.y - before
    carryRiders(o, world, 0, dy)
    if dy > 0 then
      -- Players under it get pushed down; pinned against the ground means crushed.
      for _, p in ipairs(world.players) do
        if not p.dead and overlapsPlayer(o, p) then
          p.y = o.y + o.h + p.r
          local others = solidsExcept(world, o)
          if not p:freeAt(p.x, p.y, others) then
            local side = p.x < o.x + o.w / 2 and -1 or 1
            p.x = side < 0 and o.x - p.r - 1 or o.x + o.w + p.r + 1
            if p:freeAt(p.x, p.y, others) == false then p.y = o.y - p.r end
            Objects.hazardHit(world, o, p, o.damage, side, -0.3, "crusher", 1)
          end
        end
      end
    end
  end,
  draw = function(o)
    love.graphics.setColor(0.32, 0.33, 0.4)
    love.graphics.rectangle("fill", o.x + o.w / 2 - 6, o.top - 400, 12, o.y - o.top + 400)
    love.graphics.setColor(0.5, 0.42, 0.3)
    love.graphics.rectangle("fill", o.x, o.y, o.w, o.h, 4, 4)
    love.graphics.setColor(0.95, 0.75, 0.2)
    for i = 0, math.floor(o.w / 24) do
      love.graphics.polygon("fill", o.x + i * 24, o.y + o.h - 10, o.x + i * 24 + 12, o.y + o.h - 10,
        o.x + i * 24 + 4, o.y + o.h, o.x + i * 24 - 8, o.y + o.h)
    end
  end,
}

-- Flame jet: a vent at (x, y) that shoots fire upward `length` px on a cycle.
T.flame = {
  update = function(o, world, dt)
    local ph = cyclePhase(world.time, o.off, o.warn, o.on, o.phase)
    local prev = o.s
    o.s = ph == "on" and 2 or ph == "warn" and 1 or 0
    if o.s == 2 and prev ~= 2 then sfx.play("flame", o.x) end
    if o.s == 1 and love.math.random() < dt * 20 then
      fx.spray(o.x, o.y - 4, -math.pi / 2, 0.4, { 1, 0.5, 0.15 }, 1, 120, 2, -0.2)
    end
    if o.s ~= 2 then return end
    if love.math.random() < dt * 40 then
      fx.spray(o.x, o.y - 4, -math.pi / 2, 0.25, { 1, 0.55 + love.math.random() * 0.3, 0.1 }, 2, o.length * 2.2, 5, -0.3)
    end
    local zone = { x = o.x - 18, y = o.y - o.length, w = 36, h = o.length }
    for _, p in ipairs(world.players) do
      if not p.dead and overlapsPlayer(zone, p) then
        local before = o.cd and o.cd[p]
        Objects.hazardHit(world, o, p, o.damage, (p.x - o.x) / 30, -1, "fire", 0.5)
        if o.cd[p] ~= before and not p:isBlocking() then p:poisonFor(16, 2) end
      end
    end
  end,
  draw = function(o)
    love.graphics.setColor(0.3, 0.31, 0.36)
    love.graphics.rectangle("fill", o.x - 20, o.y - 8, 40, 8, 2, 2)
    love.graphics.setColor(o.s == 0 and 0.35 or 1, 0.4, 0.1)
    love.graphics.rectangle("fill", o.x - 10, o.y - 10, 20, 4)
    if o.s == 2 then
      local t = love.timer.getTime()
      for i = 0, 5 do
        local f = i / 5
        local w = 26 * (1 - f * 0.6) + math.sin(t * 25 + i) * 4
        love.graphics.setColor(1, 0.45 + 0.4 * f, 0.1, 0.55 * (1 - f * 0.5))
        love.graphics.ellipse("fill", o.x, o.y - o.length * f, w / 2, o.length / 8)
      end
    end
  end,
  glow = function(o)
    if o.s ~= 2 then return end
    love.graphics.setColor(1, 0.5, 0.1, 0.5)
    love.graphics.rectangle("fill", o.x - 14, o.y - o.length, 28, o.length)
  end,
}

-- Acid pool: damage over time and a hop up out of it.
T.acid = {
  update = function(o, world, dt)
    o.a = (o.a + dt) % 100
    for _, p in ipairs(world.players) do
      if not p.dead and overlapsPlayer(o, p) then
        if not (o.cd and (o.cd[p] or -1) > world.time) then
          sfx.play("acid", p.x)
          fx.spray(p.x, o.y, -math.pi / 2, 1, { 0.5, 1, 0.3 }, 6, 220, 3, 1)
        end
        Objects.hazardHit(world, o, p, o.damage, 0, -1.6, "acid", 0.5)
        if p.vy > -900 then p.vy = -900 end
      end
    end
  end,
  draw = function(o)
    love.graphics.setColor(0.35, 0.85, 0.2, 0.75)
    love.graphics.rectangle("fill", o.x, o.y + 4, o.w, o.h - 4)
    love.graphics.setColor(0.6, 1, 0.4)
    local t = love.timer.getTime()
    local pts = {}
    for i = 0, 20 do
      pts[#pts + 1] = o.x + o.w * i / 20
      pts[#pts + 1] = o.y + 4 + math.sin(t * 3 + i * 0.9) * 2.5
    end
    love.graphics.setLineWidth(3)
    love.graphics.line(pts)
  end,
  glow = function(o)
    love.graphics.setColor(0.4, 1, 0.2, 0.35)
    love.graphics.rectangle("fill", o.x, o.y + 4, o.w, o.h - 4)
  end,
}

-- Turret: shoots the nearest visible player every `rate` seconds. Breakable.
T.turret = {
  init = function(o) o.timer = 1 + (o.phase or 0); o.maxHp = o.hp; o.a = -math.pi / 2 end,
  update = function(o, world, dt)
    if not o.alive then return end
    local target, best
    for _, p in ipairs(world.players) do
      if not p.dead and (p.cloakTimer or 0) <= 0 then
        local dx, dy = p.x - o.x, p.y - o.y
        local d = dx * dx + dy * dy
        if (not best or d < best) and Objects.lineClear(world, o.x, o.y, p.x, p.y) then target, best = p, d end
      end
    end
    if target then
      local want = math.atan2(target.y - o.y, target.x - o.x)
      local diff = (want - o.a + math.pi) % (math.pi * 2) - math.pi
      o.a = o.a + clamp(diff, -4 * dt, 4 * dt)
    end
    o.timer = o.timer - dt
    o.s = o.timer < 0.4 and 1 or 0
    if o.timer <= 0 then
      o.timer = o.rate
      if target then Objects.turretFire(world, o) end
    end
  end,
  draw = function(o)
    if not o.alive then
      love.graphics.setColor(0.25, 0.25, 0.28)
      love.graphics.rectangle("fill", o.x - 16, o.y + 6, 32, 10, 3, 3)
      return
    end
    love.graphics.setColor(0.4, 0.41, 0.48)
    love.graphics.rectangle("fill", o.x - 18, o.y + 4, 36, 14, 4, 4)
    love.graphics.setColor((o.hitFlash or 0) > 0 and 1 or 0.55, 0.56, 0.64)
    love.graphics.circle("fill", o.x, o.y, 16)
    love.graphics.setColor(0.8, 0.82, 0.88)
    love.graphics.setLineWidth(7)
    love.graphics.line(o.x, o.y, o.x + math.cos(o.a) * 28, o.y + math.sin(o.a) * 28)
    love.graphics.setColor(1, o.s == 1 and 0.2 or 0.6, 0.2)
    love.graphics.circle("fill", o.x, o.y, 5)
  end,
  hitTest = function(o, x, y, r)
    return o.alive and (x - o.x) ^ 2 + (y - o.y) ^ 2 < (18 + r) ^ 2
  end,
  broken = function(o, world)
    fx.debris(o.x, o.y, { 0.55, 0.56, 0.64 }, 8, 10)
    fx.burst(o.x, o.y, { 1, 0.6, 0.2 }, 16, 300, 4)
    sfx.play("explosionSmall", o.x)
  end,
}

-- Turrets fire real bullets owned by a shared "turret" pseudo-player (not in world.players).
function Objects.turretFire(world, o)
  local Bullet = require "game.bullet"
  local owner = world.turretOwner
  if not owner then
    local Player = require "game.player"
    owner = Player.new(0, { 0.9, 0.9, 0.95 }, require("core.input").remote())
    owner.slot, owner.name, owner.isTurret = 0, "Turret", true
    owner.dead, owner.invuln, owner.hp, owner.slowTimer = false, 0, 1e9, 0
    owner.comboCount, owner.swapCd = 0, 0
    owner.game = world
    world.turretOwner = owner
  end
  owner.x, owner.y = o.x, o.y
  local speed = 700
  local mx, my = o.x + math.cos(o.a) * 30, o.y + math.sin(o.a) * 30
  local b = Bullet.new(owner, mx, my, math.cos(o.a) * speed, math.sin(o.a) * speed)
  b.damage = o.damage
  b.gravity = 0
  b.bounces = 0
  b.color = { 1, 0.5, 0.3 }
  b.hitObjects = { [o] = true }
  world:addBullet(b)
  sfx.play("turretShot", o.x)
  fx.spray(mx, my, o.a, 0.4, { 1, 0.8, 0.5 }, 4, 200, 2, 0.1)
end

-- Is the straight line between two points free of solids?
function Objects.lineClear(world, x0, y0, x1, y1)
  local dx, dy = x1 - x0, y1 - y0
  local d = math.sqrt(dx * dx + dy * dy)
  local steps = math.floor(d / 12)
  for i = 1, steps - 1 do
    local t = i / steps
    if Map.hit(world.solids, x0 + dx * t - 1, y0 + dy * t - 1, 2, 2) then return false end
  end
  return true
end

-- Conveyor: solid; moves whatever stands on it.
T.conveyor = {
  solid = true,
  update = function(o, world, dt)
    o.a = (o.a + o.speed * dt) % 20
    for _, p in ipairs(world.players) do
      if not p.dead and p.groundRect == o then p:moveX(o.speed * dt, world.solids) end
    end
    for _, c in ipairs(world.objects) do
      if c.alive and c.w and c ~= o and not c.rope and math.abs(c.y + c.h - o.y) < 2
          and c.x + c.w > o.x and c.x < o.x + o.w and (c.type == "crate" or c.type == "barrel" or c.type == "gas") then
        c.x = c.x + o.speed * dt
      end
    end
  end,
  draw = function(o)
    love.graphics.setColor(0.24, 0.25, 0.3)
    love.graphics.rectangle("fill", o.x, o.y, o.w, o.h, 8, 8)
    love.graphics.setColor(0.55, 0.56, 0.62)
    local off = o.a or 0
    for i = 0, math.floor(o.w / 20) do
      local x = o.x + ((i * 20 + off) % o.w)
      love.graphics.polygon("fill", x, o.y + 4, x + 6 * (o.speed > 0 and 1 or -1), o.y + o.h / 2, x, o.y + o.h - 4)
    end
  end,
}

-- Bounce pad: launches players up; bullets that hit it come off faster.
T.pad = {
  update = function(o, world, dt)
    o.s = math.max(0, (o.s or 0) - dt * 4)
    for _, p in ipairs(world.players) do
      if not p.dead and p.vy >= -100 and overlapsPlayer(o, p) then
        p.vy = -(o.power or 1350)
        p.jumping = false
        p.dashesLeft = p.stats.dashes
        p.jumpsLeft = p.stats.airJumps
        o.s = 1
        sfx.play("pad", o.x + o.w / 2)
        fx.spray(o.x + o.w / 2, o.y, -math.pi / 2, 1.2, { 0.5, 1, 0.9 }, 8, 300, 3, 0.5)
      end
    end
  end,
  bullet = function(o, b)
    if b.vy > 0 then
      b.vy = -math.abs(b.vy) * 1.3
      b.vx = b.vx * 1.15
      o.s = 1
    end
  end,
  draw = function(o)
    local squash = (o.s or 0) * 6
    love.graphics.setColor(0.3, 0.31, 0.36)
    love.graphics.rectangle("fill", o.x, o.y + o.h - 5, o.w, 5)
    love.graphics.setColor(0.35, 0.95, 0.8)
    love.graphics.rectangle("fill", o.x + 4, o.y + squash, o.w - 8, o.h - 5 - squash, 4, 4)
  end,
  glow = function(o)
    love.graphics.setColor(0.35, 0.95, 0.8, 0.4)
    love.graphics.rectangle("fill", o.x + 4, o.y, o.w - 8, o.h - 5)
  end,
}

-- Fan: pushes players and bullets inside its stream (dir up/down/left/right).
T.fan = {
  update = function(o, world, dt)
    o.a = (o.a + dt * 20) % (math.pi * 2)
    local d = DIRS[o.dir] or DIRS.up
    for _, p in ipairs(world.players) do
      if not p.dead and overlapsPlayer(o, p) then
        p.vx = p.vx + d[1] * o.force * dt
        p.vy = p.vy + d[2] * o.force * dt
        if d[2] < 0 and p.vy < -700 then p.vy = -700 end
      end
    end
    for _, b in ipairs(world.bullets) do
      if not b.laser and not b.mine and Map.overlaps(b.x, b.y, 1, 1, o) then
        b.vx = b.vx + d[1] * o.force * 0.6 * dt
        b.vy = b.vy + d[2] * o.force * 0.6 * dt
      end
    end
    if love.math.random() < dt * 10 then
      local x, y = o.x + love.math.random() * o.w, o.y + love.math.random() * o.h
      fx.spray(x, y, math.atan2(d[2], d[1]), 0.2, { 0.8, 0.9, 1 }, 1, 260, 1.5, 0)
    end
  end,
  draw = function(o)
    local d = DIRS[o.dir] or DIRS.up
    love.graphics.setColor(0.7, 0.85, 1, 0.05)
    love.graphics.rectangle("fill", o.x, o.y, o.w, o.h)
    -- The fan housing sits at the stream's source end.
    local bx, by = o.x + o.w / 2, o.y + o.h
    if d[2] > 0 then by = o.y elseif d[1] > 0 then bx, by = o.x, o.y + o.h / 2 elseif d[1] < 0 then bx, by = o.x + o.w, o.y + o.h / 2 end
    love.graphics.setColor(0.35, 0.36, 0.42)
    love.graphics.circle("fill", bx, by, 22)
    love.graphics.setColor(0.75, 0.77, 0.85)
    for i = 0, 2 do
      local ang = o.a + i * math.pi * 2 / 3
      love.graphics.ellipse("fill", bx + math.cos(ang) * 10, by + math.sin(ang) * 10, 9, 4)
    end
  end,
}

-- Crumbling platform: breaks shortly after someone stands on it, then comes back.
T.crumble = {
  solid = true,
  init = function(o) o.timer = 0; o.state = "solid" end,
  update = function(o, world, dt)
    if o.state == "solid" then
      for _, p in ipairs(world.players) do
        if not p.dead and p.groundRect == o then
          o.state, o.timer = "shaking", 0
          sfx.play("crumble", o.x + o.w / 2, 0.6)
          break
        end
      end
    elseif o.state == "shaking" then
      o.timer = o.timer + dt
      if o.timer >= o.delay then
        o.state, o.timer = "gone", 0
        o.solid = false
        fx.debris(o.x + o.w / 2, o.y + o.h / 2, { 0.55, 0.5, 0.45 }, 6, 10)
        sfx.play("crateBreak", o.x + o.w / 2, 0.5)
      end
    elseif o.state == "gone" then
      o.timer = o.timer + dt
      if o.timer >= o.back then
        local blocked = false
        for _, p in ipairs(world.players) do
          if not p.dead and overlapsPlayer(o, p) then blocked = true end
        end
        if not blocked then o.state, o.solid = "solid", true end
      end
    end
    o.s = o.state == "solid" and 0 or o.state == "shaking" and 1 or 2
  end,
  draw = function(o)
    if o.s == 2 then
      love.graphics.setColor(1, 1, 1, 0.06)
      love.graphics.rectangle("line", o.x, o.y, o.w, o.h, 3, 3)
      return
    end
    local jx = o.s == 1 and (love.math.random() - 0.5) * 3 or 0
    love.graphics.setColor(0.5, 0.45, 0.4)
    love.graphics.rectangle("fill", o.x + jx, o.y, o.w, o.h, 3, 3)
    love.graphics.setColor(0.35, 0.3, 0.27)
    love.graphics.setLineWidth(2)
    for i = 1, math.floor(o.w / 30) do
      love.graphics.line(o.x + jx + i * 30, o.y, o.x + jx + i * 30 - 6, o.y + o.h)
    end
  end,
}

-- Rotating blade arm: `count` saws (1 or 2) on a bar spinning around (x, y).
T.arm = {
  init = function(o) o.a = o.phase or 0 end,
  update = function(o, world, dt)
    o.a = (o.a + o.spin * dt) % (math.pi * 2)
    for k = 1, o.count do
      local ang = o.a + (k - 1) * math.pi
      local sx, sy = o.x + math.cos(ang) * o.length, o.y + math.sin(ang) * o.length
      for _, p in ipairs(world.players) do
        if not p.dead and circleHitsPlayer(sx, sy, o.r - 3, p) then
          if not (o.cd and (o.cd[p] or -1) > world.time) then sfx.play("saw", sx) end
          Objects.hazardHit(world, o, p, o.damage, p.x - sx, p.y - sy, "saw", 0.4)
        end
      end
    end
  end,
  draw = function(o)
    love.graphics.setColor(0.4, 0.41, 0.48)
    love.graphics.setLineWidth(8)
    for k = 1, o.count do
      local ang = o.a + (k - 1) * math.pi
      love.graphics.line(o.x, o.y, o.x + math.cos(ang) * o.length, o.y + math.sin(ang) * o.length)
    end
    for k = 1, o.count do
      local ang = o.a + (k - 1) * math.pi
      T.saw.draw({ x = o.x + math.cos(ang) * o.length, y = o.y + math.sin(ang) * o.length, r = o.r, a = o.a * 6 })
    end
    love.graphics.setColor(0.3, 0.31, 0.36)
    love.graphics.circle("fill", o.x, o.y, 12)
  end,
}

-- Moving platform: solid, follows its path, carries riders.
T.platform = {
  solid = true,
  update = function(o, world, dt)
    if o.rope or o.falling then return end
    local dx, dy = followPath(o, dt)
    carryRiders(o, world, dx, dy)
  end,
  draw = function(o)
    love.graphics.setColor(0.36, 0.38, 0.48)
    love.graphics.rectangle("fill", o.x, o.y, o.w, o.h, 4, 4)
    love.graphics.setColor(0.6, 0.65, 0.85)
    love.graphics.rectangle("fill", o.x, o.y, o.w, 3)
  end,
}

---------------------------------------------------------------- breakables
local function physicsUpdate(o, world, dt)
  if o.rope then return end
  if o.falling then
    fall(o, world, dt)
  elseif not supported(o, world) then
    o.falling, o.vy = true, 0
  end
end

local function dropPickup(world, o)
  if love.math.random() < (o.drop or 0) then
    local kind = love.math.random() < 0.5 and 1 or 2 -- 1 health, 2 ammo
    table.insert(world.effects, { type = "pickup", kind = kind, x = o.x + o.w / 2, y = o.y + o.h / 2, life = 8, max = 8, vy = -250 })
  end
end

T.crate = {
  solid = true,
  init = function(o) o.maxHp = o.hp end,
  update = physicsUpdate,
  draw = function(o)
    if not o.alive then return end
    local f = (o.hitFlash or 0) > 0
    love.graphics.setColor(f and 1 or 0.62, f and 1 or 0.45, f and 1 or 0.26)
    love.graphics.rectangle("fill", o.x, o.y, o.w, o.h, 3, 3)
    love.graphics.setColor(0.42, 0.29, 0.16)
    love.graphics.setLineWidth(4)
    love.graphics.rectangle("line", o.x + 2, o.y + 2, o.w - 4, o.h - 4, 2, 2)
    love.graphics.line(o.x + 4, o.y + 4, o.x + o.w - 4, o.y + o.h - 4)
    local dmg = 1 - (o.hp or 1) / (o.maxHp or 1)
    if dmg > 0.3 then
      love.graphics.setColor(0.2, 0.13, 0.07)
      love.graphics.setLineWidth(2)
      love.graphics.line(o.x + o.w * 0.7, o.y, o.x + o.w * 0.55, o.y + o.h * 0.4, o.x + o.w * 0.75, o.y + o.h * 0.6)
    end
  end,
  broken = function(o, world)
    fx.debris(o.x + o.w / 2, o.y + o.h / 2, { 0.62, 0.45, 0.26 }, 10, 12)
    sfx.play("crateBreak", o.x + o.w / 2)
    dropPickup(world, o)
  end,
}

T.glass = {
  solid = true,
  draw = function(o)
    if not o.alive then return end
    love.graphics.setColor(0.6, 0.85, 1, 0.25)
    love.graphics.rectangle("fill", o.x, o.y, o.w, o.h)
    love.graphics.setColor(0.8, 0.95, 1, 0.7)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", o.x, o.y, o.w, o.h)
    love.graphics.line(o.x + o.w * 0.2, o.y + 6, o.x + o.w * 0.2, o.y + o.h * 0.4)
  end,
  broken = function(o)
    for _ = 1, 3 do
      fx.spray(o.x + o.w / 2, o.y + love.math.random() * o.h, love.math.random() * math.pi * 2, 6.3,
        { 0.75, 0.92, 1 }, 6, 260, 2.5, 1)
    end
    sfx.play("glassBreak", o.x)
  end,
}

local function explodeAt(world, x, y, radius, damage, source, color)
  fx.ring(x, y, radius, color)
  fx.burst(x, y, color, 24, 380, 5)
  fx.addShake(9)
  sfx.play("explosion", x)
  for _, p in ipairs(world.players) do
    if not p.dead then
      local dx, dy = p.x - x, p.y - y
      local d = math.sqrt(dx * dx + dy * dy)
      if d < radius + p.r then p:hit(damage * (1 - 0.4 * d / (radius + p.r)), dx, dy - 40, 700, source, "explosion") end
    end
  end
  Objects.explosion(world, x, y, radius, damage, source)
end
Objects.explodeAt = explodeAt

T.barrel = {
  solid = true,
  init = function(o) o.maxHp = o.hp end,
  update = physicsUpdate,
  draw = function(o)
    if not o.alive then return end
    local f = (o.hitFlash or 0) > 0
    love.graphics.setColor(f and 1 or 0.78, f and 1 or 0.2, f and 1 or 0.16)
    love.graphics.rectangle("fill", o.x, o.y, o.w, o.h, 6, 6)
    love.graphics.setColor(0.45, 0.1, 0.08)
    love.graphics.rectangle("fill", o.x, o.y + o.h * 0.2, o.w, 4)
    love.graphics.rectangle("fill", o.x, o.y + o.h * 0.75, o.w, 4)
    love.graphics.setColor(1, 0.85, 0.2)
    love.graphics.polygon("fill", o.x + o.w / 2, o.y + o.h * 0.35, o.x + o.w / 2 - 7, o.y + o.h * 0.62, o.x + o.w / 2 + 7, o.y + o.h * 0.62)
  end,
  broken = function(o, world, source)
    -- A short delay makes chain reactions ripple instead of all popping at once.
    table.insert(world.pendingBlasts, { t = 0.08, x = o.x + o.w / 2, y = o.y + o.h / 2, radius = o.radius,
      damage = o.damage, source = source })
    fx.debris(o.x + o.w / 2, o.y + o.h / 2, { 0.6, 0.15, 0.12 }, 8, 10)
  end,
}

T.gas = {
  solid = true,
  update = physicsUpdate,
  draw = function(o)
    if not o.alive then return end
    local f = (o.hitFlash or 0) > 0
    love.graphics.setColor(f and 1 or 0.45, f and 1 or 0.7, f and 1 or 0.3)
    love.graphics.rectangle("fill", o.x, o.y + 6, o.w, o.h - 6, 8, 8)
    love.graphics.setColor(0.3, 0.32, 0.3)
    love.graphics.rectangle("fill", o.x + o.w / 2 - 5, o.y, 10, 8)
    love.graphics.setColor(0.15, 0.2, 0.1)
    love.graphics.circle("fill", o.x + o.w / 2, o.y + o.h * 0.55, 6)
  end,
  broken = function(o, world, source)
    sfx.play("gas", o.x)
    table.insert(world.effects, { type = "cloud", x = o.x + o.w / 2, y = o.y + o.h / 2, radius = o.radius,
      life = 4, max = 4, source = source })
  end,
}

T.wall = {
  solid = true,
  init = function(o) o.maxHp = o.hp end,
  draw = function(o)
    if not o.alive then return end
    local f = (o.hitFlash or 0) > 0
    love.graphics.setColor(f and 0.7 or 0.42, f and 0.7 or 0.38, f and 0.7 or 0.36)
    love.graphics.rectangle("fill", o.x, o.y, o.w, o.h)
    love.graphics.setColor(0.32, 0.29, 0.27)
    love.graphics.setLineWidth(2)
    for row = 0, math.floor(o.h / 20) do
      local y = o.y + row * 20
      love.graphics.line(o.x, y, o.x + o.w, y)
      local off = (row % 2) * 15
      for col = 0, math.floor(o.w / 30) do
        local x = o.x + off + col * 30
        if x < o.x + o.w then love.graphics.line(x, y, x, math.min(o.y + o.h, y + 20)) end
      end
    end
    local dmg = 1 - (o.hp or 1) / (o.maxHp or 1)
    if dmg > 0.25 then
      love.graphics.setColor(0.12, 0.1, 0.1, 0.8)
      love.graphics.setLineWidth(3)
      love.graphics.line(o.x + o.w * 0.3, o.y + o.h * 0.1, o.x + o.w * 0.6, o.y + o.h * 0.35, o.x + o.w * 0.4, o.y + o.h * 0.55)
      if dmg > 0.6 then
        love.graphics.line(o.x + o.w * 0.7, o.y + o.h * 0.5, o.x + o.w * 0.35, o.y + o.h * 0.8, o.x + o.w * 0.6, o.y + o.h)
      end
    end
  end,
  broken = function(o)
    fx.debris(o.x + o.w / 2, o.y + o.h / 2, { 0.42, 0.38, 0.36 }, 14, 14)
    sfx.play("crateBreak", o.x + o.w / 2, 1, 0.7)
    fx.addShake(4)
  end,
}

-- A bridge plank (or any hanging platform): solid, held by a rope.
T.plank = {
  solid = true,
  update = function(o, world, dt)
    if o.falling then fall(o, world, dt) end
  end,
  draw = function(o)
    if not o.alive then return end
    love.graphics.setColor(0.55, 0.4, 0.24)
    love.graphics.rectangle("fill", o.x, o.y, o.w, o.h, 2, 2)
    love.graphics.setColor(0.4, 0.28, 0.15)
    love.graphics.setLineWidth(2)
    love.graphics.line(o.x + 4, o.y + o.h / 2, o.x + o.w - 4, o.y + o.h / 2)
  end,
}

-- Weight / chandelier: hangs from a rope, crushes whoever it falls on.
T.weight = {
  update = function(o, world, dt)
    if o.falling then fall(o, world, dt) end
  end,
  draw = function(o)
    if not o.alive then return end
    love.graphics.setColor(0.3, 0.3, 0.34)
    love.graphics.polygon("fill", o.x - o.r, o.y + o.r, o.x + o.r, o.y + o.r, o.x + o.r * 0.6, o.y - o.r * 0.6,
      o.x - o.r * 0.6, o.y - o.r * 0.6)
    love.graphics.setColor(0.95, 0.85, 0.4)
    for i = -1, 1 do love.graphics.circle("fill", o.x + i * o.r * 0.6, o.y + o.r + 4, 4) end
  end,
}

-- Rope: anchor (x, y), holds object `target` (map object index). Swings it as a pendulum.
T.rope = {
  update = function(o, world, dt)
    local h = o.held
    if not o.alive or not h or not h.alive then return end
    local g = 1800
    o.omega = (o.omega or 0) - (g / o.length) * math.sin(o.angle) * dt
    o.omega = o.omega * (1 - 0.6 * dt)
    o.angle = o.angle + o.omega * dt
    local bx, by = o.x + math.sin(o.angle) * o.length, o.y + math.cos(o.angle) * o.length
    local hx, hy = Objects.hangPoint(h)
    setHang(h, bx, by)
    if h.solid then carryRiders(h, world, bx - hx, by - hy) end
    o.a = o.angle
  end,
  hitTest = function(o, x, y, r)
    if not o.alive or not o.held then return false end
    local bx, by = Objects.hangPoint(o.held)
    return segDist(x, y, o.x, o.y, bx, by) < r + 3
  end,
  draw = function(o, list)
    if not o.alive then return end
    local h = o.held or (list and o.target and list[o.target])
    if not h then return end
    local bx, by = Objects.hangPoint(h)
    love.graphics.setColor(0.72, 0.6, 0.42)
    love.graphics.setLineWidth(3)
    love.graphics.line(o.x, o.y, bx, by)
    love.graphics.setColor(0.35, 0.36, 0.42)
    love.graphics.circle("fill", o.x, o.y, 5)
  end,
}

---------------------------------------------------------------- world hooks
-- Explosions damage objects in range and swing hanging ones.
function Objects.explosion(world, x, y, radius, damage, source)
  for _, o in ipairs(world.objects or {}) do
    if o.alive then
      local cx, cy = o.x, o.y
      if o.w then cx, cy = o.x + o.w / 2, o.y + o.h / 2 end
      local d = math.sqrt((cx - x) ^ 2 + (cy - y) ^ 2)
      if d < radius + 30 then
        if o.type == "rope" then
          Objects.cut(world, o, source)
        else
          if o.hp then Objects.damage(world, o, damage, source, cx, cy) end
          Objects.push(o, (cx - x) / math.max(1, d) * 500)
        end
      end
    end
  end
end

-- A bullet step at (x, y) radius r: cut ropes / damage non-solid targets. Returns true to stop the bullet.
function Objects.bulletTouch(world, b)
  for _, o in ipairs(world.objects or {}) do
    local t = T[o.type]
    if o.alive and t and t.hitTest and not (b.hitObjects and b.hitObjects[o]) and t.hitTest(o, b.x, b.y, b.r) then
      if o.type == "rope" then
        Objects.cut(world, o, b.owner)
        b.hitObjects = b.hitObjects or {}
        b.hitObjects[o] = true -- passes through ropes
      else
        Objects.damage(world, o, b:currentDamage(), b.owner, b.x, b.y)
        return true
      end
    end
  end
  -- Bounce pads speed bullets up; hanging things get swung.
  for _, o in ipairs(world.objects or {}) do
    if o.alive and o.type == "pad" and Map.overlaps(b.x - b.r, b.y - b.r, b.r * 2, b.r * 2, o) then T.pad.bullet(o, b) end
  end
  return false
end

-- A bullet bounced off (or stopped at) a solid object.
function Objects.bulletHitSolid(world, o, b)
  if not o.alive then return end
  if o.hp and o.hp > 0 then Objects.damage(world, o, b:currentDamage(), b.owner, b.x, b.y) end
  Objects.push(o, b.vx * 0.15)
end

-- Melee swings break and push objects in reach.
function Objects.melee(world, p, reach, heavy, power)
  local aim = math.atan2(p.aimY, p.aimX)
  for _, o in ipairs(world.objects or {}) do
    if o.alive and not (p.lungeHit and p.lungeHit[o]) then
      local cx, cy = o.x, o.y
      if o.w and o.type ~= "rope" then cx, cy = o.x + o.w / 2, o.y + o.h / 2 end
      local hit
      if o.type == "rope" then
        local bx, by = Objects.hangPoint(o.held or o)
        hit = segDist(p.x + p.aimX * (p.r + reach * 0.6), p.y + p.aimY * (p.r + reach * 0.6), o.x, o.y, bx, by) < reach * 0.5
      else
        local size = o.w and math.max(o.w, o.h) / 2 or (o.r or 16)
        local dx, dy = cx - p.x, cy - p.y
        local d = math.sqrt(dx * dx + dy * dy)
        local diff = math.abs((math.atan2(dy, dx) - aim + math.pi) % (math.pi * 2) - math.pi)
        hit = d < p.r + reach + size and diff < 1.4
      end
      if hit then
        if p.lungeHit then p.lungeHit[o] = true end
        if o.type == "rope" then
          Objects.cut(world, o, p)
        else
          if o.hp and o.hp > 0 then Objects.damage(world, o, heavy and 40 * (1 + power) or 15, p, cx, cy) end
          Objects.push(o, p.aimX * (heavy and 900 or 400))
        end
      end
    end
  end
end

-- Update everything (host / local only). Rebuilds world.solids afterwards.
function Objects.update(world, dt)
  for _, o in ipairs(world.objects) do
    o.hitFlash = math.max(0, (o.hitFlash or 0) - dt)
    local t = T[o.type]
    if (o.alive or o.type == "turret") and t and t.update then t.update(o, world, dt) end
  end
  -- Delayed barrel blasts (chain reactions ripple outwards).
  for i = #world.pendingBlasts, 1, -1 do
    local e = world.pendingBlasts[i]
    e.t = e.t - dt
    if e.t <= 0 then
      table.remove(world.pendingBlasts, i)
      explodeAt(world, e.x, e.y, e.radius, e.damage, e.source, { 1, 0.55, 0.15 })
    end
  end
  -- Pickups and gas clouds.
  for i = #world.effects, 1, -1 do
    local e = world.effects[i]
    e.life = e.life - dt
    if e.type == "pickup" then
      e.vy = math.min((e.vy or 0) + 900 * dt, 500)
      local ny = e.y + e.vy * dt
      if Map.hit(world.solids, e.x - 10, ny - 10, 20, 20) then e.vy = 0 else e.y = ny end
      for _, p in ipairs(world.players) do
        if not p.dead and circleHitsPlayer(e.x, e.y, 14, p) then
          if e.kind == 1 then
            p:heal(25)
            fx.burst(p.x, p.y, { 0.4, 1, 0.5 }, 12, 200, 3)
          else
            p.ammo = math.max(p.ammo, p.stats.ammo)
            p.reloadTimer = 0
            fx.burst(p.x, p.y, { 1, 0.9, 0.4 }, 12, 200, 3)
          end
          sfx.play("pickup", p.x)
          e.life = 0
        end
      end
    elseif e.type == "strike" and e.life <= 0 then
      -- Lightning (Thunder God): strikes where the enemy was when it started charging.
      fx.ring(e.x, e.y, e.radius, { 0.7, 0.85, 1 })
      fx.spray(e.x, e.y, -math.pi / 2, 0.4, { 0.8, 0.9, 1 }, 14, 500, 3, -0.5)
      fx.addShake(4)
      sfx.play("laserFire", e.x, 0.8, 1.6)
      for _, p in ipairs(world.players) do
        if not p.dead and p ~= e.owner and circleHitsPlayer(e.x, e.y, e.radius, p) then
          p:hit(e.damage, p.x - e.x, -1, 300, e.owner, "lightning")
        end
      end
    elseif e.type == "cloud" then
      for _, p in ipairs(world.players) do
        if not p.dead and circleHitsPlayer(e.x, e.y, e.radius, p) and (p.poisonTimer or 0) < 0.6 then
          p:poisonFor(8, 1)
          p.lastAttacker = e.source or p.lastAttacker
          p.lastHitKind = "gas"
        end
      end
    end
    if e.life <= 0 or e.y > 800 then table.remove(world.effects, i) end
  end
  Objects.rebuildSolids(world)
end

function Objects.rebuildSolids(world)
  local solids = {}
  for i, r in ipairs(world.map.rects) do solids[i] = r end
  for _, o in ipairs(world.objects) do
    if o.alive and o.solid then solids[#solids + 1] = o end
  end
  world.solids = solids
end

---------------------------------------------------------------- drawing
function Objects.draw(list, effects)
  -- Ropes behind what they hold.
  for _, o in ipairs(list) do
    if o.type == "rope" then T.rope.draw(o, list) end
  end
  for _, o in ipairs(list) do
    local t = T[o.type]
    if o.type ~= "rope" and t and t.draw and (o.alive or o.type == "turret") then t.draw(o) end
  end
  for _, e in ipairs(effects or {}) do Objects.drawEffect(e) end
end

function Objects.drawGlow(list, effects)
  for _, o in ipairs(list) do
    local t = T[o.type]
    if o.alive and t and t.glow then t.glow(o) end
  end
  for _, e in ipairs(effects or {}) do
    if e.type == "pickup" then
      love.graphics.setColor(e.kind == 1 and 0.4 or 1, e.kind == 1 and 1 or 0.85, e.kind == 1 and 0.5 or 0.3, 0.6)
      love.graphics.circle("fill", e.x, e.y, 14)
    end
  end
end

function Objects.drawEffect(e)
  local t = love.timer.getTime()
  if e.type == "pickup" then
    local a = (e.life or 8) < 2 and (math.floor(t * 10) % 2 == 0 and 0.4 or 1) or 1
    local y = e.y + math.sin(t * 4) * 3
    love.graphics.setColor(0.15, 0.15, 0.2, a)
    love.graphics.circle("fill", e.x, y, 13)
    if e.kind == 1 then
      love.graphics.setColor(0.4, 1, 0.5, a)
      love.graphics.rectangle("fill", e.x - 3, y - 8, 6, 16)
      love.graphics.rectangle("fill", e.x - 8, y - 3, 16, 6)
    else
      love.graphics.setColor(1, 0.85, 0.3, a)
      for i = -1, 1 do love.graphics.rectangle("fill", e.x + i * 5 - 1.5, y - 7, 3, 14, 1, 1) end
    end
  elseif e.type == "strike" then
    local k = 1 - math.max(0, e.life or 0) / (e.max or 0.75)
    love.graphics.setColor(0.7, 0.85, 1, 0.15 + 0.35 * k)
    love.graphics.circle("fill", e.x, e.y, (e.radius or 55) * k)
    love.graphics.setColor(0.85, 0.95, 1, 0.8)
    love.graphics.setLineWidth(2)
    love.graphics.circle("line", e.x, e.y, e.radius or 55)
    love.graphics.line(e.x, e.y - 400, e.x, e.y - 400 + 400 * k)
  elseif e.type == "cloud" then
    local frac = math.min(1, (e.life or 1) / 1)
    for i = 1, 6 do
      local ang = t * 0.6 + i
      love.graphics.setColor(0.45, 0.8, 0.2, 0.12 * frac)
      love.graphics.circle("fill", e.x + math.cos(ang) * e.radius * 0.35, e.y + math.sin(ang * 1.3) * e.radius * 0.25,
        e.radius * 0.6)
    end
  end
end

return Objects
