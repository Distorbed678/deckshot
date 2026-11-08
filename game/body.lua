-- The character's arms, legs, pistol and block circle. Purely visual: the hitbox is still the round
-- body. Everything is worked out on each machine from synced state (position, aim, blocking, melee),
-- so it needs no network traffic and works the same for local, host and client players.
local Body = {}

local function newPoint(x, y) return { x = x, y = y, vx = 0, vy = 0 } end

-- Springs toward a target; damping is relative to the body so limbs trail instead of being left behind.
local function spring(o, tx, ty, k, damp, bvx, bvy, dt)
  o.vx = o.vx + (k * (tx - o.x) - damp * (o.vx - bvx * 0.8)) * dt
  o.vy = o.vy + (k * (ty - o.y) - damp * (o.vy - bvy * 0.8)) * dt
  o.x, o.y = o.x + o.vx * dt, o.y + o.vy * dt
end

local function reset(p)
  local x, y, r = p.x, p.y, p.r
  p.body = {
    lastX = x, lastY = y,
    gun = newPoint(x + r, y), gunE = newPoint(x + r * 0.7, y + 4),
    off = newPoint(x - r, y + r * 0.3), offE = newPoint(x - r * 0.7, y + 4),
    legs = {
      { side = -1, x = x - r, y = y + r, kx = x - r * 0.7, ky = y + r * 0.7, step = nil, foot = newPoint(x - r, y + r), knee = newPoint(x - r * 0.7, y + r * 0.8) },
      { side = 1, x = x + r, y = y + r, kx = x + r * 0.7, ky = y + r * 0.7, step = nil, foot = newPoint(x + r, y + r), knee = newPoint(x + r * 0.7, y + r * 0.8) },
    },
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
  if not b or math.abs(p.x - b.lastX) + math.abs(p.y - b.lastY) > 220 then
    reset(p)
    b = p.body
  end
  dt = math.max(1 / 240, math.min(1 / 30, dt))
  local bvx, bvy = (p.x - b.lastX) / dt, (p.y - b.lastY) / dt
  b.lastX, b.lastY = p.x, p.y
  local x, y, r, side = p.x, p.y, p.r, p.facing or 1
  local ax, ay = p.aimX or side, p.aimY or 0

  -- Gun arm: reaches where you aim.
  local gsx, gsy = x + side * r * 0.55, y + r * 0.05
  spring(b.gun, x + ax * (r + 9), y + ay * (r + 9), 900, 40, bvx, bvy, dt)
  clampTo(b.gun, gsx, gsy, r * 2.2)
  spring(b.gunE, (gsx + b.gun.x) / 2, (gsy + b.gun.y) / 2 + r * 0.28, 300, 15, bvx, bvy, dt)

  -- Block arm: rests at your side, lifts when you block, punches when you melee.
  local osx, osy = x - side * r * 0.55, y + r * 0.05
  local tx, ty = x - side * (r + 7), y + r * 0.35 + math.sin(love.timer.getTime() * 2.4 + (p.slot or 1)) * 1.5
  local k, damp = 620, 28
  local swing = p.swingTimer or 0
  if swing > 0 then
    local reach = (p.stats and p.stats.meleeRange or 55) * (p.swingHeavy and 1 or 0.8)
    tx, ty = x + ax * reach, y + ay * reach
    k, damp = 2200, 50
  elseif p.charging then
    local full = math.min(1, (p.meleeCharge or 0) / math.max(0.05, p.stats and p.stats.heavyCharge or 0.6))
    tx, ty = x - ax * (r * 0.5 + r * full * 0.7), y - ay * (r * 0.5 + r * full * 0.7) - r * 0.2
    k = 900
  elseif p.blockTimer and p.blockTimer > 0 then
    tx, ty = x - side * r * 0.25, y - r - 14
    k, damp = 1600, 40
  end
  spring(b.off, tx, ty, k, damp, bvx, bvy, dt)
  clampTo(b.off, osx, osy, swing > 0 and r * 4 or r * 2.4)
  spring(b.offE, (osx + b.off.x) / 2, (osy + b.off.y) / 2 + r * 0.28, 300, 15, bvx, bvy, dt)

  -- Legs: feet stay planted and step when they fall behind; in the air they dangle.
  local grounded = p.onGround
  local floor = y + r
  local stepping
  for _, l in ipairs(b.legs) do if l.step then stepping = l end end
  for _, l in ipairs(b.legs) do
    local f = l.foot
    local hipX, hipY = x + l.side * r * 0.5, y + r * 0.55
    if grounded then
      local want = x + l.side * r * 0.95 + (p.vx or bvx) * 0.075
      if l.step then
        l.step = l.step + dt / 0.12
        local e = math.min(1, l.step)
        f.x = l.fromX + (l.toX - l.fromX) * e
        f.y = floor - math.sin(e * math.pi) * r * 0.45
        if l.step >= 1 then l.step = nil end
      else
        f.y = f.y + (floor - f.y) * math.min(1, dt * 30)
        if not stepping and math.abs(f.x - want) > r * 0.7 then
          l.step, l.fromX, l.toX = 0, f.x, want + (p.vx or bvx) * 0.05
          stepping = l
        end
      end
      f.vx, f.vy = bvx, bvy
    else
      l.step = nil
      local vy = p.vy or bvy
      spring(f, hipX + l.side * r * 0.25 - bvx * 0.018, y + r + r * 0.5 + math.max(-r * 0.3, math.min(r * 0.5, vy * 0.012)), 260, 16, bvx, bvy, dt)
      clampTo(f, hipX, hipY, r * 1.5)
    end
    spring(l.knee, (hipX + f.x) / 2 + l.side * r * 0.25, (hipY + f.y) / 2, 340, 16, bvx, bvy, dt)
  end
end

-- A curved limb from a to b through c.
local function noodle(ax, ay, cx, cy, bx, by, width)
  local pts = {}
  local n = 8
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
  local w = math.max(3, r * 0.22)
  limbColor(p.color, A)
  for _, l in ipairs(b.legs) do
    local hipX, hipY = p.x + l.side * r * 0.5, p.y + r * 0.55
    noodle(hipX, hipY, l.knee.x, l.knee.y, l.foot.x, l.foot.y, w)
    love.graphics.circle("fill", l.foot.x, l.foot.y, w * 0.85)
  end
end

local function drawPistol(p, A)
  local b = p.body
  local s = p.r / 20
  local angle = math.atan2(p.aimY or 0, p.aimX or 1)
  love.graphics.push()
  love.graphics.translate(b.gun.x, b.gun.y)
  love.graphics.rotate(angle)
  love.graphics.scale(s, (p.aimX or 1) < 0 and -s or s)
  love.graphics.setColor(0.2, 0.21, 0.25, A)
  love.graphics.polygon("fill", -2, 1, 5, 1, 3, 11, -4, 11) -- grip
  if p.empowered then love.graphics.setColor(1, 0.85, 0.35, A) else love.graphics.setColor(0.32, 0.33, 0.38, A) end
  love.graphics.rectangle("fill", -6, -6, 26, 8, 2, 2)      -- slide
  love.graphics.setColor(0.7, 0.72, 0.78, A)
  love.graphics.rectangle("fill", -4, -5, 20, 2)
  love.graphics.pop()
end

-- In front of the body.
function Body.drawArms(p, A)
  local b = p.body
  if not b then return end
  local r, side = p.r, p.facing or 1
  local w = math.max(3, r * 0.22)
  limbColor(p.color, A)
  noodle(p.x + side * r * 0.55, p.y + r * 0.05, b.gunE.x, b.gunE.y, b.gun.x, b.gun.y, w)
  noodle(p.x - side * r * 0.55, p.y + r * 0.05, b.offE.x, b.offE.y, b.off.x, b.off.y, w)
  drawPistol(p, A)
  limbColor(p.color, A)
  love.graphics.circle("fill", b.gun.x, b.gun.y, w)

  -- The block circle: white when ready, grey and refilling on cooldown, flashing as you block.
  local cr = r * 0.42
  local cd = p.blockCd or 0
  local total = (p.stats and p.stats.blockCooldown) or 1
  local cx, cy = b.off.x, b.off.y
  if p.blockTimer and p.blockTimer > 0 then
    local pulse = 0.65 + 0.35 * math.sin(love.timer.getTime() * 40)
    love.graphics.setColor(1, 1, 1, 0.35 * A)
    love.graphics.circle("fill", cx, cy, cr * 2.1)
    love.graphics.setColor(1, 1, 1, pulse * A)
    love.graphics.circle("fill", cx, cy, cr * 1.45)
  elseif cd > 0 then
    love.graphics.setColor(0.42, 0.42, 0.46, A)
    love.graphics.circle("fill", cx, cy, cr)
    local frac = 1 - math.min(1, cd / total)
    if frac > 0.01 then
      love.graphics.setColor(0.86, 0.86, 0.88, A)
      love.graphics.arc("fill", cx, cy, cr, -math.pi / 2, -math.pi / 2 + math.pi * 2 * frac)
    end
  else
    love.graphics.setColor(1, 1, 1, A)
    love.graphics.circle("fill", cx, cy, cr)
  end
end

return Body
