-- Particles, explosion rings and screen shake.
-- When fx.recorder is a table (online host), every effect is also recorded so it
-- can be replayed on clients.
local fx = {
  particles = {}, rings = {}, ghosts = {}, chunks = {}, shake = 0, kickX = 0, kickY = 0,
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
-- 1 burst, 2 ring, 3 shake, 4 clear, 5 sound (gfx/sfx.lua), 6 spray, 7 ghost, 8 debris, 9 kick.

function fx.burst(x, y, color, count, speed, size)
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
  for i = #fx.chunks, 1, -1 do
    local d = fx.chunks[i]
    d.life = d.life - dt
    if d.life <= 0 then
      table.remove(fx.chunks, i)
    else
      d.vy = d.vy + 1400 * dt
      d.x, d.y = d.x + d.vx * dt, d.y + d.vy * dt
      d.rot = d.rot + d.spin * dt
    end
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
  for _, d in ipairs(fx.chunks) do
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

return fx
