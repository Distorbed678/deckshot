-- All movement and collision goes through Box2D (love.physics).
--
-- A sim holds the map's rects, machines, loose objects, players and bullets. The host and local
-- play own the real one (world.physics). An online client builds a small one for predicting its
-- own player, with everything else as fixed-in-place bodies moved from snapshots.
--
-- Game code keeps reading and writing x, y, vx, vy on players and bullets. Before each step a
-- changed velocity becomes an impulse and a changed position moves the body; after the step the
-- fields are read back from the body. Player:runPhysics decides the walking force, the gravity
-- scale and the ground friction, so knockback, cards and launches all work the same way.
--
-- Loose objects keep their usual fields: rect objects keep x, y as the top-left of the unrotated
-- box, round ones x, y as the centre, and `rot` is the angle in radians.
local Map = require "game.map"
local sfx = require("game.events").sfx

local Physics = {}

local GRAVITY = 1800
local METER = 50
Physics.GRAVITY = GRAVITY
Physics.PLAYER_MASS = 2.5 -- a 50x50 crate weighs 0.8

local CAT_WORLD, CAT_SOLID, CAT_LOOSE, CAT_PLAYER, CAT_HITBOX, CAT_BULLET, CAT_ROPE = 1, 2, 3, 4, 5, 6, 7

local OWN_DAMAGE = { saw = true, spikes = true, arm = true, rail = true, flame = true, laser = true } -- these hurt only through their own update

-- Density and bounce come from data/objects.txt, through Objects.
local function defs() return require("game.objects") end

local function densityOf(o)
  local O = defs()
  if o.type == "block" then
    local m = O.MATERIALS[o.material]
    return m and m.density or 1
  end
  local d = O.DEFAULTS[o.type]
  return d and d.density or 1
end

local function bounceOf(o)
  local O = defs()
  local src = o.type == "block" and O.MATERIALS[o.material] or O.DEFAULTS[o.type]
  return src and src.bounce or 0.08
end

local IMPACT_SOUND = 350  -- speed change that makes a thud
local IMPACT_BREAK = 700  -- speed change that starts damaging the object
local HURT_SPEED = 450    -- speed at which a moving object starts hurting players
local HURT_FULL = 1350    -- speed for full damage
local HURT_DAMAGE = 30
local GROUND_NORMAL = 0.55 -- how flat a surface must be to stand on
local WALL_PROBE = 3       -- how far from your side a wall still counts as touching it

-- Arms, rails, attached objects and hinged ones always need a body; others follow the Physics toggle.
function Physics.isLoose(o)
  if o.type == "arm" or o.type == "rail" or o.parent then return true end
  if o.anchored then return o.anchorType == "hinge" end
  return o.physics == true
end

function Physics.massOf(o)
  local area
  if o.w and o.h then area = o.w * o.h else local r = o.r or 18; area = 4 * r * r end
  return area / (METER * METER) * densityOf(o)
end

local function centre(o)
  if o.w then return o.x + o.w / 2, o.y + o.h / 2 end
  return o.x, o.y
end

-- A block can be a ramp: "right" is high on its right side, "left" on its left.
function Physics.slopeOf(o)
  return o.type == "block" and (o.slope == "left" or o.slope == "right") and o.slope or nil
end

-- The collision shape of a box-like object, centred on its body.
local function boxShape(o)
  local slope = Physics.slopeOf(o)
  local hw, hh = o.w / 2, o.h / 2
  if slope == "right" then return love.physics.newPolygonShape(-hw, hh, hw, hh, hw, -hh) end
  if slope == "left" then return love.physics.newPolygonShape(-hw, hh, hw, hh, -hw, -hh) end
  return love.physics.newRectangleShape(o.w, o.h)
end

local function setCentre(o, x, y)
  if o.w then o.x, o.y = x - o.w / 2, y - o.h / 2 else o.x, o.y = x, y end
end

-- Fixtures of players and bullets carry a small tag; rects and objects carry themselves.
local function isSolidData(ud)
  return ud and not ud.kind and not ud.oneway and (ud.solid or not ud.type)
end

---------------------------------------------------------------- contacts
local function bothWays(a, b)
  return a:getUserData(), b:getUserData()
end

-- Direction pointing out of the other fixture towards `mine`.
local function normalTowards(contact, a, mine)
  local nx, ny = contact:getNormal()
  if a == mine then return -nx, -ny end
  return nx, ny
end

local function onePlayer(ua, ub, a, b)
  if ua and ua.kind == "player" then return ua.p, a, b, ub end
  if ub and ub.kind == "player" then return ub.p, b, a, ua end
end

local function preSolve(a, b, contact)
  local ua, ub = bothWays(a, b)
  -- A bullet reaching a player: the bullet code decides what happens, nothing bounces.
  if (ua and ua.kind == "hitbox") or (ub and ub.kind == "hitbox") then
    contact:setEnabled(false)
    local hit = (ua and ua.kind == "hitbox") and ua or ub
    local shot = hit == ua and ub or ua
    if shot and shot.kind == "bullet" then
      local ph = shot.ph
      ph.events[#ph.events + 1] = { shot.b, hit.p }
    end
    return
  end
  if (ua and ua.kind == "bullet") or (ub and ub.kind == "bullet") then
    local shot, other = ua, ub
    if not (ua and ua.kind == "bullet") then shot, other = ub, ua end
    if shot.b.ghost or (other and other.oneway) then contact:setEnabled(false) end
    return
  end
  local p, mine, other, otherData = onePlayer(ua, ub, a, b)
  if p then
    if otherData and otherData.kind == "player" and (otherData.p.disconnected or p.disconnected) then
      contact:setEnabled(false)
      return
    end
    if otherData and otherData.oneway then
      -- Judged by where your feet are: rising through it starts with them below its top.
      local _, vy = mine:getBody():getLinearVelocity()
      local bottom = p.y + p.r + p.leg
      if p.dropTimer > 0 or bottom > otherData.y + 6 + math.max(0, vy) / 45 then
        contact:setEnabled(false)
        return
      end
    end
    local nx, ny = normalTowards(contact, a, mine)
    if ny < -GROUND_NORMAL and not (otherData and otherData.conveyor) then
      contact:setFriction(p.groundMu or 0)
    else
      contact:setFriction(0) -- walls and ceilings never grip
    end
    return
  end
  -- Loose objects and one-way platforms: only from above.
  local r, body = nil, nil
  if ua and ua.oneway then r, body = ua, b:getBody() elseif ub and ub.oneway then r, body = ub, a:getBody() end
  if r then
    local _, vy = body:getLinearVelocity()
    local _, cy = body:getPosition()
    if vy < -1 or cy > r.y then contact:setEnabled(false) end
  end
end

-- A bullet touching something solid: Box2D has already worked out the bounce.
local function beginContact(a, b, contact)
  local ua, ub = bothWays(a, b)
  local shot, other, mine
  if ua and ua.kind == "bullet" then shot, other, mine = ua, ub, a elseif ub and ub.kind == "bullet" then shot, other, mine = ub, ua, b end
  if not shot or not other or other.kind then return end
  if other.oneway then return end
  if shot.b.ghost then
    shot.b.phased = true
    shot.b.lastSolid = other
    return
  end
  local nx, ny = normalTowards(contact, a, mine)
  local ph = shot.ph
  ph.events[#ph.events + 1] = { shot.b, other, nx, ny }
end

---------------------------------------------------------------- building
local function newSim(map)
  local P = love.physics
  P.setMeter(METER)
  local b2 = P.newWorld(0, GRAVITY, true)
  b2:setCallbacks(beginContact, nil, preSolve, nil)
  local ph = { b2 = b2, ground = P.newBody(b2, 0, 0, "static"), loose = {}, fixed = {}, fields = {}, players = {},
    bullets = {}, events = {}, probes = {}, ropes = {}, rails = {} }
  for _, r in ipairs(map.rects) do
    local f = P.newFixture(ph.ground, P.newRectangleShape(r.x + r.w / 2, r.y + r.h / 2, r.w, r.h))
    f:setFriction(0.7)
    f:setCategory(CAT_WORLD)
    f:setUserData(r)
  end
  return ph
end

local ALL_MASKS = { CAT_WORLD, CAT_SOLID, CAT_LOOSE, CAT_PLAYER, CAT_HITBOX, CAT_BULLET, CAT_ROPE }

local function looseFilter(fixture, o, attached)
  if o.solid then
    fixture:setCategory(CAT_SOLID)
  else
    fixture:setCategory(CAT_LOOSE)
    if attached then
      fixture:setMask(unpack(ALL_MASKS)) -- carried hazards don't catch on the scenery
    else
      fixture:setMask(CAT_PLAYER, CAT_HITBOX, CAT_BULLET, CAT_ROPE)
    end
  end
end

local function addLoose(ph, o)
  local P = love.physics
  local cx, cy = centre(o)
  local body = P.newBody(ph.b2, cx, cy, "dynamic")
  body:setAngle(o.rot or 0)
  local shape
  if o.w and o.h then
    shape = boxShape(o)
  elseif o.type == "saw" then
    shape = P.newCircleShape(o.r or 18)
  else
    local r = o.r or 18
    shape = P.newRectangleShape(r * 2, r * 2)
  end
  local fixture = P.newFixture(body, shape, densityOf(o))
  fixture:setFriction(0.55)
  fixture:setRestitution(bounceOf(o))
  fixture:setUserData(o)
  looseFilter(fixture, o, o.parent ~= nil)
  body:setAngularDamping(0.8)
  o.body, o.fixture = body, fixture
  o.rot = o.rot or 0
  o.loose = true
  o.mass = Physics.massOf(o)
  ph.loose[#ph.loose + 1] = o
end

local function addArm(ph, o)
  local P = love.physics
  local body = P.newBody(ph.b2, o.x, o.y, "dynamic")
  body:setAngle(o.phase or 0)
  local fixture = P.newFixture(body, P.newRectangleShape(o.length * 2, 10), 0.3)
  fixture:setCategory(CAT_LOOSE)
  fixture:setMask(unpack(ALL_MASKS))
  fixture:setUserData(o)
  o.body, o.fixture = body, fixture
  o.rot, o.loose, o.mass = o.phase or 0, true, body:getMass()
  o.joint = P.newRevoluteJoint(ph.ground, body, o.x, o.y, false)
  o.joint:setMotorEnabled(true)
  o.joint:setMotorSpeed(o.spin or 0)
  o.joint:setMaxMotorTorque(1) -- worked out once its attachments are known
  ph.loose[#ph.loose + 1] = o
end

local function addRail(ph, o)
  local P = love.physics
  local path = o.path
  if not path or #path < 2 then path = { { o.x, o.y }, { o.x, o.y } } ; o.path = path end
  o.x, o.y = path[1][1], path[1][2]
  local body = P.newBody(ph.b2, o.x, o.y, "dynamic")
  body:setFixedRotation(true)
  body:setGravityScale(0)
  local fixture = P.newFixture(body, P.newCircleShape(8), 1)
  fixture:setCategory(CAT_LOOSE)
  fixture:setMask(unpack(ALL_MASKS))
  fixture:setUserData(o)
  o.body, o.fixture = body, fixture
  o.rot, o.loose, o.mass = 0, true, body:getMass()
  o.joint = P.newMouseJoint(body, o.x, o.y)
  o.joint:setMaxForce(1)
  o.joint:setFrequency(12)
  o.joint:setDampingRatio(1)
  o.seg, o.dirn, o.tx, o.ty, o.stall = 1, 1, o.x, o.y, 0
  ph.rails[#ph.rails + 1] = o
  ph.loose[#ph.loose + 1] = o
end

-- Hold a body at one point of the world, free to turn around it.
local function addHinge(ph, o)
  local cx, cy = centre(o)
  local px, py = cx, cy
  if o.w then
    local where = o.hinge or "center"
    if where == "top" then py = o.y elseif where == "bottom" then py = o.y + o.h
    elseif where == "left" then px = o.x elseif where == "right" then px = o.x + o.w end
  end
  o.joint = love.physics.newRevoluteJoint(ph.ground, o.body, px, py, false)
end

local function addAttachment(ph, o, parent)
  local P = love.physics
  if not (parent and parent.body and o.body) then return end
  local cx, cy = centre(o)
  if o.attach == "hinge" then
    o.joint = P.newRevoluteJoint(parent.body, o.body, cx, cy, false)
  else
    o.joint = P.newWeldJoint(parent.body, o.body, cx, cy, false)
  end
  parent.load = (parent.load or 0) + (o.mass or 1)
  local dx, dy = cx - parent.x, cy - parent.y
  parent.loadTorque = (parent.loadTorque or 0) + (o.mass or 1) * math.sqrt(dx * dx + dy * dy)
end

-- Machines and anchored solids: bodies that go wherever their own update put them.
local function addFixed(ph, o)
  local P = love.physics
  local cx, cy = centre(o)
  local body = P.newBody(ph.b2, cx, cy, "kinematic")
  body:setAngle(o.rot or 0)
  local fixture = P.newFixture(body, boxShape(o))
  fixture:setFriction(0.7)
  fixture:setUserData(o)
  fixture:setCategory(CAT_WORLD)
  o.body, o.fixture = body, fixture
  ph.fixed[#ph.fixed + 1] = o
end

local SEGMENT_LENGTH = 26
local ROPE_MAX_SEGMENTS = 40

-- A chain of small bodies joined end to end, with a rope joint between its ends so that heavy
-- things can't stretch it. Ends tie to their object's body, or to the world.
local function addRope(ph, world, rope)
  local P = love.physics
  local x0, y0, x1, y1 = rope.x, rope.y, rope.x2, rope.y2
  local dist = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
  local n = math.max(2, math.min(ROPE_MAX_SEGMENTS, math.ceil(rope.length / SEGMENT_LENGTH)))
  local len = rope.length / n
  local angle = math.atan2(y1 - y0, x1 - x0) - math.pi / 2
  local ux, uy = dist > 0 and (x1 - x0) / dist or 0, dist > 0 and (y1 - y0) / dist or 1
  local step = dist / n
  rope.segs = {}
  local prev
  for i = 1, n do
    local cx, cy = x0 + ux * step * (i - 0.5), y0 + uy * step * (i - 0.5)
    local body = P.newBody(ph.b2, cx, cy, "dynamic")
    body:setAngle(angle)
    body:setAngularDamping(1.5)
    body:setLinearDamping(0.15)
    local f = P.newFixture(body, P.newRectangleShape(6, len), 0.5)
    f:setFriction(0.5)
    local seg = { body = body, fixture = f, hp = rope.segHp or 60, alive = true, len = len, index = i, rope = rope }
    f:setCategory(CAT_ROPE)
    -- The ends sit inside what they're tied to, so only the middle touches the scenery.
    local nearEnd = i <= 2 or i > n - 2
    if nearEnd or Physics.hit(world, cx - 3, cy - len / 2, 6, len) then
      f:setMask(unpack(ALL_MASKS))
    else
      f:setMask(CAT_PLAYER, CAT_HITBOX, CAT_BULLET, CAT_ROPE, CAT_LOOSE)
    end
    f:setUserData({ kind = "rope", seg = seg })
    rope.segs[i] = seg
    local topX, topY = x0 + ux * step * (i - 1), y0 + uy * step * (i - 1)
    if prev then
      seg.joint = P.newRevoluteJoint(prev.body, body, topX, topY, false)
    else
      local from = rope.heldFrom and rope.heldFrom.body or ph.ground
      seg.joint = P.newRevoluteJoint(from, body, topX, topY, false)
    end
    prev = seg
  end
  local h = rope.held
  if h and h.alive and h.body then
    rope.endJoint = P.newRevoluteJoint(h.body, prev.body, x1, y1, false)
    if rope.level then
      h.body:setFixedRotation(true)
      h.body:setLinearDamping(0.6)
    end
  end
  if not (h and h.alive and h.body) and rope.pin2 then
    rope.endJoint = P.newRevoluteJoint(ph.ground, prev.body, x1, y1, false)
  end
  local a = rope.heldFrom and rope.heldFrom.body or ph.ground
  local b = h and h.alive and h.body or prev.body
  rope.joint = P.newRopeJoint(a, b, x0, y0, x1, y1, rope.length, false)
  ph.ropes[#ph.ropes + 1] = rope
end

local function ropePoints(rope)
  local pts = rope.pts or {}
  rope.pts = pts
  local n, prevAlive = 0, false
  local count = #rope.segs
  for i = 1, count do
    local seg = rope.segs[i]
    if seg.alive then
      if not prevAlive then
        n = n + 1
        local x, y = seg.body:getWorldPoint(0, -seg.len / 2)
        pts[n] = { x, y, i > 1 or nil }
      end
      n = n + 1
      local x, y = seg.body:getWorldPoint(0, seg.len / 2)
      pts[n] = { x, y }
    end
    prevAlive = seg.alive
  end
  for i = #pts, n + 1, -1 do pts[i] = nil end
end

-- A segment took damage. When one dies the rope parts there and what it held is on its own.
function Physics.hurtSegment(world, seg, amount, source)
  if not seg.alive then return end
  if source and source.stats and source.stats.objectDamage then amount = amount * source.stats.objectDamage end
  seg.hp = seg.hp - amount
  if seg.hp > 0 then return end
  seg.alive = false
  local rope = seg.rope
  local x, y = seg.body:getPosition()
  seg.body:destroy()
  seg.body, seg.fixture = nil, nil
  sfx.play("ropeSnap", x)
  require("game.events").fx.spray(x, y, math.pi / 2, 1, { 0.75, 0.6, 0.4 }, 6, 150, 2, 1)
  if rope.joint then
    if not rope.joint:isDestroyed() then rope.joint:destroy() end
    rope.joint = nil
  end
  local h = rope.held
  if h and h.alive and h.body and rope.level then
    h.body:setFixedRotation(false)
    h.body:setLinearDamping(0)
    h.body:setAngularVelocity((love.math.random() - 0.5) * 3)
    h.body:setAwake(true)
  end
  if h then
    h.rope = nil
    h.breaker = source or h.breaker
  end
end

-- Damage rope segments within a circle (blasts and melee).
function Physics.blastRope(world, rope, x, y, radius, damage, source)
  if not rope.segs then return end
  for _, seg in ipairs(rope.segs) do
    if seg.alive then
      local sx, sy = seg.body:getPosition()
      if (sx - x) ^ 2 + (sy - y) ^ 2 < radius * radius then Physics.hurtSegment(world, seg, damage, source) end
    end
  end
end

-- A bullet's path this step: hurt rope segments on it, once each; the bullet carries on.
function Physics.ropeHits(world, b, x0, y0, x1, y1)
  x1, y1 = x1 or b.x, y1 or b.y
  local ph = world.physics
  if not ph or #ph.ropes == 0 or (x0 == x1 and y0 == y1) then return end
  local hits = {}
  ph.b2:rayCast(x0, y0, x1, y1, function(f)
    local ud = f:getUserData()
    if ud and ud.kind == "rope" then hits[#hits + 1] = ud.seg end
    return 1
  end)
  for _, seg in ipairs(hits) do
    b.hitObjects = b.hitObjects or {}
    if seg.alive and not b.hitObjects[seg] then
      b.hitObjects[seg] = true
      local speed = 0.1
      seg.body:applyLinearImpulse(b.vx * speed * seg.body:getMass(), b.vy * speed * seg.body:getMass())
      Physics.hurtSegment(world, seg, b:currentDamage(), b.owner)
    end
  end
end

-- Flames burn rope segments along their length.
function Physics.burnRopes(world, x0, y0, x1, y1, amount)
  local ph = world.physics
  if not ph or #ph.ropes == 0 or (x0 == x1 and y0 == y1) then return end
  local hits = {}
  ph.b2:rayCast(x0, y0, x1, y1, function(f)
    local ud = f:getUserData()
    if ud and ud.kind == "rope" then hits[#hits + 1] = ud.seg end
    return 1
  end)
  for _, seg in ipairs(hits) do Physics.hurtSegment(world, seg, amount) end
end

-- Build the simulation for a freshly built world.objects.
function Physics.setup(world)
  if world.physics then
    local old = world.physics
    world.physics = nil
    old.b2:destroy()
  end
  local ph = newSim(world.map)
  world.physics = ph
  for _, o in ipairs(world.objects) do
    if o.alive then
      if o.type == "arm" then
        addArm(ph, o)
      elseif o.type == "rail" then
        addRail(ph, o)
      elseif o.loose then
        addLoose(ph, o)
        if o.anchored and o.anchorType == "hinge" then addHinge(ph, o) end
      elseif o.solid and o.w and o.h then
        addFixed(ph, o)
      end
      if o.type == "fan" or o.conveyor or o.type == "pad" or (o.type == "liquid" and o.buoyant) then ph.fields[#ph.fields + 1] = o end
    end
  end
  for _, o in ipairs(world.objects) do
    if o.alive and o.parentObj then addAttachment(ph, o, o.parentObj) end
  end
  -- Motors strong enough for what they carry, but no stronger: a big enough jam stops them.
  for _, o in ipairs(world.objects) do
    if o.type == "arm" and o.joint then
      o.joint:setMaxMotorTorque(math.max(60000, (o.loadTorque or 0) * GRAVITY * 6) * (o.force or 1))
    elseif o.type == "rail" and o.joint then
      o.joint:setMaxForce(((o.load or 0) + 2) * GRAVITY * 6 * (o.force or 1))
    end
  end
  for _, o in ipairs(world.objects) do
    if o.type == "rope" and o.alive then addRope(ph, world, o) end
  end
end

-- The prediction sim on an online client: solid objects are placed from snapshots.
function Physics.newClient(map, objects)
  local ph = newSim(map)
  ph.client = true
  ph.objects = objects
  ph.actors = {}
  for _, o in ipairs(objects) do
    if o.solid and o.w and o.h then addFixed(ph, o) end
  end
  return ph
end

---------------------------------------------------------------- players
local function playerShape(p)
  local hw, hh = p.r, p.r + p.leg / 2
  -- Cut corners slide over seams between blocks and small ledges.
  local c = math.min(6, p.r * 0.4)
  return love.physics.newPolygonShape(-hw + c, -hh, hw - c, -hh, hw, -hh + c, hw, hh - c,
    hw - c, hh, -hw + c, hh, -hw, hh - c, -hw, -hh + c)
end

local function setHitbox(ph, rec, p)
  local blocking = p.isBlocking and p:isBlocking() or false
  if rec.hitbox and rec.blocking == blocking then return end
  if rec.hitbox then rec.hitbox:destroy() end
  local P = love.physics
  -- The round body; bullets only ever touch this, and blocking widens it.
  local f = P.newFixture(rec.body, P.newCircleShape(0, -p.leg / 2, p.r + (blocking and 14 or 0)), 0)
  f:setCategory(CAT_HITBOX)
  f:setMask(CAT_WORLD, CAT_SOLID, CAT_LOOSE, CAT_PLAYER, CAT_HITBOX)
  f:setUserData({ kind = "hitbox", p = p })
  rec.hitbox, rec.blocking = f, blocking
  if rec.body:getType() == "dynamic" then rec.body:setMass(Physics.PLAYER_MASS) end
end

local function newPlayerBody(ph, p, kind)
  local P = love.physics
  local body = P.newBody(ph.b2, p.x, p.y + p.leg / 2, kind)
  body:setFixedRotation(true)
  local f = P.newFixture(body, playerShape(p), 1)
  f:setCategory(CAT_PLAYER)
  f:setFriction(0)
  f:setUserData({ kind = "player", p = p })
  local rec = { body = body, fixture = f, r = p.r, leg = p.leg }
  setHitbox(ph, rec, p)
  if kind == "dynamic" then
    body:setBullet(true) -- dashes must not pass through thin things
    body:setMass(Physics.PLAYER_MASS)
    body:setSleepingAllowed(false)
  end
  ph.players[p] = rec
  return rec
end

local function recordOf(ph, p, kind)
  local rec = ph.players[p]
  if rec and (rec.r ~= p.r or rec.leg ~= p.leg) then
    rec.body:destroy()
    ph.players[p] = nil
    rec = nil
  end
  return rec or newPlayerBody(ph, p, kind)
end

-- Other players on a client's prediction sim: solid, moved by snapshots.
function Physics.syncOthers(ph, proxies, me)
  for _, o in ipairs(proxies) do
    if o.slot ~= me and o.leg and o.r then
      local rec = recordOf(ph, o, "kinematic")
      rec.body:setActive(not o.dead and not o.disconnected)
      rec.body:setPosition(o.x, o.y + o.leg / 2)
    end
  end
end

-- Hand the gameplay's decisions for this frame to the body.
function Physics.pushPlayer(p)
  local ph = p.game and p.game.physics
  if not ph then return end
  local rec = recordOf(ph, p, "dynamic")
  local body = rec.body
  setHitbox(ph, rec, p)
  local tx, ty = p.x, p.y + p.leg / 2
  local bx, by = body:getPosition()
  if math.abs(tx - bx) > 0.001 or math.abs(ty - by) > 0.001 then body:setPosition(tx, ty) end
  local vx, vy = body:getLinearVelocity()
  local dvx, dvy = p.vx - vx, p.vy - vy
  if math.abs(dvx) > 0.001 or math.abs(dvy) > 0.001 then
    body:applyLinearImpulse(dvx * Physics.PLAYER_MASS, dvy * Physics.PLAYER_MASS)
  end
  body:setGravityScale(p.gravScale or 1)
  if (p.forceX and p.forceX ~= 0) or (p.forceY and p.forceY ~= 0) then body:applyForce(p.forceX or 0, p.forceY or 0) end
end

-- Read the result back and see what the player is touching.
function Physics.pullPlayer(p)
  local ph = p.game and p.game.physics
  local rec = ph and ph.players[p]
  if not rec then return end
  local body = rec.body
  local x, y = body:getPosition()
  p.x, p.y = x, y - p.leg / 2
  p.vx, p.vy = body:getLinearVelocity()
  p.onGround, p.groundOneway, p.groundRect, p.pushing = false, false, nil, nil
  p.groundNx, p.groundNy = 0, -1
  local tag = rec.fixture:getUserData()
  for _, c in ipairs(body:getContacts()) do
    if c:isTouching() and c:isEnabled() then
      local a, b = c:getFixtures()
      local mine, other
      if a:getUserData() == tag then mine, other = a, b elseif b:getUserData() == tag then mine, other = b, a end
      local ud = other and other:getUserData()
      if mine and not (ud and ud.kind == "bullet") then
        local nx, ny = c:getNormal()
        if mine == a then nx, ny = -nx, -ny end
        -- Box2D's contact list is from the start of the step, so a jump is still "touching" here.
        -- Judged along the surface's normal, so walking up a ramp still counts as standing on it.
        local surfaceVx, surfaceVy = other:getBody():getLinearVelocity()
        local away = ny > -0.999 and ((p.vx - surfaceVx) * nx + (p.vy - surfaceVy) * ny) or (surfaceVy - p.vy)
        if ny < -GROUND_NORMAL and away <= 40 then
          if not p.onGround or ny < p.groundNy then p.groundNx, p.groundNy = nx, ny end
          p.onGround = true
          p.groundRect = ud and ud.kind == "player" and ud.p or ud
          p.groundOneway = (ud and ud.oneway) and true or false
        elseif math.abs(nx) > 0.5 and ud and ud.loose then
          p.pushing = ud
        end
      end
    end
  end
  -- Walls: a short ray out of each side.
  p.wallDir = 0
  if not p.onGround then
    local reach = p.r + WALL_PROBE
    -- Only upright faces are walls: a ramp isn't something to slide down or kick off.
    local hit, _, _, nx = Physics.ray(p.game, p.x, p.y, p.x - reach, p.y)
    if hit and math.abs(nx) > 0.8 then
      p.wallDir = -1
    else
      hit, _, _, nx = Physics.ray(p.game, p.x, p.y, p.x + reach, p.y)
      if hit and math.abs(nx) > 0.8 then p.wallDir = 1 end
    end
  end
end

---------------------------------------------------------------- queries
local function probeFor(ph, w, h)
  local key = math.floor(w * 4 + 0.5) .. "x" .. math.floor(h * 4 + 0.5)
  local pr = ph.probes[key]
  if not pr then
    local P = love.physics
    local body = P.newBody(ph.b2, 0, 0, "static")
    body:setActive(false)
    pr = { body = body, fixture = P.newFixture(body, P.newRectangleShape(w, h)) }
    pr.fixture:setSensor(true)
    ph.probes[key] = pr
  end
  return pr
end

-- First solid overlapping the box, or nil. `exclude` is an object to ignore.
function Physics.hit(world, x, y, w, h, exclude)
  local ph = world.physics
  if not ph then return nil end
  -- Slightly undersized, so that merely resting against something isn't overlapping it.
  local bw, bh = math.max(0.5, w - 1), math.max(0.5, h - 1)
  local probe = probeFor(ph, bw, bh)
  probe.body:setPosition(x + w / 2, y + h / 2)
  local found
  ph.b2:queryBoundingBox(x, y, x + w, y + h, function(f)
    local ud = f:getUserData()
    if isSolidData(ud) and ud ~= exclude and love.physics.getDistance(probe.fixture, f) <= 0 then
      found = ud
      return false
    end
    return true
  end)
  return found
end

-- Does a (possibly rotated) box touch a player's body? Hazard areas and pads use this.
function Physics.boxHitsPlayer(x, y, w, h, rot, p)
  local ph = p.game and p.game.physics
  local rec = ph and ph.players[p]
  if not rec then return false end
  local probe = probeFor(ph, w, h)
  probe.body:setPosition(x + w / 2, y + h / 2)
  probe.body:setAngle(rot or 0)
  return love.physics.getDistance(probe.fixture, rec.fixture) <= 0
end

-- Nearest solid along a segment: returns it with the hit point and surface normal, or nil.
-- `accept(ud)` may be given to let other fixtures (a laser's targets) count, or to refuse some.
function Physics.ray(world, x0, y0, x1, y1, accept, exclude)
  local ph = world.physics
  if not ph or (x0 == x1 and y0 == y1) then return nil end -- Box2D refuses zero-length rays
  local hit, hx, hy, nx, ny
  ph.b2:rayCast(x0, y0, x1, y1, function(f, x, y, xn, yn, fraction)
    local ud = f:getUserData()
    local counts
    if accept then counts = accept(ud) else counts = isSolidData(ud) end
    if not counts or (exclude and ud == exclude) then return -1 end
    hit, hx, hy, nx, ny = ud, x, y, xn, yn
    return fraction
  end)
  return hit, hx, hy, nx, ny
end

-- Is the straight line between two points free of solid things? Presence effects and blasts
-- only reach what they can see. `exclude` is the object at the far end, which doesn't block itself.
function Physics.canReach(world, x0, y0, x1, y1, exclude)
  if not world or not world.physics then return true end
  return Physics.ray(world, x0, y0, x1, y1, nil, exclude) == nil
end

-- How far a circle reaches in each of n directions, stopped by solid things.
function Physics.fan(world, x, y, radius, n)
  local out = {}
  n = n or 48
  for i = 1, n do
    local a = (i - 1) / n * math.pi * 2
    local _, hx, hy = Physics.ray(world, x, y, x + math.cos(a) * radius, y + math.sin(a) * radius)
    out[i] = hx and math.sqrt((hx - x) ^ 2 + (hy - y) ^ 2) or radius
  end
  return out
end

---------------------------------------------------------------- events
-- A shove: (ix, iy) is the speed in px/s it would give a crate-sized object. Heavier things move
-- less. (x, y) is where it lands, which is what makes things spin.
function Physics.kick(o, ix, iy, x, y, source)
  local body = o.body
  if not body or not o.loose then return end
  if x then
    body:applyLinearImpulse(ix, iy, x, y)
  else
    body:applyLinearImpulse(ix, iy)
  end
  if source and not source.isTurret then o.breaker, o.restTime = source, 0 end
end

-- An anchor gave way: the object joins the simulation where it stands.
function Physics.release(world, o)
  o.anchored = false
  local ph = world.physics
  if not ph then return end
  if o.joint then
    if not o.joint:isDestroyed() then o.joint:destroy() end
    o.joint = nil
  end
  if o.parent then
    o.parent, o.parentObj = nil, nil
    if o.fixture then looseFilter(o.fixture, o, false) end
  end
  if not o.loose or o.fixture and o.body:getType() == "kinematic" then
    if o.body then
      for i, f in ipairs(ph.fixed) do
        if f == o then table.remove(ph.fixed, i) break end
      end
      o.body:destroy()
      o.body, o.fixture = nil, nil
    end
    o.rot = o.rot or 0
    addLoose(ph, o)
  end
end

---------------------------------------------------------------- stepping
local function syncFixed(ph, dt)
  for i = #ph.fixed, 1, -1 do
    local o = ph.fixed[i]
    if ph.client then
      o.body:setActive(o.alive == true and o.solid == true and not (o.crumble and o.s == 2))
      local cx, cy = centre(o)
      o.body:setPosition(cx, cy)
      o.body:setAngle(o.rot or 0)
    elseif not o.alive then
      o.body:destroy()
      o.body, o.fixture = nil, nil
      table.remove(ph.fixed, i)
    else
      o.body:setActive(o.solid == true)
      local tx, ty = centre(o)
      local bx, by = o.body:getPosition()
      o.body:setLinearVelocity((tx - bx) / dt, (ty - by) / dt)
    end
  end
end

local FAN_DIRS = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

-- Conveyors, pads and fans act on loose objects.
local function applyFields(ph, dt)
  for _, m in ipairs(ph.fields) do
    if m.alive then
      for _, o in ipairs(ph.loose) do
        if o.alive and o.body and not o.parent and o.type ~= "arm" and o.type ~= "rail" and not (o.type == "weight" and o.rope) then
          local x0, y0, x1, y1 = o.fixture:getBoundingBox(1)
          if x1 > m.x and x0 < m.x + m.w then
            if m.type == "liquid" then
              local top, bottom = math.max(y0, m.y), math.min(y1, m.y + m.h)
              if bottom > top then
                local frac = (bottom - top) / math.max(1, y1 - y0)
                local mass = o.body:getMass()
                local volume = mass / (o.w and densityOf(o) or 1)
                local vx, vy = o.body:getLinearVelocity()
                o.body:applyForce(0, -(volume * (m.density or 1) * GRAVITY * frac))
                o.body:setLinearVelocity(vx * (1 - 2 * frac * dt), vy * (1 - 3.5 * frac * dt))
                o.body:setAngularVelocity(o.body:getAngularVelocity() * (1 - 2 * frac * dt))
              end
            elseif m.conveyor then
              if math.abs(y1 - m.y) < 6 then
                local vx, vy = o.body:getLinearVelocity()
                o.body:setLinearVelocity(vx + (m.speed - vx) * math.min(1, dt * 8), vy)
              end
            elseif m.type == "pad" then
              local vx, vy = o.body:getLinearVelocity()
              if vy >= -100 and y1 > m.y and y0 < m.y + m.h then
                o.body:setLinearVelocity(vx, -(m.power or 1350) * 0.8)
                m.s = 1
                sfx.play("pad", m.x + m.w / 2)
              end
            elseif y1 > m.y and y0 < m.y + m.h then
              local d = FAN_DIRS[m.dir or "up"] or FAN_DIRS.up
              local mass = o.body:getMass()
              local _, vy = o.body:getLinearVelocity()
              if not (d[2] < 0 and vy < -500) then
                o.body:applyForce(d[1] * m.force * 0.7 * mass, d[2] * m.force * 0.7 * mass)
              end
            end
          end
        end
      end
    end
  end
end

-- A moving object hit players. Damage grows with speed and size, up to the object's own limit.
local function hurtPlayers(ph, world, o, vx, vy, speed, cx, cy, dt)
  if OWN_DAMAGE[o.type] or speed < HURT_SPEED then return end
  local Objects = require "game.objects"
  local limit = o.type == "weight" and o.damage or HURT_DAMAGE
  local amount = limit * math.min(1, (speed - HURT_SPEED) / (HURT_FULL - HURT_SPEED) + 0.25)
    * math.max(0.4, math.min(1, math.sqrt(o.mass)))
  for _, p in ipairs(world.players) do
    local rec = ph.players[p]
    if rec and not p.dead then
      local dx, dy = p.x - cx, p.y - cy
      -- Only something coming towards you hurts.
      if dx * vx + dy * vy > 0 and (p.vx - vx) * dx + (p.vy - vy) * dy < 0
          and love.physics.getDistance(o.fixture, rec.fixture) <= 6 + speed * dt then
        local source = o.breaker
        if not (source and world.canHurt and not world:canHurt(source, p)) then
          Objects.hazardHit(world, o, p, amount, dx, 0.3, "falling", 1, source)
        end
      end
    end
  end
end

local function afterObjects(ph, world, dt, before)
  local Objects = require "game.objects"
  local g = GRAVITY * dt
  for i = #ph.loose, 1, -1 do
    local o = ph.loose[i]
    local body = o.body
    if not o.alive then
      if body then body:destroy() end
      o.body, o.fixture = nil, nil
      table.remove(ph.loose, i)
    else
      local x, y = body:getPosition()
      local vx, vy = body:getLinearVelocity()
      setCentre(o, x, y)
      o.rot = body:getAngle()
      local speed = math.sqrt(vx * vx + vy * vy)
      -- Sudden changes of speed are collisions.
      local b = before[o]
      if b then
        local dvx, dvy = vx - b[1], vy - b[2] - g
        local dv = math.sqrt(dvx * dvx + dvy * dvy)
        if dv > IMPACT_SOUND and (o.thudAt or 0) <= world.time then
          o.thudAt = world.time + 0.15
          sfx.play("thud", x, math.min(1, dv / 1000))
        end
        if dv > IMPACT_BREAK and o.hp and o.hp > 0 then
          Objects.damage(world, o, (dv - IMPACT_BREAK) / 10, o.breaker, x, y)
        end
      end
      if o.alive then
        -- Judged on the speed it arrived with: the step that hits you has already slowed it.
        local vx0, vy0 = vx, vy
        if b then vx0, vy0 = b[1], b[2] end
        hurtPlayers(ph, world, o, vx0, vy0, math.sqrt(vx0 * vx0 + vy0 * vy0), x, y, dt)
        if speed < 30 then
          o.restTime = (o.restTime or 0) + dt
          if o.restTime > 1 then o.breaker = nil end -- old news: nobody gets credit for it any more
        else
          o.restTime = 0
        end
        if y > Map.H + 180 or x < -300 or x > Map.W + 300 then o.alive = false end
      end
    end
  end
end

---------------------------------------------------------------- bullets
local function addBullet(ph, b)
  local P = love.physics
  local body = P.newBody(ph.b2, b.x, b.y, "dynamic")
  local f = P.newFixture(body, P.newCircleShape(b.r), 1)
  f:setRestitution(1)
  f:setFriction(0)
  f:setCategory(CAT_BULLET)
  f:setMask(CAT_PLAYER, CAT_LOOSE, CAT_BULLET)
  f:setUserData({ kind = "bullet", b = b, ph = ph })
  body:setBullet(true) -- continuous collision, so fast bullets can't skip through thin things
  body:setMass(0.02)
  body:setFixedRotation(true)
  body:setSleepingAllowed(false)
  b.body = body
  ph.bullets[#ph.bullets + 1] = b
end

local function syncBullets(ph, world, dt)
  local current = {}
  for _, b in ipairs(world.bullets or {}) do
    current[b] = true
    if not b.body and not b.dead and not b.mine and not b.laser then addBullet(ph, b) end
  end
  for i = #ph.bullets, 1, -1 do
    local b = ph.bullets[i]
    if b.dead or b.mine or not current[b] then
      b.body:destroy()
      b.body = nil
      table.remove(ph.bullets, i)
    else
      local k = (b.stepDt or dt) / dt -- slowed bullets (stasis, time warp)
      b.stepScale = k
      local bx, by = b.body:getPosition()
      if math.abs(b.x - bx) > 0.001 or math.abs(b.y - by) > 0.001 then b.body:setPosition(b.x, b.y) end
      b.body:setLinearVelocity(b.vx * k, b.vy * k)
      b.body:setGravityScale((b.gravity or 0) * k * k)
      b.prevX, b.prevY = b.x, b.y
    end
  end
end

-- Rails walk a target along the path; the carriage follows it with limited force, so if it
-- falls behind (something heavy in the way) the target waits, and after a while turns back.
local function syncRails(ph, dt)
  for _, o in ipairs(ph.rails) do
    if o.alive and o.body then
      local bx, by = o.body:getPosition()
      local lag = math.sqrt((bx - o.tx) ^ 2 + (by - o.ty) ^ 2)
      if lag > 28 then
        o.stall = o.stall + dt
        if o.stall > 1.2 then
          o.stall, o.dirn = 0, -o.dirn
          o.seg = o.seg + o.dirn
          if o.seg < 1 then o.seg = o.loop and #o.path or 2 elseif o.seg > #o.path then o.seg = o.loop and 1 or #o.path - 1 end
          o.tx, o.ty = bx, by
        end
      else
        o.stall = 0
        local remaining = (o.speed or 120) * dt
        for _ = 1, 8 do
          local nxt = o.seg + o.dirn
          if nxt > #o.path or nxt < 1 then
            if o.loop then
              nxt = nxt > #o.path and 1 or #o.path
            else
              o.dirn = -o.dirn
              nxt = o.seg + o.dirn
            end
          end
          local p = o.path[nxt]
          if not p then break end
          local dx, dy = p[1] - o.tx, p[2] - o.ty
          local d = math.sqrt(dx * dx + dy * dy)
          if d <= remaining then
            o.tx, o.ty = p[1], p[2]
            o.seg = nxt
            remaining = remaining - d
          else
            o.tx, o.ty = o.tx + dx / d * remaining, o.ty + dy / d * remaining
            break
          end
        end
      end
      o.joint:setTarget(o.tx, o.ty)
    end
  end
end

function Physics.step(world, dt)
  local ph = world.physics
  if not ph or dt <= 0 then return end
  dt = math.min(dt, 1 / 30)
  syncRails(ph, dt)
  for _, p in ipairs(ph.actors or world.players) do
    local rec = ph.players[p]
    if rec then rec.body:setActive(not p.dead) end
  end
  syncFixed(ph, dt)
  applyFields(ph, dt)
  syncBullets(ph, world, dt)
  local before = {}
  for _, o in ipairs(ph.loose) do
    if o.body then before[o] = { o.body:getLinearVelocity() } end
  end
  ph.b2:update(dt, 8, 3)
  if not ph.client then afterObjects(ph, world, dt, before) end
  for _, rope in ipairs(ph.ropes) do
    ropePoints(rope)
    if rope.held and not rope.held.alive then rope.held = nil end
  end
  ph.stepDt = dt
end

-- After the players have read their state back: bullets read theirs, and what they hit happens.
function Physics.finish(world)
  local ph = world.physics
  if not ph then return end
  for _, b in ipairs(ph.bullets) do
    if b.body then
      local k = b.stepScale or 1
      b.x, b.y = b.body:getPosition()
      local vx, vy = b.body:getLinearVelocity()
      b.vx, b.vy = vx / k, vy / k
    end
  end
  local events = ph.events
  ph.events = {}
  for _, e in ipairs(events) do
    local b = e[1]
    if not b.dead and not b.mine then
      if e[3] then b:onSolid(world, e[2], e[3], e[4]) else b:onPlayer(world, e[2]) end
    end
  end
  for _, b in ipairs(ph.bullets) do
    if b.body and not b.dead and not b.mine then b:afterStep(world) end
  end
end

return Physics
