-- Start-up: the logo fades in over a loading bar that follows the sounds and music being built.
-- Always takes at least MIN_LOAD seconds of loading, and never hangs on slow machines.
local app = require "core.app"
local Logo = require "gfx.logo"

local Splash = {}
Splash.__index = Splash
Splash.noPadHints = true

local FADE_IN, MIN_LOAD, MAX_LOAD, FADE_OUT = 0.45, 1.2, 6, 0.27

function Splash.new() return setmetatable({ t = 0 }, Splash) end

local function realProgress()
  local sfx = require "gfx.sfx"
  local Music = require "gfx.music"
  if sfx.silent then return 1 end
  return (sfx.progress() + Music.progress()) / 2
end

function Splash:update(dt)
  self.t = self.t + dt
  local loading = math.max(0, self.t - FADE_IN)
  local shown = math.min(loading / MIN_LOAD, realProgress())
  if loading >= MAX_LOAD then shown = 1 end
  self.progress = math.max(self.progress or 0, math.min(1, shown))
  if self.progress >= 1 and not self.outT then self.outT = 0 end
  if self.outT then
    self.outT = self.outT + dt
    if self.outT >= FADE_OUT and not self.done then
      self.done = true
      app.instant()
      app.switch(require("screens.menu").new())
      app.fadeFrom(0.5)
    end
  end
end

function Splash:draw()
  love.graphics.setColor(0.09, 0.09, 0.12)
  love.graphics.rectangle("fill", 0, 0, app.W, app.H)
  local a = math.min(1, self.t / FADE_IN)
  if self.outT then a = math.max(0, 1 - self.outT / FADE_OUT) end
  Logo.drawLoading("Loading...", self.progress or 0, a)
end

return Splash
