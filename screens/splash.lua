-- A short logo splash at start-up. Any key, click or button skips it.
local app = require "core.app"
local Logo = require "gfx.logo"

local Splash = {}
Splash.__index = Splash

local TIME = 1.5

function Splash.new() return setmetatable({ t = 0 }, Splash) end

local function finish(self)
  if self.done then return end
  self.done = true
  app.switch(require("screens.menu").new())
end

function Splash:update(dt)
  self.t = self.t + dt
  if self.t >= TIME then finish(self) end
end

function Splash:keypressed() finish(self) end
function Splash:mousepressed() finish(self) end
function Splash:gamepadpressed() finish(self) return true end

function Splash:draw()
  love.graphics.setColor(0.09, 0.09, 0.12)
  love.graphics.rectangle("fill", 0, 0, app.W, app.H)
  local k = math.min(1, self.t / 0.3)
  local out = math.max(0, math.min(1, (TIME - self.t) / 0.3))
  local s = 0.85 + 0.15 * (1 - (1 - k) ^ 3)
  Logo.draw(app.W / 2, app.H / 2, s)
  love.graphics.setColor(0.09, 0.09, 0.12, 1 - math.min(k, out))
  love.graphics.rectangle("fill", 0, 0, app.W, app.H)
end

return Splash
