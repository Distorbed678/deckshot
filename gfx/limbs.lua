-- Arms and legs as jointed Box2D bodies. Every machine simulates its own: they are for looks, and
-- only the round body takes hits. game/body.lua works out where each hand and foot wants to be;
-- here limbs are pulled there by joints, so they lag, swing and catch on the terrain.
-- When a player dies the same bodies become a ragdoll.
local Limbs = { map = nil, corpses = {} }

local CAT_TERRAIN, CAT_LIMB = 1, 2

local function addSegment(world, x0, y0, x1, y1, width)
  local P = love.physics
  local len = math.max(2, math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2))
  local body = P.newBody(world, (x0 + x1) / 2, (y0 + y1) / 2, "dynamic")
  body:setAngle(math.atan2(y1 - y0, x1 - x0))
  body:setLinearDamping(0.6)
  body:setAngularDamping(2)
  local f = P.newFixture(body, P.newRectangleShape(len, width), 0.6)
  f:setCategory(CAT_LIMB)
  f:setMask(CAT_LIMB)
  f:setFriction(0.6)
  return body, len
end

local function addTerrain(rig, map)
  local P = love.physics
  if rig.terrain then rig.terrain:destroy() end
  rig.terrain = P.newBody(rig.world, 0, 0, "static")
  for _, r in ipairs(map and map.rects or {}) do
    if not r.oneway then
      local f = P.newFixture(rig.terrain, P.newRectangleShape(r.x + r.w / 2, r.y + r.h / 2, r.w, r.h))
      f:setCategory(CAT_TERRAIN)
    end
  end
  -- Ramps (blocks with a slope) are part of the ground for ragdolls too.
  for _, o in ipairs(map and map.objects or {}) do
    if o.type == "block" and (o.slope == "left" or o.slope == "right") and not o.physics and o.w and o.h and not o.rot then
      local high = o.slope == "right" and o.x + o.w or o.x
      local f = P.newFixture(rig.terrain, P.newPolygonShape(o.x, o.y + o.h, o.x + o.w, o.y + o.h, high, o.y))
      f:setCategory(CAT_TERRAIN)
    end
  end
  rig.mapRef = map
end

-- A limb from (ax, ay): upper part to the elbow or knee, lower part to the hand or foot.
local function addLimb(rig, ax, ay, ex, ey, hx, hy, width, force)
  local P = love.physics
  local limb = { force = force }
  limb.anchor = P.newBody(rig.world, ax, ay, "kinematic")
  limb.upper, limb.upperLen = addSegment(rig.world, ax, ay, ex, ey, width)
  limb.lower, limb.lowerLen = addSegment(rig.world, ex, ey, hx, hy, width)
  limb.top = P.newRevoluteJoint(limb.anchor, limb.upper, ax, ay, false)
  limb.mid = P.newRevoluteJoint(limb.upper, limb.lower, ex, ey, false)
  limb.pull = P.newMouseJoint(limb.lower, hx, hy)
  limb.pull:setMaxForce(force)
  limb.pull:setFrequency(14)
  limb.pull:setDampingRatio(0.8)
  return limb
end

-- Elbow and hand (or knee and foot) at sensible lengths: pointing the way body.lua's targets
-- do, but never longer than a limb should be, however stale those targets are.
local function pose(ax, ay, ex, ey, hx, hy, l1, l2, defX, defY)
  local function toward(fx, fy, tx, ty, len, dx, dy)
    local vx, vy = tx - fx, ty - fy
    local d = math.sqrt(vx * vx + vy * vy)
    if d < 1 then vx, vy, d = dx, dy, 1 end
    local k = math.min(d, len) / d
    return fx + vx * k, fy + vy * k
  end
  ex, ey = toward(ax, ay, ex, ey, l1, defX, defY)
  hx, hy = toward(ex, ey, hx, hy, l2, defX, defY)
  return ex, ey, hx, hy
end

-- Build the limbs from the positions body.lua has already worked out.
local function newRig(p, b)
  local P = love.physics
  P.setMeter(50)
  local r = p.r
  local side = p.facing or 1
  local width = math.max(3, r * 0.2)
  local rig = { world = P.newWorld(0, 1800, true), legs = {}, view = { legs = {} } }
  addTerrain(rig, not p.offWorld and Limbs.map or nil)
  rig.torso = P.newBody(rig.world, p.x, p.y, "kinematic")
  local tf = P.newFixture(rig.torso, P.newCircleShape(r))
  tf:setCategory(CAT_LIMB)
  tf:setMask(CAT_LIMB)
  rig.torsoFixture = tf
  local armL = r * 0.95
  local legL = (r * 0.38 + (p.leg or r * 0.7)) * 0.62
  local function limb(ax, ay, e, h, l, dx, dy, force)
    local ex, ey, hx, hy = pose(ax, ay, e.x, e.y, h.x, h.y, l, l, dx, dy)
    return addLimb(rig, ax, ay, ex, ey, hx, hy, width, force)
  end
  rig.gun = limb(p.x + side * r * 0.55, p.y + r * 0.05, b.gunE, b.gun, armL, side, 0.3, 900)
  rig.off = limb(p.x - side * r * 0.55, p.y + r * 0.05, b.offE, b.off, armL, -side, 0.3, 600)
  for i, l in ipairs(b.legs) do
    rig.legs[i] = limb(p.x + l.side * r * 0.5, p.y + r * 0.62, l.knee, l.foot, legL, l.side * 0.2, 1, 900)
  end
  return rig
end

local function drive(limb, ax, ay, tx, ty, dt)
  local x, y = limb.anchor:getPosition()
  limb.anchor:setLinearVelocity((ax - x) / dt, (ay - y) / dt)
  if limb.pull then limb.pull:setTarget(tx, ty) end
end

-- Joints get pulled apart when a limb catches on the terrain or the body moves fast, which
-- shows as a stretched arm or leg. Put each part back on the end of the one before it, keeping
-- its angle and carrying the body's speed.
local SLACK = 3
local function placeSegment(body, len, x0, y0, vx, vy)
  local a = body:getAngle()
  body:setPosition(x0 + math.cos(a) * len / 2, y0 + math.sin(a) * len / 2)
  body:setLinearVelocity(vx, vy)
  body:setAngularVelocity(0)
end

local function repairLimb(limb, vx, vy)
  local ax, ay, ux, uy = limb.top:getAnchors()
  local ex, ey, lx, ly = limb.mid:getAnchors()
  local topGap = (ax - ux) ^ 2 + (ay - uy) ^ 2
  local midGap = (ex - lx) ^ 2 + (ey - ly) ^ 2
  if topGap <= SLACK * SLACK and midGap <= SLACK * SLACK then return end
  placeSegment(limb.upper, limb.upperLen, ax, ay, vx, vy)
  local mx, my = limb.upper:getWorldPoint(limb.upperLen / 2, 0)
  placeSegment(limb.lower, limb.lowerLen, mx, my, vx, vy)
end

local function readLimb(limb, into)
  into.elbow = into.elbow or {}
  into.hand = into.hand or {}
  local mx, my = limb.upper:getWorldPoint(limb.upperLen / 2, 0)
  local hx, hy = limb.lower:getWorldPoint(limb.lowerLen / 2, 0)
  into.elbow.x, into.elbow.y = mx, my
  into.hand.x, into.hand.y = hx, hy
end

local function readRig(rig)
  local v = rig.view
  v.gunL, v.offL = v.gunL or {}, v.offL or {}
  readLimb(rig.gun, v.gunL)
  readLimb(rig.off, v.offL)
  v.gun, v.gunE, v.off, v.offE = v.gunL.hand, v.gunL.elbow, v.offL.hand, v.offL.elbow
  for i, limb in ipairs(rig.legs) do
    v.legs[i] = v.legs[i] or {}
    readLimb(limb, v.legs[i])
    v.legs[i].foot, v.legs[i].knee = v.legs[i].hand, v.legs[i].elbow
  end
end

-- Called after body.lua's targets are up to date. Returns what to draw.
function Limbs.update(p, b, dt)
  local rig = b.rig
  if not rig then
    rig = newRig(p, b)
    b.rig = rig
  end
  local map = not p.offWorld and Limbs.map or nil -- figures on the interface have no terrain
  if rig.mapRef ~= map then addTerrain(rig, map) end
  dt = math.max(1 / 240, math.min(1 / 30, dt))
  local r, side = p.r, p.facing or 1
  local tx, ty = rig.torso:getPosition()
  rig.torso:setLinearVelocity((p.x - tx) / dt, (p.y - ty) / dt)
  drive(rig.gun, p.x + side * r * 0.55, p.y + r * 0.05, b.gun.x, b.gun.y, dt)
  drive(rig.off, p.x - side * r * 0.55, p.y + r * 0.05, b.off.x, b.off.y, dt)
  for i, limb in ipairs(rig.legs) do
    local l = b.legs[i]
    drive(limb, p.x + l.side * r * 0.5, p.y + r * 0.62, l.foot.x, l.foot.y, dt)
  end
  rig.world:update(dt, 8, 3)
  local vx, vy = rig.torso:getLinearVelocity()
  repairLimb(rig.gun, vx, vy)
  repairLimb(rig.off, vx, vy)
  for _, limb in ipairs(rig.legs) do repairLimb(limb, vx, vy) end
  readRig(rig)
  return rig.view
end

-- The player died: release every joint that was driving the limbs.
function Limbs.ragdoll(p, b)
  local rig = b.rig
  if not rig then return end
  b.rig = nil
  b.stale = true -- the next life builds its body from scratch
  local P = love.physics
  local torso = rig.torso
  torso:setType("dynamic")
  rig.torsoFixture:setCategory(CAT_LIMB)
  rig.torsoFixture:setMask(CAT_LIMB)
  rig.torsoFixture:setDensity(1)
  torso:resetMassData()
  torso:setLinearVelocity(p.vx or 0, (p.vy or 0) - 240)
  torso:setAngularVelocity((love.math.random() - 0.5) * 8)
  local function release(limb)
    limb.pull:destroy()
    limb.pull = nil
    local x, y = limb.upper:getWorldPoint(-limb.upperLen / 2, 0)
    limb.top:destroy()
    limb.top = P.newRevoluteJoint(torso, limb.upper, x, y, false)
    limb.anchor:destroy()
    limb.upper:setLinearDamping(0.1)
    limb.lower:setLinearDamping(0.1)
  end
  release(rig.gun)
  release(rig.off)
  for _, limb in ipairs(rig.legs) do release(limb) end
  Limbs.corpses[#Limbs.corpses + 1] = { rig = rig, color = p.color, r = p.r, t = 3.5 }
  while #Limbs.corpses > 8 do table.remove(Limbs.corpses, 1).rig.world:destroy() end
end

function Limbs.clear()
  for _, c in ipairs(Limbs.corpses) do c.rig.world:destroy() end
  Limbs.corpses = {}
end

function Limbs.updateCorpses(dt)
  for i = #Limbs.corpses, 1, -1 do
    local c = Limbs.corpses[i]
    c.t = c.t - dt
    if c.t <= 0 then
      c.rig.world:destroy()
      table.remove(Limbs.corpses, i)
    else
      c.rig.world:update(math.min(dt, 1 / 30), 6, 2)
      local rig = c.rig
      local vx, vy = rig.torso:getLinearVelocity()
      repairLimb(rig.gun, vx, vy)
      repairLimb(rig.off, vx, vy)
      for _, limb in ipairs(rig.legs) do repairLimb(limb, vx, vy) end
    end
  end
end

return Limbs
