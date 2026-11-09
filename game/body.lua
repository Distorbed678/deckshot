-- The character's noodle arms and legs, pistol and block circle. Purely visual: the hitbox is still
-- the round body. Everything is worked out on each machine from synced state (position, aim,
-- blocking, melee), so it needs no network traffic and works the same for local, host and client.
local Assets = require "core.assets"
local Cosmetics = require "core.cosmetics"
local Stats = require "game.stats"

local Limbs = require "gfx.limbs"
local Body = { showNames = false }

local function newPoint(x, y) return { x = x, y = y, vx = 0, vy = 0 } end

-- Springs toward a target; damping is relative to the body so limbs trail instead of being left behind.
local function spring(o, tx, ty, k, damp, bvx, bvy, dt)
  o.vx = o.vx + (k * (tx - o.x) - damp * (o.vx - bvx * 0.8)) * dt
  o.vy = o.vy + (k * (ty - o.y) - damp * (o.vy - bvy * 0.8)) * dt
  o.x, o.y = o.x + o.vx * dt, o.y + o.vy * dt
end

local function legOf(p) return p.leg or p.r * 0.7 end

local function newLeg(x, y, r, floor, side)
  return { side = side, foot = newPoint(x + side * r * 0.5, floor), knee = newPoint(x + side * r * 0.7, y + r), step = nil }
end

local function reset(p)
  local x, y, r = p.x, p.y, p.r
  local floor = y + r + legOf(p)
  p.body = {
    lastX = x, lastY = y, wasGround = p.onGround, tuck = 0, grin = 0, hurt = 0, kills = p.st and p.st.kills or 0, lastShot = 0,
    gun = newPoint(x + r, y), gunE = newPoint(x + r * 0.7, y + 6),
    off = newPoint(x - r, y + r * 0.3), offE = newPoint(x - r * 0.7, y + 6),
    legs = { newLeg(x, y, r, floor, -1), newLeg(x, y, r, floor, 1) },
  }
end

local function clampTo(o, ax, ay, maxD)
  local dx, dy = o.x - ax, o.y - ay
  local d = math.sqrt(dx * dx + dy * dy)
  if d > maxD then
    o.x, o.y = ax + dx / d * maxD, ay + dy / d * maxD
  end
end

function Body.update(p, dt)
  local b = p.body
  if not b or math.abs(p.x - b.lastX) + math.abs(p.y - b.lastY) > 260 then
    reset(p)
    b = p.body
  end
  dt = math.max(1 / 240, math.min(1 / 30, dt))
  local bvx, bvy = (p.x - b.lastX) / dt, (p.y - b.lastY) / dt
  b.lastX, b.lastY = p.x, p.y
  local x, y, r, side = p.x, p.y, p.r, p.facing or 1
  local ax, ay = p.aimX or side, p.aimY or 0
  local leg = legOf(p)
  local grounded = p.onGround

  -- Expressions.
  b.grin, b.hurt = math.max(0, b.grin - dt), math.max(0, b.hurt - dt)
  if (p.hitFlash or 0) > 0 then b.hurt = 0.7 end
  local kills = p.st and p.st.kills or 0
  if kills > b.kills then b.grin = 1.2 end
  b.kills = kills

  -- Gun arm: reaches where you aim (or at p.gunTarget), and kicks back when you fire.
  local gsx, gsy = x + side * r * 0.55, y + r * 0.05
  local gtx, gty = x + ax * (r + 16), y + ay * (r + 16)
  if p.gunTarget then gtx, gty = p.gunTarget[1], p.gunTarget[2] end
  local shot = p.shotT or 0
  if shot > b.lastShot then
    local kick = 950 * math.max(0.7, math.min(2.5, ((p.stats and p.stats.bulletSize) or 5) / 5))
    b.gun.vx, b.gun.vy = b.gun.vx - ax * kick, b.gun.vy - ay * kick
  end
  b.lastShot = shot
  spring(b.gun, gtx, gty, 780, 30, bvx, bvy, dt)
  clampTo(b.gun, gsx, gsy, p.armReach or r * 2.7)
  spring(b.gunE, (gsx + b.gun.x) / 2, (gsy + b.gun.y) / 2 + r * 0.42, 210, 9, bvx, bvy, dt)

  -- Block arm: rests at your side, lifts when you block, punches when you melee.
  local osx, osy = x - side * r * 0.55, y + r * 0.05
  local tx, ty = x - side * (r + 14), y + r * 0.5 + math.sin(love.timer.getTime() * 2.4 + (p.slot or 1)) * 2
  local k, damp = 520, 22
  local swing = p.swingTimer or 0
  if swing > 0 then
    local reach = (p.stats and p.stats.meleeRange or 55) * (p.swingHeavy and 1 or 0.8)
    tx, ty = x + ax * reach, y + ay * reach
    k, damp = 2200, 50
  elseif p.charging then
    local full = math.min(1, (p.meleeCharge or 0) / math.max(0.05, p.stats and p.stats.heavyCharge or 0.6))
    tx, ty = x - ax * (r * 0.5 + r * full * 0.8), y - ay * (r * 0.5 + r * full * 0.8) - r * 0.2
    k = 900
  elseif p.blockTimer and p.blockTimer > 0 then
    tx, ty = x - side * r * 0.25, y - r - 22
    k, damp = 1600, 40
  end
  spring(b.off, tx, ty, k, damp, bvx, bvy, dt)
  clampTo(b.off, osx, osy, swing > 0 and r * 4.5 or r * 2.9)
  spring(b.offE, (osx + b.off.x) / 2, (osy + b.off.y) / 2 + r * 0.42, 210, 9, bvx, bvy, dt)

  -- Legs tuck up for a moment when you take off and when you land.
  if grounded ~= b.wasGround then b.tuck = grounded and 0.15 or 0.2 end
  b.wasGround = grounded
  b.tuck = math.max(0, b.tuck - dt)
  local tuckK = math.sin(math.min(1, b.tuck / 0.2) * math.pi / 2)

  -- A foot steps as soon as it falls behind and can never trail further than its reach.
  local floor = y + r + leg
  local speed = math.max(-1200, math.min(1200, p.vx or bvx))
  local legs = b.legs
  for i, l in ipairs(legs) do
    local f = l.foot
    local other = legs[3 - i]
    local hipX, hipY = x + l.side * r * 0.5, y + r * 0.62
    if grounded then
      local want = x + l.side * r * 0.42 + speed * 0.07
      local reach = r * 1.7
      local lift = tuckK * leg * 1.1
      if l.step then
        l.step = l.step + dt / math.max(0.06, 0.13 - math.abs(speed) / 6000)
        local e = math.min(1, l.step)
        l.toX = want + speed * 0.05
        f.x = l.fromX + (l.toX - l.fromX) * e
        f.y = floor - math.sin(e * math.pi) * r * 0.5 - lift
        if l.step >= 1 then l.step = nil end
      else
        f.y = f.y + (floor - lift - f.y) * math.min(1, dt * 40)
        local behind = math.abs(f.x - want)
        if (not other.step and behind > r * 0.5 + math.abs(speed) * 0.015) or behind > reach then
          l.step, l.fromX, l.toX = 0, f.x, want
        end
      end
      f.x = math.max(hipX - reach - r * 0.5, math.min(hipX + reach + r * 0.5, f.x))
      f.vx, f.vy = bvx, bvy
    else
      l.step = nil
      local vy = p.vy or bvy
      local drop = leg + r * 0.62 + math.max(-r * 0.3, math.min(r * 0.45, vy * 0.012)) - tuckK * leg * 1.2
      spring(f, hipX + l.side * r * 0.3 - bvx * 0.02, hipY + drop, 280, 15, bvx, bvy, dt)
      clampTo(f, hipX, hipY, r * 1.7)
    end
    spring(l.knee, (hipX + f.x) / 2 + l.side * r * 0.42, (hipY + f.y) / 2 - r * 0.05, 240, 10, bvx, bvy, dt)
  end
  b.view = Limbs.update(p, b, dt)
end


-- "grin", "angry", "shock" or nil: what the face is doing.
function Body.expression(p)
  local b = p.body
  if not b then return nil end
  if b.grin > 0 then return "grin" end
  if b.hurt > 0 then return "angry" end
  if p.stats and p.stats.maxHp and p.hp and p.hp < p.stats.maxHp * 0.25 then return "shock" end
  return nil
end

-- A curved limb from a to b through c.
local function noodle(ax, ay, cx, cy, bx, by, width)
  local pts = {}
  local n = 10
  for i = 0, n do
    local t = i / n
    local u = 1 - t
    pts[#pts + 1] = u * u * ax + 2 * u * t * cx + t * t * bx
    pts[#pts + 1] = u * u * ay + 2 * u * t * cy + t * t * by
  end
  love.graphics.setLineWidth(width)
  love.graphics.setLineJoin("bevel")
  love.graphics.line(pts)
  love.graphics.setLineJoin("miter")
end

local function limbColor(c, A) love.graphics.setColor(c[1] * 0.72, c[2] * 0.72, c[3] * 0.72, A) end

-- Behind the body.
function Body.drawLegs(p, A)
  local b = p.body
  if not b then return end
  local r = p.r
  local w = math.max(2.5, r * 0.17)
  limbColor(p.color, A)
  local v = b.view or b
  for i, l in ipairs(b.legs) do
    local g = v.legs[i] or l
    noodle(p.x + l.side * r * 0.5, p.y + r * 0.62, g.knee.x, g.knee.y, g.foot.x, g.foot.y, w)
    love.graphics.ellipse("fill", g.foot.x + l.side * w * 0.4, g.foot.y, w * 1.3, w * 0.8)
  end
end

-- What the gun looks like, from your stats (clients work these out from your cards).
local function weaponOf(p)
  local s, b = p.weaponStats or p.stats or {}, Stats.BASE
  local function ratio(key) return (s[key] or b[key]) / b[key] end
  local w = {}
  w.chunk = math.max(0.85, math.min(1.9, ratio("gunDamage") ^ 0.4 * ratio("bulletSize") ^ 0.3))
  w.len = math.max(0.85, math.min(2.1, ratio("bulletSpeed") ^ 0.7))
  w.barrels = math.max(1, math.min(4, s.bullets or 1))
  w.mag = math.max(0, math.min(16, ((s.ammo or b.ammo) - b.ammo) * 2))
  w.vents = math.max(0, math.min(5, math.floor((1 / ratio("fireDelay") - 1) * 4)))
  if (s.laser or 0) > 0 then w.accent = { 0.35, 0.95, 1 }
  elseif (s.explosion or 0) > 0 then w.accent = { 1, 0.55, 0.2 }
  elseif (s.ghost or 0) > 0 then w.accent = { 0.9, 0.9, 1 }
  elseif (s.homing or 0) > 0 then w.accent = { 0.8, 0.45, 1 }
  elseif (s.bounces or 0) > 0 then w.accent = { 0.45, 1, 0.5 } end
  return w
end

-- How far from the body's centre the barrel ends (where the flash goes).
function Body.muzzleDist(p)
  return p.r + 16 + 20 * weaponOf(p).len * (p.r / 20)
end

local function drawPistol(p, A)
  local b = p.body
  local s = p.r / 20
  local ax, ay = p.aimX or 1, p.aimY or 0
  local w = weaponOf(p)
  local len, h = 26 * w.len, 8 * w.chunk
  love.graphics.push()
  local v = b.view or b
  love.graphics.translate(v.gun.x, v.gun.y)
  love.graphics.rotate(math.atan2(ay, ax))
  love.graphics.scale(s, ax < 0 and -s or s)
  love.graphics.setColor(0.2, 0.21, 0.25, A)
  Assets.rect("gun_grip", -4, 1, 9, 10 + w.mag) -- grip and magazine
  for i = 2, w.barrels do -- extra barrels stack on top
    love.graphics.setColor(0.26, 0.27, 0.32, A)
    Assets.rect("gun_slab", 0, 2 - h - (i - 1) * 4, len - 8, 3)
  end
  if p.empowered then love.graphics.setColor(1, 0.85, 0.35, A) else love.graphics.setColor(0.32, 0.33, 0.38, A) end
  Assets.rect("gun_slab", -6, 2 - h, len, h)
  local stripe = w.accent or { 0.7, 0.72, 0.78 }
  love.graphics.setColor(stripe[1], stripe[2], stripe[3], A)
  Assets.rect("gun_slab", -4, 3 - h, len - 6, math.max(2, h * 0.24))
  love.graphics.setColor(0.13, 0.13, 0.16, A)
  for i = 1, w.vents do Assets.rect("tile_white", i * 5 - 3, 3 - h + h * 0.4, 2.4, h * 0.42) end
  love.graphics.pop()
end

-- In front of the body.
function Body.drawArms(p, A)
  local b = p.body
  if not b then return end
  local r, side = p.r, p.facing or 1
  local w = math.max(2.5, r * 0.17)
  limbColor(p.color, A)
  local v = b.view or b
  noodle(p.x + side * r * 0.55, p.y + r * 0.05, v.gunE.x, v.gunE.y, v.gun.x, v.gun.y, w)
  noodle(p.x - side * r * 0.55, p.y + r * 0.05, v.offE.x, v.offE.y, v.off.x, v.off.y, w)
  if not p.noGun then drawPistol(p, A) end
  limbColor(p.color, A)
  Assets.center("dot", v.gun.x, v.gun.y, (w * (p.noGun and 1.9 or 1.2)) * 2, (w * (p.noGun and 1.9 or 1.2)) * 2)

  -- The block circle: white when ready, grey and refilling on cooldown, flashing as you block.
  local cr = r * 0.42
  local cd = p.blockCd or 0
  local total = (p.stats and p.stats.blockCooldown) or 1
  local cx, cy = v.off.x, v.off.y
  if p.blockTimer and p.blockTimer > 0 then
    local pulse = 0.65 + 0.35 * math.sin(love.timer.getTime() * 40)
    love.graphics.setColor(1, 1, 1, 0.35 * A)
    Assets.center("dot", cx, cy, (cr * 2.1) * 2, (cr * 2.1) * 2)
    love.graphics.setColor(1, 1, 1, pulse * A)
    Assets.center("dot", cx, cy, (cr * 1.45) * 2, (cr * 1.45) * 2)
  elseif cd > 0 then
    love.graphics.setColor(0.42, 0.42, 0.46, A)
    Assets.center("dot", cx, cy, (cr) * 2, (cr) * 2)
    local frac = 1 - math.min(1, cd / total)
    if frac > 0.01 then
      love.graphics.setColor(0.86, 0.86, 0.88, A)
      love.graphics.arc("fill", cx, cy, cr, -math.pi / 2, -math.pi / 2 + math.pi * 2 * frac)
    end
  else
    love.graphics.setColor(1, 1, 1, A)
    Assets.center("dot", cx, cy, (cr) * 2, (cr) * 2)
  end
end

-- A whole character outside a match (card picks, lobby, Customize). f has x, y, r, color, aimX,
-- aimY, facing, hat, eyes, mouth, detail; optional gunTarget.
function Body.drawFigure(f, dt)
  f.onGround = true
  f.vx, f.vy = 0, 0
  Body.update(f, dt)
  Body.drawLegs(f, 1)
  -- An arm reaching across goes behind the body rather than over the face.
  local behind = f.noGun or (f.gunTarget and f.body.gun.x < f.x)
  if behind then Body.drawArms(f, 1) end
  love.graphics.setColor(f.color)
  Assets.center("dot", f.x, f.y, (f.r) * 2, (f.r) * 2)
  local blink = (love.timer.getTime() * 0.31 + (f.slot or 1) * 0.37) % 1 < 0.045
  Cosmetics.drawFace(f.x + (f.facing or 1) * f.r * 0.14, f.y - f.r * 0.22, f.r, { f.aimX or 1, f.aimY or 0 },
    { blink = blink, expr = Body.expression(f) }, 1, f.eyes, f.mouth, f.detail)
  Cosmetics.drawHat(f.x, f.y - f.r * 0.92, f.r, f.hat, f.color)
  if not behind then Body.drawArms(f, 1) end
end

-- Draw the ragdolls of the recently dead.
function Body.drawCorpses()
  for _, c in ipairs(Limbs.corpses) do
    local A = math.min(1, c.t / 0.8)
    local rig = c.rig
    local w = math.max(2.5, c.r * 0.17)
    limbColor(c.color, A)
    local function limb(l)
      local ax, ay = l.upper:getWorldPoint(-l.upperLen / 2, 0)
      local ex, ey = l.upper:getWorldPoint(l.upperLen / 2, 0)
      local hx, hy = l.lower:getWorldPoint(l.lowerLen / 2, 0)
      noodle(ax, ay, ex, ey, hx, hy, w)
    end
    limb(rig.gun)
    limb(rig.off)
    for _, l in ipairs(rig.legs) do limb(l) end
    local x, y = rig.torso:getPosition()
    love.graphics.setColor(c.color[1], c.color[2], c.color[3], A)
    Assets.center("dot", x, y, (c.r) * 2, (c.r) * 2)
    love.graphics.setColor(0.1, 0.1, 0.12, A)
    love.graphics.setLineWidth(2)
    local e = c.r * 0.3
    for s = -1, 1, 2 do
      local ex, ey = x + s * e, y - e * 0.4
      love.graphics.line(ex - 3, ey - 3, ex + 3, ey + 3)
      love.graphics.line(ex - 3, ey + 3, ex + 3, ey - 3)
    end
  end
end

Body.Limbs = Limbs

return Body
