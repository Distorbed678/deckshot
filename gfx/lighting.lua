-- Dynamic lighting: the scene is multiplied by a light map. Each light is a fan of Box2D rays,
-- so solid things cast real shadows. Only drawn when the setting is on.
local Physics = require "game.physics"
local fx = require "gfx.fx"
local Platform = require "core.platform"

local Lighting = { ambient = 0.74 }

local canvas, cw, ch

local function ensureCanvas(w, h)
  if canvas and cw == w and ch == h then return end
  cw, ch = w, h
  canvas = love.graphics.newCanvas(w, h, { format = Platform.canvasFormat() })
end

local RAYS = 40

-- One mesh and its vertex tables serve every light; the ray directions never change.
local lightMesh, lightVerts, lightReach = nil, {}, {}
local COS, SIN = {}, {}
for i = 0, RAYS do
  local ang = (i % RAYS) / RAYS * math.pi * 2
  COS[i], SIN[i] = math.cos(ang), math.sin(ang)
  lightVerts[i + 2] = { 0, 0, 0, 0, 0, 0, 0, 1 }
end
lightVerts[1] = { 0, 0, 0.5, 0.5, 0, 0, 0, 1 }

-- Fills the light map with one light; brightest in the middle, nothing at its edge.
local function drawLight(world, x, y, radius, r, g, b, a)
  local reaches = world and world.physics and Physics.fan(world, x, y, radius, RAYS, lightReach)
  local v = lightVerts[1]
  v[1], v[2], v[5], v[6], v[7] = x, y, r * a, g * a, b * a
  for i = 0, RAYS do
    local d = reaches and math.min(radius, reaches[(i % RAYS) + 1]) or radius
    local fade = 1 - d / radius
    v = lightVerts[i + 2]
    v[1], v[2], v[5], v[6], v[7] = x + COS[i] * d, y + SIN[i] * d, r * a * fade, g * a * fade, b * a * fade
  end
  if not lightMesh then lightMesh = love.graphics.newMesh(lightVerts, "fan", "stream") end
  lightMesh:setVertices(lightVerts)
  love.graphics.draw(lightMesh)
end

local lightList = {}

-- Everything that gives off light this frame.
local function collect(players, objs, effects)
  local out, n = lightList, 0
  local function add(x, y, radius, r, g, b, a)
    n = n + 1
    local l = out[n]
    if not l then l = {}; out[n] = l end
    l[1], l[2], l[3], l[4], l[5], l[6], l[7] = x, y, radius, r, g, b, a
  end
  for _, p in ipairs(players) do
    if not p.dead then
      local c = p.color
      add(p.x, p.y, 260, 0.6 + c[1] * 0.4, 0.6 + c[2] * 0.4, 0.6 + c[3] * 0.4, 0.75)
    end
  end
  for _, o in ipairs(objs) do
    if o.alive and o.type == "flame" and o.s == 2 then
      local a = (o.rot or 0)
      local dx, dy = 0, -1
      if o.dir == "down" then dy = 1 elseif o.dir == "left" then dx, dy = -1, 0 elseif o.dir == "right" then dx, dy = 1, 0 end
      local c, s = math.cos(a), math.sin(a)
      local mid = (o.a or 0) * 0.55
      add(o.x + (dx * c - dy * s) * mid, o.y + (dx * s + dy * c) * mid, 340, 1, 0.55, 0.2, 1)
    elseif o.alive and o.type == "laser" and o.s == 2 then
      add(o.x, o.y, 180, 1, 0.25, 0.3, 0.8)
    elseif o.alive and o.type == "liquid" and (o.damage or 0) > 0 then
      add(o.x + o.w / 2, o.y, math.max(180, o.w * 0.6), o.rgb[1], o.rgb[2], o.rgb[3], 0.5)
    end
  end
  for _, ring in ipairs(fx.rings) do
    local k = ring.life / ring.max
    add(ring.x, ring.y, ring.r * 2.4, ring.color[1], ring.color[2], ring.color[3], k)
  end
  for _, e in ipairs(effects or {}) do
    if e.type == "pickup" then add(e.x, e.y, 120, 0.9, 0.9, 0.7, 0.5) end
  end
  out.n = n
  return out
end

-- Call inside the world's transform with the scene already drawn to the target canvas.
function Lighting.draw(world, target, players, objs, effects, sx, sy, scale)
  local w, h = target:getDimensions()
  local ratio = w / (require("core.app").W or w)
  ensureCanvas(w, h)
  love.graphics.push("all")
  love.graphics.origin()
  love.graphics.setCanvas(canvas)
  local a = Lighting.ambient
  love.graphics.clear(a, a, a * 1.05, 1)
  love.graphics.setBlendMode("add", "premultiplied")
  love.graphics.scale(ratio, ratio)
  love.graphics.translate(sx, sy)
  love.graphics.scale(scale)
  local lights = collect(players, objs, effects)
  for i = 1, lights.n do
    local l = lights[i]
    drawLight(world, l[1], l[2], l[3], l[4], l[5], l[6], l[7])
  end
  love.graphics.setCanvas(target)
  love.graphics.origin()
  love.graphics.setBlendMode("multiply", "premultiplied")
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(canvas)
  love.graphics.pop()
end

return Lighting
