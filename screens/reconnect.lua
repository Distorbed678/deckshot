-- Lost the connection to a LAN host mid-match: try to rejoin for a minute. When the host lets us
-- back in, lan.onEntered switches to the lobby, and the host's START puts us back in our slot.
local app = require "core.app"
local ui = require "core.ui"
local lan = require "online.lan"

local Screen = {}
Screen.__index = Screen

local TRY_FOR, TRY_EVERY = 60, 3

function Screen.new(address)
  return setmetatable({ address = address, t = 0, nextTry = 0.5 }, Screen)
end

function Screen:update(dt)
  self.t = self.t + dt
  self.nextTry = self.nextTry - dt
  if self.t > TRY_FOR then
    lan.leave()
    app.switch(require("screens.menu").new("Couldn't reconnect to the host"))
    return
  end
  if self.nextTry <= 0 and not lan.busy and not lan.active then
    self.nextTry = TRY_EVERY
    lan.join(self.address)
  end
end

function Screen:keypressed(key)
  if key == "escape" then self:cancel() end
end

function Screen:cancel()
  lan.leave()
  app.switch(require("screens.menu").new())
end

function Screen:draw()
  love.graphics.setColor(0.09, 0.09, 0.12)
  love.graphics.rectangle("fill", 0, 0, app.W, app.H)
  app.centered("CONNECTION LOST", app.fonts.big, 240)
  app.centered("Reconnecting to the host" .. string.rep(".", math.floor(self.t * 2) % 4) ..
    "   (" .. math.max(0, math.ceil(TRY_FOR - self.t)) .. "s)", app.fonts.med, 300, { 1, 1, 1, 0.7 })
  if lan.error then app.centered(lan.error, app.fonts.small, 340, { 1, 0.6, 0.45 }) end
  if ui.button("Give Up", app.W / 2 - 120, 420, 240, 50, { back = true }) then self:cancel() end
end

return Screen
