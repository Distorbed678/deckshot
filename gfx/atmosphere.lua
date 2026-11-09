-- Map backgrounds: a themed sky and two layers of silhouettes that shift a little with the action,
-- plus a few drifting motes. Maps name a theme with a `theme` line; otherwise it comes from the map's id.
local platform = require "core.platform"

local Atmosphere = { camX = 0, camY = 0 }

local THEMES = {
  foundry = { top = { 0.14, 0.09, 0.09 }, bottom = { 0.26, 0.13, 0.08 }, far = { 0.2, 0.11, 0.09 }, near = { 0.15, 0.09, 0.08 },
    block = { 0.33, 0.28, 0.27 }, edge = { 0.72, 0.45, 0.26 }, mote = { 1, 0.55, 0.2 }, shape = "towers" },
  ice = { top = { 0.08, 0.13, 0.2 }, bottom = { 0.16, 0.27, 0.36 }, far = { 0.13, 0.21, 0.3 }, near = { 0.1, 0.17, 0.25 },
    block = { 0.31, 0.38, 0.47 }, edge = { 0.72, 0.9, 1 }, mote = { 0.85, 0.95, 1 }, shape = "peaks" },
  neon = { top = { 0.07, 0.05, 0.16 }, bottom = { 0.2, 0.08, 0.3 }, far = { 0.13, 0.08, 0.26 }, near = { 0.09, 0.06, 0.18 },
    block = { 0.27, 0.25, 0.42 }, edge = { 0.95, 0.4, 0.9 }, mote = { 0.4, 0.9, 1 }, shape = "towers" },
  jungle = { top = { 0.07, 0.14, 0.11 }, bottom = { 0.13, 0.26, 0.16 }, far = { 0.1, 0.21, 0.14 }, near = { 0.07, 0.16, 0.11 },
    block = { 0.3, 0.33, 0.27 }, edge = { 0.55, 0.8, 0.35 }, mote = { 0.8, 1, 0.45 }, shape = "hills" },
  void = { top = { 0.05, 0.05, 0.09 }, bottom = { 0.11, 0.1, 0.18 }, far = { 0.09, 0.08, 0.15 }, near = { 0.07, 0.06, 0.12 },
    block = { 0.3, 0.31, 0.38 }, edge = { 0.62, 0.64, 0.82 }, mote = { 0.7, 0.65, 1 }, shape = "peaks" },
  desert = { top = { 0.2, 0.13, 0.13 }, bottom = { 0.42, 0.26, 0.16 }, far = { 0.33, 0.2, 0.15 }, near = { 0.26, 0.16, 0.13 },
    block = { 0.42, 0.34, 0.27 }, edge = { 0.9, 0.7, 0.42 }, mote = { 1, 0.85, 0.55 }, shape = "hills" },
}
Atmosphere.NAMES = { "foundry", "ice", "neon", "jungle", "void", "desert" }

local function hash(s)
  local h = 7
  for i = 1, #s do h = (h * 31 + s:byte(i)) % 1000003 end
  return h
end

function Atmosphere.themeOf(map)
  if map.theme and THEMES[map.theme] then return THEMES[map.theme], map.theme end
  local name = Atmosphere.NAMES[hash(map.id or map.name or "x") % #Atmosphere.NAMES + 1]
  return THEMES[name], name
end

-- A row of silhouettes across the width, as one polygon strip per shape.
local function drawLayer(shape, seed, base, height, color)
  local rng = love.math.newRandomGenerator(seed)
  love.graphics.setColor(color)
  local W, H = 1600, 900
  local x = -40
  while x < W do
    if shape == "towers" then
      local w = rng:random(50, 130)
      local h = base + rng:random(0, height)
      love.graphics.rectangle("fill", x, H - h, w, h)
      if rng:random() < 0.4 then love.graphics.rectangle("fill", x + w * 0.4, H - h - 40, 8, 40) end
      x = x + w + rng:random(4, 40)
    elseif shape == "peaks" then
      local w = rng:random(140, 300)
      local h = base + rng:random(0, height)
      love.graphics.polygon("fill", x, H, x + w * rng:random(), H - h, x + w, H)
      x = x + w * 0.55
    else
      local w = rng:random(200, 380)
      local h = base + rng:random(0, height)
      love.graphics.ellipse("fill", x + w / 2, H, w * 0.7, h)
      x = x + w * 0.5
    end
  end
end

local cache = {}

local function bake(name, t)
  local c = cache[name]
  if c then return c end
  c = { far = love.graphics.newCanvas(800, 450, { format = platform.canvasFormat() }), near = (not platform.web) and love.graphics.newCanvas(800, 450) or nil }
  love.graphics.push("all")
  love.graphics.origin()
  love.graphics.setScissor()
  local seed = hash(name)
  love.graphics.setCanvas(c.far)
  love.graphics.clear(t.top[1], t.top[2], t.top[3], 1)
  love.graphics.scale(0.5)
  local N = 24
  for i = 0, N - 1 do
    local k = i / (N - 1)
    love.graphics.setColor(t.top[1] + (t.bottom[1] - t.top[1]) * k, t.top[2] + (t.bottom[2] - t.top[2]) * k,
      t.top[3] + (t.bottom[3] - t.top[3]) * k)
    love.graphics.rectangle("fill", 0, 900 * i / N, 1600, 900 / N + 1)
  end
  drawLayer(t.shape, seed, 220, 280, t.far)
  if c.near then
    love.graphics.origin()
    love.graphics.setCanvas(c.near)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.scale(0.5)
    drawLayer(t.shape, seed + 17, 90, 170, t.near)
  else
    drawLayer(t.shape, seed + 17, 90, 170, t.near)
  end
  love.graphics.pop()
  cache[name] = c
  return c
end

-- Behind everything, in world coordinates.
function Atmosphere.draw(map)
  local t, name = Atmosphere.themeOf(map)
  local c = bake(name, t)
  local Map = require "game.map"
  love.graphics.setColor(1, 1, 1)
  local ox, oy = -32 - Atmosphere.camX * 8, -18 - Atmosphere.camY * 4
  love.graphics.setBlendMode("alpha", "premultiplied")
  love.graphics.draw(c.far, ox, oy, 0, (Map.W + 64) / 800, (Map.H + 36) / 450)
  love.graphics.setBlendMode("alpha")
  if c.near then
    love.graphics.draw(c.near, ox - Atmosphere.camX * 14, oy - Atmosphere.camY * 6, 0, (Map.W + 64) / 800, (Map.H + 36) / 450)
  end
  -- Drifting motes.
  local now = love.timer.getTime()
  local m = t.mote
  for i = 1, platform.web and 10 or 26 do
    local sp = 8 + (i * 7) % 18
    local x = ((i * 197.3 + now * sp) % (Map.W + 40)) - 20
    local y = (i * 83.7 + math.sin(now * 0.4 + i) * 40 - now * sp * 0.4) % Map.H
    love.graphics.setColor(m[1], m[2], m[3], 0.08 + 0.1 * (0.5 + 0.5 * math.sin(now * 1.5 + i)))
    love.graphics.circle("fill", x, y, 1.5 + i % 3)
  end
  return t
end

return Atmosphere
