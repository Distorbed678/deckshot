-- Drawing for the v0.7 cards (game/abilities.lua): their arena effects, special bullets, statuses
-- on players, shield drones. Nothing here allocates per frame.
local Assets = require "core.assets"

local V = {}
local g = love.graphics

local function ownerColor(e)
  if e.owner and e.owner.color then return e.owner.color end
  local World = require "game.world"
  return World.COLORS[e.kind or 0] or { 1, 1, 1 }
end

local quad = { 0, 0, 0, 0, 0, 0, 0, 0 } -- reused polygon points

---------------------------------------------------------------- bullets
function V.drawBullet(b)
  local t = love.timer.getTime()
  local c = b.color or { 1, 1, 1 }
  if b.isGun then
    -- Gun Toss: the spinning pistol.
    g.push()
    g.translate(b.x, b.y)
    g.rotate(t * 18)
    g.setColor(0.25, 0.26, 0.3)
    g.rectangle("fill", -12, -4, 24, 8, 2, 2)
    g.rectangle("fill", -12, 0, 8, 12, 2, 2)
    g.setColor(c[1], c[2], c[3])
    g.rectangle("fill", 4, -3, 8, 3)
    g.pop()
  elseif b.grenade or b.grenadeT then
    g.setColor(0.18, 0.19, 0.22)
    g.circle("fill", b.x, b.y, b.r + 2)
    local blink = math.floor(t * 10) % 2 == 0
    g.setColor(c[1], c[2], c[3], blink and 1 or 0.4)
    g.setLineWidth(2)
    g.circle("line", b.x, b.y, b.r + 2)
    g.circle("fill", b.x, b.y - b.r * 0.4, 2.5)
  elseif b.isBee then
    local flap = math.sin(t * 50) * 3
    g.setColor(1, 1, 1, 0.6)
    g.ellipse("fill", b.x - 3, b.y - 3, 3, 2 + flap * 0.3)
    g.ellipse("fill", b.x + 3, b.y - 3, 3, 2 - flap * 0.3)
    g.setColor(1, 0.85, 0.2)
    g.circle("fill", b.x, b.y, 4)
    g.setColor(0.15, 0.12, 0.1)
    g.rectangle("fill", b.x - 1, b.y - 4, 2, 8)
  elseif b.gravOrb then
    g.setColor(0.55, 0.35, 0.95, 0.35)
    g.circle("fill", b.x, b.y, b.r + 8)
    g.setColor(0.1, 0.05, 0.18)
    g.circle("fill", b.x, b.y, b.r)
    g.setColor(0.75, 0.6, 1)
    g.setLineWidth(2)
    g.arc("line", "open", b.x, b.y, b.r + 3, t * 6, t * 6 + 3.5, 10)
  end
end

---------------------------------------------------------------- arena effects
-- Returns true when it drew e.
function V.drawEffect(e)
  local t = love.timer.getTime()
  local k = math.max(0, (e.life or 0) / math.max(0.01, e.max or 1))
  local c = ownerColor(e)
  local typ = e.type
  if typ == "ward" then
    g.setColor(c[1], c[2], c[3], 0.08 + 0.1 * k)
    g.circle("fill", e.x, e.y, e.radius)
    g.setColor(0.85, 0.92, 1, 0.35 + 0.4 * k)
    g.setLineWidth(3)
    g.circle("line", e.x, e.y, e.radius + math.sin(t * 6) * 1.5)
  elseif typ == "fire" then
    local flick = 0.7 + 0.3 * math.sin(t * 30 + e.x)
    g.setColor(1, 0.45, 0.1, 0.45 * k * flick)
    g.circle("fill", e.x, e.y, e.radius * (0.6 + 0.4 * k))
    g.setColor(1, 0.85, 0.35, 0.6 * k * flick)
    g.circle("fill", e.x, e.y - 4, e.radius * 0.4)
  elseif typ == "trap" then
    g.setColor(0.35, 0.36, 0.4)
    g.rectangle("fill", e.x - 18, e.y + 2, 36, 5, 2, 2)
    g.setColor(c[1], c[2], c[3])
    for i = -2, 2 do
      quad[1], quad[2] = e.x + i * 7 - 3, e.y + 3
      quad[3], quad[4] = e.x + i * 7, e.y - 7
      quad[5], quad[6] = e.x + i * 7 + 3, e.y + 3
      g.polygon("fill", quad[1], quad[2], quad[3], quad[4], quad[5], quad[6])
    end
  elseif typ == "icewall" then
    local h = e.radius or 96
    g.setColor(0.7, 0.9, 1, 0.85)
    g.rectangle("fill", e.x - 12, e.y - h / 2, 24, h, 4, 4)
    g.setColor(1, 1, 1, 0.6)
    g.setLineWidth(2)
    g.rectangle("line", e.x - 12, e.y - h / 2, 24, h, 4, 4)
    g.line(e.x - 6, e.y - h / 2 + 10, e.x + 4, e.y - h / 2 + 30)
  elseif typ == "totem" then
    g.setColor(c[1], c[2], c[3], 0.08)
    g.circle("fill", e.x, e.y, e.radius)
    g.setColor(0.35, 0.28, 0.22)
    g.rectangle("fill", e.x - 7, e.y - 22, 14, 42, 3, 3)
    g.setColor(c[1], c[2], c[3])
    g.circle("fill", e.x, e.y - 26, 8 + math.sin(t * 4) * 1.5)
  elseif typ == "turret" then
    g.setColor(0.3, 0.31, 0.35)
    g.rectangle("fill", e.x - 3, e.y, 6, 26)
    g.setColor(0.16, 0.17, 0.2)
    g.circle("fill", e.x, e.y, 11)
    g.setColor(c[1], c[2], c[3])
    g.setLineWidth(2.5)
    g.circle("line", e.x, e.y, 11)
    g.circle("fill", e.x, e.y, 4)
  elseif typ == "charge" then
    local blink = math.floor(t * (4 + 8 * (1 - k))) % 2 == 0
    g.setColor(0.2, 0.2, 0.24)
    g.circle("fill", e.x, e.y, 7)
    g.setColor(c[1], c[2], c[3], blink and 1 or 0.35)
    g.circle("fill", e.x, e.y, 3.5)
    g.setLineWidth(1.5)
    g.circle("line", e.x, e.y, 10)
  elseif typ == "magnet" then
    g.setColor(c[1], c[2], c[3], 0.12)
    g.circle("fill", e.x, e.y, (e.radius or 160) * (0.4 + 0.6 * k))
    g.setColor(0.3, 0.3, 0.36)
    g.circle("fill", e.x, e.y, 8)
    g.setColor(c[1], c[2], c[3])
    g.setLineWidth(2)
    g.arc("line", "open", e.x, e.y, 11, -t * 5, -t * 5 + 4, 8)
  elseif typ == "decoy" then
    g.setColor(c[1], c[2], c[3], 0.35 + 0.2 * math.sin(t * 10))
    Assets.center("dot", e.x, e.y, (e.radius or 20) * 2, (e.radius or 20) * 2)
    g.setColor(1, 1, 1, 0.5)
    g.setLineWidth(2)
    g.circle("line", e.x, e.y, (e.radius or 20) + 2)
  else
    return false
  end
  return true
end

---------------------------------------------------------------- players
-- Statuses and drones around player p (drawn over the body). A: alpha.
function V.drawPlayer(p, A)
  local t = love.timer.getTime()
  local r = p.r
  local burning = p.burning or (p.burnT or 0) > 0
  local shocked = p.shocked or (p.shockT or 0) > 0
  local frozen = p.frozen or (p.freezeT or 0) > 0
  local bleeding = p.bleeding or (p.bleedT or 0) > 0
  if burning then
    for i = 0, 2 do
      local a = t * 9 + i * 2.1
      local fx_, fy = p.x + math.sin(a) * r * 0.6, p.y - r * 0.6 - (t * 60 + i * 20) % 22
      g.setColor(1, 0.5, 0.12, 0.7 * A)
      g.circle("fill", fx_, fy, 4)
      g.setColor(1, 0.9, 0.4, 0.8 * A)
      g.circle("fill", fx_, fy + 1, 2)
    end
  end
  if shocked then
    g.setColor(0.65, 0.88, 1, 0.9 * A)
    g.setLineWidth(1.5)
    local seed = math.floor(t * 20)
    for i = 0, 2 do
      local a = ((seed * 37 + i * 101) % 628) / 100
      local x1, y1 = p.x + math.cos(a) * r, p.y + math.sin(a) * r
      g.line(x1, y1, x1 + math.cos(a + 0.6) * 8, y1 + math.sin(a + 0.6) * 8, x1 + math.cos(a - 0.3) * 13, y1 + math.sin(a - 0.3) * 13)
    end
  end
  if frozen then
    g.setColor(0.75, 0.92, 1, 0.55 * A)
    g.rectangle("fill", p.x - r - 4, p.y - r - 4, (r + 4) * 2, (r + 4) * 2 + p.leg, 6, 6)
    g.setColor(1, 1, 1, 0.7 * A)
    g.setLineWidth(2)
    g.rectangle("line", p.x - r - 4, p.y - r - 4, (r + 4) * 2, (r + 4) * 2 + p.leg, 6, 6)
  end
  if bleeding then
    g.setColor(0.8, 0.08, 0.12, 0.8 * A)
    local y = p.y + r * 0.2 + (t * 70) % 26
    g.circle("fill", p.x + r * 0.35, y, 2.5)
  end
  -- Shield drones.
  local drones = p.stats and p.stats.drones or 0
  if drones > 0 and not p.dead then
    local Abilities = require "game.abilities"
    local c = p.color
    for i = 1, drones do
      local dx, dy = Abilities.dronePos(p, i)
      local ready = not p.droneCd or (p.droneCd[i] or 0) <= 0
      g.setColor(0.2, 0.21, 0.25, A)
      g.circle("fill", dx, dy, 6)
      g.setColor(c[1], c[2], c[3], (ready and 1 or 0.35) * A)
      g.setLineWidth(2)
      g.circle("line", dx, dy, 8)
    end
  end
end

return V
