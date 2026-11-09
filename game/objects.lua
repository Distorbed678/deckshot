-- Map objects: hazards (saws, spikes, lasers...), breakables (crates, glass, barrels...),
-- ropes that hold things up, and spawned effects (pickups, gas clouds).
--
-- A map lists objects as { type = "saw", x = .., y = .., ...props }. Every round the world
-- builds fresh instances from that list (Objects.build), so breakables come back.
-- Rect-shaped objects use x, y (top-left), w, h. Round ones (saw, blade arm pivot, rope anchor,
-- laser emitter, turret, weight, pickup) use x, y as their centre.
--
-- Loose objects are simulated in game/physics.lua and carry `rot`, their angle in radians, and
-- anchored ones stay put until their anchor (anchorHp > 0) is shot off.
--
-- Solid objects (crates, platforms, walls...) are added to world.solids, so players and
-- bullets collide with them like map rects. They carry `isObject = true` and their own `type`.
-- On clients, objects are rebuilt from the same map list and updated from snapshots; draw()
-- only reads synced fields (x, y, a, s, alive, flags) plus the map's props.
local Map = require "game.map"
local fx = require("game.events").fx
local sfx = require("game.events").sfx
local Physics = require "game.physics"

local Objects = {}

local SHOVE = 750        -- speed hazards push you away with
local SHOVE_UP = 380
local BURN = { 0.4, 0.9, 0.2 }

-- Network codes for object types (append only).
Objects.CODES = {
  "saw", "spikes", "laser", "crusher", "flame", "acid", "turret", "conveyor", "pad", "fan",
  "crumble", "arm", "platform", "crate", "glass", "rope", "barrel", "gas", "wall", "plank", "weight",
  "block", "rail", "liquid",
}
Objects.CODE = {}
for i, n in ipairs(Objects.CODES) do Objects.CODE[n] = i end
Objects.EFFECTS = { "pickup", "cloud" }
-- Types removed by the "Map hazards: off" rule (breakables stay).
Objects.HAZARD = { saw = true, spikes = true, laser = true, crusher = true, flame = true, liquid = true, turret = true }

-- Is this one a hazard? A liquid only counts if it hurts or harms.
function Objects.isHazard(o)
  if o.type == "liquid" then return (o.damage or 0) > 0 or o.poison or o.burn or o.frost or false end
  return Objects.HAZARD[o.type] or false
end

Objects.T = {}
local T = Objects.T


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

local function overlapsPlayer(o, p)
  return Physics.boxHitsPlayer(o.x, o.y, o.w, o.h, o.rot, p)
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
-- Defaults per object type and the block materials come from data/objects.txt.
Objects.DEFAULTS, Objects.MATERIALS, Objects.MATERIAL_LIST = {}, {}, {}
do
  local function value(v)
    if v == "true" then return true elseif v == "false" then return false end
    return tonumber(v) or v
  end
  local text = love.filesystem.read("data/objects.txt") or ""
  for line in text:gmatch("[^\r\n]+") do
    local kind, name, rest = line:match("^(%a+)%s+(%S+)%s*(.*)$")
    if kind == "object" or kind == "material" then
      local t = {}
      for k, v in rest:gsub("\\ ", "\1"):gmatch("([%w_]+)=(%S+)") do t[k] = value((v:gsub("\1", " "))) end
      if kind == "object" then
        Objects.DEFAULTS[name] = t
      else
        Objects.MATERIALS[name] = t
        Objects.MATERIAL_LIST[#Objects.MATERIAL_LIST + 1] = name
      end
    end
  end
end

-- "#RRGGBB" or "ch3" (a shared colour channel) to r, g, b; nil if unset.
function Objects.colorOf(value, channels)
  if type(value) ~= "string" then return nil end
  local n = value:match("^ch(%d+)$")
  if n then value = channels and channels[tonumber(n)] end
  if type(value) ~= "string" then return nil end
  local r, g, b = value:match("^#(%x%x)(%x%x)(%x%x)$")
  if not r then return nil end
  return tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255
end

local function copy(t)
  local c = {}
  for k, v in pairs(t) do c[k] = v end
  return c
end

local function markLoose(o)
  o.loose = true
  o.rot = o.rot or 0
  o.mass = Physics.massOf(o)
end

-- Fresh instances for a map. Works without a world (clients draw from the same list).
function Objects.build(map)
  local list, byId = {}, {}
  local theme
  for i, def in ipairs(map.objects or {}) do
    local o = copy(Objects.DEFAULTS[def.type] or {})
    o.density, o.bounce = nil, nil -- how it behaves in Box2D, not settings of this instance
    for k, v in pairs(def) do o[k] = v end
    o.index = i
    o.alive = true
    o.a = 0
    o.s = 0
    o.flags = 0
    o.ANIMATED = o.type == "saw" or o.type == "fan" or o.conveyor or nil
    if o.path then
      local pts = {}
      for k, pt in ipairs(o.path) do pts[k] = { pt[1], pt[2] } end
      o.path = pts
    end
    if o.id then byId[o.id] = o end
    local r, g, b = Objects.colorOf(o.color, map.channels)
    if r then
      o.rgb = { r, g, b }
    elseif o.type == "block" and o.material == "stone" then
      if not theme then theme = require("gfx.atmosphere").themeOf(map) end
      o.rgb, o.edgeRgb = theme.block, theme.edge
    end
    local t = T[o.type]
    if t then
      o.solid = t.solid
      o.isObject = t.solid or nil
      if t.solid then o.mass = Physics.massOf(o) end
      if t.init then t.init(o, list) end
    end
    if Physics.isLoose(o) then markLoose(o) end
    list[i] = o
  end
  list.byId = byId
  for _, o in ipairs(list) do
    if o.type == "rope" then
      local tgt = o.target and byId[o.target]
      local from = o.from and byId[o.from]
      o.held, o.heldFrom = tgt, from
      if tgt and not o.x2 then o.x2, o.y2 = Objects.hangPoint(tgt) end
      if not o.x2 then o.x2, o.y2 = o.x, o.y + 120 end
      o.length = math.max(10, math.sqrt((o.x2 - o.x) ^ 2 + (o.y2 - o.y) ^ 2) * (o.slack or 1))
      if tgt then tgt.rope = o end
    elseif o.parent and byId[o.parent] then
      o.parentObj = byId[o.parent]
    end
  end
  return list
end

-- The point of an object a rope attaches to (top centre for rects, centre for round ones).
function Objects.hangPoint(o)
  if o.w then return o.x + o.w / 2, o.y end
  return o.x, o.y
end

---------------------------------------------------------------- shared behaviours
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
  if not o.alive then return false end
  if source and source.stats and source.stats.objectDamage then amount = amount * source.stats.objectDamage end
  -- A breakable anchor (or attachment) takes the hits until it gives way.
  if (o.anchored or o.parent) and (o.anchorHp or 0) > 0 then
    o.anchorHp = o.anchorHp - amount
    o.hitFlash = 0.1
    if o.anchorHp <= 0 then
      local cx, cy = o.x, o.y
      if o.w then cx, cy = o.x + o.w / 2, o.y + o.h / 2 end
      Physics.release(world, o)
      o.breaker = source or o.breaker
      sfx.play("ropeSnap", cx)
      fx.spray(cx, cy, -math.pi / 2, 3, { 0.75, 0.75, 0.8 }, 8, 220, 2.5, 1)
    end
    return false
  end
  if not o.hp or o.hp <= 0 then return false end
  o.hp = o.hp - amount
  o.hitFlash = 0.1
  o.breaker = source or o.breaker
  if o.hp > 0 then
    if o.material == "brick" then fx.spray(x or o.x + o.w / 2, y or o.y + o.h / 2, -math.pi / 2, 2, { 0.55, 0.55, 0.6 }, 3, 160, 3, 1) end
    return false
  end
  o.alive = false
  local t = T[o.type]
  if t and t.broken then t.broken(o, world, source) end
  local demo = source and source.stats and source.stats.demolition or 0
  if demo > 0 and o.w and (o.onBreak or "none") ~= "explode" then
    -- Demolition Crew: whatever this player breaks goes off like a small bomb.
    table.insert(world.pendingBlasts, { t = 0.06, x = o.x + o.w / 2, y = o.y + o.h / 2, radius = 90 * (1 + 0.3 * (demo - 1)),
      damage = 30 * demo, source = source, owner = source })
  end
  return true
end

-- Shove a loose object. (ix, iy) is the speed in px/s it would give a crate; (x, y) is where it
-- lands, source who gets the credit if it hurts someone.
function Objects.push(o, ix, iy, x, y, source)
  Physics.kick(o, ix, iy, x, y, source)
end

-- Can damage do anything to this object?
local function damageable(o)
  return (o.hp and o.hp > 0) or ((o.anchored or o.parent) and (o.anchorHp or 0) > 0)
end

---------------------------------------------------------------- hazards
T.saw = {
  init = function(o) o.a = 0 end,
  update = function(o, world, dt)
    o.a = (o.a + dt * 12) % (math.pi * 2)
    for _, p in ipairs(world.players) do
      if not p.dead and circleHitsPlayer(o.x, o.y, o.r - 3, p) then
        if not (o.cd and (o.cd[p] or -1) > world.time) then sfx.play("saw", o.x) end
        Objects.hazardHit(world, o, p, o.damage, p.x - o.x, p.y - o.y, "saw", 0.4, o.breaker)
      end
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
    if o.rot then
      local c, s = math.cos(o.rot), math.sin(o.rot)
      nx, ny = nx * c - ny * s, nx * s + ny * c
    end
    for _, p in ipairs(world.players) do
      if not p.dead and overlapsPlayer(o, p) then
        if not (o.cd and (o.cd[p] or -1) > world.time) then sfx.play("spike", p.x) end
        Objects.hazardHit(world, o, p, o.damage, nx * 2 + (p.x - (o.x + o.w / 2)) / 200, ny, "spikes", 0.5)
      end
    end
  end,
}

local DIRS = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

-- Which way a flame points, turning with whatever it's attached to.
local function flameAngle(o)
  local d = DIRS[o.dir or "up"] or DIRS.up
  return math.atan2(d[2], d[1]) + (o.rot or 0)
end

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
      if px < -10 or px > Map.W + 10 or py < -10 or py > Map.H + 10 or Physics.hit(world, px - 2, py - 2, 4, 4) then break end
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
      local ny = math.min(o.top + o.travel, o.y + 1300 * dt)
      local bottom = o.y + o.h
      -- Anything under the head stops it, at the first thing it would touch.
      local blocker, stopY
      for _, f in ipairs({ 0.08, 0.5, 0.92 }) do
        local hit, _, hy = Physics.ray(world, o.x + o.w * f, bottom - 1, o.x + o.w * f, ny + o.h + 1, nil, o)
        if hit and (not stopY or hy < stopY) then blocker, stopY = hit, hy end
      end
      if not blocker then blocker = Physics.hit(world, o.x + 2, bottom, o.w - 4, math.max(1, ny - o.y), o) end
      if blocker then ny = stopY and math.max(o.y, stopY - o.h) or o.y end
      o.y = ny
      if blocker or o.y >= o.top + o.travel then
        o.state, o.timer = "bottom", 0
        sfx.play("crusher", o.x + o.w / 2)
        fx.addShake(blocker and 7 or 5)
        fx.spray(o.x, o.y + o.h, math.pi, 0.6, { 0.7, 0.7, 0.75 }, 6, 220, 3, 0.3)
        fx.spray(o.x + o.w, o.y + o.h, 0, 0.6, { 0.7, 0.7, 0.75 }, 6, 220, 3, 0.3)
        if blocker then
          fx.spray(o.x + o.w / 2, o.y + o.h, -math.pi / 2, 2.6, { 1, 0.8, 0.35 }, 14, 420, 2.5, 1)
          if blocker.isObject then Objects.damage(world, blocker, o.damage, nil, o.x + o.w / 2, o.y + o.h) end
        end
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
          if not p:freeAt(p.x, p.y, o) then
            local side = p.x < o.x + o.w / 2 and -1 or 1
            p.x = side < 0 and o.x - p.r - 1 or o.x + o.w + p.r + 1
            if p:freeAt(p.x, p.y, o) == false then p.y = o.y - p.r - p.leg end
            Objects.hazardHit(world, o, p, o.damage, side, -0.3, "crusher", 1)
          end
        end
      end
    end
  end,
}

-- Flame jet: a vent at (x, y) that shoots fire upward `length` px on a cycle.
T.flame = {
  update = function(o, world, dt)
    local ph = cyclePhase(world.time, o.off, o.warn, o.on, o.phase)
    local prev = o.s
    o.s = ph == "on" and 2 or ph == "warn" and 1 or 0
    local a = flameAngle(o)
    local dx, dy = math.cos(a), math.sin(a)
    local nx, ny = o.x + dx * 8, o.y + dy * 8
    if o.s == 2 and prev ~= 2 then sfx.play("flame", o.x) end
    if o.s == 1 and love.math.random() < dt * 20 then
      fx.spray(nx, ny, a, 0.4, { 1, 0.5, 0.15 }, 1, 120, 2, -0.2)
    end
    -- The flame reaches the first solid thing; ropes in the way burn but don't stop it.
    local hit, hx, hy = Physics.ray(world, nx, ny, nx + dx * o.length, ny + dy * o.length, nil, o)
    local reach = hit and math.sqrt((hx - nx) ^ 2 + (hy - ny) ^ 2) or o.length
    o.a = reach
    if o.s ~= 2 then return end
    Physics.burnRopes(world, nx, ny, nx + dx * reach, ny + dy * reach, 40 * dt)
    if hit and hit.isObject then
      local m = hit.material
      if m == "crate" or m == "wood" or hit.onBreak == "explode" or hit.onBreak == "gas" then
        hit.burning = true
        if (hit.hp or 0) > 0 then Objects.damage(world, hit, 45 * dt, nil, hx, hy) end
      end
    end
    if hit and love.math.random() < dt * 40 then
      fx.spray(hx, hy, a + math.pi, 1.6, { 1, 0.55, 0.12 }, 2, 200, 3.5, -0.2)
    end
    local ex, ey = nx + dx * reach, ny + dy * reach
    for _, p in ipairs(world.players) do
      if not p.dead and segDist(p.x, p.y, nx, ny, ex, ey) < p.r + 12 then
        local before = o.cd and o.cd[p]
        Objects.hazardHit(world, o, p, o.damage, (p.x - o.x) / 30 - dy * 0.1, dy < 0 and -1 or dy, "fire", 0.5)
        if o.cd[p] ~= before and not p:isBlocking() then p:poisonFor(16, 2) end
      end
    end
  end,
}

-- Acid pool: damage over time and a hop up out of it.
-- Liquid: a coloured area with waves. Its properties are toggles.
T.liquid = {
  init = function(o)
    local r, g, b = Objects.colorOf(o.color)
    if not o.rgb then o.rgb = { r or 0.23, g or 0.55, b or 0.88 } end
  end,
  update = function(o, world, dt)
    o.a = (o.a + dt) % 100
    local c = o.rgb
    for _, p in ipairs(world.players) do
      if not p.dead and overlapsPlayer(o, p) then
        local fresh = not (o.cd and (o.cd[p] or -1) > world.time)
        if (o.damage or 0) > 0 then
          if fresh then
            sfx.play("acid", p.x)
            fx.spray(p.x, o.y, -math.pi / 2, 1, c, 6, 220, 3, 1)
          end
          Objects.hazardHit(world, o, p, o.damage, 0, -1.6, "acid", 0.5)
          if p.vy > -900 then p.vy = -900 end
        elseif fresh then
          o.cd = o.cd or {}
          o.cd[p] = world.time + 0.5
          fx.spray(p.x, o.y, -math.pi / 2, 0.8, c, 4, 140, 3, 1)
        end
        if fresh and not p:isBlocking() then
          if o.poison then p:poisonFor(8, 1) end
          if o.burn then p:poisonFor(16, 2) end
          if o.frost then p.slowTimer = math.max(p.slowTimer, 1) end
        end
      end
    end
  end,
  bullet = function(o, b)
    if b.vy > 0 and b.y - o.y < 14 then
      b.vy = -math.abs(b.vy)
      fx.spray(b.x, o.y, -math.pi / 2, 1, o.rgb, 3, 180, 2.5, 1)
    end
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
  return Physics.ray(world, x0, y0, x1, y1) == nil
end

-- Conveyor: solid; moves whatever stands on it.

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
        p.fallJump = true
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
}

-- Crumbling platform: breaks shortly after someone stands on it, then comes back.

-- Rotating blade arm: `count` saws (1 or 2) on a bar spinning around (x, y).
-- Arm: a beam on a motor. It does nothing by itself; attach objects to it.
T.arm = {
}

-- Rail: a track. Attach objects to it and its carriage drives them along the path.
T.rail = {
}

-- Moving platform: solid, follows its path, carries riders.

---------------------------------------------------------------- breakables
local function dropPickup(world, o)
  if love.math.random() < (o.drop or 0) then
    local kind = love.math.random() < 0.5 and 1 or 2 -- 1 health, 2 ammo
    table.insert(world.effects, { type = "pickup", kind = kind, x = o.x + o.w / 2, y = o.y + o.h / 2, life = 8, max = 8, vy = -250 })
  end
end



-- owner: when a player's card made the blast, it only hurts who that player can hurt.
local function explodeAt(world, x, y, radius, damage, source, color, owner)
  fx.explosion(x, y, radius, color)
  fx.addShake(owner and 5 or 9)
  sfx.play(radius > 100 and "explosion" or "explosionSmall", x)
  for _, p in ipairs(world.players) do
    if not p.dead and (not owner or world:canHurt(owner, p)) then
      local dx, dy = p.x - x, p.y - y
      local d = math.sqrt(dx * dx + dy * dy)
      if d < radius + p.r and Physics.canReach(world, x, y, p.x, p.y) then p:hit(damage * (1 - 0.4 * d / (radius + p.r)), dx, dy - 40, 700, source, "explosion") end
    end
  end
  Objects.explosion(world, x, y, radius, damage, source)
end
Objects.explodeAt = explodeAt




-- A bridge plank (or any hanging platform): solid, held by a rope.

local BREAK_COLOR = { crate = { 0.62, 0.45, 0.26 }, wood = { 0.55, 0.4, 0.24 }, brick = { 0.42, 0.38, 0.36 },
  stone = { 0.45, 0.43, 0.5 }, metal = { 0.5, 0.52, 0.6 }, barrel = { 0.6, 0.15, 0.12 }, gas = { 0.4, 0.6, 0.3 } }

T.block = {
  solid = true,
  init = function(o)
    if (o.hp or 0) > 0 then o.maxHp = o.hp end
    if o.crumble then o.timer, o.state = 0, "solid" end
  end,
  update = function(o, world, dt)
    if o.conveyor then
      o.a = (o.a + (o.speed or 0) * dt) % 20
      for _, p in ipairs(world.players) do
        if not p.dead and p.groundRect == o then p.beltVx = o.speed end
      end
    end
    if o.crumble then
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
        if o.timer >= (o.delay or 0.5) then
          o.state, o.timer = "gone", 0
          o.solid = false
          fx.debris(o.x + o.w / 2, o.y + o.h / 2, { 0.55, 0.5, 0.45 }, 6, 10)
          sfx.play("crateBreak", o.x + o.w / 2, 0.5)
        end
      elseif o.state == "gone" then
        o.timer = o.timer + dt
        if o.timer >= (o.back or 4) then
          local blocked = false
          for _, p in ipairs(world.players) do
            if not p.dead and overlapsPlayer(o, p) then blocked = true end
          end
          if not blocked then o.state, o.solid = "solid", true end
        end
      end
      o.s = o.state == "solid" and 0 or o.state == "shaking" and 1 or 2
    end
  end,
  broken = function(o, world, source)
    local cx, cy = o.x + o.w / 2, o.y + o.h / 2
    if o.material == "glass" then
      for _ = 1, 3 do
        fx.spray(cx, o.y + love.math.random() * o.h, love.math.random() * math.pi * 2, 6.3, { 0.75, 0.92, 1 }, 6, 260, 2.5, 1)
      end
      sfx.play("glassBreak", o.x)
    else
      fx.debris(cx, cy, BREAK_COLOR[o.material] or BREAK_COLOR.stone, 10, 12)
      sfx.play("crateBreak", cx, 1, o.material == "brick" and 0.7 or 1)
      if o.material == "brick" or o.material == "stone" then fx.addShake(4) end
    end
    if o.onBreak == "explode" then
      -- A short delay makes chain reactions ripple instead of all popping at once.
      table.insert(world.pendingBlasts, { t = 0.08, x = cx, y = cy, radius = o.radius or 110, damage = o.damage or 55, source = source })
    elseif o.onBreak == "gas" then
      sfx.play("gas", o.x)
      table.insert(world.effects, { type = "cloud", x = cx, y = cy, radius = o.radius or 110, life = 4, max = 4, source = source })
    elseif o.onBreak == "pickup" then
      dropPickup(world, o)
    end
  end,
}

-- Weight / chandelier: hangs from a rope, crushes whoever it falls on.
T.weight = {
}

-- Rope: anchor (x, y), holds object `target` (map object index). The swinging is a Box2D joint.
-- Rope: a chain of Box2D segments between (x, y) and (x2, y2). Each segment has its own health;
-- one end or both can be tied to objects (`from`, `target`). See Physics.addRope.
T.rope = {
}

---------------------------------------------------------------- world hooks
-- Explosions damage objects in range and swing hanging ones.
function Objects.explosion(world, x, y, radius, damage, source)
  for _, o in ipairs(world.objects or {}) do
    if o.alive and o.type == "rope" then
      Physics.blastRope(world, o, x, y, radius + 30, damage, source)
    elseif o.alive then
      local cx, cy = o.x, o.y
      if o.w then cx, cy = o.x + o.w / 2, o.y + o.h / 2 end
      local d = math.sqrt((cx - x) ^ 2 + (cy - y) ^ 2)
      if d < radius + 30 and Physics.canReach(world, x, y, cx, cy, o) then
        do
          if damageable(o) then Objects.damage(world, o, damage, source, cx, cy) end
          local power = 1100 * (1 - 0.5 * d / (radius + 30))
          d = math.max(1, d)
          -- Off centre, so the blast also sets it spinning.
          Objects.push(o, (cx - x) / d * power, (cy - y) / d * power - 150, x + (cx - x) * 0.6, y + (cy - y) * 0.6, source)
        end
      end
    end
  end
end

-- Does a bullet at (x, y) touch the bolt of a non-solid anchored object?
function Objects.anchorHit(o, x, y, r)
  if o.w then return Map.overlaps(x - r, y - r, r * 2, r * 2, o) end
  local reach = (o.r or 14) + r
  return (x - o.x) ^ 2 + (y - o.y) ^ 2 < reach * reach
end

-- A bullet step at (x, y) radius r: cut ropes / damage non-solid targets. Returns true to stop the bullet.
function Objects.bulletTouch(world, b)
  for _, o in ipairs(world.objects or {}) do
    local t = T[o.type]
    if o.alive and t and t.hitTest and not (b.hitObjects and b.hitObjects[o]) and t.hitTest(o, b.x, b.y, b.r) then
      Objects.damage(world, o, b:currentDamage(), b.owner, b.x, b.y)
      return true
    elseif o.alive and o.anchored and (o.anchorHp or 0) > 0 and not o.solid and not (b.hitObjects and b.hitObjects[o])
        and Objects.anchorHit(o, b.x, b.y, b.r) then
      Objects.damage(world, o, b:currentDamage(), b.owner, b.x, b.y)
      return true
    end
  end
  -- Bounce pads speed bullets up; hanging things get swung.
  for _, o in ipairs(world.objects or {}) do
    if o.alive and o.type == "pad" and Map.overlaps(b.x - b.r, b.y - b.r, b.r * 2, b.r * 2, o) then T.pad.bullet(o, b) end
    if o.alive and o.type == "liquid" and o.bounce and Map.overlaps(b.x - b.r, b.y - b.r, b.r * 2, b.r * 2, o) then T.liquid.bullet(o, b) end
  end
  return false
end

-- A bullet bounced off (or stopped at) a solid object.
function Objects.bulletHitSolid(world, o, b)
  if not o.alive then return end
  if damageable(o) then Objects.damage(world, o, b:currentDamage(), b.owner, b.x, b.y) end
  Objects.push(o, b.vx * 0.25, b.vy * 0.25, b.x, b.y, b.owner)
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
        Physics.blastRope(world, o, p.x + p.aimX * (p.r + reach * 0.6), p.y + p.aimY * (p.r + reach * 0.6), reach * 0.6,
          heavy and 40 * (1 + power) or 15, p)
      else
        local size = o.w and math.max(o.w, o.h) / 2 or (o.r or 16)
        local dx, dy = cx - p.x, cy - p.y
        local d = math.sqrt(dx * dx + dy * dy)
        local diff = math.abs((math.atan2(dy, dx) - aim + math.pi) % (math.pi * 2) - math.pi)
        hit = d < p.r + reach + size and diff < 1.4
      end
      if hit then
        if p.lungeHit then p.lungeHit[o] = true end
        do
          if damageable(o) then Objects.damage(world, o, heavy and 40 * (1 + power) or 15, p, cx, cy) end
          local kick = heavy and 1100 or 500
          Objects.push(o, p.aimX * kick, p.aimY * kick, p.x + p.aimX * (p.r + reach), p.y + p.aimY * (p.r + reach), p)
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
      explodeAt(world, e.x, e.y, e.radius, e.damage, e.source, { 1, 0.55, 0.15 }, e.owner)
    end
  end
  -- Pickups and gas clouds.
  for i = #world.effects, 1, -1 do
    local e = world.effects[i]
    e.life = e.life - dt
    if e.follow then e.x, e.y = e.follow.x, e.follow.y end
    if e.follow and e.follow.dead then e.life = 0 end
    if e.type == "bomb" then
      if e.life <= 0 then explodeAt(world, e.x, e.y, e.radius, e.damage, e.owner, e.owner and e.owner.color, e.owner) end
    elseif e.type == "star" then
      if e.life <= 0 then
        fx.ring(e.x, e.y, e.radius, { 1, 0.9, 0.6 })
        fx.burst(e.x, e.y, { 1, 0.9, 0.6 }, 24, 420, 4)
        fx.addShake(8)
        sfx.play("explosion", e.x, 0.7, 1.5)
        for _, p in ipairs(world.players) do
          if not p.dead and p ~= e.owner and world:canHurt(e.owner, p) and circleHitsPlayer(e.x, e.y, e.radius, p) then
            p:stun(e.stun or 1)
          end
        end
      end
    elseif e.type == "field" then
      for _, p in ipairs(world.players) do
        if not p.dead and p ~= e.owner and world:canHurt(e.owner, p) and circleHitsPlayer(e.x, e.y, e.radius, p)
            and p.invuln <= 0 and not p:isBlocking() then
          p.slowTimer = math.max(p.slowTimer or 0, 0.3)
          p.hp = p.hp - e.dps * dt
          p.lastAttacker, p.lastHitKind = e.owner, "field"
          if p.hp <= 0 then p:die() end
        end
      end
    elseif e.type == "pickup" then
      e.vy = math.min((e.vy or 0) + 900 * dt, 500)
      local ny = e.y + e.vy * dt
      if Physics.hit(world, e.x - 10, ny - 10, 20, 20) then e.vy = 0 else e.y = ny end
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
        if not p.dead and (not e.owner or world:canHurt(e.owner, p)) and circleHitsPlayer(e.x, e.y, e.radius, p)
            and Physics.canReach(world, e.x, e.y, p.x, p.y) then
          p:hit(e.damage, p.x - e.x, -1, 300, e.owner, "lightning")
        end
      end
    elseif e.type == "cloud" then
      for _, p in ipairs(world.players) do
        if not p.dead and circleHitsPlayer(e.x, e.y, e.radius, p) and (not e.owner or world:canHurt(e.owner, p))
            and Physics.canReach(world, e.x, e.y, p.x, p.y) then
          if e.slow then p.slowTimer = math.max(p.slowTimer or 0, 0.3) end
        end
        if not p.dead and circleHitsPlayer(e.x, e.y, e.radius, p) and (p.poisonTimer or 0) < 0.6
            and (not e.owner or world:canHurt(e.owner, p)) and Physics.canReach(world, e.x, e.y, p.x, p.y) then
          p:poisonFor(8, 1)
          p.lastAttacker = e.source or p.lastAttacker
          p.lastHitKind = "gas"
        end
      end
    end
    if e.life <= 0 or e.y > Map.H + 80 then table.remove(world.effects, i) end
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

-- Drawing lives in gfx/objectview.lua, except this easing of client positions.
-- Clients get positions at snapshot rate; this eases loose objects between them.
function Objects.smooth(list, dt)
  local k = math.min(1, dt * 22)
  for _, o in ipairs(list) do
    -- Purely visual spinning, so it needn't come over the network.
    if o.type == "saw" then o.a = (o.a + dt * 12) % (math.pi * 2)
    elseif o.type == "fan" then o.a = (o.a + dt * 20) % (math.pi * 2)
    elseif o.conveyor then o.a = (o.a + (o.speed or 0) * dt) % 20 end
    if o.tx then
      o.x, o.y = o.x + (o.tx - o.x) * k, o.y + (o.ty - o.y) * k
      local diff = (o.trot - o.rot + math.pi) % (math.pi * 2) - math.pi
      o.rot = o.rot + diff * k
    end
  end
end

return Objects
