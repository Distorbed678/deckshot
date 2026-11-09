-- What map objects look like. The simulation (game/objects.lua) knows nothing about drawing;
-- this reads the fields it maintains and draws sprites from core/assets.lua.
local Map = require "game.map"
local Objects = require "game.objects"
local Assets = require "core.assets"
local fx = require "gfx.fx"

local View = {}
local g = love.graphics
local DIRS = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

local function white(a) g.setColor(1, 1, 1, a or 1) end

local function flash(o)
  g.setColor(1, 1, 1, 0.55)
  Assets.rect("tile_white", o.x, o.y, o.w, o.h)
end

local CRACKS = { crate = 0.3, brick = 0.25 }

local MATERIAL = {
  stone = function(o)
    local c, e = o.rgb or { 0.35, 0.33, 0.4 }, o.edgeRgb or o.rgb or { 0.6, 0.58, 0.68 }
    g.setColor(c)
    Assets.rect("tile_white", o.x, o.y, o.w, o.h)
    g.setColor(e[1], e[2], e[3], 0.8)
    Assets.rect("tile_white", o.x, o.y, o.w, 3)
  end,
  crate = function(o) Assets.rect("crate", o.x, o.y, o.w, o.h) end,
  brick = function(o) Assets.tile("brick", o.x, o.y, o.w, o.h, 30, 20) end,
  wood = function(o) Assets.rect("wood", o.x, o.y, o.w, o.h) end,
  glass = function(o) Assets.rect("glass", o.x, o.y, o.w, o.h) end,
  metal = function(o) Assets.rect("metal", o.x, o.y, o.w, o.h) end,
  barrel = function(o) Assets.rect("barrel", o.x, o.y, o.w, o.h) end,
  gas = function(o) Assets.rect("gas", o.x, o.y, o.w, o.h) end,
}

local function drawBlock(o)
  if not o.alive then return end
  if o.crumble and o.s == 2 then
    g.setColor(1, 1, 1, 0.06)
    g.rectangle("line", o.x, o.y, o.w, o.h, 3, 3)
    return
  end
  g.push()
  if o.crumble and o.s == 1 then g.translate((love.math.random() - 0.5) * 3, 0) end
  if o.oneway then
    local c, e = o.rgb or { 0.35, 0.33, 0.4 }, o.edgeRgb or { 0.8, 0.5, 0.9 }
    g.setColor(c[1], c[2], c[3], 0.55)
    Assets.rect("tile_white", o.x, o.y, o.w, math.min(o.h, 10))
    g.setColor(e)
    Assets.rect("tile_white", o.x, o.y, o.w, 3)
  else
    if o.material ~= "stone" and o.rgb then g.setColor(o.rgb) else white() end
    ;(MATERIAL[o.material] or MATERIAL.stone)(o)
    local limit = CRACKS[o.material]
    if limit and o.maxHp and 1 - (o.hp or 1) / o.maxHp > limit then
      white(0.9)
      Assets.rect("crack", o.x, o.y, o.w, o.h)
    end
    if (o.hitFlash or 0) > 0 then flash(o) end
  end
  if o.conveyor then
    white()
    local size = math.min(16, o.h - 4)
    local flip = (o.speed or 0) >= 0 and 0 or math.pi
    for i = 0, math.floor(o.w / 20) do
      local x = o.x + ((i * 20 + (o.a or 0)) % o.w)
      Assets.center("arrow", x, o.y + o.h / 2, size, size, flip)
    end
  end
  if o.crumble then
    white(0.8)
    Assets.tile("crack", o.x, o.y, o.w, o.h, math.max(40, o.h * 2), o.h)
  end
  if o.burning then
    g.setColor(0.05, 0.03, 0.02, 0.5)
    Assets.rect("tile_white", o.x, o.y, o.w, o.h)
  end
  g.pop()
end

local function flameAngle(o)
  local d = DIRS[o.dir or "up"] or DIRS.up
  return math.atan2(d[2], d[1]) + (o.rot or 0)
end

local function drawFlame(o)
  g.push()
  g.translate(o.x, o.y)
  g.rotate(flameAngle(o) + math.pi / 2)
  white()
  Assets.center("flame_nozzle", 0, -2, 44, 22)
  local reach = (o.a or 0) > 0 and o.a or o.length
  if o.s == 2 then
    local t = love.timer.getTime()
    local blocked = reach < o.length - 2
    -- Red outer flame through to a white-hot core, each made of flickering tongues.
    local LAYERS = { { 46, 0.95, 0.22, 0.05, 0.6 }, { 30, 1, 0.55, 0.1, 0.85 }, { 15, 1, 0.92, 0.55, 1 } }
    for layer, l in ipairs(LAYERS) do
      g.setColor(l[2], l[3], l[4], l[5])
      local n = 7
      for i = 0, n do
        local f = i / n
        local w = l[1] * (0.7 + 0.55 * math.sin(f * 2.7)) * (blocked and 1 or (1 - f * 0.5))
        local wob = math.sin(t * 26 + i * 1.7 + layer) * (2 + f * 8)
        local h = reach / n * 2.3
        Assets.center("flame_tongue", wob, -12 - reach * f, math.max(4, w + math.sin(t * 31 + i) * 4), h)
      end
    end
    if blocked then
      -- Licks sideways along whatever it hit.
      for side = -1, 1, 2 do
        for i = 1, 4 do
          local f = i / 4
          g.setColor(1, 0.45 + 0.35 * f, 0.1, 0.8 * (1 - f * 0.7))
          Assets.center("flame_tongue", side * (8 + 13 * i + math.sin(t * 20 + i) * 4), -12 - reach + f * 3, 24 * (1.2 - f), 18 * (1.2 - f), side * 1.3)
        end
      end
    end
  elseif o.s == 1 then
    g.setColor(1, 0.5, 0.15, 0.6)
    Assets.center("flame_tongue", 0, -18, 12, 18 + math.sin(love.timer.getTime() * 40) * 4)
  end
  g.pop()
end

local function drawRope(o)
  if not o.alive then return end
  white()
  local pts = o.pts
  if pts and #pts >= 2 then
    local run = {}
    local function flush()
      Assets.strip("rope", run, 5, 16)
      run = {}
    end
    for _, p in ipairs(pts) do
      if p[3] then flush() end
      run[#run + 1] = p[1]
      run[#run + 1] = p[2]
    end
    flush()
  else
    Assets.strip("rope", { o.x, o.y, o.x2 or o.x, o.y2 or o.y }, 5, 16)
  end
  if not o.heldFrom then
    white()
    Assets.center("bolt_steel", o.x, o.y, 12, 12)
  end
end

local D = {}
D.block = drawBlock
D.flame = drawFlame

function D.saw(o) white() Assets.center("saw", o.x, o.y, o.r * 2, o.r * 2, o.a) end

function D.spikes(o)
  local ext = o.s == 2 and 1 or o.s == 1 and 0.25 or (o.on and 0.08 or 1)
  if o.s == 1 then ext = 0.25 + 0.1 * math.sin(love.timer.getTime() * 40) end
  white()
  local dir = o.dir or "up"
  local vertical = dir == "up" or dir == "down"
  local cx, cy = o.x + o.w / 2, o.y + o.h / 2
  local long, deep = vertical and o.w or o.h, vertical and o.h or o.w
  local angle = dir == "down" and math.pi or dir == "left" and -math.pi / 2 or dir == "right" and math.pi / 2 or 0
  g.push()
  g.translate(cx, cy)
  g.rotate(angle)
  g.setColor(0.3, 0.31, 0.36)
  Assets.rect("tile_white", -long / 2, deep / 2 - 4, long, 4)
  white()
  local n = math.max(1, math.floor(long / 16 + 0.5))
  local step = long / n
  for i = 0, n - 1 do Assets.rect("spike", -long / 2 + i * step, deep / 2 - deep * ext, step, deep * ext) end
  g.pop()
end

function D.laser(o)
  local d = DIRS[o.dir] or DIRS.down
  local len = o.a or 0
  local ex, ey = o.x + d[1] * (len + 14), o.y + d[2] * (len + 14)
  if o.s == 1 then
    g.setColor(1, 0.25, 0.25, 0.35 + 0.25 * math.sin(love.timer.getTime() * 30))
    Assets.strip("beam", { o.x, o.y, ex, ey }, 6, 32)
  elseif o.s == 2 then
    g.setColor(1, 0.2, 0.25)
    Assets.strip("beam", { o.x, o.y, ex, ey }, 22, 32)
    g.setColor(1, 0.92, 0.92)
    Assets.strip("beam", { o.x, o.y, ex, ey }, 8, 32)
  end
  white()
  Assets.center("laser_emitter", o.x, o.y, 28, 28)
  g.setColor(o.s == 0 and 0.4 or 1, 0.2, 0.25)
  Assets.center("dot", o.x + d[1] * 8, o.y + d[2] * 8, 12, 12)
end

function D.crusher(o)
  white()
  local top = (o.top or o.y) - 400
  Assets.tile("crusher_shaft", o.x + o.w / 2 - 6, top, 12, o.y - top, 12, 64)
  Assets.rect("crusher_head", o.x, o.y, o.w, o.h)
end

function D.liquid(o)
  local c = o.rgb
  g.setColor(c[1], c[2], c[3], 0.72)
  Assets.rect("tile_white", o.x, o.y + 4, o.w, o.h - 4)
  g.setColor(math.min(1, c[1] + 0.25), math.min(1, c[2] + 0.25), math.min(1, c[3] + 0.25))
  Assets.tile("wave", o.x, o.y - 2, o.w, 14, 64, 14, love.timer.getTime() * 22)
end

function D.turret(o)
  white()
  if not o.alive then
    Assets.center("turret_wreck", o.x, o.y + 11, 36, 14)
    return
  end
  Assets.center("turret_base", o.x, o.y + 11, 36, 14, o.rot)
  if (o.hitFlash or 0) > 0 then g.setColor(1.4, 1.4, 1.4) end
  Assets.center("turret_body", o.x, o.y, 34, 34)
  white()
  g.draw(Assets.image("turret_barrel"), o.x, o.y, o.a, 0.5, 0.5, 0, 10)
  g.setColor(1, o.s == 1 and 0.2 or 0.6, 0.2)
  Assets.center("dot", o.x, o.y, 10, 10)
end

function D.pad(o)
  white()
  local squash = (o.s or 0) * 6
  Assets.rect("pad_base", o.x, o.y + o.h - 5, o.w, 5)
  Assets.rect("pad_top", o.x + 4, o.y + squash, o.w - 8, o.h - 5 - squash)
end

function D.fan(o)
  local d = DIRS[o.dir] or DIRS.up
  g.setColor(0.7, 0.85, 1, 0.05)
  Assets.rect("tile_white", o.x, o.y, o.w, o.h)
  local bx, by = o.x + o.w / 2, o.y + o.h
  if d[2] > 0 then by = o.y elseif d[1] > 0 then bx, by = o.x, o.y + o.h / 2 elseif d[1] < 0 then bx, by = o.x + o.w, o.y + o.h / 2 end
  white()
  Assets.center("fan_housing", bx, by, 44, 44)
  for i = 0, 2 do
    local ang = (o.a or 0) + i * math.pi * 2 / 3
    Assets.center("fan_blade", bx + math.cos(ang) * 10, by + math.sin(ang) * 10, 18, 8, ang)
  end
end

function D.arm(o)
  white()
  local one = o.count == 1
  Assets.tile("arm_beam", one and o.x or (o.x - o.length), o.y - 5, one and o.length or o.length * 2, 10, 32, 10)
  Assets.center("hub", o.x, o.y, 24, 24)
end

function D.rail(o)
  local path = o.path
  if path and #path >= 2 then
    local flat = {}
    for _, p in ipairs(path) do
      flat[#flat + 1] = p[1]
      flat[#flat + 1] = p[2]
    end
    if o.loop then
      flat[#flat + 1] = path[1][1]
      flat[#flat + 1] = path[1][2]
    end
    g.setColor(0.3, 0.32, 0.4, 0.8)
    g.setLineWidth(5)
    g.line(flat)
    g.setColor(0.55, 0.58, 0.68, 0.8)
    g.setLineWidth(1.5)
    g.line(flat)
  end
  white()
  Assets.center("carriage", o.x, o.y, 18, 18)
end

function D.weight(o)
  if not o.alive then return end
  white()
  Assets.center("weight", o.x, o.y, o.r * 2, o.r * 2)
end

local GLOW = {}

function GLOW.flame(o)
  if o.s ~= 2 then return end
  g.push()
  g.translate(o.x, o.y)
  g.rotate(flameAngle(o) + math.pi / 2)
  g.setColor(1, 0.5, 0.1, 0.5)
  Assets.rect("tile_white", -14, -12 - o.a, 28, o.a)
  g.pop()
end

function GLOW.laser(o)
  if o.s ~= 2 then return end
  local d = DIRS[o.dir] or DIRS.down
  local len = o.a or 0
  g.setColor(1, 0.2, 0.25, 0.9)
  Assets.strip("beam", { o.x, o.y, o.x + d[1] * (len + 14), o.y + d[2] * (len + 14) }, 28, 32)
end

function GLOW.pad(o)
  g.setColor(0.35, 0.95, 0.8, 0.4)
  Assets.rect("tile_white", o.x + 4, o.y, o.w - 8, o.h - 5)
end

function GLOW.liquid(o)
  local c = o.rgb
  g.setColor(c[1], c[2], c[3], 0.3)
  Assets.rect("tile_white", o.x, o.y + 4, o.w, o.h - 4)
end

local function centreOf(o)
  if o.w then return o.x + o.w / 2, o.y + o.h / 2 end
  return o.x, o.y
end

-- Draw `fn` turned by the object's angle (turrets, flames and saws turn themselves).
local NO_TURN = { turret = true, flame = true, saw = true }
local function drawTurned(o, fn)
  if o.rot and o.rot ~= 0 and not NO_TURN[o.type] then
    local cx, cy = centreOf(o)
    g.push()
    g.translate(cx, cy)
    g.rotate(o.rot)
    g.translate(-cx, -cy)
    fn(o)
    g.pop()
  else
    fn(o)
  end
end

local function drawAnchor(o)
  local cx, cy = centreOf(o)
  local points
  if o.w and o.h and o.w >= 30 and o.h >= 30 then
    local dx, dy = o.w / 2 - 7, o.h / 2 - 7
    points = { { cx - dx, cy - dy }, { cx + dx, cy - dy }, { cx - dx, cy + dy }, { cx + dx, cy + dy } }
  elseif o.w and o.h and o.w > o.h then
    local dx = o.w / 2 - 8
    points = { { cx - dx, cy }, { cx + dx, cy } }
  elseif o.w and o.h then
    local dy = o.h / 2 - 8
    points = { { cx, cy - dy }, { cx, cy + dy } }
  else
    points = { { cx, cy } }
  end
  local sprite = (o.anchorHp or 0) > 0 and "bolt_orange" or "bolt_steel"
  white()
  for _, p in ipairs(points) do Assets.center(sprite, p[1], p[2], 10, 10) end
end

-- A gas cloud: layered smoke that drifts and curls, and stops at walls.
local function drawCloud(e, t)
  local frac = math.min(1, (e.life or 1) / 1)
  local fade = math.min(1, ((e.max or 4) - (e.life or 0)) * 3 + 0.2) * frac
  local radius = e.radius or 110
  local n = 24
  local reaches = fx.fan(e.x, e.y, radius, n)
  local function offset(ang, d)
    if reaches then
      local i = math.floor((ang % (math.pi * 2)) / (math.pi * 2) * n) % n + 1
      d = math.min(d, math.max(0, reaches[i] - 22))
    end
    return e.x + math.cos(ang) * d, e.y + math.sin(ang) * d
  end
  -- Dark body first, then lighter wisps on top.
  for i = 1, 11 do
    local ang = i * 2.399 + t * 0.25 * (i % 2 == 0 and 1 or -1)
    local d = radius * (0.2 + 0.62 * ((i * 0.618) % 1))
    local x, y = offset(ang, d + math.sin(t * 1.3 + i) * 10)
    local size = radius * (0.85 + 0.25 * math.sin(t * 0.9 + i * 2))
    g.setColor(0.2, 0.36, 0.1, 0.34 * fade)
    Assets.center("puff", x, y, size, size, t * 0.3 + i)
  end
  for i = 1, 9 do
    local ang = i * 1.7 - t * 0.4
    local x, y = offset(ang, radius * (0.1 + 0.55 * ((i * 0.381) % 1)))
    y = y - ((t * 22 + i * 19) % 26)
    local size = radius * (0.42 + 0.14 * math.sin(t * 2 + i))
    g.setColor(0.62, 0.95, 0.28, 0.24 * fade)
    Assets.center("puff", x, y, size, size)
  end
  -- Small bubbles rising through it.
  for i = 1, 5 do
    local life = (t * 0.7 + i * 0.37) % 1
    local x, y = offset(i * 1.25, radius * 0.35 * life + 6)
    g.setColor(0.85, 1, 0.5, 0.5 * (1 - life) * fade)
    Assets.center("dot", x, y - life * 30, 6, 6)
  end
end

function Objects.drawEffect(e)
  local t = love.timer.getTime()
  if e.type == "pickup" then
    local a = (e.life or 8) < 2 and (math.floor(t * 10) % 2 == 0 and 0.4 or 1) or 1
    white(a)
    Assets.center(e.kind == 1 and "pickup_health" or "pickup_ammo", e.x, e.y + math.sin(t * 4) * 3, 26, 26)
  elseif e.type == "strike" then
    local k = 1 - math.max(0, e.life or 0) / (e.max or 0.75)
    g.setColor(0.7, 0.85, 1, 0.15 + 0.35 * k)
    g.circle("fill", e.x, e.y, (e.radius or 55) * k)
    g.setColor(0.85, 0.95, 1, 0.8)
    g.setLineWidth(2)
    g.circle("line", e.x, e.y, e.radius or 55)
    g.line(e.x, e.y - 400, e.x, e.y - 400 + 400 * k)
  elseif e.type == "cloud" then
    drawCloud(e, t)
  end
end

function Objects.draw(list, effects)
  for _, o in ipairs(list) do
    if o.type == "rope" then drawRope(o) end
  end
  for _, o in ipairs(list) do
    local draw = D[o.type]
    if o.type ~= "rope" and draw and (o.alive or o.type == "turret") then drawTurned(o, draw) end
  end
  for _, o in ipairs(list) do
    if o.alive and o.anchored then drawAnchor(o) end
  end
  for _, e in ipairs(effects or {}) do Objects.drawEffect(e) end
end

function Objects.drawGlow(list, effects)
  for _, o in ipairs(list) do
    local glow = GLOW[o.type]
    if o.alive and glow then drawTurned(o, glow) end
  end
  for _, e in ipairs(effects or {}) do
    if e.type == "pickup" then
      g.setColor(e.kind == 1 and 0.4 or 1, e.kind == 1 and 1 or 0.85, e.kind == 1 and 0.5 or 0.3, 0.6)
      Assets.center("dot", e.x, e.y, 28, 28)
    end
  end
end

-- The arena's blocks. map.rects stay plain stone in the map's theme colours.
function Map.draw(map, plain)
  local Atmosphere = require "gfx.atmosphere"
  local t = plain and Atmosphere.themeOf(map) or Atmosphere.draw(map)
  local c, e = t.block, t.edge
  for _, b in ipairs(map.rects) do
    if b.oneway then
      g.setColor(c[1], c[2], c[3], 0.55)
      Assets.rect("tile_white", b.x, b.y, b.w, math.min(b.h, 10))
      g.setColor(e)
      Assets.rect("tile_white", b.x, b.y, b.w, 3)
    else
      g.setColor(c)
      Assets.rect("tile_white", b.x, b.y, b.w, b.h)
      g.setColor(e[1], e[2], e[3], 0.8)
      Assets.rect("tile_white", b.x, b.y, b.w, 3)
    end
  end
end

return View
