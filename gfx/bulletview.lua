-- How bullets look. The simulation is in game/bullet.lua.
local Assets = require "core.assets"
local Bullet = require "game.bullet"
local fx = require "gfx.fx"
local Map = require "game.map"
local LASER_FADE = Bullet.LASER_FADE
local MINE_TRIGGER = Bullet.MINE_TRIGGER

function Bullet:draw()
  local c = self.color

  if self.laser then
    if not self.points then return end
    local flat = {}
    for _, pt in ipairs(self.points) do
      flat[#flat + 1] = pt[1]
      flat[#flat + 1] = pt[2]
    end
    if #flat < 4 then return end
    local a = math.max(0, self.beam / LASER_FADE)
    love.graphics.setColor(c[1], c[2], c[3], a)
    Assets.strip("beam", flat, (self.r * 1.4 + 3) * 2.4, 32)
    love.graphics.setColor(1, 1, 1, a)
    Assets.strip("beam", flat, math.max(4, self.r * 1.4), 32)
    return
  end

  if self.mine then
    local pulse = 0.5 + 0.5 * math.sin(self.life * (self.armTime > 0 and 6 or 14))
    love.graphics.setColor(c[1], c[2], c[3], 0.25 + 0.25 * pulse)
    Assets.center("ring", self.x, self.y, (self.trigger or MINE_TRIGGER) * 0.7, (self.trigger or MINE_TRIGGER) * 0.7)
    love.graphics.setColor(1, 1, 1)
    Assets.center("mine", self.x, self.y, (self.r + 4) * 2, (self.r + 4) * 2)
    love.graphics.setColor(c[1], c[2], c[3], 0.5 + 0.5 * pulse)
    Assets.center("dot", self.x, self.y, (self.r * 0.6) * 2, (self.r * 0.6) * 2)
    return
  end

  for i, t in ipairs(self.trail) do
    love.graphics.setColor(c[1], c[2], c[3], 0.4 * (1 - i / 7))
    Assets.center("puff", t[1], t[2], (self.r * (1 - i / 8)) * 3, (self.r * (1 - i / 8)) * 3)
  end
  love.graphics.setColor(1, 1, 1, self.ghost and 0.5 or 1)
  Assets.center("bullet", self.x, self.y, (self.r + 1.5) * 2, (self.r + 1.5) * 2)
  love.graphics.setColor(c[1], c[2], c[3], self.ghost and 0.6 or 1)
  Assets.center("bullet", self.x, self.y, (self.r) * 2, (self.r) * 2)
end


return Bullet
