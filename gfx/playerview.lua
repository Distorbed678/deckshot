-- How players look. The simulation is in game/player.lua.
local Assets = require "core.assets"
local Player = require "game.player"
local Body = require "game.body"
local Map = require "game.map"
local fx = require "gfx.fx"
local Cosmetics = require "core.cosmetics"
local MELEE = Player.MELEE
local ORB_SIZE = Player.ORB_SIZE

function Player:drawGlow()
  if self.dead then return end
  local A = self.cloakTimer > 0 and 0.08 or 1
  local c = self.color
  love.graphics.setColor(c[1], c[2], c[3], 0.45 * A)
  Assets.center("dot", self.x, self.y, (self.r) * 2, (self.r) * 2)
  if self:isBlocking() then
    love.graphics.setColor(1, 1, 1, 0.6)
    love.graphics.setLineWidth(4)
    love.graphics.circle("line", self.x, self.y, (self.r + 14) * ((self.stats and self.stats.blockSize) or 1))
  end
  if self.empowered then
    love.graphics.setColor(1, 0.9, 0.5, 0.8 * A)
    Assets.center("dot", self.x + self.aimX * (self.r + 12), self.y + self.aimY * (self.r + 12), (6) * 2, (6) * 2)
  end
  for i = 1, self.stats.orbs do
    local ox, oy = self:orbPos(i)
    love.graphics.setColor(c[1], c[2], c[3], 0.9)
    Assets.center("orb", ox, oy, (ORB_SIZE) * 2, (ORB_SIZE) * 2)
  end
end

-- Melee charge ring, swing arc and stun stars.
function Player:drawMelee(A)
  local r, c = self.r, self.color
  local aim = math.atan2(self.aimY, self.aimX)
  if self.charging and (self.meleeCharge or 0) > MELEE.lightThreshold then
    local p = math.min(1, (self.meleeCharge - MELEE.lightThreshold) / math.max(0.05, self.stats.heavyCharge or 0.6))
    love.graphics.setColor(1, 1, 1, 0.25 * A)
    love.graphics.setLineWidth(3)
    love.graphics.circle("line", self.x, self.y, r + 10)
    love.graphics.setColor(1, p >= 1 and 0.85 or 1, p >= 1 and 0.3 or 1, 0.9 * A)
    love.graphics.arc("line", "open", self.x, self.y, r + 10, -math.pi / 2, -math.pi / 2 + math.pi * 2 * p)
  end
  if (self.swingTimer or 0) > 0 then
    local t = self.swingTimer / (MELEE.swingShow + (self.swingHeavy and MELEE.lungeTime or 0))
    local reach = r + (self.stats.meleeRange or 55) * (self.swingHeavy and 1.2 or 1)
    local spread = MELEE.cone
    local sweep = aim - spread + (1 - t) * spread * 2
    love.graphics.setColor(1, 1, 1, 0.55 * t * A)
    love.graphics.setLineWidth(self.swingHeavy and 8 or 5)
    love.graphics.arc("line", "open", self.x, self.y, reach, aim - spread, sweep)
    love.graphics.setColor(c[1], c[2], c[3], 0.35 * t * A)
    love.graphics.arc("fill", self.x, self.y, reach, aim - spread, sweep)
  end
  if (self.stunTimer or 0) > 0 then
    local t = love.timer.getTime()
    love.graphics.setColor(1, 0.95, 0.4, A)
    for i = 1, 3 do
      local a = t * 5 + i * math.pi * 2 / 3
      Assets.center("dot", self.x + math.cos(a) * r * 0.9, self.y - r - 8 + math.sin(a) * 4, (3) * 2, (3) * 2)
    end
  end
end

function Player:draw()
  if self.dead then return end
  local r, s = self.r, self.stats
  local c = self.color

  local A = 1
  if self.cloakTimer > 0 then
    A = 0.12
  elseif self.invuln > 0 and math.floor(self.invuln * 15) % 2 == 0 then
    A = 0.4
  end

  if s.stasis > 0 then
    local sr = Player.stasisRadius(s.stasis)
    local Fx = require "gfx.fx"
    local reaches = Fx.fan(self.x, self.y, sr)
    love.graphics.setColor(0.6, 0.8, 1, 0.06 * A)
    Fx.drawReach("fill", self.x, self.y, sr, reaches)
    love.graphics.setColor(0.6, 0.8, 1, 0.3 * A)
    love.graphics.setLineWidth(1.5)
    Fx.drawReach("line", self.x, self.y, sr, reaches)
  end

  if self.isJugg then
    love.graphics.setColor(1, 0.75, 0.15, 0.22 * A)
    Assets.center("dot", self.x, self.y, (r + 11) * 2, (r + 11) * 2)
    love.graphics.setColor(1, 0.8, 0.2, A)
    local cy, cw = self.y - r - 6, r * 0.75
    love.graphics.polygon("fill", self.x - cw, cy, self.x - cw, cy - 10, self.x - cw * 0.45, cy - 5, self.x, cy - 13,
      self.x + cw * 0.45, cy - 5, self.x + cw, cy - 10, self.x + cw, cy)
  end

  if self:isBlocking() then
    local br = (r + 14) * (s.blockSize or 1) -- Fortress: a bigger block
    love.graphics.setColor(1, 1, 1, 0.3)
    Assets.center("dot", self.x, self.y, br * 2, br * 2)
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.setLineWidth(3)
    love.graphics.circle("line", self.x, self.y, br)
  end

  -- Shield Generator bubble
  if (self.shield or 0) > 0 then
    love.graphics.setColor(0.5, 0.8, 1, (0.25 + 0.35 * math.min(1, self.shield / 60)) * A)
    love.graphics.setLineWidth(2)
    love.graphics.circle("line", self.x, self.y, r + 5)
  end

  -- Stillness: a ring fills while you stand still; when it's full a star glints on the muzzle.
  local still = self.stillK or 0
  if (s.stillness or 0) > 0 and still > 0 and not self.dead then
    local gold = { 1, 0.85, 0.35 }
    love.graphics.setLineWidth(3)
    love.graphics.setColor(gold[1], gold[2], gold[3], 0.25 * A)
    love.graphics.circle("line", self.x, self.y, r + 12)
    love.graphics.setColor(gold[1], gold[2], gold[3], 0.9 * A)
    love.graphics.arc("line", "open", self.x, self.y, r + 12, -math.pi / 2, -math.pi / 2 + math.pi * 2 * still, 32)
    if still >= 1 then
      local md = Body.muzzleDist(self)
      local mx, my = self.x + (self.aimX or 1) * md, self.y + (self.aimY or 0) * md
      local t = love.timer.getTime()
      local size = 9 + 3 * math.sin(t * 9)
      local rot = t * 1.5
      -- A four-point star: two thin crossed diamonds (fill only works on convex shapes).
      local pts = self.starPts or {}
      self.starPts = pts
      love.graphics.setColor(1, 0.97, 0.8, A)
      for arm = 0, 1 do
        local a = rot + arm * math.pi / 2
        local ca, sa = math.cos(a), math.sin(a)
        local w = size * 0.22
        pts[1], pts[2] = mx + ca * size, my + sa * size
        pts[3], pts[4] = mx - sa * w, my + ca * w
        pts[5], pts[6] = mx - ca * size, my - sa * size
        pts[7], pts[8] = mx + sa * w, my - ca * w
        love.graphics.polygon("fill", pts)
      end
    end
  end

  -- Homing cone: the arc ahead of the gun that homing bullets look in, faint, for everyone to see.
  if ((s.homing or 0) > 0 or (s.seek or 0) > 0) and not self.dead then
    local Bullet = require "game.bullet"
    local aim = math.atan2(self.aimY or 0, self.aimX or 1)
    local half = Bullet.HOMING_CONE / 2
    local reach = 260
    local gx, gy = self.x + (self.aimX or 1) * (r + 10), self.y + (self.aimY or 0) * (r + 10)
    love.graphics.setColor(c[1], c[2], c[3], 0.07 * A)
    love.graphics.arc("fill", gx, gy, reach, aim - half, aim + half, 16)
    love.graphics.setColor(c[1], c[2], c[3], 0.22 * A)
    love.graphics.setLineWidth(1.5)
    love.graphics.arc("line", "open", gx, gy, reach, aim - half, aim + half, 16)
  end

  -- Turret Buddy: round turrets floating above, each aiming its barrel at the nearest enemy.
  local turrets = s.sentry or 0
  if turrets > 0 and not self.dead then
    local game = self.game
    for i = 1, turrets do
      local sx, sy = self:sentryPos(i, turrets)
      local aim = math.atan2(self.aimY or 0, self.aimX or 1)
      local foe = game and game.nearestEnemy and game:nearestEnemy(self, sx, sy, true)
      if foe then aim = math.atan2(foe.y - sy, foe.x - sx) end
      love.graphics.push()
      love.graphics.translate(sx, sy)
      love.graphics.rotate(aim)
      love.graphics.setColor(0.2, 0.21, 0.25, A)
      love.graphics.rectangle("fill", 2, -3, 15, 6, 2, 2)
      love.graphics.setColor(0.45, 0.47, 0.52, A)
      love.graphics.rectangle("fill", 13, -3.5, 4, 7, 1, 1)
      love.graphics.pop()
      love.graphics.setColor(0.16, 0.17, 0.2, A)
      love.graphics.circle("fill", sx, sy, 9)
      love.graphics.setColor(c[1], c[2], c[3], A)
      love.graphics.setLineWidth(2.5)
      love.graphics.circle("line", sx, sy, 9)
      love.graphics.circle("fill", sx, sy, 3.5)
    end
  end

  for i = 1, s.orbs do
    local ox, oy = self:orbPos(i)
    love.graphics.setColor(1, 1, 1, 0.9)
    Assets.center("orb", ox, oy, (ORB_SIZE + 1.5) * 2, (ORB_SIZE + 1.5) * 2)
    love.graphics.setColor(c)
    Assets.center("orb", ox, oy, (ORB_SIZE) * 2, (ORB_SIZE) * 2)
  end

  self:drawMelee(A)

  Body.update(self, love.timer.getDelta())
  Body.drawLegs(self, A)

  -- Body
  if self.hitFlash > 0 then
    love.graphics.setColor(1, 1, 1, A)
  elseif self.poisonTimer > 0 then
    love.graphics.setColor(c[1] * 0.6 + 0.16, c[2] * 0.6 + 0.36, c[3] * 0.6 + 0.08, A)
  elseif self.slowTimer > 0 then
    love.graphics.setColor(c[1] * 0.5 + 0.3, c[2] * 0.5 + 0.4, c[3] * 0.5 + 0.5, A)
  else
    love.graphics.setColor(c[1], c[2], c[3], A)
  end
  -- Squash and stretch: stretched while moving fast vertically, squashed on landing.
  local sx, sy, by0 = 1, 1, self.y
  love.graphics.ellipse("fill", self.x, by0, r * sx, r * sy)
  if self.slowTimer > 0 then
    love.graphics.setColor(0.7, 0.9, 1, 0.7 * A)
    love.graphics.setLineWidth(2)
    love.graphics.circle("line", self.x, self.y, r + 2)
  end

  -- Face and hat. The eyes follow your aim, blink, and react to shooting and getting hurt.
  local blink = (love.timer.getTime() * 0.31 + (self.slot or 1) * 0.37) % 1 < 0.045
  local lookY = self.aimY + ((self.vy or 0) < -250 and -0.4 or (self.vy or 0) > 350 and 0.4 or 0)
  Cosmetics.drawFace(self.x + self.facing * r * 0.14, by0 - r * 0.22 * sy, r,
    { self.aimX, math.max(-1, math.min(1, lookY)) },
    { blink = blink, hurt = self.hitFlash > 0, firing = (self.shotT or 0) > 0, expr = Body.expression(self) }, A,
    self.eyes, self.mouth, self.detail)
  if A > 0.3 then Cosmetics.drawHat(self.x, by0 - r * 0.92 * sy, r, self.hat, c) end
  Body.drawArms(self, A)
  require("gfx.abilityview").drawPlayer(self, A) -- statuses and drones from the v0.7 cards

  -- HP bar (pending Decay damage shown faded)
  local pending = 0
  for _, d in ipairs(self.decay) do pending = pending + d.remaining end
  local bw, bx, by = 56, self.x - 28, self.y - r - 18
  local hpFrac = math.max(0, self.hp) / s.maxHp
  local solidFrac = math.max(0, self.hp - pending) / s.maxHp
  love.graphics.setColor(0, 0, 0, 0.6 * A)
  Assets.rect("tile_white", bx - 1, by - 1, bw + 2, 8)
  love.graphics.setColor(c[1], c[2], c[3], 0.35 * A)
  Assets.rect("tile_white", bx, by, bw * hpFrac, 6)
  love.graphics.setColor(c[1], c[2], c[3], A)
  Assets.rect("tile_white", bx, by, bw * solidFrac, 6)

  -- Phoenix lives
  for i = 1, self.livesLeft do
    love.graphics.setColor(1, 0.6, 0.15, A)
    Assets.center("dot", bx + bw + 4 + i * 8, by + 3, (3) * 2, (3) * 2)
  end

  -- Ammo pips, or a reload bar while reloading from empty
  local py = by - 8
  if self.ammo == 0 and self.reloadTimer > 0 then
    love.graphics.setColor(1, 1, 1, 0.8 * A)
    Assets.rect("tile_white", bx, py - 1, bw * (1 - self.reloadTimer / s.reloadTime), 3)
  else
    local slots = math.max(s.ammo, self.ammo) -- Supply Drop can overfill
    local spacing = math.min(9, bw / math.max(1, slots))
    local startX = self.x - (slots - 1) * spacing / 2
    for i = 1, slots do
      love.graphics.setColor(1, 1, 1, (i <= self.ammo and 0.9 or 0.2) * A)
      Assets.center("dot", startX + (i - 1) * spacing, py, (2.5) * 2, (2.5) * 2)
    end
  end

  if Body.showNames and A > 0.3 then
    local font = require("core.app").fonts.small
    love.graphics.setFont(font)
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.printf(self.name or "", self.x - 90, py - 8 - font:getHeight(), 180, "center")
    if Body.speakingSlot and Body.speakingSlot(self) then
      require("online.voice").drawIcon(self.x + font:getWidth(self.name or "") / 2 + 14, py - 8 - font:getHeight() / 2)
    end
  end
end


-- Upside Down: the whole figure is drawn mirrored top to bottom while gravity is flipped.
local drawUpright = Player.draw
function Player:draw(...)
  if not (self.flipped or (self.flipT or 0) > 0) or self.dead then return drawUpright(self, ...) end
  love.graphics.push()
  love.graphics.translate(self.x, self.y)
  love.graphics.scale(1, -1)
  love.graphics.translate(-self.x, -self.y)
  drawUpright(self, ...)
  love.graphics.pop()
end

return Player
