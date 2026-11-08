-- Particles, explosion rings and screen shake.
-- When fx.recorder is a table (online host), every effect is also recorded so it
-- can be replayed on clients.
local fx = {
  particles = {}, rings = {}, ghosts = {}, chunks = {}, numbers = {}, flashes = {}, puffs = {}, shake = 0, kickX = 0, kickY = 0,
  showNumbers = true, -- damage numbers (a per-player setting)
  shakeScale = 1, particleScale = 1,
  recorder = nil,
}

local MAX_RECORDED = 300

local function record(ev)
  local r = fx.recorder
  if r and #r < MAX_RECORDED then r[#r + 1] = ev end
end
fx.record = record

-- Event kinds (also the network codes in online/snapshot.lua):
-- 1 burst, 2 ring, 3 shake, 4 clear, 5 sound (gfx/sfx.lua), 6 spray, 7 ghost, 8 debris, 9 kick,
-- 10 damage number, 11 death chunks, 12 muzzle flash, 13 explosion.

-- fx.mute: create nothing (client prediction re-simulates moves the host already showed).
function fx.burst(x, y, color, count, speed, size)
  if fx.mute then return end
  count = count or 12
  speed = speed or 250
  size = size or 4
  record({ 1, x, y, color, count, speed, size })
  count = math.max(1, math.floor(count * fx.particleScale + 0.5))
  for _ = 1, count do
    local a = love.math.random() * math.pi * 2
    local s = speed * (0.3 + love.math.random() * 0.7)
    local life = 0.3 + love.math.random() * 0.4
    table.insert(fx.particles, {
      x = x, y = y,
      vx = math.cos(a) * s, vy = math.sin(a) * s,
      life = life, max = life,
      color = color,
      size = size * (0.5 + love.math.random() * 0.8),
    })
  end
end

-- A cone of particles: angle (radians), spread (radians), gravity multiplier.
-- Used for wall sparks (along the surface normal), dust puffs and muzzle flashes.
function fx.spray(x, y, angle, spread, color, count, speed, size, gravity)
  if fx.mute then return end
  record({ 6, x, y, angle, spread, color, count, speed, size, gravity or 1 })
  count = math.max(1, math.floor(count * fx.particleScale + 0.5))
  for _ = 1, count do
    local a = angle + (love.math.random() - 0.5) * spread
    local s = speed * (0.35 + love.math.random() * 0.65)
    local life = 0.15 + love.math.random() * 0.3
    table.insert(fx.particles, {
      x = x, y = y, vx = math.cos(a) * s, vy = math.sin(a) * s,
      life = life, max = life, color = color, size = size * (0.5 + love.math.random() * 0.7),
      gravity = gravity or 1,
    })
  end
end

-- A fading copy of a player's body (dash afterimages).
function fx.ghost(x, y, r, color)
  if fx.mute then return end
  record({ 7, x, y, r, color })
  table.insert(fx.ghosts, { x = x, y = y, r = r, color = color, life = 0.22, max = 0.22 })
end

-- Spinning chunks that fall and fade (breakables, deaths).
function fx.debris(x, y, color, count, size)
  record({ 8, x, y, color, count, size })
  count = math.max(1, math.floor(count * fx.particleScale + 0.5))
  for _ = 1, count do
    local a = -math.pi / 2 + (love.math.random() - 0.5) * 2.4
    local s = 150 + love.math.random() * 300
    local life = 0.6 + love.math.random() * 0.5
    table.insert(fx.chunks, {
      x = x + (love.math.random() - 0.5) * size, y = y + (love.math.random() - 0.5) * size,
      vx = math.cos(a) * s, vy = math.sin(a) * s, rot = love.math.random() * 6, spin = (love.math.random() - 0.5) * 20,
      w = size * (0.4 + love.math.random() * 0.6), h = size * (0.3 + love.math.random() * 0.4),
      life = life, max = life, color = color,
    })
  end
end

-- A flash at the barrel with sparks and a puff of smoke. size: 1 = a default bullet.
function fx.muzzle(x, y, angle, size)
  record({ 12, x, y, angle, size })
  if fx.mute then return end
  local k = math.max(0.7, math.min(3, size))
  table.insert(fx.flashes, { x = x, y = y, a = angle, k = k, life = 0.075, max = 0.075 })
  local keep = fx.recorder
  fx.recorder = nil -- clients replay the single event above
  fx.spray(x, y, angle, 0.7, { 1, 0.9, 0.55 }, math.floor(5 + 4 * k), 380 + 140 * k, 2.4, 0.15)
  fx.spray(x, y, angle, 1.4, { 0.62, 0.62, 0.66 }, math.floor(2 + 2 * k), 110, 4 + k, -0.08)
  fx.recorder = keep
end

-- An explosion: a fiery core, chunky smoke puffs and bouncing debris. radius is the blast size.
function fx.explosion(x, y, radius, color)
  record({ 13, x, y, radius, color })
  if fx.mute then return end
  local k = math.max(0.45, math.min(3, radius / 70))
  local rnd = love.math.random
  local keep = fx.recorder
  fx.recorder = nil -- clients replay the single event above
  local fire = math.max(3, math.floor((4 + 5 * k) * fx.particleScale + 0.5))
  for i = 1, fire do
    local a, d = rnd() * math.pi * 2, rnd() * radius * 0.45
    local life = 0.16 + rnd() * 0.2
    table.insert(fx.puffs, { x = x + math.cos(a) * d, y = y + math.sin(a) * d, vx = math.cos(a) * 90 * k, vy = math.sin(a) * 90 * k - 30,
      r0 = radius * (0.22 + rnd() * 0.15), r1 = radius * (0.45 + rnd() * 0.25), life = life, max = life, fire = true, hot = i % 2 == 0 })
  end
  local smoke = math.max(4, math.floor((7 + 8 * k) * fx.particleScale + 0.5))
  local tint = 0.25
  local base = 0.34 + rnd() * 0.06
  local sc = { base + (color[1] - base) * tint, base + (color[2] - base) * tint, base + (color[3] - base) * tint }
  for _ = 1, smoke do
    local a, d = rnd() * math.pi * 2, rnd() * radius * 0.75
    local life = 0.55 + rnd() * 0.6
    table.insert(fx.puffs, { x = x + math.cos(a) * d, y = y + math.sin(a) * d, vx = math.cos(a) * 60 * k, vy = math.sin(a) * 60 * k - 55,
      r0 = radius * (0.12 + rnd() * 0.12), r1 = radius * (0.4 + rnd() * 0.3), life = life, max = life, color = sc })
  end
  for _ = 1, math.max(3, math.floor((4 + 5 * k) * fx.particleScale + 0.5)) do
    local a = -math.pi / 2 + (rnd() - 0.5) * 3.4
    local s = (220 + rnd() * 420) * math.min(1.6, k)
    local life = 0.8 + rnd() * 0.8
    local shade = 0.22 + rnd() * 0.2
    table.insert(fx.chunks, { x = x, y = y, vx = math.cos(a) * s, vy = math.sin(a) * s, rot = rnd() * 6, spin = (rnd() - 0.5) * 18,
      w = 3 + rnd() * 6 * k, h = 2 + rnd() * 4 * k, life = life, max = life, color = { shade, shade, shade + 0.03 }, bounce = true })
  end
  fx.spray(x, y, -math.pi / 2, 6.2, { 1, 0.75, 0.3 }, math.floor(8 + 8 * k), 480 * math.min(1.4, k), 3, 0.3)
  fx.recorder = keep
end

-- A body bursting into chunks that bounce off the map (fx.solids), plus the face.
function fx.gibs(x, y, color, count, size)
  record({ 11, x, y, color, count, size })
  if fx.mute then return end
  count = math.max(8, math.floor(count * fx.particleScale + 0.5)) -- always a face, four limbs and the pistol
  for i = 1, count do
    local a = love.math.random() * math.pi * 2
    local s = 180 + love.math.random() * 420
    local life = 1.6 + love.math.random() * 0.9
    table.insert(fx.chunks, {
      x = x, y = y, vx = math.cos(a) * s, vy = math.sin(a) * s - 180,
      rot = love.math.random() * 6, spin = (love.math.random() - 0.5) * 16,
      w = i == 1 and 2 or size * (0.5 + love.math.random() * 0.8), h = i == 1 and 2 or size * (0.4 + love.math.random() * 0.6),
      life = life, max = life, color = color, bounce = true, face = i == 1 and size or nil,
    })
    local c = fx.chunks[#fx.chunks]
    if i >= 2 and i <= 5 then     -- arms and legs
      c.w, c.h = size * 2.2, 4
      c.color = { color[1] * 0.72, color[2] * 0.72, color[3] * 0.72 }
    elseif i == 6 then            -- the pistol
      c.w, c.h, c.color = size * 2, 8, { 0.32, 0.33, 0.38 }
    end
  end
end

-- A floating damage number over a player (key: their slot). Hits close together add up.
function fx.number(x, y, amount, key, crit)
  if amount <= 0 then return end
  record({ 10, x, y, amount, key or 0, crit and 1 or 0 })
  if fx.mute then return end
  for _, n in ipairs(fx.numbers) do
    if n.key == key and n.age < 0.25 then
      n.amount, n.x, n.y, n.age = n.amount + amount, x, y, 0
      n.crit = n.crit or crit
      return
    end
  end
  table.insert(fx.numbers, { x = x, y = y, amount = amount, key = key, crit = crit, age = 0,
    drift = (love.math.random() - 0.5) * 30 })
end

-- A small directional camera nudge (shooting recoil). Follows the shake setting.
function fx.kick(dx, dy)
  record({ 9, dx, dy })
  fx.kickX = fx.kickX + dx * fx.shakeScale
  fx.kickY = fx.kickY + dy * fx.shakeScale
end

-- Current camera offset from shake and kicks.
function fx.offset()
  local sx, sy = fx.kickX, fx.kickY
  if fx.shake > 0 then
    sx = sx + (love.math.random() - 0.5) * fx.shake * 2
    sy = sy + (love.math.random() - 0.5) * fx.shake * 2
  end
  return sx, sy
end

function fx.ring(x, y, radius, color)
  if fx.mute then return end
  record({ 2, x, y, radius, color })
  table.insert(fx.rings, { x = x, y = y, r = radius, life = 0.25, max = 0.25, color = color })
end

function fx.addShake(amount)
  record({ 3, amount })
  fx.shake = math.max(fx.shake, amount * fx.shakeScale)
end

function fx.clear()
  record({ 4 })
  fx.particles = {}
  fx.rings = {}
  fx.ghosts = {}
  fx.chunks = {}
  fx.flashes = {}
  fx.puffs = {}
  fx.numbers = {}
  fx.shake = 0
  fx.kickX, fx.kickY = 0, 0
end

function fx.update(dt)
  for i = #fx.particles, 1, -1 do
    local p = fx.particles[i]
    p.life = p.life - dt
    if p.life <= 0 then
      table.remove(fx.particles, i)
    else
      p.vy = p.vy + 700 * (p.gravity or 1) * dt
      p.vx = p.vx * (1 - 2 * dt)
      p.x = p.x + p.vx * dt
      p.y = p.y + p.vy * dt
    end
  end
  for i = #fx.rings, 1, -1 do
    local r = fx.rings[i]
    r.life = r.life - dt
    if r.life <= 0 then table.remove(fx.rings, i) end
  end
  for i = #fx.ghosts, 1, -1 do
    local g = fx.ghosts[i]
    g.life = g.life - dt
    if g.life <= 0 then table.remove(fx.ghosts, i) end
  end
  for i = #fx.puffs, 1, -1 do
    local p = fx.puffs[i]
    p.life = p.life - dt
    if p.life <= 0 then
      table.remove(fx.puffs, i)
    else
      p.vx, p.vy = p.vx * (1 - 2.4 * dt), p.vy * (1 - 2.4 * dt)
      p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt
    end
  end
  for i = #fx.flashes, 1, -1 do
    local f = fx.flashes[i]
    f.life = f.life - dt
    if f.life <= 0 then table.remove(fx.flashes, i) end
  end
  for i = #fx.chunks, 1, -1 do
    local d = fx.chunks[i]
    d.life = d.life - dt
    if d.life <= 0 then
      table.remove(fx.chunks, i)
    else
      d.vy = d.vy + 1400 * dt
      d.x, d.y = d.x + d.vx * dt, d.y + d.vy * dt
      d.rot = d.rot + d.spin * dt
      if d.bounce and fx.solids then
        for _, b in ipairs(fx.solids) do
          if not b.oneway and d.x > b.x and d.x < b.x + b.w and d.y > b.y and d.y < b.y + b.h then
            if d.vy > 0 and d.y - d.vy * dt <= b.y then
              d.y, d.vy, d.vx, d.spin = b.y, -d.vy * 0.45, d.vx * 0.7, d.spin * 0.6
            else
              d.vx = -d.vx * 0.5
              d.x = d.x + d.vx * dt * 2
            end
            break
          end
        end
      end
    end
  end
  for i = #fx.numbers, 1, -1 do
    local n = fx.numbers[i]
    n.age = n.age + dt
    if n.age > 0.9 then table.remove(fx.numbers, i) end
  end
  fx.shake = math.max(0, fx.shake - 40 * dt)
  local k = math.max(0, 1 - 18 * dt)
  fx.kickX, fx.kickY = fx.kickX * k, fx.kickY * k
end

function fx.draw()
  for _, g in ipairs(fx.ghosts) do
    local c = g.color
    love.graphics.setColor(c[1], c[2], c[3], 0.45 * g.life / g.max)
    love.graphics.circle("fill", g.x, g.y, g.r)
  end
  for _, p in ipairs(fx.puffs) do
    if not p.fire and not fx.glowPass then -- smoke would glow grey in the bloom pass
      local t = p.life / p.max
      local g = 1 - (1 - (1 - t)) ^ 2
      local r = p.r0 + (p.r1 - p.r0) * (1 - t * t)
      local a = math.min(1, t * 2.2) * 0.85
      local c = p.color
      love.graphics.setColor(c[1], c[2], c[3], a)
      love.graphics.circle("fill", p.x, p.y, r)
      love.graphics.setColor(c[1] + 0.09, c[2] + 0.09, c[3] + 0.09, a)
      love.graphics.circle("fill", p.x - r * 0.22, p.y - r * 0.26, r * 0.62)
    end
  end
  for _, p in ipairs(fx.puffs) do
    if p.fire then
      local t = p.life / p.max
      local r = p.r0 + (p.r1 - p.r0) * (1 - t)
      if p.hot then love.graphics.setColor(1, 0.95, 0.65, t) else love.graphics.setColor(1, 0.55, 0.15, t) end
      love.graphics.circle("fill", p.x, p.y, r)
    end
  end
  for _, f in ipairs(fx.flashes) do
    local t = f.life / f.max
    love.graphics.push()
    love.graphics.translate(f.x, f.y)
    love.graphics.rotate(f.a)
    love.graphics.scale(f.k * (0.75 + 0.45 * t))
    love.graphics.setColor(1, 0.72, 0.25, t)
    love.graphics.polygon("fill", -4, -6, 30, 0, -4, 6)
    love.graphics.polygon("fill", 0, -13, 8, 0, 0, 13)
    love.graphics.setColor(1, 1, 0.85, t)
    love.graphics.polygon("fill", -2, -3, 18, 0, -2, 3)
    love.graphics.circle("fill", 0, 0, 5)
    love.graphics.pop()
  end
  for _, d in ipairs(fx.chunks) do
    if d.face then
      love.graphics.push()
      love.graphics.translate(d.x, d.y)
      love.graphics.rotate(d.rot)
      love.graphics.setColor(d.color[1], d.color[2], d.color[3], math.min(1, d.life * 2))
      love.graphics.circle("fill", 0, 0, d.face)
      love.graphics.setColor(0.1, 0.1, 0.12, math.min(1, d.life * 2))
      love.graphics.setLineWidth(2)
      for _, s in ipairs({ -1, 1 }) do
        love.graphics.line(s * 4 - 2, -2, s * 4 + 2, 2)
        love.graphics.line(s * 4 + 2, -2, s * 4 - 2, 2)
      end
      love.graphics.pop()
    end
    local c = d.color
    love.graphics.setColor(c[1], c[2], c[3], math.min(1, 2 * d.life / d.max))
    love.graphics.push()
    love.graphics.translate(d.x, d.y)
    love.graphics.rotate(d.rot)
    love.graphics.rectangle("fill", -d.w / 2, -d.h / 2, d.w, d.h)
    love.graphics.pop()
  end
  for _, p in ipairs(fx.particles) do
    local c = p.color
    love.graphics.setColor(c[1], c[2], c[3], p.life / p.max)
    love.graphics.circle("fill", p.x, p.y, p.size * (0.4 + 0.6 * p.life / p.max))
  end
  for _, r in ipairs(fx.rings) do
    local t = 1 - r.life / r.max
    local c = r.color
    love.graphics.setColor(c[1], c[2], c[3], 0.35 * (1 - t))
    love.graphics.circle("fill", r.x, r.y, r.r * (0.4 + 0.6 * t))
    love.graphics.setColor(1, 1, 1, 0.8 * (1 - t))
    love.graphics.setLineWidth(3)
    love.graphics.circle("line", r.x, r.y, r.r * (0.4 + 0.6 * t))
  end
end

-- Damage numbers (drawn above everything in the arena).
function fx.drawNumbers()
  if not fx.showNumbers then return end
  local app = require "core.app"
  for _, n in ipairs(fx.numbers) do
    local t = n.age
    local a = t < 0.6 and 1 or math.max(0, 1 - (t - 0.6) / 0.3)
    local pop = 1 + 0.4 * math.max(0, 1 - t * 8)
    local font = n.crit and app.fonts.title or app.fonts.med
    local text = tostring(math.floor(n.amount + 0.5))
    love.graphics.setFont(font)
    local w = font:getWidth(text)
    local x, y = n.x + n.drift * t, n.y - 30 - 50 * t
    love.graphics.push()
    love.graphics.translate(x, y)
    love.graphics.scale(pop, pop)
    love.graphics.setColor(0, 0, 0, 0.6 * a)
    love.graphics.print(text, -w / 2 + 2, 2)
    if n.crit then love.graphics.setColor(1, 0.85, 0.2, a) else love.graphics.setColor(1, 1, 1, a) end
    love.graphics.print(text, -w / 2, 0)
    love.graphics.pop()
  end
end

return fx
